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
    let mut offset = 0.0f64;
    let mut t = start;
    while t < end {
        let seg_end = (t + STEP_MS).min(end);
        offset += eval_speed_at(clip, t) as f64 * (seg_end - t) as f64;
        t += STEP_MS;
    }
    offset as i64
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

/// The timeline compositor — mirrors C++ renderTimelineFrame. Called with the
/// engine state (shared lock) and the render mutex held.
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
                if c.start_ms > pos_ms {
                    break;
                }
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
        // Clips are sorted by startMs — once a clip starts after posMs no
        // later clip can cover posMs either.
        if c.start_ms > pos_ms {
            break;
        }
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
                    blend_rgba(out, &render_scratch[..frame_bytes], pixel_count, (1.0 - crossfade_t) * prev_clip.opacity);
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
                if pip_active {
                    blend_pip(out, &render_scratch[..frame_bytes], width, height, &clip.pip, &kf, alpha, clip.blend_mode, masked);
                } else {
                    blend_clip(out, &render_scratch[..frame_bytes], pixel_count, alpha, clip.blend_mode, masked);
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

    // The global filter applies on top of the composed frame.
    if apply_fx && active_filter_type != 0 {
        #[cfg(feature = "parallel")]
        apply_filter_parallel(out, width, height, active_filter_type, filter_intensity);
        #[cfg(not(feature = "parallel"))]
        apply_filter_to_buffer(out, width, height, active_filter_type, filter_intensity);
    }
    true
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
        assert!(render_timeline_frame(&state, &mut rstate, &mut out, 64, 36, 1000, true, 0, 0.0));
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
        assert!(render_timeline_frame(&state, &mut rstate, &mut out, 64, 36, 1000, true, 0, 0.0));
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
        assert!(render_timeline_frame(&state, &mut rstate, &mut out, 64, 36, 1000, true, 0, 0.0));
        // Track hidden → pure black frame.
        assert!(out[0] == 0 && out[1] == 0 && out[2] == 0 && out[3] == 255);
    }
}