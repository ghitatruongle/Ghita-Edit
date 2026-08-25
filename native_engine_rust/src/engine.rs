//! The GhitaEngine — port of C++ `GhitaEngine` with equivalent locking
//! semantics:
//!   engine state        → RwLock<EngineState>   (shared_mutex equivalent)
//!   decoder access      → Mutex<RenderState>    (m_renderMutex equivalent)
//!   playhead clock      → Mutex<Instant>        (m_tickTimeMutex equivalent)
//!   export join         → ExportState           (m_exportJoinMutex equivalent)
//!   audio thread join   → AudioThreadState      (m_audioThreadMutex equivalent)
//! Lock order is always state → render → (direct buffer).

use std::collections::{HashMap, VecDeque};
use std::sync::atomic::{AtomicBool, AtomicI32, AtomicI64, AtomicU32, Ordering};
use std::sync::{Mutex, RwLock};
use std::time::Instant;

use crate::compositor::{decode_clip_frame, get_clip_decoder, render_timeline_frame};
use crate::gdi::{render_text_gdi, TextGlyphCacheEntry};
use crate::model::{filters_json, BlendMode, Bookmark, ColorCorrection, Keyframe,
                   KeyframeInterpolation, MaskType, NativeClip, NativeClipKind, PipGeometry,
                   SpeedRampPoint, TransitionType};
use crate::synth::MediaDecoder;

#[cfg(feature = "ffmpeg")]
use ffmpeg_sys_next as ffi;
#[cfg(feature = "ffmpeg")]
use ffmpeg_sys_next::{AVChannelOrder::*, AVCodecConfig::*, AVPixelFormat::*, AVSampleFormat::*};
#[cfg(feature = "ffmpeg")]
use std::ffi::{c_int, CString as FCString};

// ---------------------------------------------------------------------------
// State containers
// ---------------------------------------------------------------------------

/// State guarded by the engine read/write lock (m_engineMutex).
pub struct EngineState {
    pub loaded_file_path: String,
    pub decoder: std::cell::RefCell<MediaDecoder>,
    pub clips: Vec<NativeClip>,
    pub next_clip_id: i32,
    pub track_states: Vec<crate::model::NativeTrackState>,
    pub export_media_path: String,
    pub export_output_path: String,
    // v1.5.0 T3 (#9): canvas background (kind 0=solid, 1=gradient, 2=blur).
    pub canvas_bg_kind: i32,
    pub canvas_bg_color: u32,
    pub canvas_bg_color2: u32,
    // v1.5.0 T3 (#10): timeline bookmarks.
    pub bookmarks: Vec<Bookmark>,
    pub next_bookmark_id: i32,
    /// v1.5.0-T5 (P2): paused-scrub frame cache — keyed by position + size +
    /// full timeline-state hash; RefCell is safe here because every access
    /// happens while the render mutex is held (serialized).
    pub processing: std::cell::RefCell<crate::processing_cache::ProcessingCache>,
}

impl Default for EngineState {
    fn default() -> Self {
        EngineState {
            loaded_file_path: String::new(),
            decoder: std::cell::RefCell::new(MediaDecoder::new()),
            clips: Vec::new(),
            next_clip_id: 1,
            track_states: Vec::new(),
            export_media_path: String::new(),
            export_output_path: String::new(),
            canvas_bg_kind: 0,
            canvas_bg_color: 0xFF000000,
            canvas_bg_color2: 0xFF000000,
            bookmarks: Vec::new(),
            next_bookmark_id: 1,
            processing: std::cell::RefCell::new(crate::processing_cache::ProcessingCache::new()),
        }
    }
}

/// State guarded by the render mutex (m_renderMutex) — decoder cache and
/// grow-only scratch buffers so steady-state renders allocate nothing.
pub struct RenderState {
    pub clip_decoders: HashMap<i32, MediaDecoder>,
    pub decoder_lru: VecDeque<i32>,
    pub render_scratch: Vec<u8>,
    pub scale_scratch: Vec<u8>,
    pub mix_seg_buf: Vec<f32>,
    pub text_cache: VecDeque<TextGlyphCacheEntry>,
    pub active_clips: Vec<Option<usize>>,
}

pub fn new_render_state() -> RenderState {
    RenderState {
        clip_decoders: HashMap::new(),
        decoder_lru: VecDeque::new(),
        render_scratch: Vec::new(),
        scale_scratch: Vec::new(),
        mix_seg_buf: Vec::new(),
        text_cache: VecDeque::new(),
        active_clips: Vec::new(),
    }
}

/// f32 stored as bits for lock-free atomic access.
pub struct AtomicF32 {
    bits: AtomicU32,
}

impl AtomicF32 {
    pub fn new(v: f32) -> Self {
        AtomicF32 { bits: AtomicU32::new(v.to_bits()) }
    }
    pub fn load(&self) -> f32 {
        f32::from_bits(self.bits.load(Ordering::Relaxed))
    }
    pub fn store(&self, v: f32) {
        self.bits.store(v.to_bits(), Ordering::Relaxed);
    }
}

/// Raw engine pointer that is Send+Sync — safe because the context outlives
/// any spawned thread (destroy() joins export/audio threads first), mirroring
/// the C++ `this` capture in worker threads.
/// T2 (P4): mixes one callback chunk from the engine's timeline audio
/// (stereo @ 44100, master volume) and converts to the device's sample format.
#[cfg(feature = "ffmpeg")]
fn cpal_mix_chunk<T: cpal::SizedSample + cpal::FromSample<f32>>(this: &EnginePtr, data: &mut [T], channels: usize) {
    use cpal::{FromSample, Sample};
    let frames = data.len() / channels.max(1);
    if frames == 0 {
        return;
    }
    let engine = unsafe { &*this.raw() };
    let pos = engine.get_position_ms();
    let window_ms = (frames as f64 * 1000.0 / 44100.0) as i64;
    // v1.5.0-T4 (P5): the mix scratch lives in a thread-local pool owned by
    // the audio-callback thread — the old path allocated a fresh Vec on
    // EVERY realtime callback (allocation in the RT path).
    thread_local! {
        static CPAL_MIX_SCRATCH: std::cell::RefCell<Vec<f32>> =
            const { std::cell::RefCell::new(Vec::new()) };
    }
    let mut mix = CPAL_MIX_SCRATCH.with(|b| {
        let mut b = b.borrow_mut();
        b.clear();
        b.resize(frames * 2, 0.0);
        std::mem::take(&mut *b)
    });
    // An audio callback must never unwind across cpal's thread and must not
    // propagate a poisoned-lock panic — degrade to silence instead.
    let has_audio = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        engine.mix_audio_window(pos, pos + window_ms, &mut mix, frames * 2, true)
    }))
    .unwrap_or(false);
    CPAL_MIX_SCRATCH.with(|b| {
        let mut b = b.borrow_mut();
        if b.capacity() < mix.capacity() {
            b.reserve(mix.capacity());
        }
        b.clear();
        b.append(&mut mix);
    });
    for f in 0..frames {
        let (l, r) = if has_audio { (mix[f * 2], mix[f * 2 + 1]) } else { (0.0, 0.0) };
        match channels {
            1 => data[f] = ((l + r) * 0.5).to_sample::<T>(),
            _ => {
                data[f * channels] = l.to_sample::<T>();
                data[f * channels + 1] = r.to_sample::<T>();
                for c in 2..channels {
                    data[f * channels + c] = (if c % 2 == 0 { l } else { r }).to_sample::<T>();
                }
            }
        }
    }
}

struct EnginePtr(*const GhitaEngine);
unsafe impl Send for EnginePtr {}
unsafe impl Sync for EnginePtr {}

impl EnginePtr {
    /// Method access forces whole-variable capture in move closures (edition
    /// 2021 would otherwise capture the raw-pointer field directly).
    fn raw(&self) -> *const GhitaEngine {
        self.0
    }
}

struct ExportState {
    join_mutex: Mutex<Option<std::thread::JoinHandle<()>>>,
}

struct AudioThreadState {
    thread_mutex: Mutex<Option<std::thread::JoinHandle<()>>>,
    running: AtomicBool,
    stop: AtomicBool,
}

/// v1.5.0 perf: cached per-bucket peak/RMS of the timeline audio (one entry
/// per distinct timeline signature × bucket count, oldest evicted). Served by
/// get_timeline_waveform / get_timeline_rms so repeated UI fetches never
/// re-decode.
struct TimelineAudioStats {
    signature: u64,
    sample_count: usize,
    peaks: Vec<f32>,
    rms: Vec<f32>,
}

// ---------------------------------------------------------------------------
// Engine
// ---------------------------------------------------------------------------

pub struct GhitaEngine {
    pub(crate) state: RwLock<EngineState>,
    render: Mutex<RenderState>,
    direct_buffer: Mutex<Vec<u8>>,
    tick: Mutex<Instant>,

    is_playing: AtomicBool,
    ready: AtomicBool,
    current_pos_ms: AtomicI64,
    duration_ms: AtomicI64,
    width: AtomicI32,
    height: AtomicI32,
    volume: AtomicF32,
    snapping_fps: AtomicI32,
    playback_rate: AtomicF32,
    active_filter_type: AtomicI32,
    filter_intensity: AtomicF32,

    audio_preview_enabled: AtomicBool,
    noise_suppress: AtomicBool,

    is_exporting: AtomicBool,
    cancel_export_flag: AtomicBool,
    export_error: AtomicBool,
    export_progress: AtomicF32,
    export_file_size: AtomicI64,
    export: ExportState,
    audio_thread: AudioThreadState,
    // T2 (P4): preferred audio output device (None = default).
    audio_device: Mutex<Option<String>>,
    // T2 (P5): export audio channel layout ("stereo" | "5.1" | "7.1").
    export_channel_layout: Mutex<String>,
    // v1.5.0 perf: cached timeline audio stats (see TimelineAudioStats).
    timeline_audio_stats: Mutex<Vec<TimelineAudioStats>>,
    // v1.5.0 T4: audio features state (effect chain, loop, recording, ...).
    #[cfg(feature = "ffmpeg")]
    pub(crate) t4: crate::audio_t4::T4State,
}

impl Default for GhitaEngine {
    fn default() -> Self {
        Self::new()
    }
}

impl GhitaEngine {
    pub fn new() -> Self {
        GhitaEngine {
            state: RwLock::new(EngineState::default()),
            render: Mutex::new(new_render_state()),
            direct_buffer: Mutex::new(Vec::new()),
            tick: Mutex::new(Instant::now()),
            is_playing: AtomicBool::new(false),
            ready: AtomicBool::new(false),
            current_pos_ms: AtomicI64::new(0),
            duration_ms: AtomicI64::new(60000),
            width: AtomicI32::new(1280),
            height: AtomicI32::new(720),
            volume: AtomicF32::new(1.0),
            snapping_fps: AtomicI32::new(30),
            playback_rate: AtomicF32::new(1.0),
            active_filter_type: AtomicI32::new(0),
            filter_intensity: AtomicF32::new(1.0),
            audio_preview_enabled: AtomicBool::new(true),
            noise_suppress: AtomicBool::new(false),
            is_exporting: AtomicBool::new(false),
            cancel_export_flag: AtomicBool::new(false),
            export_error: AtomicBool::new(false),
            export_progress: AtomicF32::new(0.0),
            export_file_size: AtomicI64::new(0),
            export: ExportState { join_mutex: Mutex::new(None) },
            audio_thread: AudioThreadState {
                thread_mutex: Mutex::new(None),
                running: AtomicBool::new(false),
                stop: AtomicBool::new(false),
            },
            audio_device: Mutex::new(None),
            export_channel_layout: Mutex::new("stereo".to_string()),
            timeline_audio_stats: Mutex::new(Vec::new()),
            #[cfg(feature = "ffmpeg")]
            t4: crate::audio_t4::T4State::default(),
        }
    }

    // ------------------------------------------------------------------
    // Lifecycle / playback
    // ------------------------------------------------------------------

    pub fn initialize(&self) -> bool {
        let _guard = self.state.write().unwrap();
        if self.ready.load(Ordering::Relaxed) {
            return true;
        }
        self.is_playing.store(false, Ordering::Relaxed);
        self.current_pos_ms.store(0, Ordering::Relaxed);
        self.volume.store(1.0);
        self.filter_intensity.store(1.0);
        self.snapping_fps.store(30, Ordering::Relaxed);
        self.active_filter_type.store(0, Ordering::Relaxed);
        *self.tick.lock().unwrap() = Instant::now();
        self.ready.store(true, Ordering::Relaxed);
        true
    }

    pub fn load_media(&self, file_path: &str) -> bool {
        let mut state = self.state.write().unwrap();
        state.loaded_file_path = file_path.to_string();
        // v0.8.0: Report missing files honestly — a nonexistent path silently
        // switched to synthetic content while returning success.
        let file_exists = std::fs::File::open(file_path).is_ok();
        state.decoder.borrow_mut().open(file_path);
        self.width.store(state.decoder.borrow().width, Ordering::Relaxed);
        self.height.store(state.decoder.borrow().height, Ordering::Relaxed);
        // Only the legacy single-media path owns the duration when there is
        // no timeline.
        if state.clips.is_empty() {
            self.duration_ms.store(state.decoder.borrow().duration_ms, Ordering::Relaxed);
        }
        self.current_pos_ms.store(0, Ordering::Relaxed);
        *self.tick.lock().unwrap() = Instant::now();
        file_exists
    }

    pub fn play(&self) {
        {
            let _guard = self.state.write().unwrap();
            if !self.ready.load(Ordering::Relaxed) {
                return;
            }
            *self.tick.lock().unwrap() = Instant::now();
            self.is_playing.store(true, Ordering::Relaxed);
        }
        // Audio preview follows playback. Started OUTSIDE the engine lock —
        // the preview thread blocks on the engine lock inside mixAudioWindow.
        self.start_audio_preview_thread();
    }

    pub fn pause(&self) {
        {
            let _guard = self.state.write().unwrap();
            self.is_playing.store(false, Ordering::Relaxed);
        }
        self.stop_audio_preview_thread();
    }

    pub fn is_playing(&self) -> bool {
        self.is_playing.load(Ordering::Relaxed)
    }

    pub fn seek(&self, position_ms: i64) {
        let _guard = self.state.write().unwrap();
        let duration = self.duration_ms.load(Ordering::Relaxed);
        let pos = position_ms.clamp(0, duration);
        self.current_pos_ms.store(pos, Ordering::Relaxed);
        *self.tick.lock().unwrap() = Instant::now();
    }

    pub fn get_position_ms(&self) -> i64 {
        self.current_pos_ms.load(Ordering::Relaxed)
    }

    pub fn get_duration_ms(&self) -> i64 {
        self.duration_ms.load(Ordering::Relaxed)
    }

    pub fn get_width(&self) -> i32 {
        self.width.load(Ordering::Relaxed)
    }

    pub fn get_height(&self) -> i32 {
        self.height.load(Ordering::Relaxed)
    }

    pub fn set_volume(&self, volume: f32) {
        let _guard = self.state.write().unwrap();
        self.volume.store(volume.clamp(0.0, 2.0));
    }

    pub fn get_volume(&self) -> f32 {
        self.volume.load()
    }

    pub fn set_playback_rate(&self, rate: f32) {
        let _guard = self.state.write().unwrap();
        self.playback_rate.store(rate.clamp(0.25, 4.0));
    }

    pub fn get_playback_rate(&self) -> f32 {
        self.playback_rate.load()
    }

    pub fn apply_filter(&self, filter_type: i32, intensity: f32) {
        let _guard = self.state.write().unwrap();
        self.active_filter_type.store(filter_type.clamp(0, 22), Ordering::Relaxed);
        self.filter_intensity.store(intensity.clamp(0.0, 1.0));
    }

    pub fn get_active_filter_type(&self) -> i32 {
        self.active_filter_type.load(Ordering::Relaxed)
    }

    pub fn get_filter_intensity(&self) -> f32 {
        self.filter_intensity.load()
    }

    pub fn set_frame_snapping_fps(&self, fps: i32) {
        self.snapping_fps.store(fps.clamp(1, 120), Ordering::Relaxed);
    }

    pub fn get_frame_snapping_fps(&self) -> i32 {
        self.snapping_fps.load(Ordering::Relaxed)
    }

    pub fn set_audio_preview_enabled(&self, enabled: bool) {
        self.audio_preview_enabled.store(enabled, Ordering::Relaxed);
    }

    pub fn is_audio_preview_enabled(&self) -> bool {
        self.audio_preview_enabled.load(Ordering::Relaxed)
    }

    pub fn set_noise_suppress(&self, enabled: bool) {
        self.noise_suppress.store(enabled, Ordering::Relaxed);
    }

    pub fn is_noise_suppress_enabled(&self) -> bool {
        self.noise_suppress.load(Ordering::Relaxed)
    }

    // ------------------------------------------------------------------
    // Rendering
    // ------------------------------------------------------------------

    /// Renders the current-position frame; advances the playhead by
    /// wall-clock elapsed × playback rate when playing (the Dart tick loop
    /// drives this).
    pub fn render_frame_rgba(&self, out: &mut [u8], width: usize, height: usize) -> bool {
        if !self.ready.load(Ordering::Relaxed) {
            return false;
        }
        let state = self.state.read().unwrap();
        let mut rstate = self.render.lock().unwrap();

        let mut pos = self.current_pos_ms.load(Ordering::Relaxed);
        let duration = self.duration_ms.load(Ordering::Relaxed);

        if self.is_playing.load(Ordering::Relaxed) {
            let mut tt = self.tick.lock().unwrap();
            let now = Instant::now();
            let elapsed = now.duration_since(*tt).as_millis() as i64;
            *tt = now;
            pos += (elapsed as f64 * self.playback_rate.load() as f64) as i64;
            if duration > 0 && pos >= duration {
                pos = 0;
            }
            self.current_pos_ms.store(pos, Ordering::Relaxed);
        }

        if !state.clips.is_empty() {
            // v1.5.0-T5 (P2): playback tick — cache OFF (frames are
            // single-use; caching would burn memory for zero hits).
            return render_timeline_frame(
                &state,
                &mut rstate,
                out,
                width,
                height,
                pos,
                true,
                self.active_filter_type.load(Ordering::Relaxed),
                self.filter_intensity.load(),
                false,
            );
        }
        let mut dec = state.decoder.borrow_mut();
        dec.decode_frame(
            out,
            width,
            height,
            pos,
            self.active_filter_type.load(Ordering::Relaxed),
            self.filter_intensity.load(),
        )
    }

    /// v0.7.9: Render at an explicit position without mutating playback state.
    pub fn render_frame_at(&self, out: &mut [u8], width: usize, height: usize, position_ms: i64) -> bool {
        if !self.ready.load(Ordering::Relaxed) {
            return false;
        }
        let state = self.state.read().unwrap();
        let mut rstate = self.render.lock().unwrap();

        if !state.clips.is_empty() {
            // v1.5.0-T5 (P2): paused scrub — cache ON.
            return render_timeline_frame(
                &state,
                &mut rstate,
                out,
                width,
                height,
                position_ms.max(0),
                true,
                self.active_filter_type.load(Ordering::Relaxed),
                self.filter_intensity.load(),
                true,
            );
        }
        let duration = self.duration_ms.load(Ordering::Relaxed);
        let clamped = position_ms.clamp(0, if duration > 0 { duration - 1 } else { 0 });
        let mut dec = state.decoder.borrow_mut();
        dec.decode_frame(
            out,
            width,
            height,
            clamped,
            self.active_filter_type.load(Ordering::Relaxed),
            self.filter_intensity.load(),
        )
    }

    /// v1.1.0 (PLAN 3.5): render_frame_at without the effects (raw timeline).
    pub fn render_frame_at_ex(&self, out: &mut [u8], width: usize, height: usize, position_ms: i64, apply_fx: bool) -> bool {
        if !self.ready.load(Ordering::Relaxed) {
            return false;
        }
        let state = self.state.read().unwrap();
        let mut rstate = self.render.lock().unwrap();

        if !state.clips.is_empty() {
            // v1.5.0-T5 (P2): raw (effects-free) path — cache ON when paused.
            return render_timeline_frame(
                &state,
                &mut rstate,
                out,
                width,
                height,
                position_ms.max(0),
                apply_fx,
                self.active_filter_type.load(Ordering::Relaxed),
                self.filter_intensity.load(),
                !self.is_playing.load(Ordering::Relaxed),
            );
        }
        let duration = self.duration_ms.load(Ordering::Relaxed);
        let clamped = position_ms.clamp(0, if duration > 0 { duration - 1 } else { 0 });
        let mut dec = state.decoder.borrow_mut();
        dec.decode_frame(
            out,
            width,
            height,
            clamped,
            if apply_fx { self.active_filter_type.load(Ordering::Relaxed) } else { 0 },
            if apply_fx { self.filter_intensity.load() } else { 0.0 },
        )
    }

    /// Zero-copy direct buffer pointer for GPU sharing (grow-only buffer —
    /// the pointer stays valid until the buffer must grow).
    pub fn get_frame_direct_buffer_pointer(&self, out_width: &mut i32, out_height: &mut i32) -> *mut u8 {
        let state = self.state.read().unwrap();
        let mut rstate = self.render.lock().unwrap();
        let mut db = self.direct_buffer.lock().unwrap();
        if !self.ready.load(Ordering::Relaxed) {
            return std::ptr::null_mut();
        }
        let w = self.width.load(Ordering::Relaxed);
        let h = self.height.load(Ordering::Relaxed);
        let needed = w as usize * h as usize * 4;
        if db.len() < needed {
            db.resize(needed, 0);
        }
        let pos = self.current_pos_ms.load(Ordering::Relaxed);
        if !state.clips.is_empty() {
            render_timeline_frame(
                &state,
                &mut rstate,
                &mut db[..],
                w as usize,
                h as usize,
                pos,
                true,
                self.active_filter_type.load(Ordering::Relaxed),
                self.filter_intensity.load(),
                // v1.5.0-T5 (P2): native preview thread — cache only when
                // paused so playback never pollutes the LRU.
                !self.is_playing.load(Ordering::Relaxed),
            );
        } else {
            let mut dec = state.decoder.borrow_mut();
            dec.decode_frame(
                &mut db[..],
                w as usize,
                h as usize,
                pos,
                self.active_filter_type.load(Ordering::Relaxed),
                self.filter_intensity.load(),
            );
        }
        *out_width = w;
        *out_height = h;
        db.as_mut_ptr()
    }

    // ------------------------------------------------------------------
    // Media info / JSON
    // ------------------------------------------------------------------

    pub fn get_media_info_json(&self) -> String {
        let state = self.state.read().unwrap();
        let info = {
            let dec = state.decoder.borrow();
            dec.media_info()
        };
        info.to_json()
    }

    pub fn get_available_filters_json(&self) -> String {
        filters_json()
    }

    // ------------------------------------------------------------------
    // Timeline / clip operations
    // ------------------------------------------------------------------

    fn recalculate_duration(&self, state: &EngineState) {
        let mut max_end = 0i64;
        for clip in &state.clips {
            let end = clip.start_ms + clip.duration_ms;
            if end > max_end {
                max_end = end;
            }
        }
        self.duration_ms.store(max_end, Ordering::Relaxed);
    }

    fn sort_clips_by_start(state: &mut EngineState) {
        state.clips.sort_by(|a, b| a.start_ms.cmp(&b.start_ms));
    }

    pub fn add_clip(&self, file_path: &str, start_ms: i64, duration_ms: i64, track_index: i32) -> i32 {
        let mut state = self.state.write().unwrap();
        let mut clip = NativeClip::new(state.next_clip_id);
        state.next_clip_id += 1;
        clip.file_path = file_path.to_string();
        clip.start_ms = start_ms.max(0);
        clip.duration_ms = duration_ms.max(100);
        clip.track_index = track_index.max(0);
        clip.filter_type = 0;
        clip.filter_intensity = 1.0;
        state.clips.push(clip);
        self.recalculate_duration(&state);
        state.next_clip_id - 1
    }

    pub fn remove_clip(&self, clip_id: i32) -> bool {
        let mut state = self.state.write().unwrap();
        let before = state.clips.len();
        state.clips.retain(|c| c.id != clip_id);
        if state.clips.len() == before {
            return false;
        }
        self.recalculate_duration(&state);
        Self::sort_clips_by_start(&mut state);
        true
    }

    pub fn get_clip_count(&self) -> i32 {
        let state = self.state.read().unwrap();
        state.clips.len() as i32
    }

    pub fn set_clip_position(&self, clip_id: i32, start_ms: i64) -> bool {
        let mut state = self.state.write().unwrap();
        for clip in state.clips.iter_mut() {
            if clip.id == clip_id {
                clip.start_ms = start_ms.max(0);
                self.recalculate_duration(&state);
                return true;
            }
        }
        false
    }

    pub fn set_clip_filter(&self, clip_id: i32, filter_type: i32, intensity: f32) -> bool {
        let mut state = self.state.write().unwrap();
        for clip in state.clips.iter_mut() {
            if clip.id == clip_id {
                clip.filter_type = filter_type.clamp(0, 22);
                clip.filter_intensity = intensity.clamp(0.0, 1.0);
                return true;
            }
        }
        false
    }

    pub fn set_clip_transition(&self, clip_id: i32, transition_type: TransitionType, duration_ms: i32) -> bool {
        let mut state = self.state.write().unwrap();
        for clip in state.clips.iter_mut() {
            if clip.id == clip_id {
                clip.transition.kind = transition_type;
                clip.transition.duration_ms = duration_ms.max(0);
                return true;
            }
        }
        false
    }

    /// Full timeline sync — insert or update. Returns 1 on success, 0 on failure.
    pub fn upsert_clip(
        &self,
        clip_id: i32,
        file_path: &str,
        start_ms: i64,
        duration_ms: i64,
        source_in_ms: i64,
        track_index: i32,
        kind: NativeClipKind,
        volume: f32,
        opacity: f32,
        speed: f32,
    ) -> i32 {
        let mut state = self.state.write().unwrap();
        if clip_id <= 0 || duration_ms <= 0 {
            return 0;
        }

        for clip in state.clips.iter_mut() {
            if clip.id == clip_id {
                let path_changed = clip.file_path != file_path;
                clip.file_path = file_path.to_string();
                clip.start_ms = start_ms.max(0);
                clip.duration_ms = duration_ms;
                clip.source_in_ms = source_in_ms.max(0);
                clip.track_index = track_index.max(0);
                clip.kind = kind;
                clip.volume = volume.clamp(0.0, 2.0);
                clip.opacity = opacity.clamp(0.0, 1.0);
                clip.speed = speed.clamp(0.25, 4.0);
                if path_changed {
                    let mut rstate = self.render.lock().unwrap();
                    rstate.clip_decoders.remove(&clip_id);
                    if let Some(pos) = rstate.decoder_lru.iter().position(|&id| id == clip_id) {
                        rstate.decoder_lru.remove(pos);
                    }
                }
                self.recalculate_duration(&state);
                Self::sort_clips_by_start(&mut state);
                return 1;
            }
        }

        let mut clip = NativeClip::new(clip_id);
        clip.file_path = file_path.to_string();
        clip.start_ms = start_ms.max(0);
        clip.duration_ms = duration_ms;
        clip.source_in_ms = source_in_ms.max(0);
        clip.track_index = track_index.max(0);
        clip.kind = kind;
        clip.volume = volume.clamp(0.0, 2.0);
        clip.opacity = opacity.clamp(0.0, 1.0);
        clip.speed = speed.clamp(0.25, 4.0);
        state.clips.push(clip);
        if clip_id >= state.next_clip_id {
            state.next_clip_id = clip_id + 1;
        }
        self.recalculate_duration(&state);
        Self::sort_clips_by_start(&mut state);
        1
    }

    pub fn clear_clips(&self) {
        let mut state = self.state.write().unwrap();
        state.clips.clear();
        state.track_states.clear();
        {
            let mut rstate = self.render.lock().unwrap();
            rstate.clip_decoders.clear();
            rstate.decoder_lru.clear();
        }
        self.recalculate_duration(&state);
    }

    pub fn set_track_state(&self, track_index: i32, muted: bool, visible: bool, volume: f32) -> i32 {
        let mut state = self.state.write().unwrap();
        if track_index < 0 {
            return 0;
        }
        if track_index as usize >= state.track_states.len() {
            state.track_states.resize(track_index as usize + 1, Default::default());
        }
        state.track_states[track_index as usize].muted = muted;
        state.track_states[track_index as usize].visible = visible;
        state.track_states[track_index as usize].volume = volume.clamp(0.0, 2.0);
        1
    }

    pub fn set_clip_color_correction(&self, clip_id: i32, cc: ColorCorrection) -> i32 {
        let mut state = self.state.write().unwrap();
        for clip in state.clips.iter_mut() {
            if clip.id == clip_id {
                clip.cc = cc;
                return 1;
            }
        }
        0
    }

    pub fn set_clip_text(&self, clip_id: i32, text: &str, font_size: f32, color_argb: u32) -> i32 {
        let mut state = self.state.write().unwrap();
        for clip in state.clips.iter_mut() {
            if clip.id == clip_id {
                clip.text_content = text.to_string();
                clip.text_font_size = font_size.max(4.0);
                clip.text_color = color_argb;
                return 1;
            }
        }
        0
    }

    pub fn has_clip(&self, clip_id: i32) -> bool {
        let state = self.state.read().unwrap();
        state.clips.iter().any(|c| c.id == clip_id)
    }

    // ------------------------------------------------------------------
    // Keyframes / animation
    // ------------------------------------------------------------------

    pub fn add_clip_keyframe(&self, clip_id: i32, time_ms: i64, value: f32) -> bool {
        let mut state = self.state.write().unwrap();
        for clip in state.clips.iter_mut() {
            if clip.id == clip_id {
                clip.keyframes.push(Keyframe::new(time_ms, value));
                clip.keyframes.sort_by(|a, b| a.time_ms.cmp(&b.time_ms));
                return true;
            }
        }
        false
    }

    pub fn clear_clip_keyframes(&self, clip_id: i32) -> bool {
        let mut state = self.state.write().unwrap();
        for clip in state.clips.iter_mut() {
            if clip.id == clip_id {
                clip.keyframes.clear();
                return true;
            }
        }
        false
    }

    /// v1.1.0 (PLAN 3.1): property/interpolation/bezier-aware insertion.
    pub fn add_clip_keyframe_ex(
        &self,
        clip_id: i32,
        time_ms: i64,
        value: f32,
        property: i32,
        interpolation: i32,
        cp1x: f32,
        cp1y: f32,
        cp2x: f32,
        cp2y: f32,
    ) -> i32 {
        let mut state = self.state.write().unwrap();
        for clip in state.clips.iter_mut() {
            if clip.id == clip_id {
                // Replace an existing keyframe at the same time AND property.
                for kf in clip.keyframes.iter_mut() {
                    if kf.time_ms == time_ms && kf.property == property {
                        kf.value = value;
                        kf.interpolation = interpolation;
                        kf.cp1x = cp1x;
                        kf.cp1y = cp1y;
                        kf.cp2x = cp2x;
                        kf.cp2y = cp2y;
                        return 0;
                    }
                }
                clip.keyframes.push(Keyframe {
                    time_ms,
                    value,
                    property,
                    interpolation,
                    cp1x,
                    cp1y,
                    cp2x,
                    cp2y,
                });
                clip.keyframes.sort_by(|a, b| {
                    if a.time_ms != b.time_ms {
                        a.time_ms.cmp(&b.time_ms)
                    } else {
                        a.property.cmp(&b.property)
                    }
                });
                return 0;
            }
        }
        -1
    }

    pub fn set_keyframe_bezier_ex(
        &self,
        clip_id: i32,
        keyframe_index: i32,
        cp1x: f32,
        cp1y: f32,
        cp2x: f32,
        cp2y: f32,
    ) -> i32 {
        let mut state = self.state.write().unwrap();
        for clip in state.clips.iter_mut() {
            if clip.id == clip_id {
                if keyframe_index < 0 || keyframe_index as usize >= clip.keyframes.len() {
                    return -1;
                }
                let kf = &mut clip.keyframes[keyframe_index as usize];
                kf.cp1x = cp1x;
                kf.cp1y = cp1y;
                kf.cp2x = cp2x;
                kf.cp2y = cp2y;
                kf.interpolation = 2; // bezier
                return 0;
            }
        }
        -1
    }

    pub fn get_clip_keyframe_count(&self, clip_id: i32) -> i32 {
        let state = self.state.read().unwrap();
        for clip in &state.clips {
            if clip.id == clip_id {
                return clip.keyframes.len() as i32;
            }
        }
        -1
    }

    pub fn set_clip_pip(&self, clip_id: i32, pip: PipGeometry) -> i32 {
        let mut state = self.state.write().unwrap();
        for clip in state.clips.iter_mut() {
            if clip.id == clip_id {
                clip.pip = pip;
                return 0;
            }
        }
        -1
    }

    pub fn set_clip_speed_curve(&self, clip_id: i32, curve: Vec<SpeedRampPoint>) -> i32 {
        let mut state = self.state.write().unwrap();
        for clip in state.clips.iter_mut() {
            if clip.id == clip_id {
                clip.speed_curve = curve;
                clip.speed_curve.sort_by(|a, b| a.t.partial_cmp(&b.t).unwrap());
                return 0;
            }
        }
        -1
    }

    pub fn add_speed_ramp_point(&self, clip_id: i32, t: f32, speed: f32) -> i32 {
        let mut state = self.state.write().unwrap();
        for clip in state.clips.iter_mut() {
            if clip.id == clip_id {
                for p in clip.speed_curve.iter_mut() {
                    if p.t == t {
                        p.speed = speed;
                        return 0;
                    }
                }
                clip.speed_curve.push(SpeedRampPoint { t, speed });
                clip.speed_curve.sort_by(|a, b| a.t.partial_cmp(&b.t).unwrap());
                return 0;
            }
        }
        -1
    }

    pub fn set_clip_keyframe_interpolation(&self, clip_id: i32, interpolation: KeyframeInterpolation) -> bool {
        let mut state = self.state.write().unwrap();
        for clip in state.clips.iter_mut() {
            if clip.id == clip_id {
                clip.keyframe_interpolation = interpolation as i32;
                return true;
            }
        }
        false
    }

    pub fn get_clip_keyframe_interpolation(&self, clip_id: i32) -> KeyframeInterpolation {
        let state = self.state.read().unwrap();
        for clip in &state.clips {
            if clip.id == clip_id {
                return KeyframeInterpolation::from_i32(clip.keyframe_interpolation);
            }
        }
        KeyframeInterpolation::Linear
    }

    // ------------------------------------------------------------------
    // v1.5.0 T3: blend modes / masks / canvas / bookmarks / keyframe copy
    // ------------------------------------------------------------------

    pub fn set_clip_blend_mode(&self, clip_id: i32, mode: BlendMode) -> i32 {
        let mut state = self.state.write().unwrap();
        for clip in state.clips.iter_mut() {
            if clip.id == clip_id {
                clip.blend_mode = mode;
                return 0;
            }
        }
        -1
    }

    pub fn set_clip_mask(&self, clip_id: i32, mask_type: MaskType, feather: f32, stroke: f32) -> i32 {
        let mut state = self.state.write().unwrap();
        for clip in state.clips.iter_mut() {
            if clip.id == clip_id {
                clip.mask_type = mask_type;
                clip.mask_feather = feather.clamp(0.0, 1.0);
                clip.mask_stroke = stroke.clamp(0.0, 1.0);
                return 0;
            }
        }
        -1
    }

    pub fn set_clip_maintain_pitch(&self, clip_id: i32, enabled: bool) -> i32 {
        let mut state = self.state.write().unwrap();
        for clip in state.clips.iter_mut() {
            if clip.id == clip_id {
                clip.maintain_pitch = enabled;
                return 0;
            }
        }
        -1
    }

    /// v1.5.0-T5 (P5): sticker transform — scale about center (0.05..8×) and
    /// rotation in degrees. Only meaningful for Sticker clips.
    pub fn set_clip_sticker_transform(&self, clip_id: i32, scale: f32, rotation_deg: f32) -> i32 {
        let mut state = self.state.write().unwrap();
        for clip in state.clips.iter_mut() {
            if clip.id == clip_id && clip.kind == crate::model::NativeClipKind::Sticker {
                clip.sticker_scale = scale.clamp(0.05, 8.0);
                clip.sticker_rotation = rotation_deg;
                return 0;
            }
        }
        -1
    }

    pub fn set_clip_font(&self, clip_id: i32, family: &str) -> i32 {
        let mut state = self.state.write().unwrap();
        for clip in state.clips.iter_mut() {
            if clip.id == clip_id {
                clip.font_family = family.to_string();
                return 0;
            }
        }
        -1
    }

    pub fn set_canvas_background(&self, kind: i32, color: u32, color2: u32) {
        let mut state = self.state.write().unwrap();
        state.canvas_bg_kind = kind.clamp(0, 2);
        state.canvas_bg_color = color;
        state.canvas_bg_color2 = color2;
    }

    pub fn add_bookmark(&self, time_ms: i64, color: u32, note: &str) -> i32 {
        let mut state = self.state.write().unwrap();
        let id = state.next_bookmark_id;
        state.next_bookmark_id += 1;
        state.bookmarks.push(Bookmark { id, time_ms, color, note: note.to_string() });
        id
    }

    pub fn remove_bookmark(&self, id: i32) -> i32 {
        let mut state = self.state.write().unwrap();
        let before = state.bookmarks.len();
        state.bookmarks.retain(|b| b.id != id);
        if state.bookmarks.len() == before { -1 } else { 0 }
    }

    pub fn get_bookmark_count(&self) -> i32 {
        let state = self.state.read().unwrap();
        state.bookmarks.len() as i32
    }

    pub fn get_bookmarks_json(&self) -> String {
        let state = self.state.read().unwrap();
        let mut s = String::from("[");
        for (i, b) in state.bookmarks.iter().enumerate() {
            if i > 0 {
                s.push(',');
            }
            s.push_str(&format!(
                "{{\"id\":{},\"timeMs\":{},\"color\":{},\"note\":\"{}\"}}",
                b.id,
                b.time_ms,
                b.color,
                crate::model::json_escape(&b.note)
            ));
        }
        s.push(']');
        s
    }

    /// T3 (#2): clones all keyframes of [src] onto [dst] (merged, re-sorted).
    pub fn copy_keyframes(&self, src: i32, dst: i32) -> i32 {
        let mut state = self.state.write().unwrap();
        let src_kf: Vec<Keyframe> = match state.clips.iter().find(|c| c.id == src) {
            Some(c) => c.keyframes.clone(),
            None => return -1,
        };
        for clip in state.clips.iter_mut() {
            if clip.id == dst {
                clip.keyframes.extend(src_kf);
                clip.keyframes.sort_by(|a, b| {
                    if a.time_ms != b.time_ms {
                        a.time_ms.cmp(&b.time_ms)
                    } else {
                        a.property.cmp(&b.property)
                    }
                });
                return 0;
            }
        }
        -1
    }

    /// T3 (#11 engine part): parses an .srt/.vtt transcript into text clips
    /// on [track_index]; returns the number of clips created (0 on failure).
    pub fn import_transcript(&self, path: &str, track_index: i32) -> i32 {
        let data = match std::fs::read_to_string(path) {
            Ok(d) => d,
            Err(_) => return 0,
        };
        // Normalize CRLF/CR — .srt/.vtt saved on Windows never contain a bare
        // "\n\n" block separator, so without this only the first cue imported.
        let data = data.replace("\r\n", "\n").replace('\r', "\n");
        let mut cues: Vec<(i64, i64, String)> = Vec::new();
        let is_vtt = data.contains("WEBVTT");
        // Split into blocks: index (srt) then timing line then text.
        for block in data.split("

") {
            let mut lines = block.lines();
            let timing = lines.find(|l| l.contains("-->"));
            let timing = match timing {
                Some(t) => t.to_string(),
                None => continue,
            };
            let text: Vec<&str> = lines.collect();
            if text.is_empty() {
                continue;
            }
            let (start, end) = parse_timing(&timing, is_vtt);
            if start >= 0 && end > start {
                cues.push((start, end - start, text.join(" ")));
            }
        }
        let n = cues.len();
        let mut state = self.state.write().unwrap();
        for (t, d, txt) in cues {
            let mut clip = NativeClip::new(state.next_clip_id);
            state.next_clip_id += 1;
            clip.kind = NativeClipKind::Text;
            clip.start_ms = t;
            clip.duration_ms = d;
            clip.track_index = track_index.max(0);
            clip.text_content = txt;
            clip.text_font_size = 42.0;
            clip.text_color = 0xFFFFFFFF;
            state.clips.push(clip);
        }
        Self::sort_clips_by_start(&mut state);
        self.recalculate_duration(&state);
        n as i32
    }

    // ------------------------------------------------------------------
    // Audio
    // ------------------------------------------------------------------

    /// v0.8.0: Mix interleaved float-stereo PCM @ 44100 for [start, end) from
    /// every clip that overlaps the window (clip volume × track volume/mute ×
    /// optional master). Returns true when any clip contributed audio.
    pub fn mix_audio_window(&self, start_ms: i64, end_ms: i64, out: &mut [f32], count: usize, apply_master: bool) -> bool {
        if count == 0 || end_ms <= start_ms {
            return false;
        }
        for s in out.iter_mut().take(count) {
            *s = 0.0;
        }

        let state = self.state.read().unwrap();
        let mut rstate = self.render.lock().unwrap();

        let master = if apply_master { self.volume.load() } else { 1.0 };
        #[allow(unused_mut)]
        let mut any_audio = false;
        const SAMPLE_RATE: f64 = 44100.0;

        let RenderState { clip_decoders, decoder_lru, mix_seg_buf, .. } = &mut *rstate;

        // m_clips is sorted by startMs — a clip that starts at/after endMs
        // cannot overlap this window, and neither can any later clip.
        for clip in &state.clips {
            if clip.start_ms >= end_ms {
                break;
            }
            let clip_end = clip.start_ms + clip.duration_ms;
            if clip_end <= start_ms {
                continue;
            }

            let mut track_vol = 1.0f32;
            if (clip.track_index as usize) < state.track_states.len() {
                if state.track_states[clip.track_index as usize].muted {
                    continue;
                }
                track_vol = state.track_states[clip.track_index as usize].volume;
            }
            let gain = clip.volume * track_vol * master;
            if gain <= 0.0 {
                continue;
            }

            // Overlap window on the timeline → source-time window (speed-scaled).
            let ov_start = start_ms.max(clip.start_ms);
            let ov_end = end_ms.min(clip_end);
            if ov_end <= ov_start {
                continue;
            }
            let src_start = clip.source_in_ms
                + ((ov_start - clip.start_ms) as f64 * clip.speed as f64) as i64;
            let ov_frames = (((ov_end - ov_start) as f64 / 1000.0 * SAMPLE_RATE).ceil()) as i64;
            let ov_floats = ov_frames * 2;
            let out_offset_frames = ((ov_start - start_ms) as f64 / 1000.0 * SAMPLE_RATE) as i64;
            let max_copy = (ov_floats as i64).min(count as i64 - out_offset_frames * 2);
            if max_copy <= 0 {
                continue;
            }

            // Clip kinds without media (text/sticker) contribute no audio.
            if clip.kind == NativeClipKind::Text || clip.kind == NativeClipKind::Sticker {
                continue;
            }

            // The mixer only accepts sources with a decodable audio stream —
            // synthetic fallbacks report no stream, so no fake audio mixes.
            get_clip_decoder(clip_decoders, decoder_lru, clip.id, &clip.file_path);
            let has_audio = clip_decoders
                .get(&clip.id)
                .map(|d| d.has_audio_stream())
                .unwrap_or(false);
            if !has_audio {
                continue;
            }

            // T2: decode the window through the clip's own decoder
            // (interleaved FLT stereo @ 44100) and ADD it into the output —
            // overlapping clips on different tracks sum, like the C++ mixer.
            #[cfg(feature = "ffmpeg")]
            {
                let dec = match clip_decoders.get_mut(&clip.id) {
                    Some(d) => d,
                    None => continue,
                };
                let out_off = out_offset_frames as usize * 2;
                let n = max_copy as usize;
                if mix_seg_buf.len() < n {
                    mix_seg_buf.resize(n, 0.0);
                }
                let seg_ok = if clip.maintain_pitch && (clip.speed - 1.0).abs() > 0.001 {
                    // T3 (#7): decode the speed-scaled source window, then
                    // time-stretch it back so the pitch stays constant.
                    let n_src = ((n as f64) * clip.speed as f64).ceil() as usize;
                    if mix_seg_buf.len() < n_src {
                        mix_seg_buf.resize(n_src, 0.0);
                    }
                    let src_ok = dec.decode_audio_segment(src_start, &mut mix_seg_buf[..n_src], n_src, 1.0);
                    if src_ok {
                        let stretched = Self::maintain_pitch_stretch(&mix_seg_buf[..n_src], 1.0 / clip.speed as f64, 2);
                        let n_out = n.min(stretched.len());
                        for i in 0..n_out {
                            out[out_off + i] += stretched[i] * gain;
                        }
                        any_audio = true;
                    }
                    src_ok
                } else {
                    let ok = dec.decode_audio_segment(src_start, &mut mix_seg_buf[..n], n, gain);
                    if ok {
                        #[cfg(feature = "ffmpeg")]
                        {
                            let pitches = self.t4.clip_pitch.lock().unwrap();
                            if let Some(st) = pitches.get(&clip.id) {
                                let mut seg = mix_seg_buf[..n].to_vec();
                                Self::t4_pitch_shift(&mut seg, *st);
                                for i in 0..n {
                                    out[out_off + i] += seg[i];
                                }
                                any_audio = true;
                                let _ = &ok;
                            } else {
                                for i in 0..n {
                                    out[out_off + i] += mix_seg_buf[i];
                                }
                                any_audio = true;
                            }
                        }
                        #[cfg(not(feature = "ffmpeg"))]
                        {
                            for i in 0..n {
                                out[out_off + i] += mix_seg_buf[i];
                            }
                            any_audio = true;
                        }
                    }
                    ok
                };
                let _ = seg_ok;
            }
        }

        // v1.0.3: Noise suppression — one-pole low-cut (DC blocker, ≈85 Hz)
        // applied per channel to the mixed preview.
        if self.noise_suppress.load(Ordering::Relaxed) {
            const KR: f64 = 0.98;
            let mut lp_l = 0.0f64;
            let mut lp_r = 0.0f64;
            let mut i = 0usize;
            while i + 1 < count {
                let in_l = out[i] as f64;
                let in_r = out[i + 1] as f64;
                lp_l = KR * lp_l + (1.0 - KR) * in_l;
                lp_r = KR * lp_r + (1.0 - KR) * in_r;
                out[i] = (in_l - lp_l) as f32;
                out[i + 1] = (in_r - lp_r) as f32;
                i += 2;
            }
        }

        // v1.5.0 T4 (#24): realtime effect chain + spectral edits on the bus
        // (preview and export share this path).
        #[cfg(feature = "ffmpeg")]
        self.t4_process_window(&mut out[..count], start_ms);

        for s in out.iter_mut().take(count) {
            *s = s.clamp(-1.0, 1.0);
        }
        any_audio
    }

    /// T3 (#7): pitch-preserving time stretch (rubato SincFixedIn, stereo).
    #[cfg(feature = "ffmpeg")]
    fn maintain_pitch_stretch(input: &[f32], ratio: f64, channels: usize) -> Vec<f32> {
        use rubato::{Resampler, SincFixedIn, SincInterpolationParameters, SincInterpolationType, WindowFunction};
        let mut deint: Vec<Vec<f64>> = (0..channels)
            .map(|c| input.iter().skip(c).step_by(channels).map(|v| *v as f64).collect())
            .collect();
        let params = SincInterpolationParameters {
            sinc_len: 128,
            f_cutoff: 0.95,
            oversampling_factor: 256,
            interpolation: SincInterpolationType::Nearest,
            window: WindowFunction::BlackmanHarris2,
        };
        // v1.5.0-T4 (P4): cache the resampler per (ratio, channels) and call
        // reset() before each window — reset() restores the exact
        // as-constructed state, so the OUTPUT IS IDENTICAL to the old
        // construct-per-window path while skipping the expensive sinc-table
        // rebuild on every 10ms mix window (maintain-pitch used to rebuild
        // it ~100×/second of stretched audio).
        thread_local! {
            static PITCH_RESAMPLER: std::cell::RefCell<Option<((u64, usize), SincFixedIn<f64>)>> =
                const { std::cell::RefCell::new(None) };
        }
        let key = (ratio.to_bits(), channels);
        PITCH_RESAMPLER.with(|cell| {
            let mut slot = cell.borrow_mut();
            let cached = slot.as_mut().and_then(|(k, r)| if *k == key { Some(r) } else { None });
            let res = match cached {
                Some(r) => r,
                None => {
                    *slot = Some((
                        key,
                        SincFixedIn::<f64>::new(ratio, 1.2, params, 512, channels)
                            .expect("rubato init"),
                    ));
                    &mut slot.as_mut().unwrap().1
                }
            };
            res.reset();
            let out = match res.process(&mut deint, None) {
                Ok(o) => o,
                Err(_) => return input.to_vec(),
            };
            let frames = out[0].len();
            let mut result = vec![0.0f32; frames * channels];
            for f in 0..frames {
                for c in 0..channels {
                    result[f * channels + c] = out[c][f] as f32;
                }
            }
            result
        })
    }

    /// Legacy waveform — reads the single loadMedia() decoder (real PCM via
    /// FFmpeg; rectified synthetic without).
    pub fn get_audio_waveform(&self, out: &mut [f32], sample_count: usize) -> bool {
        if sample_count == 0 {
            return false;
        }
        let state = self.state.read().unwrap();
        let _rstate = self.render.lock().unwrap();
        let mut dec = state.decoder.borrow_mut();
        dec.extract_pcm_audio_samples(&mut out[..sample_count], self.volume.load())
    }

    /// v1.1.0 (PLAN 3.7): REAL timeline waveform — peak per bucket.
    /// v1.5.0 perf: served from the cached single-pass stats (the old body
    /// re-mixed thousands of 10 ms windows, each an FFmpeg seek — 70–107 s
    /// on a 3-minute MP3).
    pub fn get_timeline_waveform(&self, out: &mut [f32], sample_count: usize, _track_index: i32) -> bool {
        if sample_count == 0 || out.len() < sample_count {
            return false;
        }
        let Some((peaks, _rms)) = self.cached_timeline_audio_stats(sample_count) else {
            return false;
        };
        out[..sample_count].copy_from_slice(&peaks[..sample_count]);
        peaks.iter().any(|&p| p > 0.0)
    }

    // ------------------------------------------------------------------
    // v1.5.0 perf: timeline audio stats (waveform + RMS) — one sequential
    // decode pass, cached until any audio-affecting timeline field changes.
    // ------------------------------------------------------------------

    fn timeline_audio_signature(clips: &[NativeClip], track_gains: &[(bool, f32)], duration_ms: i64) -> u64 {
        use std::hash::{Hash, Hasher};
        let mut h = std::collections::hash_map::DefaultHasher::new();
        duration_ms.hash(&mut h);
        for c in clips {
            (c.id, c.kind as i32, c.track_index).hash(&mut h);
            c.file_path.hash(&mut h);
            (c.start_ms, c.duration_ms, c.source_in_ms).hash(&mut h);
            (c.speed.to_bits(), c.volume.to_bits()).hash(&mut h);
        }
        for t in track_gains {
            (t.0, t.1.to_bits()).hash(&mut h);
        }
        h.finish()
    }

    /// Per-bucket [peak, rms] over the whole timeline's audio, from cache when
    /// the timeline signature and bucket count are unchanged. Buckets tile
    /// [0, duration) uniformly. Reflects clip/track gains only — master FX,
    /// noise suppression and clip pitch are preview-bus processing and are
    /// deliberately not part of the display waveform.
    pub(crate) fn cached_timeline_audio_stats(&self, sample_count: usize) -> Option<(Vec<f32>, Vec<f32>)> {
        if sample_count == 0 || sample_count > 262_144 {
            return None;
        }
        // Snapshot metadata so the pass decodes a consistent timeline and the
        // stored signature describes exactly what was decoded.
        let duration = self.duration_ms.load(Ordering::Relaxed);
        if duration <= 0 {
            return None;
        }
        let (clips, track_gains) = {
            let state = self.state.read().unwrap();
            let gains: Vec<(bool, f32)> = state
                .track_states
                .iter()
                .map(|t| (t.muted, t.volume))
                .collect();
            (state.clips.clone(), gains)
        };
        let signature = Self::timeline_audio_signature(&clips, &track_gains, duration);
        {
            let cache = self.timeline_audio_stats.lock().unwrap();
            if let Some(e) = cache
                .iter()
                .find(|e| e.signature == signature && e.sample_count == sample_count)
            {
                return Some((e.peaks.clone(), e.rms.clone()));
            }
        }
        let (peaks, rms) = self.compute_timeline_audio_stats(&clips, &track_gains, duration, sample_count);
        let mut cache = self.timeline_audio_stats.lock().unwrap();
        if cache.len() >= 4 {
            cache.remove(0);
        }
        cache.push(TimelineAudioStats {
            signature,
            sample_count,
            peaks: peaks.clone(),
            rms: rms.clone(),
        });
        Some((peaks, rms))
    }

    /// One sequential decode pass: every audio-capable clip is decoded front
    /// to back in 1 s chunks — after the first chunk each call hits the
    /// decoder's continuity fast path (`seg_continuity_ms`) instead of
    /// seeking, which is what made the old per-10 ms-window mixing take
    /// minutes. Overlapping clips combine by max-abs peak / mean power per
    /// bucket (display statistics, not a phase-accurate mix).
    fn compute_timeline_audio_stats(
        &self,
        clips: &[NativeClip],
        track_gains: &[(bool, f32)],
        duration: i64,
        sample_count: usize,
    ) -> (Vec<f32>, Vec<f32>) {
        let bucket_ms = (duration / sample_count as i64).max(1);
        let mut peaks = vec![0f32; sample_count];
        let mut sq_sums = vec![0f64; sample_count];
        let mut frames = vec![0u64; sample_count];
        // Exactly 1 s of interleaved stereo @44100: decode_audio_segment then
        // records seg_continuity_ms = start + 1000, so advancing src_ms by
        // 1000 keeps every subsequent chunk seek-free.
        const CHUNK_FLOATS: usize = 88_200;
        let mut chunk = vec![0f32; CHUNK_FLOATS];

        for clip in clips {
            if clip.start_ms >= duration {
                break; // sorted by start_ms — nothing later can overlap either
            }
            if matches!(
                clip.kind,
                NativeClipKind::Image | NativeClipKind::Text | NativeClipKind::Sticker | NativeClipKind::Effect
            ) {
                continue;
            }
            // Without ffmpeg there are no real decoders — stats stay all-zero,
            // matching the old mixer path (no synthetic waveform).
            #[cfg(feature = "ffmpeg")]
            {
                let (muted, track_vol) = track_gains
                    .get(clip.track_index.max(0) as usize)
                    .copied()
                    .unwrap_or((false, 1.0));
                if muted {
                    continue;
                }
                let gain = clip.volume * track_vol;
                if gain <= 0.0 {
                    continue;
                }
                let speed = if clip.speed > 0.001 { clip.speed } else { 1.0 } as f64;
                let clip_end = clip.start_ms + clip.duration_ms;
                let src_base = clip.source_in_ms;
                let src_limit = src_base + (clip.duration_ms as f64 * speed).ceil() as i64;

                let mut rstate = self.render.lock().unwrap();
                let RenderState { clip_decoders, decoder_lru, .. } = &mut *rstate;
                get_clip_decoder(clip_decoders, decoder_lru, clip.id, &clip.file_path);
                let Some(dec) = clip_decoders.get_mut(&clip.id) else {
                    continue;
                };
                if !dec.has_audio_stream() {
                    continue;
                }

                let mut src_ms = src_base;
                while src_ms < src_limit {
                    chunk.fill(0.0); // EOF short-reads leave the tail stale otherwise
                    if !dec.decode_audio_segment(src_ms, &mut chunk, CHUNK_FLOATS, 1.0) {
                        break;
                    }
                    let base_off_s = (src_ms - src_base) as f64 / 1000.0; // seconds into source span
                    for (f, s) in chunk.chunks_exact(2).enumerate() {
                        let tl_ms = clip.start_ms as f64
                            + (base_off_s + f as f64 / 44_100.0) * 1000.0 / speed;
                        if tl_ms >= clip_end as f64 {
                            break;
                        }
                        let idx =
                            ((tl_ms as i64) / bucket_ms).clamp(0, sample_count as i64 - 1) as usize;
                        let l = s[0] * gain;
                        let r = s[1] * gain;
                        let peak = l.abs().max(r.abs());
                        if peak > peaks[idx] {
                            peaks[idx] = peak;
                        }
                        sq_sums[idx] += (l * l + r * r) as f64;
                        frames[idx] += 1;
                    }
                    src_ms += 1000;
                }
            }
        }

        let rms = sq_sums
            .iter()
            .zip(&frames)
            .map(|(&sq, &n)| {
                if n > 0 {
                    (sq / (2.0 * n as f64)).sqrt() as f32
                } else {
                    0.0
                }
            })
            .collect();
        (peaks, rms)
    }

    /// v1.1.0 (PLAN 3.6): Decode the frame of ONE timeline clip.
    pub fn get_clip_thumbnail(&self, out: &mut [u8], width: usize, height: usize, clip_id: i32, time_ms: i64) -> bool {
        if width == 0 || height == 0 || out.len() < width * height * 4 {
            return false;
        }
        let state = self.state.read().unwrap();
        let mut rstate = self.render.lock().unwrap();
        for clip in &state.clips {
            if clip.id == clip_id {
                if clip.kind == NativeClipKind::Text || clip.kind == NativeClipKind::Sticker {
                    return render_text_gdi(
                        &mut rstate.text_cache,
                        out,
                        width,
                        height,
                        &clip.text_content,
                        clip.text_font_size,
                        clip.text_color,
                    );
                }
                if clip.file_path.is_empty() {
                    return false;
                }
                let src = clip.source_in_ms + time_ms;
                let RenderState { clip_decoders, decoder_lru, .. } = &mut *rstate;
                return decode_clip_frame(
                    clip_decoders,
                    decoder_lru,
                    out,
                    clip,
                    width,
                    height,
                    src,
                    clip.filter_type,
                    clip.filter_intensity,
                );
            }
        }
        false
    }

    // ------------------------------------------------------------------
    // Audio preview thread (T1 parity stub — T2 replaces with cpal)
    // ------------------------------------------------------------------

    /// T1 parity stub — no output device (lifecycle matches the C++ thread).
    #[cfg(not(feature = "ffmpeg"))]
    fn audio_preview_loop(&self) {
        {
            let state = self.state.read().unwrap();
            if state.clips.is_empty() {
                self.audio_thread.running.store(false, Ordering::Relaxed);
                return;
            }
        }
        while !self.audio_thread.stop.load(Ordering::Relaxed) {
            std::thread::sleep(std::time::Duration::from_millis(50));
        }
        self.audio_thread.running.store(false, Ordering::Relaxed);
    }

    /// T2 (P4): real audio preview via cpal — default or selected device,
    /// 44.1 kHz; mono devices downmix, >2 channels duplicate L/R.
    #[cfg(feature = "ffmpeg")]
    fn audio_preview_loop(&self) {
        use cpal::traits::{DeviceTrait, HostTrait, StreamTrait};
        {
            let state = self.state.read().unwrap();
            if state.clips.is_empty() {
                self.audio_thread.running.store(false, Ordering::Relaxed);
                return;
            }
        }
        let host = cpal::default_host();
        let device = {
            let want = self.audio_device.lock().unwrap().clone();
            match want {
                Some(name) => host
                    .output_devices()
                    .ok()
                    .and_then(|mut it| it.find(|d| d.name().map(|n| n == name).unwrap_or(false))),
                None => host.default_output_device(),
            }
        };
        let device = match device {
            Some(d) => d,
            None => {
                self.audio_thread.running.store(false, Ordering::Relaxed);
                return;
            }
        };
        let channels = device
            .default_output_config()
            .map(|c| c.channels())
            .unwrap_or(2)
            .max(1) as usize;
        let config = cpal::StreamConfig {
            channels: channels as u16,
            sample_rate: cpal::SampleRate(44100),
            buffer_size: cpal::BufferSize::Default,
        };
        let this = EnginePtr(self);
        let err_fn = |e| eprintln!("[ghita] cpal stream error: {e}");
        let build = |fmt: cpal::SampleFormat| -> Result<Box<dyn StreamTrait>, cpal::BuildStreamError> {
            match fmt {
                cpal::SampleFormat::F32 => device
                    .build_output_stream(&config, move |d: &mut [f32], _| cpal_mix_chunk(&this, d, channels), err_fn, None)
                    .map(|s| Box::new(s) as Box<dyn StreamTrait>),
                cpal::SampleFormat::I16 => device
                    .build_output_stream(&config, move |d: &mut [i16], _| cpal_mix_chunk(&this, d, channels), err_fn, None)
                    .map(|s| Box::new(s) as Box<dyn StreamTrait>),
                cpal::SampleFormat::U16 => device
                    .build_output_stream(&config, move |d: &mut [u16], _| cpal_mix_chunk(&this, d, channels), err_fn, None)
                    .map(|s| Box::new(s) as Box<dyn StreamTrait>),
                _ => Err(cpal::BuildStreamError::StreamConfigNotSupported),
            }
        };
        let fmt = device.default_output_config().map(|c| c.sample_format()).unwrap_or(cpal::SampleFormat::F32);
        let stream = match build(fmt) {
            Ok(s) => s,
            Err(e) => {
                eprintln!("[ghita] audio preview unavailable: {e}");
                self.audio_thread.running.store(false, Ordering::Relaxed);
                return;
            }
        };
        if stream.play().is_err() {
            self.audio_thread.running.store(false, Ordering::Relaxed);
            return;
        }
        while !self.audio_thread.stop.load(Ordering::Relaxed) {
            std::thread::sleep(std::time::Duration::from_millis(50));
        }
        drop(stream);
        self.audio_thread.running.store(false, Ordering::Relaxed);
    }

    /// T2 (P4): lists available output devices (Audio Setup).
    #[cfg(feature = "ffmpeg")]
    pub fn output_device_names(&self) -> Vec<String> {
        use cpal::traits::{DeviceTrait, HostTrait};
        cpal::default_host()
            .output_devices()
            .map(|it| it.filter_map(|d| d.name().ok()).collect())
            .unwrap_or_default()
    }

    /// T2 (P4): selects the audio output device by name (None = default).
    pub fn set_audio_device(&self, name: Option<String>) {
        *self.audio_device.lock().unwrap() = name;
    }

    /// T2 (P5): sets the export audio layout ("stereo" | "5.1" | "7.1").
    pub fn set_export_channel_layout(&self, layout: &str) {
        let l = match layout {
            "5.1" | "7.1" => layout.to_string(),
            _ => "stereo".to_string(),
        };
        *self.export_channel_layout.lock().unwrap() = l;
    }

    pub fn get_export_channel_layout(&self) -> String {
        self.export_channel_layout.lock().unwrap().clone()
    }

    fn start_audio_preview_thread(&self) {
        let mut guard = self.audio_thread.thread_mutex.lock().unwrap();
        if self.audio_thread.running.load(Ordering::Relaxed) || !self.audio_preview_enabled.load(Ordering::Relaxed) {
            return;
        }
        self.audio_thread.stop.store(false, Ordering::Relaxed);
        self.audio_thread.running.store(true, Ordering::Relaxed);
        let this = EnginePtr(self);
        let handle = std::thread::spawn(move || unsafe {
            let e = &*this.raw();
            e.audio_preview_loop();
        });
        *guard = Some(handle);
    }

    fn stop_audio_preview_thread(&self) {
        let mut guard = self.audio_thread.thread_mutex.lock().unwrap();
        if !self.audio_thread.running.load(Ordering::Relaxed) {
            if let Some(h) = guard.take() {
                let _ = h.join();
            }
            return;
        }
        self.audio_thread.stop.store(true, Ordering::Relaxed);
        if let Some(h) = guard.take() {
            let _ = h.join();
        }
        self.audio_thread.running.store(false, Ordering::Relaxed);
    }

    // ------------------------------------------------------------------
    // Export pipeline
    // ------------------------------------------------------------------

    pub fn start_export(&self, output_path: &str, width: usize, height: usize, fps: i32) -> bool {
        self.start_export_ex(output_path, width, height, fps, "h264", 10_000_000, true)
    }

    pub fn start_export_ex(
        &self,
        output_path: &str,
        width: usize,
        height: usize,
        fps: i32,
        codec: &str,
        bitrate: i64,
        include_audio: bool,
    ) -> bool {
        if output_path.is_empty() {
            return false;
        }
        // v1.1.0 (PLAN 3.8): Audio-only (MP3) exports pass 0×0×0.
        if codec != "mp3" && (width == 0 || height == 0 || fps <= 0) {
            return false;
        }

        // Two-phase publish — claim the export slot under the engine lock,
        // then join the previous (finished) thread OUTSIDE it.
        {
            let mut state = self.state.write().unwrap();
            if !self.ready.load(Ordering::Relaxed) || self.is_exporting.load(Ordering::Relaxed) {
                return false;
            }
            state.export_media_path = state.loaded_file_path.clone();
            self.export_error.store(false, Ordering::Relaxed);
            state.export_output_path = output_path.to_string();
            self.is_exporting.store(true, Ordering::Relaxed);
            self.cancel_export_flag.store(false, Ordering::Relaxed);
            self.export_progress.store(0.0);
            self.export_file_size.store(0, Ordering::Relaxed);
        }

        {
            let mut guard = self.export.join_mutex.lock().unwrap();
            if let Some(h) = guard.take() {
                let _ = h.join();
            }
        }

        // SAFETY: the engine outlives this thread — destroy() always calls
        // cancelExport() (join) before the context is freed, mirroring the
        // C++ `this` capture in the export thread.
        let this = EnginePtr(self);
        let output_path = output_path.to_string();
        let codec = codec.to_string();
        let handle = std::thread::spawn(move || unsafe {
            let e = &*this.raw();
            // A panic anywhere in the export loop must never skip the flag
            // reset — is_exporting stuck true bricks every future export.
            let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
                e.run_export_loop_ex(output_path, width, height, fps, codec, bitrate, include_audio)
            }));
            if result.is_err() {
                e.export_error.store(true, Ordering::Relaxed);
            }
            e.is_exporting.store(false, Ordering::Relaxed);
        });
        *self.export.join_mutex.lock().unwrap() = Some(handle);
        true
    }

    pub fn get_export_progress(&self) -> f32 {
        self.export_progress.load()
    }

    pub fn is_exporting(&self) -> bool {
        self.is_exporting.load(Ordering::Relaxed)
    }

    pub fn cancel_export(&self) {
        // Hold the join mutex while checking is_exporting — checking before
        // locking let a cancel racing a just-finished export + immediate
        // re-export join/flag the NEW export's handle instead.
        let mut guard = self.export.join_mutex.lock().unwrap();
        if !self.is_exporting.load(Ordering::Relaxed) {
            return;
        }
        self.cancel_export_flag.store(true, Ordering::Relaxed);
        if let Some(h) = guard.take() {
            let _ = h.join();
        }
    }

    pub fn get_export_file_size(&self) -> i64 {
        self.export_file_size.load(Ordering::Relaxed)
    }

    fn run_export_loop_ex(
        &self,
        output_path: String,
        width: usize,
        height: usize,
        fps: i32,
        codec: String,
        bitrate: i64,
        mut include_audio: bool,
    ) {
        self.export_error.store(false, Ordering::Relaxed);
        // v1.1.0 (PLAN 3.12): GIF is an image container — it can't carry audio.
        if codec == "gif" {
            include_audio = false;
        }
        let total_frames = (self.duration_ms.load(Ordering::Relaxed) as f64 / 1000.0 * fps as f64) as i32;
        if codec == "mp3" {
            if self.duration_ms.load(Ordering::Relaxed) <= 0 {
                self.is_exporting.store(false, Ordering::Relaxed);
                self.export_error.store(true, Ordering::Relaxed);
                return;
            }
        } else if total_frames <= 0 {
            self.is_exporting.store(false, Ordering::Relaxed);
            self.export_error.store(true, Ordering::Relaxed);
            return;
        }

        let mut frame_buffer = vec![0u8; width.max(1) * height.max(1) * 4];
        let mut decoder = MediaDecoder::new();

        // v0.7.9: open() failure used to be ignored — fail loudly instead.
        let media_path = {
            let state = self.state.read().unwrap();
            state.export_media_path.clone()
        };
        if !decoder.open(if media_path.is_empty() { "synthetic" } else { &media_path }) {
            self.export_error.store(true, Ordering::Relaxed);
            self.is_exporting.store(false, Ordering::Relaxed);
            return;
        }

        // v0.7.8: Only a fully written output counts as success.
        #[allow(unused_variables)]
        let mut write_completed = false;

        #[cfg(feature = "ffmpeg")]
        {
            unsafe {
                self.run_export_ffmpeg(
                    &output_path, width, height, fps, &codec, bitrate, include_audio, media_path.as_str(), total_frames, &mut frame_buffer, &mut decoder,
                );
            }
            return;
        }

        #[cfg(not(feature = "ffmpeg"))]
        {
            use std::io::Write;
            // T1: no-FFmpeg fallback — raw concatenated RGBA frames.
            let mut out_file = std::fs::File::create(&output_path).ok();
            let mut written_bytes = 0i64;
            let mut frame = 0i32;
            while frame < total_frames {
                if self.cancel_export_flag.load(Ordering::Relaxed) {
                    break;
                }
                let frame_time_ms = (frame as f32 / fps as f32 * 1000.0) as i64;
                {
                    let state = self.state.read().unwrap();
                    let _rstate = self.render.lock().unwrap();
                    let mut dec = state.decoder.borrow_mut();
                    if !dec.decode_frame(
                        &mut frame_buffer,
                        width,
                        height,
                        frame_time_ms,
                        self.active_filter_type.load(Ordering::Relaxed),
                        self.filter_intensity.load(),
                    ) {
                        self.export_error.store(true, Ordering::Relaxed);
                        break;
                    }
                }
                if let Some(f) = out_file.as_mut() {
                    if f.write_all(&frame_buffer).is_err() {
                        self.export_error.store(true, Ordering::Relaxed);
                        break;
                    }
                    written_bytes += frame_buffer.len() as i64;
                    self.export_file_size.store(written_bytes, Ordering::Relaxed);
                }
                self.export_progress.store((frame + 1) as f32 / total_frames as f32);
                frame += 1;
            }
            // Only a fully-written file counts — an early `break` above (decode
            // or write error) must not mark the fallback export as complete,
            // matching the ffmpeg path's trailer-gated semantics.
            if out_file.is_some() && frame >= total_frames {
                write_completed = true;
            }
            let _ = (bitrate, include_audio);

            if !write_completed && !self.cancel_export_flag.load(Ordering::Relaxed) {
                self.export_error.store(true, Ordering::Relaxed);
            }

            self.is_exporting.store(false, Ordering::Relaxed);
            if !self.cancel_export_flag.load(Ordering::Relaxed) && !self.export_error.load(Ordering::Relaxed) {
                self.export_progress.store(1.0);
            }
        }
    }
}

/// FFmpeg export pipeline — port of the C++ `#ifdef GHITA_HAS_FFMPEG` body of
/// runExportLoopEx: encoder fallback chain (yuv420 capability probe),
/// AAC/MP3 audio with priming-delay PTS, GIF/ProRes special cases, timeline
/// compositing, trailer + real file-size capture.
#[cfg(feature = "ffmpeg")]
impl GhitaEngine {
    unsafe fn cstr(s: &str) -> FCString {
        FCString::new(s).unwrap_or_default()
    }

    unsafe fn stereo_layout() -> ffi::AVChannelLayout {
        ffi::AVChannelLayout {
            order: AV_CHANNEL_ORDER_NATIVE,
            nb_channels: 2,
            u: ffi::AVChannelLayout__bindgen_ty_1 { mask: ffi::AV_CH_LAYOUT_STEREO as u64 },
            opaque: std::ptr::null_mut(),
        }
    }

    /// Native-order layout from a channel mask (stereo / 5.1 / 7.1).
    unsafe fn layout_native(mask: u64, nb_channels: c_int) -> ffi::AVChannelLayout {
        ffi::AVChannelLayout {
            order: AV_CHANNEL_ORDER_NATIVE,
            nb_channels,
            u: ffi::AVChannelLayout__bindgen_ty_1 { mask },
            opaque: std::ptr::null_mut(),
        }
    }

    /// Encoder selection with the FFmpeg ≥ 7 pixel-format capability probe
    /// (the always-available mpeg4 encoder is the last resort).
    unsafe fn pick_encoder(names: &[&str]) -> *const ffi::AVCodec {
        for n in names {
            let cs = Self::cstr(n);
            let c = ffi::avcodec_find_encoder_by_name(cs.as_ptr());
            if c.is_null() {
                continue;
            }
            let mut fmts: *const std::ffi::c_void = std::ptr::null();
            let mut n_fmts: c_int = 0;
            if ffi::avcodec_get_supported_config(
                std::ptr::null(),
                c,
                AV_CODEC_CONFIG_PIX_FORMAT,
                0,
                &mut fmts,
                &mut n_fmts,
            ) < 0 || fmts.is_null()
            {
                continue;
            }
            let it = fmts as *const ffi::AVPixelFormat;
            let mut yuv420 = false;
            for i in 0..n_fmts {
                if *it.add(i as usize) == AV_PIX_FMT_YUV420P {
                    yuv420 = true;
                    break;
                }
            }
            if !yuv420 {
                continue;
            }
            return c;
        }
        std::ptr::null()
    }

    /// Runs the FFmpeg encoder pipeline; sets the export flags exactly like
    /// the C++ body. Only reachable with the `ffmpeg` feature.
    #[allow(clippy::too_many_arguments)]
    unsafe fn run_export_ffmpeg(
        &self,
        output_path: &str,
        width: usize,
        height: usize,
        fps: i32,
        codec: &str,
        bitrate: i64,
        mut include_audio: bool,
        _media_path: &str,
        total_frames: i32,
        frame_buffer: &mut Vec<u8>,
        decoder: &mut MediaDecoder,
    ) {
        if codec == "gif" {
            include_audio = false;
        }

        // T2-P5: audio channel layout ("stereo" | "5.1" | "7.1").
        let (audio_channels, audio_mask) = match self.get_export_channel_layout().as_str() {
            "5.1" => (6usize, ffi::AV_CH_LAYOUT_5POINT1),
            "7.1" => (8usize, ffi::AV_CH_LAYOUT_7POINT1),
            _ => (2usize, ffi::AV_CH_LAYOUT_STEREO),
        };

        let mut fmt_ctx: *mut ffi::AVFormatContext = std::ptr::null_mut();
        let mut video_stream: *mut ffi::AVStream = std::ptr::null_mut();
        let mut enc_ctx: *mut ffi::AVCodecContext = std::ptr::null_mut();
        let mut encoder: *const ffi::AVCodec = std::ptr::null();
        let mut enc_frame: *mut ffi::AVFrame = std::ptr::null_mut();
        let mut enc_pkt: *mut ffi::AVPacket = std::ptr::null_mut();
        let mut sws: *mut ffi::SwsContext = std::ptr::null_mut();
        let mut audio_enc_ctx: *mut ffi::AVCodecContext = std::ptr::null_mut();
        let mut audio_stream: *mut ffi::AVStream = std::ptr::null_mut();
        let mut audio_swr: *mut ffi::SwrContext = std::ptr::null_mut();
        let mut audio_frame: *mut ffi::AVFrame = std::ptr::null_mut();
        let mut audio_pkt: *mut ffi::AVPacket = std::ptr::null_mut();
        #[allow(unused_variables)]
        let mut write_completed = false;
        let mut failed = false;

        // Encoder selection (codec dispatch + fallback chain).
        if codec == "h265" || codec == "hevc" {
            encoder = Self::pick_encoder(&["libx265", "hevc"]);
        } else if codec == "vp9" {
            encoder = Self::pick_encoder(&["libvpx-vp9", "vp9"]);
        } else if codec == "gif" {
            encoder = ffi::avcodec_find_encoder(ffi::AVCodecID::AV_CODEC_ID_GIF);
        } else if codec == "mp3" {
            encoder = std::ptr::null();
        } else if codec == "prores" {
            encoder = ffi::avcodec_find_encoder_by_name(Self::cstr("prores_ks").as_ptr());
            if encoder.is_null() {
                encoder = ffi::avcodec_find_encoder_by_name(Self::cstr("prores").as_ptr());
            }
            if encoder.is_null() {
                encoder = ffi::avcodec_find_encoder(ffi::AVCodecID::AV_CODEC_ID_PRORES);
            }
        } else {
            encoder = Self::pick_encoder(&["libx264", "libopenh264", "h264", "mpeg4"]);
        }
        if encoder.is_null() && codec != "mp3" {
            encoder = ffi::avcodec_find_encoder(ffi::AVCodecID::AV_CODEC_ID_H264);
            if encoder.is_null() {
                encoder = ffi::avcodec_find_encoder(ffi::AVCodecID::AV_CODEC_ID_MPEG4);
            }
        }

        'export: {
            if ffi::avformat_alloc_output_context2(
                &mut fmt_ctx,
                std::ptr::null(),
                std::ptr::null(),
                Self::cstr(output_path).as_ptr(),
            ) < 0
            {
                failed = true;
            }
            if fmt_ctx.is_null() || (encoder.is_null() && codec != "mp3") {
                failed = true;
                break 'export;
            }

            // Audio encoder (must exist before avformat_write_header).
            let mut audio_codec: *const ffi::AVCodec = std::ptr::null();
            if codec == "mp3" {
                audio_codec = ffi::avcodec_find_encoder(ffi::AVCodecID::AV_CODEC_ID_MP3);
            } else if include_audio {
                audio_codec = ffi::avcodec_find_encoder(ffi::AVCodecID::AV_CODEC_ID_AAC);
            }
            if !audio_codec.is_null() {
                audio_enc_ctx = ffi::avcodec_alloc_context3(audio_codec);
                if !audio_enc_ctx.is_null() {
                    (*audio_enc_ctx).sample_rate = 44100;
                    (*audio_enc_ctx).ch_layout = Self::layout_native(audio_mask, audio_channels as c_int);
                    (*audio_enc_ctx).sample_fmt = AV_SAMPLE_FMT_FLTP;
                    if codec == "mp3" && bitrate >= 32000 && bitrate <= 320000 {
                        (*audio_enc_ctx).bit_rate = bitrate;
                    } else {
                        (*audio_enc_ctx).bit_rate = 128000;
                    }
                    if (*(*fmt_ctx).oformat).flags & ffi::AVFMT_GLOBALHEADER != 0 {
                        (*audio_enc_ctx).flags |= ffi::AV_CODEC_FLAG_GLOBAL_HEADER as c_int;
                    }
                    if ffi::avcodec_open2(audio_enc_ctx, audio_codec, std::ptr::null_mut()) >= 0 {
                        audio_stream = ffi::avformat_new_stream(fmt_ctx, audio_codec);
                        if !audio_stream.is_null() {
                            ffi::avcodec_parameters_from_context((*audio_stream).codecpar, audio_enc_ctx);
                            (*audio_stream).time_base = ffi::AVRational { num: 1, den: 44100 };
                        }
                    }
                }
            }

            // Video encoder chain (mp3 keeps encoder null).
            if !encoder.is_null() {
                enc_ctx = ffi::avcodec_alloc_context3(encoder);
                if !enc_ctx.is_null() {
                    (*enc_ctx).width = width as c_int;
                    (*enc_ctx).height = height as c_int;
                    (*enc_ctx).time_base = ffi::AVRational { num: 1, den: fps };
                    (*enc_ctx).framerate = ffi::AVRational { num: fps, den: 1 };
                    (*enc_ctx).pix_fmt = if codec == "gif" {
                        AV_PIX_FMT_BGRA
                    } else if codec == "prores" {
                        AV_PIX_FMT_YUV422P10LE
                    } else {
                        AV_PIX_FMT_YUV420P
                    };
                    (*enc_ctx).bit_rate = bitrate;
                    (*enc_ctx).gop_size = if codec == "gif" { 0 } else { fps * 2 };
                    (*enc_ctx).max_b_frames = if codec == "gif" { 0 } else { 2 };
                    if (*(*fmt_ctx).oformat).flags & ffi::AVFMT_GLOBALHEADER != 0 {
                        (*enc_ctx).flags |= ffi::AV_CODEC_FLAG_GLOBAL_HEADER as c_int;
                    }
                    if ffi::avcodec_open2(enc_ctx, encoder, std::ptr::null_mut()) >= 0 {
                        video_stream = ffi::avformat_new_stream(fmt_ctx, encoder);
                        if !video_stream.is_null() {
                            ffi::avcodec_parameters_from_context((*video_stream).codecpar, enc_ctx);
                        }
                    }
                }
            }

            // Open output file.
            if (*(*fmt_ctx).oformat).flags & ffi::AVFMT_NOFILE == 0 {
                if ffi::avio_open(&mut (*fmt_ctx).pb, Self::cstr(output_path).as_ptr(), 2) < 0 {
                    failed = true;
                    break 'export;
                }
            }

            if ffi::avformat_write_header(fmt_ctx, std::ptr::null_mut()) < 0 {
                failed = true;
                break 'export;
            }

            // Video encode resources.
            if !encoder.is_null() {
                enc_frame = ffi::av_frame_alloc();
                (*enc_frame).width = width as c_int;
                (*enc_frame).height = height as c_int;
                (*enc_frame).format = if codec == "gif" {
                    AV_PIX_FMT_BGRA as c_int
                } else if codec == "prores" {
                    AV_PIX_FMT_YUV422P10LE as c_int
                } else {
                    AV_PIX_FMT_YUV420P as c_int
                };
                ffi::av_frame_get_buffer(enc_frame, 0);
                enc_pkt = ffi::av_packet_alloc();

                let sws_dst = if codec == "gif" {
                    AV_PIX_FMT_BGRA
                } else if codec == "prores" {
                    AV_PIX_FMT_YUV422P10LE
                } else {
                    AV_PIX_FMT_YUV420P
                };
                sws = ffi::sws_getContext(
                    width as c_int,
                    height as c_int,
                    AV_PIX_FMT_RGBA,
                    width as c_int,
                    height as c_int,
                    sws_dst,
                    ffi::SwsFlags::SWS_BILINEAR as c_int,
                    std::ptr::null_mut(),
                    std::ptr::null_mut(),
                    std::ptr::null_mut(),
                );
            }

            // Audio encode resources (shared by video-with-audio and mp3 paths).
            if !audio_enc_ctx.is_null() && !audio_stream.is_null() {
                let flt = Self::stereo_layout();
                let fltp = Self::layout_native(audio_mask, audio_channels as c_int);
                if ffi::swr_alloc_set_opts2(
                    &mut audio_swr,
                    &fltp,
                    AV_SAMPLE_FMT_FLTP,
                    44100,
                    &flt,
                    AV_SAMPLE_FMT_FLT,
                    44100,
                    0,
                    std::ptr::null_mut(),
                ) >= 0
                {
                    ffi::swr_init(audio_swr);
                }
                audio_frame = ffi::av_frame_alloc();
                (*audio_frame).format = AV_SAMPLE_FMT_FLTP as c_int;
                ffi::av_channel_layout_copy(&mut (*audio_frame).ch_layout, &fltp);
                (*audio_frame).sample_rate = 44100;
                (*audio_frame).nb_samples = if (*audio_enc_ctx).frame_size > 0 {
                    (*audio_enc_ctx).frame_size
                } else {
                    1024
                };
                ffi::av_frame_get_buffer(audio_frame, 0);
                audio_pkt = ffi::av_packet_alloc();
            }

            let frame_samples = (44100.0 / fps.max(1) as f64).round().max(1.0) as i32;
            let audio_window_ms = ((frame_samples as f64 * 1000.0 / 44100.0).ceil().max(1.0)) as i64;
            let mut mix_buf = vec![0.0f32; (frame_samples as usize) * 2];
            let mut audio_pts_accum: i64 = 0;
            let audio_delay = if !audio_enc_ctx.is_null() {
                let d = (*audio_enc_ctx).delay;
                if d > 0 { d as i64 } else { 1024 }
            } else {
                0
            };

            // Video encode loop.
            if !encoder.is_null() {
                for frame in 0..total_frames {
                    if self.cancel_export_flag.load(Ordering::Relaxed) {
                        break;
                    }
                    let frame_time_ms = (frame as f32 / fps as f32 * 1000.0) as i64;

                    // Render the ACTUAL timeline, or the legacy decoder path.
                    {
                        let state = self.state.read().unwrap();
                        let mut rstate = self.render.lock().unwrap();
                        if !state.clips.is_empty() {
                            // v1.5.0-T5 (P2): export — every frame is unique,
                            // cache stays OFF.
                            render_timeline_frame(
                                &state,
                                &mut rstate,
                                frame_buffer,
                                width,
                                height,
                                frame_time_ms,
                                true,
                                self.active_filter_type.load(Ordering::Relaxed),
                                self.filter_intensity.load(),
                                false,
                            );
                        } else if !decoder.decode_frame(
                            frame_buffer,
                            width,
                            height,
                            frame_time_ms,
                            self.active_filter_type.load(Ordering::Relaxed),
                            self.filter_intensity.load(),
                        ) {
                            self.export_error.store(true, Ordering::Relaxed);
                            failed = true;
                            break;
                        }
                    }
                    if failed {
                        break;
                    }

                    // RGBA → destination format.
                    if !sws.is_null() {
                        let src_slice = [frame_buffer.as_ptr()];
                        let src_stride = [(width * 4) as c_int];
                        ffi::sws_scale(
                            sws,
                            src_slice.as_ptr(),
                            src_stride.as_ptr(),
                            0,
                            height as c_int,
                            (*enc_frame).data.as_ptr(),
                            (*enc_frame).linesize.as_ptr(),
                        );
                    }

                    // Mix + encode this frame's audio window.
                    if !audio_enc_ctx.is_null() && !audio_swr.is_null() && !audio_frame.is_null() && !audio_pkt.is_null() {
                        self.mix_audio_window(
                            frame_time_ms,
                            frame_time_ms + audio_window_ms,
                            &mut mix_buf,
                            (frame_samples as usize) * 2,
                            true,
                        );
                        let mut consumed = 0i32;
                        while consumed < frame_samples {
                            let n = ((*audio_frame).nb_samples).min(frame_samples - consumed);
                            let src = mix_buf[(consumed as usize) * 2..].as_ptr() as *const u8;
                            let in_planes = [src, src];
                            let mut out_planes: Vec<*mut u8> =
                                (0..audio_channels).map(|c| (*audio_frame).data[c]).collect();
                            let got = ffi::swr_convert(
                                audio_swr,
                                out_planes.as_ptr(),
                                n,
                                in_planes.as_ptr(),
                                n,
                            );
                            if got > 0 {
                                // v0.8.0: offset by the encoder priming delay
                                // (AAC = 1024) so pts stays non-negative.
                                (*audio_frame).pts = audio_pts_accum + audio_delay;
                                audio_pts_accum += got as i64;
                                ffi::avcodec_send_frame(audio_enc_ctx, audio_frame);
                                while ffi::avcodec_receive_packet(audio_enc_ctx, audio_pkt) == 0 {
                                    ffi::av_packet_rescale_ts(
                                        audio_pkt,
                                        (*audio_enc_ctx).time_base,
                                        (*audio_stream).time_base,
                                    );
                                    (*audio_pkt).stream_index = (*audio_stream).index;
                                    if ffi::av_interleaved_write_frame(fmt_ctx, audio_pkt) < 0 {
                                        self.export_error.store(true, Ordering::Relaxed);
                                        failed = true;
                                        break;
                                    }
                                    ffi::av_packet_unref(audio_pkt);
                                }
                                if failed {
                                    break;
                                }
                            }
                            consumed += n;
                        }
                        if failed {
                            break;
                        }
                    }

                    (*enc_frame).pts = frame as i64;
                    let mut ret = ffi::avcodec_send_frame(enc_ctx, enc_frame);
                    while ret >= 0 {
                        ret = ffi::avcodec_receive_packet(enc_ctx, enc_pkt);
                        if ret == 0 {
                            ffi::av_packet_rescale_ts(
                                enc_pkt,
                                (*enc_ctx).time_base,
                                (*video_stream).time_base,
                            );
                            (*enc_pkt).stream_index = (*video_stream).index;
                            if ffi::av_interleaved_write_frame(fmt_ctx, enc_pkt) < 0 {
                                self.export_error.store(true, Ordering::Relaxed);
                                failed = true;
                                break;
                            }
                            ffi::av_packet_unref(enc_pkt);
                        } else {
                            break;
                        }
                    }
                    if failed {
                        break;
                    }

                    self.export_progress.store((frame + 1) as f32 / total_frames as f32);
                }

                // Flush the video encoder.
                if !failed {
                    ffi::avcodec_send_frame(enc_ctx, std::ptr::null_mut());
                    while ffi::avcodec_receive_packet(enc_ctx, enc_pkt) == 0 {
                        ffi::av_packet_rescale_ts(enc_pkt, (*enc_ctx).time_base, (*video_stream).time_base);
                        (*enc_pkt).stream_index = (*video_stream).index;
                        if ffi::av_interleaved_write_frame(fmt_ctx, enc_pkt) < 0 {
                            self.export_error.store(true, Ordering::Relaxed);
                            failed = true;
                            break;
                        }
                        ffi::av_packet_unref(enc_pkt);
                    }
                }
            }

            // Audio-only (MP3) encode loop.
            if encoder.is_null() && !audio_enc_ctx.is_null() && !audio_swr.is_null()
                && !audio_frame.is_null() && !audio_pkt.is_null() && !audio_stream.is_null()
            {
                let total_ms = self.duration_ms.load(Ordering::Relaxed).max(1);
                let chunk_samples = if (*audio_frame).nb_samples > 0 { (*audio_frame).nb_samples } else { 1152 };
                let chunk_ms = ((chunk_samples as f64 * 1000.0 / 44100.0).ceil().max(1.0)) as i64;
                let mut audio_pts_accum = 0i64;
                let audio_delay = if (*audio_enc_ctx).delay > 0 { (*audio_enc_ctx).delay as i64 } else { 0 };
                let mut pos_ms = 0i64;
                let mut mix_buf = vec![0.0f32; (chunk_samples as usize) * 2];
                while pos_ms < total_ms && !self.cancel_export_flag.load(Ordering::Relaxed) {
                    self.mix_audio_window(
                        pos_ms,
                        (pos_ms + chunk_ms).min(total_ms),
                        &mut mix_buf,
                        (chunk_samples as usize) * 2,
                        true,
                    );
                    let out_planes = [(*audio_frame).data[0], (*audio_frame).data[1]];
                    let in_plane = mix_buf.as_ptr() as *const u8;
                    let in_planes = [in_plane, in_plane];
                    let got = ffi::swr_convert(
                        audio_swr,
                        out_planes.as_ptr(),
                        chunk_samples,
                        in_planes.as_ptr(),
                        chunk_samples,
                    );
                    if got > 0 {
                        (*audio_frame).pts = audio_pts_accum + audio_delay;
                        audio_pts_accum += got as i64;
                        ffi::avcodec_send_frame(audio_enc_ctx, audio_frame);
                        while ffi::avcodec_receive_packet(audio_enc_ctx, audio_pkt) == 0 {
                            ffi::av_packet_rescale_ts(audio_pkt, (*audio_enc_ctx).time_base, (*audio_stream).time_base);
                            (*audio_pkt).stream_index = (*audio_stream).index;
                            if ffi::av_interleaved_write_frame(fmt_ctx, audio_pkt) < 0 {
                                self.export_error.store(true, Ordering::Relaxed);
                                failed = true;
                                break;
                            }
                            ffi::av_packet_unref(audio_pkt);
                        }
                    }
                    if failed {
                        break;
                    }
                    pos_ms += chunk_ms;
                    self.export_progress.store(pos_ms as f32 / total_ms as f32);
                }
            }

            // Flush the audio encoder. audio_stream can be null when
            // avformat_new_stream failed while the encoder opened — guard the
            // deref or the export thread crashes instead of failing cleanly.
            if !failed && !audio_enc_ctx.is_null() && !audio_stream.is_null() {
                ffi::avcodec_send_frame(audio_enc_ctx, std::ptr::null_mut());
                while !audio_pkt.is_null() && ffi::avcodec_receive_packet(audio_enc_ctx, audio_pkt) == 0 {
                    ffi::av_packet_rescale_ts(audio_pkt, (*audio_enc_ctx).time_base, (*audio_stream).time_base);
                    (*audio_pkt).stream_index = (*audio_stream).index;
                    if ffi::av_interleaved_write_frame(fmt_ctx, audio_pkt) < 0 {
                        self.export_error.store(true, Ordering::Relaxed);
                        failed = true;
                        break;
                    }
                    ffi::av_packet_unref(audio_pkt);
                }
            }

            // Trailer — only a successful trailer counts as a completed write.
            if !failed {
                if ffi::av_write_trailer(fmt_ctx) >= 0 {
                    write_completed = true;
                } else {
                    self.export_error.store(true, Ordering::Relaxed);
                }
                if !(*fmt_ctx).pb.is_null() {
                    self.export_file_size.store(ffi::avio_size((*fmt_ctx).pb), Ordering::Relaxed);
                }
            }
        } // 'export

        // Cleanup (every exit path).
        if !sws.is_null() {
            ffi::sws_freeContext(sws);
        }
        if !enc_pkt.is_null() {
            ffi::av_packet_free(&mut enc_pkt);
        }
        if !enc_frame.is_null() {
            ffi::av_frame_free(&mut enc_frame);
        }
        if !enc_ctx.is_null() {
            ffi::avcodec_free_context(&mut enc_ctx);
        }
        if !audio_swr.is_null() {
            ffi::swr_free(&mut audio_swr);
        }
        if !audio_pkt.is_null() {
            ffi::av_packet_free(&mut audio_pkt);
        }
        if !audio_frame.is_null() {
            ffi::av_frame_free(&mut audio_frame);
        }
        if !audio_enc_ctx.is_null() {
            ffi::avcodec_free_context(&mut audio_enc_ctx);
        }
        if !fmt_ctx.is_null() {
            if (*(*fmt_ctx).oformat).flags & ffi::AVFMT_NOFILE == 0 {
                ffi::avio_closep(&mut (*fmt_ctx).pb);
            }
            ffi::avformat_free_context(fmt_ctx);
        }

        // v0.8.0: real output size from disk (avio_size on the closed pb was
        // unreliable and reported 0 for a valid file).
        if write_completed {
            if let Ok(md) = std::fs::metadata(output_path) {
                self.export_file_size.store(md.len() as i64, Ordering::Relaxed);
            }
        }

        if !write_completed && !self.cancel_export_flag.load(Ordering::Relaxed) {
            self.export_error.store(true, Ordering::Relaxed);
        }
        self.is_exporting.store(false, Ordering::Relaxed);
        if !self.cancel_export_flag.load(Ordering::Relaxed) && !self.export_error.load(Ordering::Relaxed) {
            self.export_progress.store(1.0);
        }
    }
}

/// Parses an SRT/VTT timing line into (start_ms, end_ms).
fn parse_timing(line: &str, _is_vtt: bool) -> (i64, i64) {
    let arrow = line.find("-->").unwrap_or(0);
    let start_part = line[..arrow].trim();
    let end_part = line[arrow + 3..].trim().split_whitespace().next().unwrap_or("");
    let parse = |p: &str| -> i64 {
        let (hms, frac) = match p.find(['.', ',']) {
            Some(i) => (&p[..i], &p[i + 1..]),
            None => (p, ""),
        };
        let mut ms = 0i64;
        for part in hms.split(':') {
            let v: i64 = part.trim().parse().unwrap_or(0);
            ms = ms * 60 + v;
        }
        ms * 1000 + frac.parse::<i64>().unwrap_or(0)
    };
    (parse(start_part), parse(end_part))
}

impl Drop for GhitaEngine {
    fn drop(&mut self) {
        // Join the input-capture thread FIRST — it derefs a raw pointer to
        // this engine and must be gone before any field is dropped.
        #[cfg(feature = "ffmpeg")]
        self.join_input_capture();
        self.cancel_export();
        self.stop_audio_preview_thread();
        self.is_playing.store(false, Ordering::Relaxed);
        self.ready.store(false, Ordering::Relaxed);
    }
}
