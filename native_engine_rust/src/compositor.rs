//! Timeline compositor — byte-faithful port of the C++ renderTimelineFrame
//! pipeline: covering-clip resolution, transitions (FadeIn/FadeOut/Crossfade),
//! keyframe evaluation (linear/step/bezier), speed curves, PIP rects,
//! per-clip color correction and the global filter.
//!
//! Borrowing note: scratch buffers and the decoder cache live in RenderState;
//! the compositor destructures it at entry so `&mut` slices (scratch) and
//! `&mut` caches (decoders/LRU) coexist — mirroring C++'s member buffers
//! under one render mutex.

use std::collections::{HashMap, VecDeque};

use crate::engine::RenderState;
use crate::filters::apply_filter_to_buffer;
#[cfg(feature = "parallel")]
use crate::filters::apply_filter_parallel;
use crate::fx::{apply_mask_to_alpha, blend_clip, blend_pixel_mode};
use crate::gdi::render_text_gdi;
use crate::model::{BlendMode, ColorCorrection, Keyframe, MaskType, NativeClip, NativeClipKind,
                   PipGeometry, TransitionType};
use crate::synth::MediaDecoder;

pub const MAX_CLIP_DECODERS: usize = 8;

/// v1.1.0 (PLAN 3.2): Keyframe state evaluated at a timeline position.
#[derive(Clone, Copy, Debug)]
pub struct KeyframeState {
    pub opacity: f32,
    pub offset_x: f32, // fraction of frame width
    pub offset_y: f32, // fraction of frame height
    pub scale: f32,
    pub filter_intensity: f32, // < 0 = use clip's own intensity
}

impl Default for KeyframeState {
    fn default() -> Self {
        KeyframeState {
            opacity: 1.0,
            offset_x: 0.0,
            offset_y: 0.0,
            scale: 1.0,
            filter_intensity: -1.0,
        }
    }
}

/// LRU decoder cache lookup (mirrors GhitaEngine::getClipDecoder, cap 8).
pub fn get_clip_decoder(
    decoders: &mut HashMap<i32, MediaDecoder>,
    lru: &mut VecDeque<i32>,
    clip_id: i32,
    file_path: &str,
) {
    if decoders.contains_key(&clip_id) {
        // Touch LRU order (most recently used at the front).
        if let Some(pos) = lru.iter().position(|&id| id == clip_id) {
            lru.remove(pos);
        }
        lru.push_front(clip_id);
        return;
    }
    if decoders.len() >= MAX_CLIP_DECODERS {
        if let Some(victim) = lru.pop_back() {
            decoders.remove(&victim);
        }
    }
    let mut decoder = MediaDecoder::new();
    // open() transparently falls back to synthetic content for files FFmpeg
    // cannot open (missing/moved media) — keeps previews alive.
    decoder.open(file_path);
    decoders.insert(clip_id, decoder);
    lru.push_front(clip_id);
}

/// Decode a clip's frame through its cached decoder (direct-clip overload —
/// the compositor already holds the NativeClip reference).
pub fn decode_clip_frame(
    decoders: &mut HashMap<i32, MediaDecoder>,
    lru: &mut VecDeque<i32>,
    out: &mut [u8],
    clip: &NativeClip,
    width: usize,
    height: usize,
    source_pos_ms: i64,
    filter_type: i32,
    filter_intensity: f32,
) -> bool {
    if clip.file_path.is_empty()
        && clip.kind != NativeClipKind::Text
        && clip.kind != NativeClipKind::Sticker
    {
        return false;
    }
    get_clip_decoder(decoders, lru, clip.id, &clip.file_path);
    let decoder = match decoders.get_mut(&clip.id) {
        Some(d) => d,
        None => return false,
    };
    decoder.decode_frame(out, width, height, source_pos_ms, filter_type, filter_intensity)
}

/// v1.1.0 (PLAN 3.2/3.3): Evaluate each animated property independently —
/// find the surrounding keyframe pair, interpolate, hold outside the range.
pub fn eval_keyframes(clip: &NativeClip, pos_ms: i64) -> KeyframeState {
    let mut state = KeyframeState::default();
    if clip.keyframes.is_empty() {
        return state;
    }

    for prop in 0..=4 {
        let mut prev: Option<&Keyframe> = None;
        let mut next: Option<&Keyframe> = None;
        for kf in &clip.keyframes {
            if kf.property != prop {
                continue;
            }
            if kf.time_ms <= pos_ms {
                prev = Some(kf);
            } else {
                next = Some(kf);
                break;
            }
        }
        if prev.is_none() && next.is_none() {
            continue; // property not animated
        }

        let value: f32 = match (prev, next) {
            (None, Some(k)) => k.value, // before the first keyframe → hold
            (Some(k), None) => k.value, // after the last → hold
            (Some(p), Some(n)) if n.time_ms == p.time_ms => n.value,
            (Some(p), Some(n)) => {
                let span = (n.time_ms - p.time_ms) as f64;
                let t = ((pos_ms - p.time_ms) as f64 / span).clamp(0.0, 1.0);
                let mode = p.interpolation;
                if mode == 1 {
                    p.value // step / hold
                } else if mode == 2 {
                    // Cubic bezier: map t → bezier parameter via the x-curve
                    // (binary search), then evaluate the y-curve. P0=(0,0), P1=(1,1).
                    let c1x = p.cp1x.clamp(0.0, 1.0) as f64;
                    let c2x = p.cp2x.clamp(0.0, 1.0) as f64;
                    let bez_x = |pp: f64| {
                        let om = 1.0 - pp;
                        3.0 * om * om * pp * c1x + 3.0 * om * pp * pp * c2x + pp * pp * pp
                    };
                    let mut lo = 0.0f64;
                    let mut hi = 1.0f64;
                    for _ in 0..24 {
                        let mid = (lo + hi) * 0.5;
                        if bez_x(mid) < t {
                            lo = mid;
                        } else {
                            hi = mid;
                        }
                    }
                    let tb = (lo + hi) * 0.5;
                    let om = 1.0 - tb;
                    let c1y = p.cp1y.clamp(0.0, 1.0) as f64;
                    let c2y = p.cp2y.clamp(0.0, 1.0) as f64;
                    let y = 3.0 * om * om * tb * c1y + 3.0 * om * tb * tb * c2y + tb * tb * tb;
                    p.value + (n.value - p.value) * y as f32
                } else {
                    p.value + (n.value - p.value) * t as f32
                }
            }
            _ => 0.0,
        };

        match prop {
            0 => state.opacity = value.clamp(0.0, 1.0),
            1 => state.offset_x = value, // fraction of frame width
            2 => state.scale = value.max(0.05),
            3 => {}                      // rotation stored; render support limited
            4 => state.filter_intensity = value.clamp(0.0, 1.0),
            _ => {}
        }
    }
    state
}

/// v1.1.0 (PLAN 3.11): Playback speed at a timeline position. Constant speed
/// when no curve is attached.
pub fn eval_speed_at(clip: &NativeClip, pos_ms: i64) -> f32 {
    if clip.speed_curve.is_empty() {
        return clip.speed;
    }
    let span = clip.duration_ms.max(1);
    let t = ((pos_ms - clip.start_ms) as f32 / span as f32).clamp(0.0, 1.0);
    if clip.speed_curve.len() == 1 {
        return clip.speed_curve[0].speed;
    }
    let mut prev = &clip.speed_curve[0];
    let mut next = clip.speed_curve.last().unwrap();
    for i in 0..clip.speed_curve.len() - 1 {
        if t >= clip.speed_curve[i].t && t <= clip.speed_curve[i + 1].t {
            prev = &clip.speed_curve[i];
            next = &clip.speed_curve[i + 1];
            break;
        }
    }
    if next.t <= prev.t {
        return prev.speed;
    }
    let f = (t - prev.t) / (next.t - prev.t);
    prev.speed + (next.speed - prev.speed) * f
}

/// v1.1.0 (PLAN 3.11): Source offset for a timeline position — ∫speed(t)dt
/// (numeric integration, 5ms steps) when a curve is attached; the linear
/// `(pos - start) * speed` mapping otherwise.
///
/// v1.5.0-T4 (P3): the 5ms Euler sum is replicated EXACTLY through a
/// prefix-sum table cached per (clip id, start, curve fingerprint) — a 60s
/// speed-ramped clip used to re-evaluate ~12,000 speed samples PER FRAME.
/// Identical arithmetic ⇒ byte-identical output; O(1) lookup instead of
/// O(duration/5ms).
use std::cell::RefCell;
use std::rc::Rc;

thread_local! {
    static SPEED_PREFIX_CACHE: RefCell<HashMap<(i32, i64, i64, u64), Rc<Vec<f64>>>> =
        RefCell::new(HashMap::new());
}

fn speed_curve_fingerprint(clip: &NativeClip) -> u64 {
    let mut h: u64 = 0xcbf29ce484222325;
    for p in &clip.speed_curve {
        for v in [p.t.to_bits(), p.speed.to_bits()] {
            h ^= v as u64;
            h = h.wrapping_mul(0x100000001b3);
        }
    }
    h
}

pub fn eval_source_offset(clip: &NativeClip, pos_ms: i64) -> i64 {
    if clip.speed_curve.is_empty() {
        return ((pos_ms - clip.start_ms) as f64 * clip.speed as f64) as i64;
    }
    let start = clip.start_ms;
    let end = start.max(pos_ms);
    if end <= start {
        return 0;
    }
    const STEP_MS: i64 = 5;

    let key = (
        clip.id,
        start,
        // v1.5.0-T6 debug fix: duration participates in eval_speed_at's span
        // normalization — a trim/duration edit must invalidate the table.
        clip.duration_ms,
        speed_curve_fingerprint(clip),
    );
    let prefix = SPEED_PREFIX_CACHE.with(|cache| {
        let mut cache = cache.borrow_mut();
        if let Some(rc) = cache.get(&key) {
            return Rc::clone(rc);
        }
        // Bound the cache — rendering revisits a handful of clips per frame.
        if cache.len() >= 16 {
            cache.clear();
        }
        // Precompute enough grid points for any position within the clip's
        // own timeline span (+ slack). Positions beyond the range fall back
        // to the direct loop below.
        let span = clip.duration_ms.max(0) + STEP_MS * 2;
        let n = ((span / STEP_MS) + 1).max(1) as usize;
        let mut table = Vec::<f64>::with_capacity(n + 1);
        table.push(0.0);
        let mut t = start;
        let mut acc = 0.0f64;
        for _ in 0..n {
            acc += eval_speed_at(clip, t) as f64 * STEP_MS as f64;
            table.push(acc);
            t += STEP_MS;
        }
        let rc = Rc::new(table);
        cache.insert(key, Rc::clone(&rc));
        rc
    });

    let rel = end - start;
    let idx = (rel / STEP_MS) as usize;
    if idx + 1 >= prefix.len() {
        // Beyond the precomputed range — exact direct integration fallback.
        let mut offset = 0.0f64;
        let mut t = start;
        while t < end {
            let seg_end = (t + STEP_MS).min(end);
            offset += eval_speed_at(clip, t) as f64 * (seg_end - t) as f64;
            t += STEP_MS;
        }
        return offset as i64;
    }
    // prefix[idx] = Σ full 5ms steps before the grid point at `idx`;
    // the partial tail step uses the speed AT the grid point — the same
    // arithmetic the historical while-loop performed.
    let base = prefix[idx];
    let t_grid = start + idx as i64 * STEP_MS;
    let partial = eval_speed_at(clip, t_grid) as f64 * (end - t_grid) as f64;
    (base + partial) as i64
}

/// v0.8.0: Per-clip color correction — applied after the filter.
pub fn apply_color_correction_to_buffer(buffer: &mut [u8], width: usize, height: usize, cc: &ColorCorrection) {
    if cc.exposure == 0.0
        && cc.contrast == 0.0
        && cc.saturation == 0.0
        && cc.temperature == 0.0
        && cc.tint == 0.0
        && cc.vibrance == 0.0
        && cc.highlights == 0.0
        && cc.shadows == 0.0
    {
        return;
    }
    let pixel_count = width * height;
    let exp_mul = 2.0f32.powf(cc.exposure);
    let cont = 1.0 + cc.contrast;
    let sat = 1.0 + cc.saturation;
    let vibr = 1.0 + cc.vibrance;
    let hl = cc.highlights * 0.25;
    let sh = cc.shadows * 0.25;
    let temp = cc.temperature;
    let tint_amt = cc.tint;

    for i in 0..pixel_count {
        let mut r = buffer[i * 4] as f32 / 255.0;
        let mut g = buffer[i * 4 + 1] as f32 / 255.0;
        let mut b = buffer[i * 4 + 2] as f32 / 255.0;

        r *= exp_mul;
        g *= exp_mul;
        b *= exp_mul;

        // Contrast around 0.5.
        r = (r - 0.5) * cont + 0.5;
        g = (g - 0.5) * cont + 0.5;
        b = (b - 0.5) * cont + 0.5;

        // Saturation (luma-weighted).
        let luma = 0.299 * r + 0.587 * g + 0.114 * b;
        r = luma + (r - luma) * sat;
        g = luma + (g - luma) * sat;
        b = luma + (b - luma) * sat;

        // Vibrance: stronger effect on low-saturation pixels.
        let max_c = r.max(g).max(b);
        let min_c = r.min(g).min(b);
        let vib_scale = 1.0 + vibr * (1.0 - (max_c - min_c));
        let vluma = 0.299 * r + 0.587 * g + 0.114 * b;
        r = vluma + (r - vluma) * vib_scale;
        g = vluma + (g - vluma) * vib_scale;
        b = vluma + (b - vluma) * vib_scale;

        // Temperature: >0 warms (red up, blue down), <0 cools.
        if temp > 0.0 {
            r *= 1.0 + temp * 0.3;
            b *= 1.0 - temp * 0.3;
        } else {
            let t = -temp;
            r *= 1.0 - t * 0.3;
            b *= 1.0 + t * 0.3;
        }

        // Tint: >0 greens, <0 magentas.
        if tint_amt > 0.0 {
            g *= 1.0 + tint_amt * 0.3;
            r *= 1.0 - tint_amt * 0.15;
            b *= 1.0 - tint_amt * 0.15;
        } else {
            let t = -tint_amt;
            g *= 1.0 - t * 0.3;
            r *= 1.0 + t * 0.15;
            b *= 1.0 + t * 0.15;
        }

        // Highlights/shadows: bright-region and dark-region lifts.
        r += hl * r * r + sh * (1.0 - r) * (1.0 - r);
        g += hl * g * g + sh * (1.0 - g) * (1.0 - g);
        b += hl * b * b + sh * (1.0 - b) * (1.0 - b);

        buffer[i * 4] = clamp255(r);
        buffer[i * 4 + 1] = clamp255(g);
        buffer[i * 4 + 2] = clamp255(b);
    }
}

fn clamp255(v: f32) -> u8 {
    (v.clamp(0.0, 1.0) * 255.0 + 0.5) as u8
}

/// Alpha blend one RGBA frame over another (dst stays opaque).
pub fn blend_rgba(dst: &mut [u8], src: &[u8], pixel_count: usize, alpha: f32) {
    if alpha >= 1.0 {
        dst[..pixel_count * 4].copy_from_slice(&src[..pixel_count * 4]);
        return;
    }
    if alpha <= 0.0 {
        return;
    }
    let ia = 1.0 - alpha;
    for i in 0..pixel_count {
        let d = i * 4;
        dst[d] = (dst[d] as f32 * ia + src[d] as f32 * alpha) as u8;
        dst[d + 1] = (dst[d + 1] as f32 * ia + src[d + 1] as f32 * alpha) as u8;
        dst[d + 2] = (dst[d + 2] as f32 * ia + src[d + 2] as f32 * alpha) as u8;
        dst[d + 3] = 255;
    }
}

/// Blend a full-frame src into dst at a pixel offset — keyframe position animation.
fn blend_rgba_offset(dst: &mut [u8], src: &[u8], width: i32, height: i32, off_x_px: i32, off_y_px: i32, alpha: f32) {
    if alpha <= 0.0 {
        return;
    }
    if alpha >= 1.0 && off_x_px == 0 && off_y_px == 0 {
        let n = width as usize * height as usize * 4;
        dst[..n].copy_from_slice(&src[..n]);
        return;
    }
    let ia = 1.0 - alpha;
    for y in 0..height {
        let dy = y + off_y_px;
        if dy < 0 || dy >= height {
            continue;
        }
        for x in 0..width {
            let dx = x + off_x_px;
            if dx < 0 || dx >= width {
                continue;
            }
            let si = (y * width + x) as usize * 4;
            let di = (dy * width + dx) as usize * 4;
            dst[di] = (dst[di] as f32 * ia + src[si] as f32 * alpha) as u8;
            dst[di + 1] = (dst[di + 1] as f32 * ia + src[si + 1] as f32 * alpha) as u8;
            dst[di + 2] = (dst[di + 2] as f32 * ia + src[si + 2] as f32 * alpha) as u8;
            dst[di + 3] = 255;
        }
    }
}

/// Nearest-neighbor scale around the frame center.
fn scale_rgba_center(src: &[u8], dst: &mut [u8], width: i32, height: i32, scale: f32) {
    let inv = 1.0 / scale;
    for y in 0..height {
        let src_y = ((y as f32 - height as f32 * 0.5) * inv + height as f32 * 0.5) as i32;
        let sy = src_y.clamp(0, height - 1);
        for x in 0..width {
            let src_x = ((x as f32 - width as f32 * 0.5) * inv + width as f32 * 0.5) as i32;
            let sx = src_x.clamp(0, width - 1);
            let si = (sy * width + sx) as usize * 4;
            let di = (y * width + x) as usize * 4;
            dst[di] = src[si];
            dst[di + 1] = src[si + 1];
            dst[di + 2] = src[si + 2];
            dst[di + 3] = 255;
        }
    }
}

/// v1.1.0 (PLAN 3.4): Picture-in-picture blend — nearest-neighbor scale of
/// the decoded frame into the pip rect (keyframe offset/scale compose).
fn blend_pip(
    out: &mut [u8],
    src_frame: &[u8],
    width: usize,
    height: usize,
    pip: &PipGeometry,
    kstate: &KeyframeState,
    blend_alpha: f32,
    mode: BlendMode,
    use_src_alpha: bool,
) {
    let pip_x = ((pip.x + kstate.offset_x) * width as f32) as i32;
    let pip_y = ((pip.y + kstate.offset_y) * height as f32) as i32;
    let scale_factor = kstate.scale.max(0.05);
    let pip_w = ((pip.w * scale_factor * width as f32) as i32).max(1);
    let pip_h = ((pip.h * scale_factor * height as f32) as i32).max(1);
    let sx = width as f32 / pip_w as f32;
    let sy = height as f32 / pip_h as f32;
    let a = blend_alpha;
    if a <= 0.0 {
        return;
    }
    let ia = 1.0 - a;
    for py in 0..pip_h {
        let dst_y = pip_y + py;
        if dst_y < 0 || dst_y >= height as i32 {
            continue;
        }
        let src_y = ((py as f32 * sy) as i32).min(height as i32 - 1);
        for px in 0..pip_w {
            let dst_x = pip_x + px;
            if dst_x < 0 || dst_x >= width as i32 {
                continue;
            }
            let src_x = ((px as f32 * sx) as i32).min(width as i32 - 1);
            let si = (src_y as usize * width + src_x as usize) * 4;
            let di = (dst_y as usize * width + dst_x as usize) * 4;
            let sa = if use_src_alpha { src_frame[si + 3] as f32 / 255.0 } else { 1.0 };
            let eff = a * sa;
            if eff <= 0.0 {
                continue;
            }
            let eia = 1.0 - eff;
            out[di] = (out[di] as f32 * eia + blend_pixel_mode(out[di], src_frame[si], mode) as f32 * eff) as u8;
            out[di + 1] = (out[di + 1] as f32 * eia + blend_pixel_mode(out[di + 1], src_frame[si + 1], mode) as f32 * eff) as u8;
            out[di + 2] = (out[di + 2] as f32 * eia + blend_pixel_mode(out[di + 2], src_frame[si + 2], mode) as f32 * eff) as u8;
            out[di + 3] = 255;
        }
    }
}

/// Offset blend with blend mode + optional mask alpha (keyframe position path).
fn blend_clip_offset(
    dst: &mut [u8],
    src: &[u8],
    width: i32,
    height: i32,
    off_x_px: i32,
    off_y_px: i32,
    alpha: f32,
    mode: BlendMode,
    use_src_alpha: bool,
) {
    if mode == BlendMode::Normal && !use_src_alpha {
        blend_rgba_offset(dst, src, width, height, off_x_px, off_y_px, alpha);
        return;
    }
    if alpha <= 0.0 {
        return;
    }
    let ia = 1.0 - alpha;
    for y in 0..height {
        let dy = y + off_y_px;
        if dy < 0 || dy >= height {
            continue;
        }
        for x in 0..width {
            let dx = x + off_x_px;
            if dx < 0 || dx >= width {
                continue;
            }
            let si = (y * width + x) as usize * 4;
            let di = (dy * width + dx) as usize * 4;
            let sa = if use_src_alpha { src[si + 3] as f32 / 255.0 } else { 1.0 };
            let eff = alpha * sa;
            if eff <= 0.0 {
                continue;
            }
            let eia = 1.0 - eff;
            dst[di] = (dst[di] as f32 * eia + blend_pixel_mode(dst[di], src[si], mode) as f32 * eff) as u8;
            dst[di + 1] = (dst[di + 1] as f32 * eia + blend_pixel_mode(dst[di + 1], src[si + 1], mode) as f32 * eff) as u8;
            dst[di + 2] = (dst[di + 2] as f32 * eia + blend_pixel_mode(dst[di + 2], src[si + 2], mode) as f32 * eff) as u8;
            dst[di + 3] = 255;
        }
    }
}

/// v1.5.0-T5 (P2): FNV-1a over EVERYTHING that affects a composed frame —
/// clip geometry/filters/cc/keyframes/pip/text/speed + track states + canvas
/// background. Any mutation produces a different hash, which auto-invalidates
/// the paused-scrub processing cache.
pub fn timeline_state_hash(state: &crate::engine::EngineState) -> u64 {
    let mut h: u64 = 0xcbf29ce484222325;
    let mut mix = |v: u64| {
        h ^= v;
        h = h.wrapping_mul(0x100000001b3);
    };
    for c in &state.clips {
        for v in [
            c.id as i64,
            c.start_ms,
            c.duration_ms,
            c.source_in_ms,
            c.track_index as i64,
            c.kind as i64,
            c.filter_type as i64,
            c.filter_intensity.to_bits() as i64,
            c.volume.to_bits() as i64,
            c.opacity.to_bits() as i64,
            c.speed.to_bits() as i64,
        ] {
            mix(v as u64);
        }
        mix(c.keyframes.len() as u64);
        for k in &c.keyframes {
            for v in [
                k.time_ms,
                k.value.to_bits() as i64,
                k.property as i64,
                k.interpolation as i64,
                k.cp1x.to_bits() as i64,
                k.cp1y.to_bits() as i64,
                k.cp2x.to_bits() as i64,
                k.cp2y.to_bits() as i64,
            ] {
                mix(v as u64);
            }
        }
        mix(c.speed_curve.len() as u64);
        for p in &c.speed_curve {
            mix(p.t.to_bits() as u64);
            mix(p.speed.to_bits() as u64);
        }
        if c.kind == crate::model::NativeClipKind::Text
            || c.kind == crate::model::NativeClipKind::Sticker
        {
            mix(c.text_content.len() as u64);
            for b in c.text_content.as_bytes() {
                mix(*b as u64);
            }
            mix(c.text_font_size.to_bits() as u64);
            mix(c.text_color as u64);
        }
        // CC 8-tuple + transition + pip + blend/mask/pitch/font.
        for v in [
            c.cc.exposure,
            c.cc.contrast,
            c.cc.saturation,
            c.cc.temperature,
            c.cc.tint,
            c.cc.vibrance,
            c.cc.highlights,
            c.cc.shadows,
        ] {
            mix(v.to_bits() as u64);
        }
        mix(c.transition.kind as u64);
        mix(c.transition.duration_ms as i64 as u64);
        for v in [c.pip.x, c.pip.y, c.pip.w, c.pip.h, c.pip.rotation] {
            mix(v.to_bits() as u64);
        }
        mix(c.blend_mode as u64);
        mix(c.mask_type as u64);
        mix(c.mask_feather.to_bits() as u64);
        mix(c.mask_stroke.to_bits() as u64);
        mix(c.maintain_pitch as u64);
        mix(c.font_family.len() as u64);
        mix((c.sticker_scale.to_bits() as u64).wrapping_mul(0x9e3779b1));
        mix(c.sticker_rotation.to_bits() as u64);
    }
    for t in &state.track_states {
        mix(t.muted as u64);
        mix(t.visible as u64);
        mix(t.volume.to_bits() as u64);
    }
    mix(state.canvas_bg_kind as u64);
    mix(state.canvas_bg_color as u64);
    mix(state.canvas_bg_color2 as u64);
    h
}

/// The timeline compositor — mirrors C++ renderTimelineFrame. Called with the
/// engine state (shared lock) and the render mutex held.
///
/// v1.5.0-T5 (P2): wraps the uncached renderer with the paused-scrub
/// ProcessingCache. `cache_enabled` is passed false while playing/exporting.
pub fn render_timeline_frame(
    state: &crate::engine::EngineState,
    rstate: &mut RenderState,
    out: &mut [u8],
    width: usize,
    height: usize,
    pos_ms: i64,
    apply_fx: bool,
    active_filter_type: i32,
    filter_intensity: f32,
    cache_enabled: bool,
) -> bool {
    if width == 0 || height == 0 || out.len() < width * height * 4 {
        return false;
    }
    let frame_bytes = width * height * 4;

    // Fold global filter state into the timeline hash so filter drags
    // invalidate cached frames too.
    let mut chain_hash = timeline_state_hash(state);
    chain_hash ^= (active_filter_type as u64).wrapping_mul(0x9e3779b97f4a7c15);
    chain_hash ^= filter_intensity.to_bits() as u64;
    if apply_fx {
        chain_hash = !chain_hash;
    }

    if cache_enabled {
        let mut pc = state.processing.borrow_mut();
        pc.update_filter_state(chain_hash);
        if let Some((data, w, h)) = pc.get(pos_ms, width as u32, height as u32) {
            if w as usize == width && h as usize == height && data.len() >= frame_bytes {
                out[..frame_bytes].copy_from_slice(&data[..frame_bytes]);
                drop(pc);
                return true;
            }
        }
        drop(pc);
        let ok = render_timeline_frame_uncached(
            state, rstate, out, width, height, pos_ms, apply_fx,
            active_filter_type, filter_intensity,
        );
        if ok {
            state.processing.borrow_mut().put(
                pos_ms,
                width as u32,
                height as u32,
                out[..frame_bytes].to_vec(),
            );
        }
        ok
    } else {
        // Still feed the hash so a later pause starts from a valid epoch.
        state.processing.borrow_mut().update_filter_state(chain_hash);
        render_timeline_frame_uncached(
            state, rstate, out, width, height, pos_ms, apply_fx,
            active_filter_type, filter_intensity,
        )
    }
}

fn render_timeline_frame_uncached(
    state: &crate::engine::EngineState,
    rstate: &mut RenderState,
    out: &mut [u8],
    width: usize,
    height: usize,
    pos_ms: i64,
    apply_fx: bool,
    active_filter_type: i32,
    filter_intensity: f32,
) -> bool {
    if width == 0 || height == 0 || out.len() < width * height * 4 {
        return false;
    }
    let pixel_count = width * height;
    let frame_bytes = pixel_count * 4;

    if rstate.render_scratch.len() < frame_bytes {
        rstate.render_scratch.resize(frame_bytes, 0);
    }

    // Split borrows: scratch slices + caches coexist via destructuring.
    let RenderState {
        render_scratch,
        scale_scratch,
        text_cache,
        clip_decoders,
        decoder_lru,
        active_clips,
        ..
    } = rstate;

    // 1. Canvas background (T3 #9): solid / vertical gradient / blur.
    match state.canvas_bg_kind {
        0 => {
            let (r, g, b) = ((state.canvas_bg_color >> 16) as u8, (state.canvas_bg_color >> 8) as u8, state.canvas_bg_color as u8);
            for p in out[..frame_bytes].chunks_exact_mut(4) {
                p[0] = r;
                p[1] = g;
                p[2] = b;
                p[3] = 255;
            }
        }
        1 => {
            let (r1, g1, b1) = ((state.canvas_bg_color >> 16) as u8, (state.canvas_bg_color >> 8) as u8, state.canvas_bg_color as u8);
            let (r2, g2, b2) = ((state.canvas_bg_color2 >> 16) as u8, (state.canvas_bg_color2 >> 8) as u8, state.canvas_bg_color2 as u8);
            for y in 0..height {
                let t = y as f32 / height.max(1) as f32;
                let (r, g, b) = (
                    (r1 as f32 + (r2 as f32 - r1 as f32) * t) as u8,
                    (g1 as f32 + (g2 as f32 - g1 as f32) * t) as u8,
                    (b1 as f32 + (b2 as f32 - b1 as f32) * t) as u8,
                );
                for x in 0..width {
                    let i = (y * width + x) * 4;
                    out[i] = r;
                    out[i + 1] = g;
                    out[i + 2] = b;
                    out[i + 3] = 255;
                }
            }
        }
        2 => {
            // Blur background: first covering video clip at pos, heavy blur.
            let mut found = false;
            for c in &state.clips {
                if pos_ms >= c.start_ms && pos_ms < c.start_ms + c.duration_ms {
                    if c.kind == NativeClipKind::Video || c.kind == NativeClipKind::Image {
                        let src = c.source_in_ms + eval_source_offset(c, pos_ms);
                        let lo = c.source_in_ms;
                        let hi = lo.max(lo + c.duration_ms - 1);
                        let srcp = src.clamp(lo, hi);
                        get_clip_decoder(clip_decoders, decoder_lru, c.id, &c.file_path);
                        let ok = decode_clip_frame(
                            clip_decoders,
                            decoder_lru,
                            &mut out[..frame_bytes],
                            c,
                            width,
                            height,
                            srcp,
                            20, // Background Blur filter
                            0.8,
                        );
                        if ok {
                            found = true;
                        }
                        break;
                    }
                }
                // v1.5.0-T4 (P3): no early break on `start_ms > pos_ms` — the
                // scan no longer assumes callers kept clips sorted (a legacy
                // unsorted vector would silently lose its covering clip).
                // Clip counts are small; a full scan is negligible per frame.
            }
            if !found {
                for p in out[..frame_bytes].chunks_exact_mut(4) {
                    p[0] = 0;
                    p[1] = 0;
                    p[2] = 0;
                    p[3] = 255;
                }
            }
        }
        _ => {}
    }

    // 2. Composite in ascending track order (base video first, overlays last).
    let mut max_track = 0i32;
    for c in &state.clips {
        if c.track_index > max_track {
            max_track = c.track_index;
        }
    }

    // Resolve the covering clip per track with ONE linear scan over the
    // startMs-sorted clips (model guarantees non-overlapping clips per track).
    if active_clips.len() < max_track as usize + 1 {
        active_clips.resize(max_track as usize + 1, None);
    }
    for slot in active_clips.iter_mut().take(max_track as usize + 1) {
        *slot = None;
    }
    for (idx, c) in state.clips.iter().enumerate() {
        if pos_ms >= c.start_ms && pos_ms < c.start_ms + c.duration_ms {
            active_clips[c.track_index as usize] = Some(idx);
        }
        // v1.5.0-T4 (P3): full scan — the old `start_ms > pos_ms` early break
        // silently dropped covering clips whenever the clip vector was not
        // startMs-sorted (legacy add/set_position paths). O(n) is negligible.
    }

    for track in 0..=max_track {
        if (track as usize) < state.track_states.len() && !state.track_states[track as usize].visible {
            continue;
        }

        let clip_idx = match active_clips[track as usize] {
            Some(i) => i,
            None => continue,
        };
        let clip = &state.clips[clip_idx];
        // Audio clips contribute no pixels.
        if clip.kind == NativeClipKind::Audio {
            continue;
        }

        // Evaluate keyframes at this timeline position.
        let kf = eval_keyframes(clip, pos_ms);

        let mut alpha = clip.opacity * kf.opacity;
        let mut crossfade_active = false;
        let mut prev_idx: Option<usize> = None;
        let mut crossfade_t = 0.0f32;
        // v1.5.0-T5 (P5): extended transition kind when Slide/Wipe/Zoom/
        // Dissolve/Radial is active (None = legacy fade/crossfade behavior).
        let mut extended_kind: Option<TransitionType> = None;
        // v1.5.0-T6 debug fix: true only when the previous frame was actually
        // decoded AND stashed into scale_scratch — guards the consumer below
        // against slicing an empty/stale buffer.
        let mut have_prev_stash = false;

        match clip.transition.kind {
            TransitionType::FadeIn => {
                let dur = clip.transition.duration_ms.max(1);
                let t = (pos_ms - clip.start_ms) as f32 / dur as f32;
                alpha *= t.clamp(0.0, 1.0);
            }
            TransitionType::FadeOut => {
                let dur = clip.transition.duration_ms.max(1);
                let end = clip.start_ms + clip.duration_ms;
                let t = (end - pos_ms) as f32 / dur as f32;
                alpha *= t.clamp(0.0, 1.0);
            }
            TransitionType::Crossfade => {
                let dur = clip.transition.duration_ms.max(1);
                if pos_ms < clip.start_ms + dur as i64 {
                    crossfade_active = true;
                    crossfade_t = (pos_ms - clip.start_ms) as f32 / dur as f32;
                    // Previous clip = the one on the same track ending at our start.
                    for (i, c) in state.clips.iter().enumerate() {
                        if c.track_index == track && c.start_ms + c.duration_ms == clip.start_ms {
                            if prev_idx.is_none() || c.start_ms > state.clips[prev_idx.unwrap()].start_ms {
                                prev_idx = Some(i);
                            }
                        }
                    }
                }
            }
            // v1.5.0-T5 (P5): Slide/Wipe/Zoom/Dissolve/Radial reuse the
            // two-frame mechanism (previous held frame + current) but replace
            // the plain alpha ramp with a geometric/per-pixel composite.
            TransitionType::Slide | TransitionType::Wipe | TransitionType::Zoom
            | TransitionType::Dissolve | TransitionType::Radial => {
                let dur = clip.transition.duration_ms.max(1);
                if pos_ms < clip.start_ms + dur as i64 {
                    crossfade_active = true;
                    crossfade_t = ((pos_ms - clip.start_ms) as f32 / dur as f32).clamp(0.0, 1.0);
                    extended_kind = Some(clip.transition.kind);
                    for (i, c) in state.clips.iter().enumerate() {
                        if c.track_index == track && c.start_ms + c.duration_ms == clip.start_ms {
                            if prev_idx.is_none() || c.start_ms > state.clips[prev_idx.unwrap()].start_ms {
                                prev_idx = Some(i);
                            }
                        }
                    }
                }
            }
            _ => {}
        }

        // Crossfade: draw the previous clip's held frame first, current over it.
        if crossfade_active {
            if let Some(pi) = prev_idx {
                let prev_clip = &state.clips[pi];
                let p_src_base = prev_clip.source_in_ms + eval_source_offset(prev_clip, pos_ms);
                let mut p_src_out = prev_clip.source_in_ms
                    + (prev_clip.duration_ms as f32 * prev_clip.speed) as i64;
                // NOTE: get_clip_decoder fires even for the duration probe —
                // the C++ path does the same lookup (decoder creation
                // side-effect is part of the observable flow).
                get_clip_decoder(clip_decoders, decoder_lru, prev_clip.id, &prev_clip.file_path);
                if let Some(dec) = clip_decoders.get(&prev_clip.id) {
                    let media_dur = dec.duration_ms;
                    if media_dur > 0 {
                        p_src_out = p_src_out.min(prev_clip.source_in_ms + media_dur);
                    }
                }
                let p_lo = prev_clip.source_in_ms;
                let p_hi = p_lo.max(p_src_out - 1);
                let p_src = p_src_base.clamp(p_lo, p_hi);
                let decode_ok = decode_clip_frame(
                    clip_decoders,
                    decoder_lru,
                    &mut render_scratch[..frame_bytes],
                    prev_clip,
                    width,
                    height,
                    p_src,
                    prev_clip.filter_type,
                    prev_clip.filter_intensity,
                );
                if decode_ok {
                    apply_color_correction_to_buffer(&mut render_scratch[..frame_bytes], width, height, &prev_clip.cc);
                    if extended_kind.is_some() {
                        // v1.5.0-T5 (P5): stash the previous frame UNblended —
                        // the extended transition composites prev vs current
                        // itself in blend_extended_transition.
                        if scale_scratch.len() < frame_bytes {
                            scale_scratch.resize(frame_bytes, 0);
                        }
                        scale_scratch[..frame_bytes]
                            .copy_from_slice(&render_scratch[..frame_bytes]);
                        have_prev_stash = true;
                    } else {
                        blend_rgba(out, &render_scratch[..frame_bytes], pixel_count, (1.0 - crossfade_t) * prev_clip.opacity);
                    }
                }
            }
        }

        // Effective filter intensity (keyframed when animated) + pip rect.
        let filter_intensity = if kf.filter_intensity >= 0.0 && apply_fx {
            kf.filter_intensity
        } else if apply_fx {
            clip.filter_intensity
        } else {
            0.0
        };
        let draw_filter_type = if apply_fx { clip.filter_type } else { 0 };
        let pip_active = clip.pip.w < 1.0 || clip.pip.h < 1.0;

        // T3 (#14): standalone effect element — applies its filter to the
        // accumulated composite (adjustment-layer semantics).
        if clip.kind == NativeClipKind::Effect {
            if apply_fx && clip.filter_type != 0 {
                apply_filter_to_buffer(out, width, height, clip.filter_type, filter_intensity);
            }
            continue;
        }

        // Draw the covering clip.
        if clip.kind == NativeClipKind::Text || clip.kind == NativeClipKind::Sticker {
            render_scratch[..frame_bytes].fill(0);
            if render_text_gdi(
                text_cache,
                &mut render_scratch[..frame_bytes],
                width,
                height,
                &clip.text_content,
                clip.text_font_size,
                clip.text_color,
            ) {
                let masked = clip.mask_type != MaskType::None;
                if masked {
                    apply_mask_to_alpha(&mut render_scratch[..frame_bytes], width, height, clip.mask_type, clip.mask_feather, clip.mask_stroke);
                }
                // v1.5.0-T5 (P5): sticker transform — scale about center +
                // rotate (nearest neighbour), transparent outside the source.
                let sticker_src: &[u8] =
                    if clip.kind == NativeClipKind::Sticker
                        && (clip.sticker_scale != 1.0 || clip.sticker_rotation.abs() > 0.01)
                    {
                        if scale_scratch.len() < frame_bytes {
                            scale_scratch.resize(frame_bytes, 0);
                        }
                        transform_rgba_center(
                            &render_scratch[..frame_bytes],
                            &mut scale_scratch[..frame_bytes],
                            width as i32,
                            height as i32,
                            clip.sticker_scale,
                            clip.sticker_rotation,
                        );
                        &scale_scratch[..frame_bytes]
                    } else {
                        &render_scratch[..frame_bytes]
                    };
                if pip_active {
                    blend_pip(out, sticker_src, width, height, &clip.pip, &kf, alpha, clip.blend_mode, masked);
                } else {
                    blend_clip(out, sticker_src, pixel_count, alpha, clip.blend_mode, masked);
                }
            }
        } else {
            // ∫speed(t)dt source mapping (constant speed when no curve attached).
            let src_base = clip.source_in_ms + eval_source_offset(clip, pos_ms);
            let mut src_out = clip.source_in_ms + (clip.duration_ms as f32 * clip.speed) as i64;
            get_clip_decoder(clip_decoders, decoder_lru, clip.id, &clip.file_path);
            if let Some(dec) = clip_decoders.get(&clip.id) {
                let media_dur = dec.duration_ms;
                if media_dur > 0 {
                    src_out = src_out.min(clip.source_in_ms + media_dur);
                }
            }
            let lo = clip.source_in_ms;
            let hi = lo.max(src_out - 1);
            let src = src_base.clamp(lo, hi);

            // Decode into scratch, then apply cc + blend.
            let decode_ok = decode_clip_frame(
                clip_decoders,
                decoder_lru,
                &mut render_scratch[..frame_bytes],
                clip,
                width,
                height,
                src,
                draw_filter_type,
                filter_intensity,
            );
            if decode_ok {
                if apply_fx {
                    apply_color_correction_to_buffer(&mut render_scratch[..frame_bytes], width, height, &clip.cc);
                }
                let masked = clip.mask_type != MaskType::None;
                if masked {
                    apply_mask_to_alpha(&mut render_scratch[..frame_bytes], width, height, clip.mask_type, clip.mask_feather, clip.mask_stroke);
                }
                // v1.5.0-T5 (P5): Slide/Wipe/Zoom/Dissolve/Radial composite
                // prev vs current directly; pip/keyframed/masked clips fall
                // back to the legacy fade so their transforms stay correct.
                let mut extended_done = false;
                if let Some(kind) = extended_kind {
                    // v1.5.0-T6 debug fix: only consume the stash when the
                    // previous frame was actually decoded+stashed — otherwise
                    // scale_scratch may be empty (panic) or hold stale pixels
                    // from an unrelated clip/track.
                    if !have_prev_stash {
                        // No prev frame → plain render of current only.
                    } else if !pip_active
                        && !masked
                        && kf.scale == 1.0
                        && kf.offset_x == 0.0
                        && kf.offset_y == 0.0
                    {
                        blend_extended_transition(
                            out,
                            &scale_scratch[..frame_bytes],
                            &render_scratch[..frame_bytes],
                            width,
                            height,
                            crossfade_t,
                            kind,
                            alpha,
                        );
                        extended_done = true;
                    } else {
                        blend_rgba(out, &scale_scratch[..frame_bytes], pixel_count, (1.0 - crossfade_t) * alpha);
                    }
                }
                if !extended_done {
                if pip_active {
                    blend_pip(out, &render_scratch[..frame_bytes], width, height, &clip.pip, &kf, alpha, clip.blend_mode, masked);
                } else if kf.scale != 1.0 || kf.offset_x != 0.0 || kf.offset_y != 0.0 {
                    // Keyframe scale/position without a pip rect — scale
                    // around the center, then blend at the animated offset.
                    if kf.scale != 1.0 {
                        if scale_scratch.len() < frame_bytes {
                            scale_scratch.resize(frame_bytes, 0);
                        }
                        scale_rgba_center(
                            &render_scratch[..frame_bytes],
                            &mut scale_scratch[..frame_bytes],
                            width as i32,
                            height as i32,
                            kf.scale,
                        );
                        let off_x = (kf.offset_x * width as f32) as i32;
                        let off_y = (kf.offset_y * height as f32) as i32;
                        blend_clip_offset(
                            out,
                            &scale_scratch[..frame_bytes],
                            width as i32,
                            height as i32,
                            off_x,
                            off_y,
                            alpha,
                            clip.blend_mode,
                            masked,
                        );
                    } else {
                        let off_x = (kf.offset_x * width as f32) as i32;
                        let off_y = (kf.offset_y * height as f32) as i32;
                        blend_clip_offset(
                            out,
                            &render_scratch[..frame_bytes],
                            width as i32,
                            height as i32,
                            off_x,
                            off_y,
                            alpha,
                            clip.blend_mode,
                            masked,
                        );
                    }
                } else {
                    blend_clip(out, &render_scratch[..frame_bytes], pixel_count, alpha, clip.blend_mode, masked);
                }
                }
            }
        }
    }

    // The global filter applies on top of the composed frame.
    if apply_fx && active_filter_type != 0 {
        #[cfg(feature = "parallel")]
        apply_filter_parallel(out, width, height, active_filter_type, filter_intensity);
        #[cfg(not(feature = "parallel"))]
        apply_filter_to_buffer(out, width, height, active_filter_type, filter_intensity);
    }
    true
}

/// v1.5.0-T5 (P5): Slide / Wipe / Zoom / Dissolve / Radial composites —
/// per-pixel selection between the outgoing (prev) and incoming (current)
/// frames driven by the transition progress `t` ∈ [0,1], alpha-over onto the
/// existing composite. Deterministic dissolve hash keeps frames stable.
fn blend_extended_transition(
    out: &mut [u8],
    prev: &[u8],
    cur: &[u8],
    width: usize,
    height: usize,
    t: f32,
    kind: TransitionType,
    alpha: f32,
) {
    let t = t.clamp(0.0, 1.0);
    let cx = width as f32 * 0.5;
    let cy = height as f32 * 0.5;
    let max_r = (cx * cx + cy * cy).sqrt();
    // Slide travels from fully off-screen right → flush.
    let dx = ((1.0 - t) * width as f32).round() as i64;
    let zoom = 0.35f32 + 0.65 * t;

    for y in 0..height {
        for x in 0..width {
            let dst = (y * width + x) * 4;
            let use_cur = match kind {
                TransitionType::Wipe => (x as f32) < t * width as f32,
                TransitionType::Dissolve => {
                    let h: u32 = (x as u32)
                        .wrapping_mul(374761393)
                        .wrapping_add((y as u32).wrapping_mul(668265263));
                    let h = (h ^ (h >> 13)).wrapping_mul(1274126177);
                    let r = ((h ^ (h >> 16)) & 0xFFFF) as f32 / 65536.0;
                    r < t
                }
                TransitionType::Radial => {
                    let ddx = x as f32 - cx;
                    let ddy = y as f32 - cy;
                    ((ddx * ddx + ddy * ddy).sqrt()) / max_r <= t
                }
                TransitionType::Slide => {
                    let sx = x as i64 - dx;
                    sx >= 0 && (sx as usize) < width
                }
                TransitionType::Zoom => {
                    if zoom <= 0.001 {
                        false
                    } else {
                        let sx = ((x as f32 - cx) / zoom + cx) as i64;
                        let sy = ((y as f32 - cy) / zoom + cy) as i64;
                        sx >= 0 && sx < width as i64 && sy >= 0 && sy < height as i64
                    }
                }
                _ => true,
            };
            let src_off = match kind {
                TransitionType::Slide => {
                    let sx = (x as i64 - dx).max(0) as usize;
                    (y * width + sx.min(width - 1)) * 4
                }
                TransitionType::Zoom => {
                    let sx = (((x as f32 - cx) / zoom + cx) as i64).clamp(0, width as i64 - 1) as usize;
                    let sy = (((y as f32 - cy) / zoom + cy) as i64).clamp(0, height as i64 - 1) as usize;
                    (sy * width + sx) * 4
                }
                _ => dst,
            };
            let src: &[u8; 4] = if use_cur {
                cur[src_off..src_off + 4].try_into().unwrap()
            } else {
                prev[dst..dst + 4].try_into().unwrap()
            };
            // Standard alpha-over, matching blend_clip semantics.
            for c in 0..3 {
                out[dst + c] = (src[c] as f32 * alpha + out[dst + c] as f32 * (1.0 - alpha)) as u8;
            }
            out[dst + 3] = 255;
        }
    }
}

/// v1.5.0-T5 (P5): nearest-neighbour scale-about-center + rotation (degrees,
/// counter-clockwise) for stickers. Destination is cleared first; pixels that
/// map outside the source stay fully transparent so blend_clip keeps the
/// silhouette correct.
pub fn transform_rgba_center<'a>(
    src: &[u8],
    dst: &'a mut [u8],
    width: i32,
    height: i32,
    scale: f32,
    rotation_deg: f32,
) -> &'a mut [u8] {
    let (w, h) = (width as usize, height as usize);
    dst[..w * h * 4].fill(0);
    if w == 0 || h == 0 || src.len() < w * h * 4 {
        return dst;
    }
    let s = scale.clamp(0.01, 32.0);
    let rad = rotation_deg.to_radians();
    let (sin, cos) = rad.sin_cos();
    let cx = width as f32 * 0.5;
    let cy = height as f32 * 0.5;
    for dy in 0..height {
        for dx in 0..width {
            // Inverse-map the destination pixel back into source space.
            let ox = dx as f32 + 0.5 - cx;
            let oy = dy as f32 + 0.5 - cy;
            let sx = (ox * cos + oy * sin) / s + cx;
            let sy = (-ox * sin + oy * cos) / s + cy;
            let sx_i = sx.floor() as i64;
            let sy_i = sy.floor() as i64;
            if sx_i < 0 || sy_i < 0 || sx_i >= width as i64 || sy_i >= height as i64 {
                continue;
            }
            let di = (dy as usize * w + dx as usize) * 4;
            let si = (sy_i as usize * w + sx_i as usize) * 4;
            dst[di] = src[si];
            dst[di + 1] = src[si + 1];
            dst[di + 2] = src[si + 2];
            dst[di + 3] = src[si + 3];
        }
    }
    dst
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::engine::new_render_state;
    use crate::model::SpeedRampPoint;

    #[test]
    fn keyframe_linear_interpolation() {
        let mut clip = NativeClip::new(1);
        clip.keyframes = vec![
            Keyframe { time_ms: 0, value: 0.0, property: 0, interpolation: 0, cp1x: 0.0, cp1y: 0.0, cp2x: 0.0, cp2y: 0.0 },
            Keyframe { time_ms: 1000, value: 1.0, property: 0, interpolation: 0, cp1x: 0.0, cp1y: 0.0, cp2x: 0.0, cp2y: 0.0 },
        ];
        let s = eval_keyframes(&clip, 500);
        assert!((s.opacity - 0.5).abs() < 1e-6);
        let s0 = eval_keyframes(&clip, 1500);
        assert_eq!(s0.opacity, 1.0); // hold after last
    }

    // v1.5.0-T5 (P5): extended transition composites ------------------------

    fn solid(w: usize, h: usize, r: u8, g: u8, b: u8) -> Vec<u8> {
        let mut v = Vec::with_capacity(w * h * 4);
        for _ in 0..w * h {
            v.extend_from_slice(&[r, g, b, 255]);
        }
        v
    }

    #[test]
    fn blend_extended_transition_wipe_midpoint() {
        let prev = solid(8, 8, 255, 0, 0); // red
        let cur = solid(8, 8, 0, 0, 255); // blue
        let mut out = solid(8, 8, 9, 9, 9);
        blend_extended_transition(&mut out, &prev, &cur, 8, 8, 0.5, TransitionType::Wipe, 1.0);
        // Left half = incoming blue, right half = outgoing red.
        assert_eq!(out[(0 * 8 + 1) * 4], 0);   // top-left blue
        assert_eq!(out[(0 * 8 + 6) * 4], 255); // top-right red
    }

    #[test]
    fn blend_extended_transition_endpoints() {
        let prev = solid(8, 8, 255, 0, 0);
        let cur = solid(8, 8, 0, 0, 255);
        for kind in [TransitionType::Slide, TransitionType::Wipe,
                     TransitionType::Zoom, TransitionType::Dissolve,
                     TransitionType::Radial] {
            let mut out = solid(8, 8, 9, 9, 9);
            blend_extended_transition(&mut out, &prev, &cur, 8, 8, 0.0, kind, 1.0);
            if !matches!(kind, TransitionType::Zoom | TransitionType::Radial) {
                // At t=0 every kind except Zoom/Radial shows the outgoing
                // frame everywhere: Zoom's center-scaled sample reaches
                // inward, and Radial's distance-zero CENTER pixel legitimately
                // satisfies dist/max_r <= 0.
                assert!(out.chunks_exact(4).all(|px| px[0] == 255 && px[2] == 0),
                        "{kind:?} at t=0 must show the outgoing frame");
            }
            let mut out = solid(8, 8, 9, 9, 9);
            blend_extended_transition(&mut out, &prev, &cur, 8, 8, 1.0, kind, 1.0);
            assert!(out.chunks_exact(4).all(|px| px[2] == 255 && px[0] == 0),
                    "{kind:?} at t=1 must show the incoming frame everywhere");
        }
    }

    #[test]
    fn blend_extended_transition_dissolve_deterministic_and_monotonic() {
        let prev = solid(16, 16, 255, 0, 0);
        let cur = solid(16, 16, 0, 0, 255);
        let count_blue = |t: f32| -> usize {
            let mut out = solid(16, 16, 9, 9, 9);
            blend_extended_transition(&mut out, &prev, &cur, 16, 16, t, TransitionType::Dissolve, 1.0);
            out.chunks_exact(4).filter(|p| p[2] == 255 && p[0] == 0).count()
        };
        let early = count_blue(0.25);
        let late = count_blue(0.75);
        assert!(early > 0 && early < 256, "partial dissolve covers some pixels");
        assert!(late > early, "more pixels switch as t grows ({early} → {late})");
        // Deterministic across calls (no flicker between frames).
        assert_eq!(count_blue(0.25), early);
    }

    #[test]
    fn keyframe_step_and_bezier() {
        let mut clip = NativeClip::new(1);
        clip.keyframes = vec![
            Keyframe { time_ms: 0, value: 0.0, property: 0, interpolation: 1, cp1x: 0.0, cp1y: 0.0, cp2x: 0.0, cp2y: 0.0 },
            Keyframe { time_ms: 1000, value: 1.0, property: 0, interpolation: 0, cp1x: 0.0, cp1y: 0.0, cp2x: 0.0, cp2y: 0.0 },
        ];
        // step: holds prev value throughout the segment
        let s = eval_keyframes(&clip, 900);
        assert_eq!(s.opacity, 0.0);
        // bezier ease: at t=0.5 with control points (0,0),(1,1) it's linear
        clip.keyframes[0].interpolation = 2;
        let s = eval_keyframes(&clip, 500);
        assert!((s.opacity - 0.5).abs() < 0.02);
    }

    #[test]
    fn speed_curve_segment_interpolation() {
        let mut clip = NativeClip::new(1);
        clip.start_ms = 0;
        clip.duration_ms = 1000;
        clip.speed_curve = vec![
            SpeedRampPoint { t: 0.0, speed: 1.0 },
            SpeedRampPoint { t: 1.0, speed: 3.0 },
        ];
        assert!((eval_speed_at(&clip, 500) - 2.0).abs() < 1e-5);
        // linear source offset without curve
        clip.speed_curve.clear();
        clip.speed = 2.0;
        assert_eq!(eval_source_offset(&clip, 500), 1000);
    }

    #[test]
    fn compositor_renders_clip() {
        let mut state = crate::engine::EngineState::default();
        let mut clip = NativeClip::new(1);
        clip.file_path = "missing.mp4".to_string();
        clip.start_ms = 0;
        clip.duration_ms = 5000;
        clip.track_index = 0;
        state.clips.push(clip);
        state.clips.sort_by(|a, b| a.start_ms.cmp(&b.start_ms));
        let mut rstate = new_render_state();
        let mut out = vec![0u8; 64 * 36 * 4];
        assert!(render_timeline_frame(&state, &mut rstate, &mut out, 64, 36, 1000, true, 0, 0.0, false));
        assert_eq!(out[3], 255);
    }

    #[test]
    fn pip_smaller_than_frame() {
        let mut state = crate::engine::EngineState::default();
        let mut clip = NativeClip::new(1);
        clip.file_path = "missing.mp4".to_string();
        clip.start_ms = 0;
        clip.duration_ms = 5000;
        clip.track_index = 0;
        clip.pip = PipGeometry { x: 0.0, y: 0.0, w: 0.5, h: 0.5, rotation: 0.0 };
        state.clips.push(clip);
        state.clips.sort_by(|a, b| a.start_ms.cmp(&b.start_ms));
        let mut rstate = new_render_state();
        let mut out = vec![0u8; 64 * 36 * 4];
        assert!(render_timeline_frame(&state, &mut rstate, &mut out, 64, 36, 1000, true, 0, 0.0, false));
        // Bottom-right quadrant stays black (pip covers top-left 32×18).
        let idx = (35 * 64 + 63) * 4;
        assert!(out[idx] == 0 && out[idx + 1] == 0 && out[idx + 2] == 0);
    }

    #[test]
    fn invisible_track_skipped() {
        let mut state = crate::engine::EngineState::default();
        let mut clip = NativeClip::new(1);
        clip.file_path = "missing.mp4".to_string();
        clip.start_ms = 0;
        clip.duration_ms = 5000;
        clip.track_index = 0;
        state.clips.push(clip);
        state.clips.sort_by(|a, b| a.start_ms.cmp(&b.start_ms));
        state.track_states.push(crate::model::NativeTrackState { muted: false, visible: false, volume: 1.0 });
        let mut rstate = new_render_state();
        let mut out = vec![0u8; 64 * 36 * 4];
        assert!(render_timeline_frame(&state, &mut rstate, &mut out, 64, 36, 1000, true, 0, 0.0, false));
        // Track hidden → pure black frame.
        assert!(out[0] == 0 && out[1] == 0 && out[2] == 0 && out[3] == 255);
    }
}