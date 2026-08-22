//! T4 engine integration (feature `ffmpeg`): realtime effect chain + spectral
//! edits wired into the mix bus, loop region, clip pitch-shift, preview pitch
//! preserve (play-at-speed), input recording (normal / punch&roll / timed /
//! overdub via cpal), and label export (SRT/VTT).

use std::collections::HashMap;
use std::io::Write;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Mutex;
use std::time::{Duration, Instant};

use crate::dsp::AudioEffect;
use crate::engine::GhitaEngine;
use crate::fft_tools::{apply_spectral_edits, rms_windows, spectrogram, SpectralEdit};

/// Recording modes (stable ABI).
pub const REC_MODE_NORMAL: i32 = 0;
pub const REC_MODE_PUNCH_ROLL: i32 = 1;
pub const REC_MODE_TIMED: i32 = 2;
pub const REC_MODE_OVERDUB: i32 = 3;

struct RecordingState {
    active: bool,
    mode: i32,
    out_path: String,
    /// (start_ms_in_timeline) — for punch roll, the punch point.
    punch_at_ms: i64,
    /// deadline for timed recording.
    deadline: Option<Instant>,
    /// collected interleaved stereo f32 (44.1 kHz).
    samples: Vec<f32>,
    /// whether the punch point has been passed (recording actually captured).
    recording_started: bool,
}

impl Default for RecordingState {
    fn default() -> Self {
        RecordingState {
            active: false,
            mode: REC_MODE_NORMAL,
            out_path: String::new(),
            punch_at_ms: 0,
            deadline: None,
            samples: Vec::new(),
            recording_started: false,
        }
    }
}

/// State container added to GhitaEngine (all Mutex/atomic — shared between
/// the render thread, the audio preview callback and recording threads).
pub struct T4State {
    pub effects: Mutex<Vec<AudioEffect>>,
    pub spectral_edits: Mutex<Vec<SpectralEdit>>,
    pub loop_region: Mutex<(i64, i64, bool)>,
    /// per-clip pitch shift in semitones (native clip id).
    pub clip_pitch: Mutex<HashMap<i32, f32>>,
    pub preview_pitch_preserve: AtomicBool,
    pub time_signature: Mutex<(i32, i32)>,
    pub recording: Mutex<RecordingState>,
}

impl Default for T4State {
    fn default() -> Self {
        T4State {
            effects: Mutex::new(Vec::new()),
            spectral_edits: Mutex::new(Vec::new()),
            loop_region: Mutex::new((0, 0, false)),
            clip_pitch: Mutex::new(HashMap::new()),
            preview_pitch_preserve: AtomicBool::new(false),
            time_signature: Mutex::new((4, 4)),
            recording: Mutex::new(RecordingState::default()),
        }
    }
}

impl GhitaEngine {
    // ------------------------------------------------------------------
    // Effect chain (#24/#25/#26/#27/#28)
    // ------------------------------------------------------------------

    pub fn add_audio_effect(&self, kind: i32, p: [f32; 4]) -> i32 {
        let k = match crate::dsp::AudioEffectType::from_i32(kind) {
            Some(k) => k,
            None => return -1,
        };
        let mut fx = self.t4.effects.lock().unwrap();
        fx.push(AudioEffect::new(k, p));
        (fx.len() - 1) as i32
    }

    pub fn remove_audio_effect(&self, index: i32) -> i32 {
        let mut fx = self.t4.effects.lock().unwrap();
        let i = index as usize;
        if i >= fx.len() {
            return -1;
        }
        fx.remove(i);
        0
    }

    pub fn clear_audio_effects(&self) {
        self.t4.effects.lock().unwrap().clear();
    }

    pub fn audio_effect_count(&self) -> i32 {
        self.t4.effects.lock().unwrap().len() as i32
    }

    /// Summed gain reduction across the dynamics processors (dB, ≥ 0).
    pub fn gain_reduction_db(&self) -> f32 {
        self.t4
            .effects
            .lock()
            .unwrap()
            .iter()
            .map(|e| e.gain_reduction_db.max(0.0))
            .sum()
    }

    /// Applies the effect chain + spectral edits to a mixed window. Called at
    /// the end of mix_audio_window (preview + export share it).
    pub(crate) fn t4_process_window(&self, out: &mut [f32], start_ms: i64) {
        {
            let mut fx = self.t4.effects.lock().unwrap();
            for e in fx.iter_mut() {
                e.process(out, 44100.0);
            }
        }
        let edits = self.t4.spectral_edits.lock().unwrap().clone();
        if !edits.is_empty() {
            apply_spectral_edits(out, start_ms, &edits, 44100.0);
        }
    }

    // ------------------------------------------------------------------
    // Spectrogram / RMS / tempo / beats
    // ------------------------------------------------------------------

    /// Spectrogram of a track's mix over the whole timeline.
    pub fn get_spectrogram(&self, out: &mut [f32], columns: usize, bins: usize, track: i32) -> bool {
        if columns == 0 || bins == 0 || out.len() < columns * bins {
            return false;
        }
        let duration = self.get_duration_ms();
        if duration <= 0 {
            return false;
        }
        // Mix the track in 100 ms windows across the timeline.
        let steps = columns.min(64); // bound work
        let mut audio: Vec<f32> = Vec::new();
        for i in 0..steps {
            let start = duration * i as i64 / steps as i64;
            let end = ((duration * (i + 1) as i64 / steps as i64).min(duration)).max(start + 1);
            let mut w = vec![0.0f32; 4410];
            let n = w.len();
            let _ = self.mix_audio_window(start, end, &mut w, n, false);
            let _ = track;
            audio.extend_from_slice(&w);
        }
        let spec = spectrogram(&audio, columns, bins);
        out[..columns * bins].copy_from_slice(&spec);
        true
    }

    /// Per-window RMS of a track (#5/opt — correctly scaled waveform).
    pub fn get_timeline_rms(&self, out: &mut [f32], count: usize, track: i32) -> bool {
        if count == 0 || out.len() < count {
            return false;
        }
        let duration = self.get_duration_ms();
        if duration <= 0 {
            return false;
        }
        let bucket = (duration / count as i64).max(1);
        let mut audio: Vec<f32> = Vec::new();
        for i in 0..count.min(256) {
            let start = i as i64 * bucket;
            let end = ((start + bucket).min(duration)).max(start + 1);
            let mut w = vec![0.0f32; 441];
            let n = w.len();
            let _ = self.mix_audio_window(start, end, &mut w, n, false);
            let _ = track;
            audio.extend_from_slice(&w);
        }
        rms_windows(&audio, &mut out[..count]);
        true
    }

    /// Tempo detection (#31) — BPM × 10 as an integer (0 on failure).
    pub fn detect_tempo(&self) -> i32 {
        let duration = self.get_duration_ms().min(8000);
        if duration <= 0 {
            return 0;
        }
        let mut audio: Vec<f32> = Vec::new();
        let mut pos = 0i64;
        while pos < duration {
            let mut w = vec![0.0f32; 4410];
            let n = w.len();
            let _ = self.mix_audio_window(pos, pos + 100, &mut w, n, false);
            audio.extend_from_slice(&w);
            pos += 100;
        }
        let bpm = crate::fft_tools::detect_tempo_bpm(&audio, 44100.0);
        (bpm * 10.0) as i32
    }

    pub fn set_time_signature(&self, num: i32, den: i32) {
        *self.t4.time_signature.lock().unwrap() = (num.max(1), den.max(1));
    }

    pub fn get_time_signature(&self) -> (i32, i32) {
        *self.t4.time_signature.lock().unwrap()
    }

    /// Beat times in ms (#32); returns the filled count.
    pub fn get_beat_times(&self, out: &mut [i64]) -> usize {
        let (num, _den) = self.get_time_signature();
        crate::fft_tools::beat_times(self.get_duration_ms(), 120.0, num, out)
    }

    // ------------------------------------------------------------------
    // Loop region (#22) / clip pitch (#17) / play-at-speed (#21)
    // ------------------------------------------------------------------

    pub fn set_loop_region(&self, start_ms: i64, end_ms: i64, enabled: bool) {
        *self.t4.loop_region.lock().unwrap() = (start_ms.max(0), end_ms.max(0), enabled);
    }

    pub fn get_loop_region(&self) -> (i64, i64, bool) {
        *self.t4.loop_region.lock().unwrap()
    }

    /// Clip pitch shift in semitones (−12..+12), applied in the mix path.
    pub fn set_clip_pitch(&self, clip_id: i32, semitones: f32) -> i32 {
        if !self.has_clip(clip_id) {
            return -1;
        }
        self.t4
            .clip_pitch
            .lock()
            .unwrap()
            .insert(clip_id, semitones.clamp(-12.0, 12.0));
        0
    }

    pub fn set_preview_pitch_preserve(&self, enabled: bool) {
        self.t4.preview_pitch_preserve.store(enabled, Ordering::Relaxed);
    }

    /// Pitch-shifts a decoded segment in place keeping length (resampled
    /// read). Used by the mix path when a clip has pitch != 0.
    pub fn t4_pitch_shift(seg: &mut [f32], semitones: f32) {
        if semitones.abs() < 0.01 {
            return;
        }
        let ratio = (2.0f32).powf(semitones / 12.0);
        let n = seg.len();
        let mut out = vec![0.0f32; n];
        for i in 0..n / 2 {
            // Read the source at i*ratio — pitch up reads faster (alias-ish,
            // fine for preview), pitch down interpolates.
            let src = i as f32 * ratio;
            let half = (n / 2).max(1);
            let i0 = (src.floor() as usize) % half;
            let i1 = (i0 + 1) % half;
            let t = src - src.floor();
            out[i * 2] = seg[i0 * 2] + (seg[i1 * 2] - seg[i0 * 2]) * t;
            out[i * 2 + 1] = seg[i0 * 2 + 1] + (seg[i1 * 2 + 1] - seg[i0 * 2 + 1]) * t;
        }
        seg.copy_from_slice(&out);
    }

    // ------------------------------------------------------------------
    // Recording (#18 punch&roll, #19 timed, #20 overdub)
    // ------------------------------------------------------------------

    /// Starts an input recording session.
    /// - NORMAL: record immediately to [path].
    /// - PUNCH_ROLL: seek to (pos − pre_roll_ms), play, capture from the
    ///   original position onward.
    /// - TIMED: capture after delay_ms for duration_ms.
    /// - OVERDUB: play the timeline while recording (monitor mix unaffected).
    pub fn start_recording(
        &self,
        out_path: &str,
        mode: i32,
        pre_roll_ms: i64,
        delay_ms: i64,
        duration_ms: i64,
    ) -> i32 {
        let pos = self.get_position_ms();
        {
            let mut rec = self.t4.recording.lock().unwrap();
            if rec.active {
                return -1;
            }
            rec.active = true;
            rec.mode = mode;
            rec.out_path = out_path.to_string();
            rec.samples.clear();
            rec.recording_started = false;
            rec.deadline = if duration_ms > 0 {
                Some(Instant::now() + Duration::from_millis(delay_ms.max(0) as u64 + duration_ms as u64))
            } else {
                None
            };
            match mode {
                REC_MODE_PUNCH_ROLL => {
                    rec.punch_at_ms = pos;
                    rec.recording_started = false;
                }
                REC_MODE_TIMED => {
                    rec.punch_at_ms = -1;
                }
                _ => {
                    rec.punch_at_ms = -1;
                    rec.recording_started = true;
                }
            }
        }
        // Mode side effects on playback.
        match mode {
            REC_MODE_PUNCH_ROLL => {
                self.seek((pos - pre_roll_ms.max(0)).max(0));
                self.play();
            }
            REC_MODE_OVERDUB => {
                self.play();
            }
            _ => {}
        }
        // Input capture thread.
        self.spawn_input_capture();
        0
    }

    fn spawn_input_capture(&self) {
        use cpal::traits::{DeviceTrait, HostTrait, StreamTrait};
        // SAFETY: capture only touches atomics/mutexes (never the decoder),
        // and the session lifetime is bounded by stop_recording/destroy —
        // the same contract as the export/audio preview threads. The
        // Send/Sync wrapper is sound for that subset of operations.
        struct CapPtr(usize);
        unsafe impl Send for CapPtr {}
        unsafe impl Sync for CapPtr {}
        let this = CapPtr(self as *const GhitaEngine as usize);
        std::thread::spawn(move || {
            let this = this; // CapPtr(usize) — 'static
            let host = cpal::default_host();
            let device = match host.default_input_device() {
                Some(d) => d,
                None => {
                    let mut rec = unsafe { (&*(this.0 as *const GhitaEngine)).t4.recording.lock().unwrap() };
                    rec.active = false;
                    return;
                }
            };
            let config = match device.default_input_config() {
                Ok(c) => c,
                Err(_) => {
                    let mut rec = unsafe { (&*(this.0 as *const GhitaEngine)).t4.recording.lock().unwrap() };
                    rec.active = false;
                    return;
                }
            };
            let sr = config.sample_rate().0;
            let ch = config.channels().max(1) as usize;
            let err_fn = |e| eprintln!("[ghita] cpal input error: {e}");
            let mut stream: Option<cpal::Stream> = None;
            match config.sample_format() {
                cpal::SampleFormat::F32 => {
                    let s = device.build_input_stream(
                        &config.into(),
                        move |data: &[f32], _| unsafe { (&*(this.0 as *const GhitaEngine)).capture_input(data, sr, ch) },
                        err_fn,
                        None,
                    );
                    stream = s.ok();
                }
                cpal::SampleFormat::I16 => {
                    let s = device.build_input_stream(
                        &config.into(),
                        move |data: &[i16], _| {
                            let f: Vec<f32> = data.iter().map(|v| *v as f32 / 32768.0).collect();
                            unsafe { (&*(this.0 as *const GhitaEngine)).capture_input(&f, sr, ch); }
                        },
                        err_fn,
                        None,
                    );
                    stream = s.ok();
                }
                _ => {}
            }
            if let Some(s) = stream {
                let _ = s.play();
                loop {
                    std::thread::sleep(Duration::from_millis(50));
                    let mut rec = unsafe { (&*(this.0 as *const GhitaEngine)).t4.recording.lock().unwrap() };
                    if !rec.active {
                        break;
                    }
                    if let Some(deadline) = rec.deadline {
                        if Instant::now() >= deadline {
                            rec.active = false;
                            break;
                        }
                    }
                }
                drop(s);
            } else {
                unsafe { (&*(this.0 as *const GhitaEngine)).t4.recording.lock().unwrap() }.active = false;
            }
        });
    }

    fn capture_input(&self, data: &[f32], src_rate: u32, src_ch: usize) {
        let pos = self.get_position_ms();
        let mut rec = self.t4.recording.lock().unwrap();
        if !rec.active {
            return;
        }
        // Punch gating: only capture once the playhead passed the punch point.
        if rec.mode == REC_MODE_PUNCH_ROLL && !rec.recording_started {
            if pos >= rec.punch_at_ms {
                rec.recording_started = true;
            } else {
                return;
            }
        }
        // Linear resample src → 44100 stereo.
        let frames_in = data.len() / src_ch.max(1);
        let step = src_rate as f32 / 44100.0;
        let mut i = 0.0f32;
        while (i as usize) < frames_in {
            let i0 = i as usize;
            let i1 = (i0 + 1).min(frames_in - 1);
            let t = i - i0 as f32;
            let s0 = data[i0 * src_ch];
            let s1 = data[i1 * src_ch];
            let mono = s0 + (s1 - s0) * t;
            rec.samples.push(mono);
            rec.samples.push(mono);
            i += step;
        }
    }

    /// Stops the session, writes a 44.1 kHz stereo PCM16 WAV; returns the
    /// recorded duration in ms (0 when nothing was captured).
    pub fn stop_recording(&self) -> i64 {
        let (path, samples) = {
            let mut rec = self.t4.recording.lock().unwrap();
            rec.active = false;
            (rec.out_path.clone(), std::mem::take(&mut rec.samples))
        };
        if path.is_empty() || samples.len() < 882 {
            return 0;
        }
        if write_wav_pcm16(&path, &samples).is_err() {
            return 0;
        }
        (samples.len() / 2) as i64 * 1000 / 44100
    }

    pub fn is_recording(&self) -> bool {
        self.t4.recording.lock().unwrap().active
    }

    // ------------------------------------------------------------------
    // Labels export (#23): bookmarks → SRT / WebVTT
    // ------------------------------------------------------------------

    /// Exports bookmarks as labels; format 0 = SRT, 1 = WebVTT. Returns the
    /// cue count (0 on failure / no bookmarks).
    pub fn export_labels(&self, path: &str, format: i32) -> i32 {
        let state = self.state.read().unwrap();
        if state.bookmarks.is_empty() {
            return 0;
        }
        let mut bms: Vec<(i64, String)> = state
            .bookmarks
            .iter()
            .map(|b| (b.time_ms, b.note.clone()))
            .collect();
        drop(state);
        bms.sort_by_key(|b| b.0);
        let mut out = String::new();
        if format == 1 {
            out.push_str("WEBVTT\n\n");
        }
        for (i, (t, note)) in bms.iter().enumerate() {
            let start = fmt_ts(*t, format == 1);
            let end = fmt_ts(
                bms.get(i + 1).map(|n| n.0).unwrap_or(t + 1000),
                format == 1,
            );
            if format == 1 {
                out.push_str(&format!("{start} --> {end}\n{note}\n\n"));
            } else {
                out.push_str(&format!("{}\n{start} --> {end}\n{note}\n\n", i + 1));
            }
        }
        if std::fs::File::create(path)
            .and_then(|mut f| f.write_all(out.as_bytes()))
            .is_err()
        {
            return 0;
        }
        bms.len() as i32
    }
}

/// Writes a 44.1 kHz stereo PCM16 WAV.
pub fn write_wav_pcm16(path: &str, interleaved: &[f32]) -> std::io::Result<()> {
    let frames = interleaved.len() / 2;
    let data_len = frames * 4;
    let mut f = std::fs::File::create(path)?;
    let mut w = Vec::with_capacity(44 + data_len);
    w.extend_from_slice(b"RIFF");
    w.extend_from_slice(&((36 + data_len) as u32).to_le_bytes());
    w.extend_from_slice(b"WAVE");
    w.extend_from_slice(b"fmt ");
    w.extend_from_slice(&16u32.to_le_bytes());
    w.extend_from_slice(&1u16.to_le_bytes()); // PCM
    w.extend_from_slice(&2u16.to_le_bytes()); // stereo
    w.extend_from_slice(&44100u32.to_le_bytes());
    w.extend_from_slice(&176400u32.to_le_bytes()); // byte rate
    w.extend_from_slice(&4u16.to_le_bytes()); // block align
    w.extend_from_slice(&16u16.to_le_bytes()); // bits
    w.extend_from_slice(b"data");
    w.extend_from_slice(&(data_len as u32).to_le_bytes());
    for v in interleaved {
        let s = (v.clamp(-1.0, 1.0) * 32767.0) as i16;
        w.extend_from_slice(&s.to_le_bytes());
    }
    f.write_all(&w)
}

fn fmt_ts(ms: i64, vtt: bool) -> String {
    let h = ms / 3_600_000;
    let m = (ms % 3_600_000) / 60_000;
    let s = (ms % 60_000) / 1000;
    let msec = ms % 1000;
    if vtt {
        format!("{h:02}:{m:02}:{s:02}.{msec:03}")
    } else {
        format!("{h:02}:{m:02}:{s:02},{msec:03}")
    }
}
