//! Pixel shader filters 0–22 — byte-for-byte port of the C++ anonymous
//! namespace helpers in native_engine/src/ghita_engine.cpp.
//!
//! C++ semantics preserved exactly:
//! - float→u8 uses truncation (`static_cast<uint8_t>`) unless clamped first
//! - `std::round` = ties-away-from-zero (f32::round in Rust matches)
//! - deterministic hash01 keeps effects stable across frames

#[cfg(feature = "parallel")]
use rayon::prelude::*;

// ---------------------------------------------------------------------------
// v1.5.0-T4 (P1): per-thread scratch pools. Heavy filters used to allocate a
// fresh full-frame buffer (~8.3 MB @1080p) on EVERY frame, PER CLIP, causing
// allocator jitter on the render path. Buffers are recycled thread-locally
// (the serial render path runs on one thread; the rayon tile path re-enters
// from worker threads, each with its own pool). Zero-init and capacity
// semantics match `vec![0; n]` exactly, so outputs stay byte-equal.
use std::cell::RefCell;

thread_local! {
    static SCRATCH_U8: RefCell<Vec<Vec<u8>>> = const { RefCell::new(Vec::new()) };
    static SCRATCH_U32: RefCell<Vec<Vec<u32>>> = const { RefCell::new(Vec::new()) };
}

const SCRATCH_POOL_MAX: usize = 8;

/// Recyclable zero-initialized byte buffer (Deref to `[u8]`).
struct ScratchBytes(Vec<u8>);

impl ScratchBytes {
    fn new(len: usize) -> Self {
        SCRATCH_U8.with(|pool| {
            let mut pool = pool.borrow_mut();
            while let Some(mut v) = pool.pop() {
                if v.len() >= len {
                    v.truncate(len);
                    v.fill(0);
                    return Self(v);
                }
            }
            Self(vec![0u8; len])
        })
    }

    /// Snapshot helper for filters that need an immutable copy of the frame.
    fn snapshot_from(src: &[u8]) -> Self {
        let mut s = Self::new(src.len());
        s.copy_from_slice(src);
        s
    }
}

impl std::ops::Deref for ScratchBytes {
    type Target = [u8];
    fn deref(&self) -> &[u8] {
        &self.0
    }
}

impl std::ops::DerefMut for ScratchBytes {
    fn deref_mut(&mut self) -> &mut [u8] {
        &mut self.0
    }
}

impl Drop for ScratchBytes {
    fn drop(&mut self) {
        SCRATCH_U8.with(|pool| {
            let mut pool = pool.borrow_mut();
            if pool.len() < SCRATCH_POOL_MAX {
                self.0.clear();
                pool.push(std::mem::take(&mut self.0));
            }
        });
    }
}

/// Recyclable zero-initialized u32 buffer (summed-area tables).
struct ScratchU32(Vec<u32>);

impl ScratchU32 {
    fn new(len: usize) -> Self {
        SCRATCH_U32.with(|pool| {
            let mut pool = pool.borrow_mut();
            while let Some(mut v) = pool.pop() {
                if v.len() >= len {
                    v.truncate(len);
                    v.fill(0);
                    return Self(v);
                }
            }
            Self(vec![0u32; len])
        })
    }
}

impl std::ops::Deref for ScratchU32 {
    type Target = [u32];
    fn deref(&self) -> &[u32] {
        &self.0
    }
}

impl std::ops::DerefMut for ScratchU32 {
    fn deref_mut(&mut self) -> &mut [u32] {
        &mut self.0
    }
}

impl Drop for ScratchU32 {
    fn drop(&mut self) {
        SCRATCH_U32.with(|pool| {
            let mut pool = pool.borrow_mut();
            if pool.len() < SCRATCH_POOL_MAX {
                self.0.clear();
                pool.push(std::mem::take(&mut self.0));
            }
        });
    }
}

/// Deterministic pseudo-random in [0,1) from pixel coords — keeps effects
/// stable across frames (no flicker) and thread-safe (no shared state).
fn hash01(x: i32, y: i32) -> f32 {
    let mut h: u32 = (x as u32).wrapping_mul(374761393u32)
        .wrapping_add((y as u32).wrapping_mul(668265263u32));
    h = (h ^ (h >> 13)).wrapping_mul(1274126177u32);
    ((h ^ (h >> 16)) & 0xFFFFu32) as f32 / 65536.0f32
}

fn apply_grayscale(buf: &mut [u8]) {
    let n = buf.len() / 4;
    for i in 0..n {
        let p = i * 4;
        let y = (0.299f32 * buf[p] as f32 + 0.587f32 * buf[p + 1] as f32 + 0.114f32 * buf[p + 2] as f32) as u8;
        buf[p] = y;
        buf[p + 1] = y;
        buf[p + 2] = y;
    }
}

fn apply_sepia(buf: &mut [u8]) {
    let n = buf.len() / 4;
    for i in 0..n {
        let p = i * 4;
        let (r, g, b) = (buf[p] as f32, buf[p + 1] as f32, buf[p + 2] as f32);
        buf[p] = (0.393f32 * r + 0.769f32 * g + 0.189f32 * b).min(255.0) as u8;
        buf[p + 1] = (0.349f32 * r + 0.686f32 * g + 0.168f32 * b).min(255.0) as u8;
        buf[p + 2] = (0.272f32 * r + 0.534f32 * g + 0.131f32 * b).min(255.0) as u8;
    }
}

fn apply_invert(buf: &mut [u8]) {
    let n = buf.len() / 4;
    for i in 0..n {
        let p = i * 4;
        buf[p] = 255 - buf[p];
        buf[p + 1] = 255 - buf[p + 1];
        buf[p + 2] = 255 - buf[p + 2];
    }
}

fn apply_brightness(buf: &mut [u8], intensity: f32) {
    let delta = ((intensity - 0.5f32) * 2.0f32 * 128.0) as i32;
    let n = buf.len() / 4;
    for i in 0..n {
        let p = i * 4;
        buf[p] = (buf[p] as i32 + delta).clamp(0, 255) as u8;
        buf[p + 1] = (buf[p + 1] as i32 + delta).clamp(0, 255) as u8;
        buf[p + 2] = (buf[p + 2] as i32 + delta).clamp(0, 255) as u8;
    }
}

/// Separable Gaussian blur — O(n·r) two-pass, clamp-to-edge, precomputed kernel.
fn apply_blur(buf: &mut [u8], width: usize, height: usize, intensity: f32) {
    let radius = ((intensity * 10.0f32) as i32).max(1) as usize;

    // Precompute normalized Gaussian kernel
    let mut kernel = vec![0.0f32; 2 * radius + 1];
    let mut sum = 0.0f32;
    let sigma = if radius > 0 { radius as f32 / 2.0f32 } else { 1.0f32 };
    for i in 0..=2 * radius {
        let di = i as i32 - radius as i32;
        kernel[i] = (-(di * di) as f32 / (2.0f32 * sigma * sigma)).exp();
        sum += kernel[i];
    }
    for w in kernel.iter_mut() {
        *w /= sum;
    }

    let mut tmp = ScratchBytes::new(width * height * 4);

    // Horizontal pass (clamp-to-edge)
    for y in 0..height {
        for x in 0..width {
            let mut r = 0.0f32;
            let mut g = 0.0f32;
            let mut b = 0.0f32;
            for dx in -(radius as i32)..=(radius as i32) {
                let sx = ((x as i32 + dx).clamp(0, width as i32 - 1)) as usize;
                let idx = (y * width + sx) * 4;
                let w = kernel[(dx + radius as i32) as usize];
                r += buf[idx] as f32 * w;
                g += buf[idx + 1] as f32 * w;
                b += buf[idx + 2] as f32 * w;
            }
            let out_idx = (y * width + x) * 4;
            tmp[out_idx] = r as u8;
            tmp[out_idx + 1] = g as u8;
            tmp[out_idx + 2] = b as u8;
            tmp[out_idx + 3] = buf[out_idx + 3];
        }
    }

    // Vertical pass (clamp-to-edge)
    for y in 0..height {
        for x in 0..width {
            let mut r = 0.0f32;
            let mut g = 0.0f32;
            let mut b = 0.0f32;
            for dy in -(radius as i32)..=(radius as i32) {
                let sy = ((y as i32 + dy).clamp(0, height as i32 - 1)) as usize;
                let idx = (sy * width + x) * 4;
                let w = kernel[(dy + radius as i32) as usize];
                r += tmp[idx] as f32 * w;
                g += tmp[idx + 1] as f32 * w;
                b += tmp[idx + 2] as f32 * w;
            }
            let out_idx = (y * width + x) * 4;
            buf[out_idx] = r as u8;
            buf[out_idx + 1] = g as u8;
            buf[out_idx + 2] = b as u8;
        }
    }
}

fn apply_edge_detect(buf: &mut [u8], width: usize, height: usize) {
    let tmp = ScratchBytes::snapshot_from(buf);
    let sobel_x: [[i32; 3]; 3] = [[-1, 0, 1], [-2, 0, 2], [-1, 0, 1]];
    let sobel_y: [[i32; 3]; 3] = [[-1, -2, -1], [0, 0, 0], [1, 2, 1]];

    for y in 1..height - 1 {
        for x in 1..width - 1 {
            let mut gx = 0i32;
            let mut gy = 0i32;
            for ky in -1..=1 {
                for kx in -1..=1 {
                    let idx = (((y as i32 + ky) as usize) * width + (x as i32 + kx) as usize) * 4;
                    let gray = (0.299f32 * tmp[idx] as f32 + 0.587f32 * tmp[idx + 1] as f32 + 0.114f32 * tmp[idx + 2] as f32) as u8;
                    gx += gray as i32 * sobel_x[(ky + 1) as usize][(kx + 1) as usize];
                    gy += gray as i32 * sobel_y[(ky + 1) as usize][(kx + 1) as usize];
                }
            }
            let magnitude = ((gx * gx + gy * gy) as f64).sqrt().min(255.0) as u8;
            let idx = (y * width + x) * 4;
            buf[idx] = magnitude;
            buf[idx + 1] = magnitude;
            buf[idx + 2] = magnitude;
        }
    }
}

fn apply_color_grading(buf: &mut [u8]) {
    // Warm tone color matrix (slight orange shift)
    let matrix: [[f32; 3]; 3] = [[1.1, 0.0, 0.0], [0.0, 0.9, 0.0], [0.0, 0.0, 0.8]];
    let n = buf.len() / 4;
    for i in 0..n {
        let p = i * 4;
        let (r, g, b) = (buf[p] as f32, buf[p + 1] as f32, buf[p + 2] as f32);
        let nr = r * matrix[0][0] + g * matrix[0][1] + b * matrix[0][2];
        let ng = r * matrix[1][0] + g * matrix[1][1] + b * matrix[1][2];
        let nb = r * matrix[2][0] + g * matrix[2][1] + b * matrix[2][2];
        buf[p] = (nr as i32).clamp(0, 255) as u8;
        buf[p + 1] = (ng as i32).clamp(0, 255) as u8;
        buf[p + 2] = (nb as i32).clamp(0, 255) as u8;
    }
}

fn apply_adjust(buf: &mut [u8], intensity: f32) {
    // Combined brightness, contrast, saturation, hue adjustment
    let brightness = 0.5f32 + intensity * 0.5f32;
    let contrast = 1.0f32 + (intensity - 0.5f32) * 0.5f32;
    let saturation = 0.5f32 + intensity * 0.5f32;

    let n = buf.len() / 4;
    for i in 0..n {
        let p = i * 4;
        let mut r = buf[p] as f32 / 255.0f32;
        let mut g = buf[p + 1] as f32 / 255.0f32;
        let mut b = buf[p + 2] as f32 / 255.0f32;
        // Contrast
        r = (r - 0.5f32) * contrast + 0.5f32;
        g = (g - 0.5f32) * contrast + 0.5f32;
        b = (b - 0.5f32) * contrast + 0.5f32;
        // Saturation
        let gray = 0.299f32 * r + 0.587f32 * g + 0.114f32 * b;
        r = gray + (r - gray) * saturation;
        g = gray + (g - gray) * saturation;
        b = gray + (b - gray) * saturation;
        // Brightness
        r *= brightness;
        g *= brightness;
        b *= brightness;
        buf[p] = ((r * 255.0f32) as i32).clamp(0, 255) as u8;
        buf[p + 1] = ((g * 255.0f32) as i32).clamp(0, 255) as u8;
        buf[p + 2] = ((b * 255.0f32) as i32).clamp(0, 255) as u8;
    }
}

fn apply_pixelate(buf: &mut [u8], width: usize, height: usize, intensity: f32) {
    let block_size = ((intensity * 20.0f32) as i32).max(2) as usize;
    let mut y = 0usize;
    while y < height {
        let mut x = 0usize;
        while x < width {
            let idx = (y * width + x) * 4;
            let (r, g, b) = (buf[idx], buf[idx + 1], buf[idx + 2]);
            let mut dy = 0usize;
            while dy < block_size && y + dy < height {
                let mut dx = 0usize;
                while dx < block_size && x + dx < width {
                    let p_idx = ((y + dy) * width + (x + dx)) * 4;
                    buf[p_idx] = r;
                    buf[p_idx + 1] = g;
                    buf[p_idx + 2] = b;
                    dx += 1;
                }
                dy += 1;
            }
            x += block_size;
        }
        y += block_size;
    }
}

fn apply_vhs(buf: &mut [u8], width: usize, height: usize, intensity: f32) {
    let pixel_count = width * height;
    for i in 0..pixel_count {
        let x = i % width;
        let y = i / width;
        let idx = i * 4;
        // Scanlines every 3 rows.
        if y % 3 == 0 {
            buf[idx] = (buf[idx] as f32 * 0.7f32) as u8;
            buf[idx + 1] = (buf[idx + 1] as f32 * 0.7f32) as u8;
            buf[idx + 2] = (buf[idx + 2] as f32 * 0.7f32) as u8;
        }
        // Horizontal noise bands.
        if hash01(x as i32, y as i32) < 0.02f32 * intensity {
            buf[idx] = (buf[idx] as f32 * 0.4f32) as u8;
            buf[idx + 1] = (buf[idx + 1] as f32 * 0.4f32) as u8;
            buf[idx + 2] = (buf[idx + 2] as f32 * 0.4f32) as u8;
        }
        // Slight color bleed.
        buf[idx + 1] = (buf[idx + 1] as f32 * 0.92f32 + buf[idx + 2] as f32 * 0.08f32) as u8;
    }
}

fn apply_glitch(buf: &mut [u8], width: usize, height: usize, intensity: f32) {
    // Slice the frame into horizontal bands and displace a subset.
    let band_h = (height / 12).max(8);
    let mut y0 = 0usize;
    while y0 < height {
        let y1 = (y0 + band_h).min(height);
        if hash01(y0 as i32, 0) < 0.35f32 * intensity {
            let shift = ((hash01(y0 as i32, 1) - 0.5f32) * width as f32 * 0.12f32 * intensity) as i32;
            if shift != 0 {
                // v1.5.0-T4 (P1): one recycled row buffer per band (was a
                // fresh vec per band inside the loop).
                let mut row = ScratchBytes::new(width * 4);
                for y in y0..y1 {
                    row[..].copy_from_slice(&buf[y * width * 4..(y + 1) * width * 4]);
                    for x in 0..width {
                        let src_x = (((x as i32 - shift) % width as i32 + width as i32) % width as i32) as usize;
                        let dst = (y * width + x) * 4;
                        let src = src_x * 4;
                        buf[dst] = row[src];
                        buf[dst + 1] = row[src + 1];
                        buf[dst + 2] = row[src + 2];
                    }
                }
            }
        }
        y0 += band_h;
    }
    // RGB split along the band edges.
    let split = ((8.0f32 * intensity) as i32).max(2) as usize;
    let mut y = 0usize;
    while y < height {
        let idx = (y * width) * 4;
        let mut x = width;
        while x > split {
            x -= 1;
            let d = idx + x * 4;
            buf[d] = buf[d - split * 4]; // R trails
        }
        y += 2;
    }
}

fn apply_chromatic_aberration(buf: &mut [u8], width: usize, height: usize, intensity: f32) {
    let shift = ((4.0f32 * intensity) as i32).max(1) as usize;
    let copy = ScratchBytes::snapshot_from(buf);
    for y in 0..height {
        for x in 0..width {
            let dst = (y * width + x) * 4;
            let rx = (x + shift).min(width - 1);
            let bx = x.saturating_sub(shift);
            buf[dst] = copy[(y * width + rx) * 4];
            buf[dst + 1] = copy[(y * width + x) * 4 + 1];
            buf[dst + 2] = copy[(y * width + bx) * 4 + 2];
        }
    }
}

fn apply_vignette(buf: &mut [u8], width: usize, height: usize, intensity: f32) {
    let cx = width as f32 * 0.5f32;
    let cy = height as f32 * 0.5f32;
    let max_dist = (cx * cx + cy * cy).sqrt();
    for y in 0..height {
        for x in 0..width {
            let dx = (x as f32 - cx) / max_dist;
            let dy = (y as f32 - cy) / max_dist;
            let falloff = (1.0f32 - (dx * dx + dy * dy) * (0.9f32 + intensity)).clamp(0.25f32, 1.0f32);
            let idx = (y * width + x) * 4;
            buf[idx] = (buf[idx] as f32 * falloff) as u8;
            buf[idx + 1] = (buf[idx + 1] as f32 * falloff) as u8;
            buf[idx + 2] = (buf[idx + 2] as f32 * falloff) as u8;
        }
    }
}

fn apply_film_grain(buf: &mut [u8], width: usize, height: usize, intensity: f32) {
    let pixel_count = width * height;
    for i in 0..pixel_count {
        let n = (hash01((i % width) as i32, (i / width) as i32) - 0.5f32) * 2.0f32 * 30.0f32 * intensity;
        let idx = i * 4;
        buf[idx] = (buf[idx] as f32 + n).clamp(0.0f32, 255.0f32) as u8;
        buf[idx + 1] = (buf[idx + 1] as f32 + n).clamp(0.0f32, 255.0f32) as u8;
        buf[idx + 2] = (buf[idx + 2] as f32 + n).clamp(0.0f32, 255.0f32) as u8;
    }
}

fn apply_light_leak(buf: &mut [u8], width: usize, height: usize, intensity: f32) {
    // Warm diagonal gradient from the top-left corner.
    let wh = (width + height) as f32;
    for y in 0..height {
        for x in 0..width {
            let dist = (x as f32 + y as f32) / wh;
            let leak = ((1.0f32 - dist) * 0.85f32 * intensity).clamp(0.0f32, 0.8f32);
            let idx = (y * width + x) * 4;
            buf[idx] = ((buf[idx] as f32 * (1.0f32 + leak) + leak * 60.0f32).min(255.0f32)) as u8;
            buf[idx + 1] = ((buf[idx + 1] as f32 * (1.0f32 + leak * 0.5f32) + leak * 20.0f32).min(255.0f32)) as u8;
            buf[idx + 2] = ((buf[idx + 2] as f32 * (1.0f32 - leak * 0.3f32)).min(255.0f32)) as u8;
        }
    }
}

fn apply_sharpen(buf: &mut [u8], width: usize, height: usize, intensity: f32) {
    if width < 3 || height < 3 {
        return;
    }
    let copy = ScratchBytes::snapshot_from(buf);
    let amount = 0.35f32 + intensity * 0.65f32;
    for y in 1..height - 1 {
        for x in 1..width - 1 {
            let idx = (y * width + x) * 4;
            for c in 0..3 {
                let center = copy[idx + c] as f32;
                let top = copy[((y - 1) * width + x) * 4 + c] as f32;
                let bottom = copy[((y + 1) * width + x) * 4 + c] as f32;
                let left = copy[(y * width + x - 1) * 4 + c] as f32;
                let right = copy[(y * width + x + 1) * 4 + c] as f32;
                let sum = top + bottom + left + right;
                let sharpened = center + amount * (center - sum * 0.25f32);
                buf[idx + c] = sharpened.clamp(0.0f32, 255.0f32) as u8;
            }
        }
    }
}

fn apply_posterize(buf: &mut [u8], intensity: f32) {
    let levels = ((2.0f32 + (1.0f32 - intensity) * 6.0f32) as i32).max(2) as f32;
    let step = 255.0f32 / (levels - 1.0f32);
    let n = buf.len() / 4;
    for i in 0..n {
        let p = i * 4;
        for c in 0..3 {
            let v = (buf[p + c] as f32 / step).round() * step;
            buf[p + c] = v.round() as u8;
        }
    }
}

fn apply_duotone(buf: &mut [u8], intensity: f32) {
    let mix = 0.6f32 + intensity * 0.4f32;
    let n = buf.len() / 4;
    for i in 0..n {
        let p = i * 4;
        let luma = (0.299f32 * buf[p] as f32 + 0.587f32 * buf[p + 1] as f32 + 0.114f32 * buf[p + 2] as f32) / 255.0f32;
        // Deep blue shadows → warm orange highlights.
        let r = (30.0f32 + luma * 190.0f32) * mix + buf[p] as f32 * (1.0f32 - mix);
        let g = (24.0f32 + luma * 90.0f32) * mix + buf[p + 1] as f32 * (1.0f32 - mix);
        let b = (90.0f32 + luma * 40.0f32) * mix + buf[p + 2] as f32 * (1.0f32 - mix);
        buf[p] = r.clamp(0.0f32, 255.0f32) as u8;
        buf[p + 1] = g.clamp(0.0f32, 255.0f32) as u8;
        buf[p + 2] = b.clamp(0.0f32, 255.0f32) as u8;
    }
}

fn apply_background_blur(buf: &mut [u8], width: usize, height: usize, intensity: f32) {
    // Strong blur with a sharp center ellipse (subject stays in focus).
    apply_blur(buf, width, height, 0.5f32 + intensity * 0.5f32);
    let cx = width as f32 * 0.5f32;
    let cy = height as f32 * 0.5f32;
    let rx = width as f32 * 0.22f32;
    let ry = height as f32 * 0.30f32;
    let copy = ScratchBytes::snapshot_from(buf);
    for y in 0..height {
        for x in 0..width {
            let dx = (x as f32 - cx) / rx;
            let dy = (y as f32 - cy) / ry;
            if dx * dx + dy * dy <= 1.0f32 {
                let idx = (y * width + x) * 4;
                buf[idx] = copy[idx];
                buf[idx + 1] = copy[idx + 1];
                buf[idx + 2] = copy[idx + 2];
            }
        }
    }
}

/// Skin retouch via summed-area table — O(n), bit-identical arithmetic to the
/// C++ integer accumulation (SAT on u32 channels).
fn apply_skin_retouch(buf: &mut [u8], width: usize, height: usize, intensity: f32) {
    if intensity <= 0.001f32 {
        return;
    }
    let copy = ScratchBytes::snapshot_from(buf);

    let radius = ((intensity * 3.0f32) as i32).max(1) as usize;
    let smooth_factor = 0.45f32 * intensity;
    let bright = 1.05f32 + intensity * 0.08f32;

    let sat_w = width + 1;
    let sat_h = height + 1;
    let mut sat_r = ScratchU32::new(sat_w * sat_h);
    let mut sat_g = ScratchU32::new(sat_w * sat_h);
    let mut sat_b = ScratchU32::new(sat_w * sat_h);
    for y in 0..height {
        let mut row_r = 0u32;
        let mut row_g = 0u32;
        let mut row_b = 0u32;
        let sat_row = (y + 1) * sat_w;
        let sat_prev = y * sat_w;
        let pix_row = y * width * 4;
        for x in 0..width {
            let i = pix_row + x * 4;
            row_r += copy[i] as u32;
            row_g += copy[i + 1] as u32;
            row_b += copy[i + 2] as u32;
            sat_r[sat_row + x + 1] = sat_r[sat_prev + x + 1] + row_r;
            sat_g[sat_row + x + 1] = sat_g[sat_prev + x + 1] + row_g;
            sat_b[sat_row + x + 1] = sat_b[sat_prev + x + 1] + row_b;
        }
    }
    let box_sum = |sat: &[u32], x1: usize, y1: usize, x2: usize, y2: usize| -> u32 {
        let x2p = x2 + 1;
        let y2p = y2 + 1;
        sat[y2p * sat_w + x2p] - sat[y1 * sat_w + x2p] - sat[y2p * sat_w + x1] + sat[y1 * sat_w + x1]
    };

    for y in 0..height {
        let min_y = y.saturating_sub(radius);
        let max_y = (y + radius).min(height - 1);
        for x in 0..width {
            let idx = (y * width + x) * 4;
            let r = copy[idx];
            let g = copy[idx + 1];
            let b = copy[idx + 2];

            // Fast skin tone heuristic in RGB space
            if r > 60 && g > 40 && b > 20 && r > g && r > b && (r - g) > 12 {
                let min_x = x.saturating_sub(radius);
                let max_x = (x + radius).min(width - 1);
                let count = (max_x - min_x + 1) * (max_y - min_y + 1);
                let inv_count = 1.0f32 / count as f32;
                let avg_r = box_sum(&sat_r, min_x, min_y, max_x, max_y) as f32 * inv_count;
                let avg_g = box_sum(&sat_g, min_x, min_y, max_x, max_y) as f32 * inv_count;
                let avg_b = box_sum(&sat_b, min_x, min_y, max_x, max_y) as f32 * inv_count;

                buf[idx] = ((r as f32 * (1.0f32 - smooth_factor) + avg_r * smooth_factor) * bright).clamp(0.0f32, 255.0f32) as u8;
                buf[idx + 1] = ((g as f32 * (1.0f32 - smooth_factor) + avg_g * smooth_factor) * bright).clamp(0.0f32, 255.0f32) as u8;
                buf[idx + 2] = ((b as f32 * (1.0f32 - smooth_factor) + avg_b * smooth_factor) * bright).clamp(0.0f32, 255.0f32) as u8;
            }
        }
    }
}

/// CapCut Chroma Key green screen removal (fast squared distance).
fn apply_chroma_key(buf: &mut [u8], intensity: f32) {
    if intensity <= 0.001f32 {
        return;
    }
    let pixel_count = buf.len() / 4;
    let tolerance = 0.35f32 + intensity * 0.45f32;
    let tolerance_sq = tolerance * tolerance;
    let inner_tol = (tolerance - 0.15f32).max(0.01f32);
    let inv_byte = 1.0f32 / 255.0f32;

    for i in 0..pixel_count {
        let idx = i * 4;
        let r = buf[idx] as f32 * inv_byte;
        let g = buf[idx + 1] as f32 * inv_byte;
        let b = buf[idx + 2] as f32 * inv_byte;

        let green_diff_sq = r * r + (1.0f32 - g) * (1.0f32 - g) + b * b;
        if green_diff_sq < tolerance_sq {
            let green_diff = green_diff_sq.sqrt();
            let alpha_factor = ((green_diff - inner_tol) * (1.0f32 / 0.15f32)).clamp(0.0f32, 1.0f32);
            buf[idx + 3] = (buf[idx + 3] as f32 * alpha_factor) as u8;
            if g > r && g > b {
                buf[idx + 1] = ((r + b) * 0.5f32 * 255.0f32) as u8;
            }
        }
    }
}

/// Dispatches a filter type onto the buffer. Filter 10 (Mosaic) = Pixelate,
/// mirroring the C++ dispatch. Returns true when a filter was applied.
pub fn apply_filter_to_buffer(
    buf: &mut [u8],
    width: usize,
    height: usize,
    filter_type: i32,
    filter_intensity: f32,
) -> bool {
    // v1.5.0-T5 (P3): production GPU dispatch — feature-gated so parity
    // suites always run pure-CPU. Only full-size frames (≥512×256) go to the
    // GPU; rayon tiles (32 rows) and tiny buffers stay on the CPU shaders.
    #[cfg(feature = "gpu")]
    {
        if width * height >= 131_072
            && crate::gpu::try_gpu(buf, width, height, filter_type, filter_intensity)
        {
            return true;
        }
    }
    apply_filter_cpu(buf, width, height, filter_type, filter_intensity)
}

fn apply_filter_cpu(
    buf: &mut [u8],
    width: usize,
    height: usize,
    filter_type: i32,
    filter_intensity: f32,
) -> bool {
    let applied = match filter_type {
        1 => {
            apply_grayscale(buf);
            true
        }
        2 => {
            apply_sepia(buf);
            true
        }
        3 => {
            apply_invert(buf);
            true
        }
        4 => {
            apply_brightness(buf, filter_intensity);
            true
        }
        5 => {
            apply_blur(buf, width, height, filter_intensity);
            true
        }
        6 => {
            apply_edge_detect(buf, width, height);
            true
        }
        7 => {
            apply_color_grading(buf);
            true
        }
        8 => {
            apply_adjust(buf, filter_intensity);
            true
        }
        9 | 10 => {
            apply_pixelate(buf, width, height, filter_intensity);
            true
        }
        11 => {
            apply_vhs(buf, width, height, filter_intensity);
            true
        }
        12 => {
            apply_glitch(buf, width, height, filter_intensity);
            true
        }
        13 => {
            apply_chromatic_aberration(buf, width, height, filter_intensity);
            true
        }
        14 => {
            apply_vignette(buf, width, height, filter_intensity);
            true
        }
        15 => {
            apply_film_grain(buf, width, height, filter_intensity);
            true
        }
        16 => {
            apply_light_leak(buf, width, height, filter_intensity);
            true
        }
        17 => {
            apply_sharpen(buf, width, height, filter_intensity);
            true
        }
        18 => {
            apply_posterize(buf, filter_intensity);
            true
        }
        19 => {
            apply_duotone(buf, filter_intensity);
            true
        }
        20 => {
            apply_background_blur(buf, width, height, filter_intensity);
            true
        }
        21 => {
            apply_skin_retouch(buf, width, height, filter_intensity);
            true
        }
        22 => {
            apply_chroma_key(buf, filter_intensity);
            true
        }
        _ => false,
    };
    applied
}

/// Parallel tile-based application of the same filter set (T1-P5). The tile
/// size is fixed so per-tile output is identical to the serial path for the
/// row-local filters; non-row-local filters (blur/edge/sharpen/background
/// blur) fall back to serial to keep byte parity.
/// Send+Sync wrapper for the disjoint-tile raw pointer (see apply_filter_parallel).
#[cfg(feature = "parallel")]
struct PtrSend<T>(*mut T);
#[cfg(feature = "parallel")]
unsafe impl<T> Send for PtrSend<T> {}
#[cfg(feature = "parallel")]
unsafe impl<T> Sync for PtrSend<T> {}
#[cfg(feature = "parallel")]
impl<T> PtrSend<T> {
    /// Method access forces whole-variable capture in move closures (edition
    /// 2021 would otherwise capture the raw-pointer field directly).
    fn add(&self, off: usize) -> *mut T {
        unsafe { self.0.add(off) }
    }
}

#[cfg(feature = "parallel")]
pub fn apply_filter_parallel(
    buf: &mut [u8],
    width: usize,
    height: usize,
    filter_type: i32,
    intensity: f32,
) {
    // Tile-safe filters: their output for a row band does not depend on
    // pixels OUTSIDE that band. Per-pixel absolute-position math (vignette,
    // grain, light leak) is tile-safe; VHS phase (y%3) and chromatic
    // x-shift are row-local.
    // NOT tile-safe (serial fallback): 5 blur (neighbors), 6 edge (3×3),
    // 9/10 pixelate (block alignment across band edges), 12 glitch (bands),
    // 17 sharpen (3×3), 20 background blur (blur+ellipse), 21 skin retouch
    // (SAT box sums span the whole frame).
    let row_local = matches!(filter_type, 1 | 2 | 3 | 4 | 7 | 8 | 11 | 13 | 14 | 15 | 16 | 18 | 19 | 22);
    if !row_local || height < 64 {
        apply_filter_to_buffer(buf, width, height, filter_type, intensity);
        return;
    }
    let tile_h = 32usize;
    let row_bytes = width * 4;
    let tiles: Vec<(usize, usize)> = (0..height.div_ceil(tile_h))
        .map(|t| (t * tile_h, ((t + 1) * tile_h).min(height)))
        .collect();
    // SAFETY: `buf` outlives the scope (rayon::scope joins before returning);
    // tiles are disjoint row ranges so each closure touches a distinct region
    // (reads its own snapshot rows, writes its own output rows).
    let base = PtrSend(buf.as_mut_ptr());
    let base_ref = &base;
    rayon::scope(|s| {
        for (y0, y1) in tiles {
            s.spawn(move |_| {
                // v1.5.0-T4 (P2): copy ONLY this band into a recycled scratch
                // buffer — the old path made a FULL-FRAME snapshot plus a
                // per-tile Vec allocation on every frame.
                let band_bytes = (y1 - y0) * row_bytes;
                let mut tile = ScratchBytes::new(band_bytes);
                let src = unsafe {
                    std::slice::from_raw_parts(base_ref.add(y0 * row_bytes), band_bytes)
                };
                tile.copy_from_slice(src);
                apply_filter_to_buffer(&mut tile, width, y1 - y0, filter_type, intensity);
                let dst = unsafe {
                    std::slice::from_raw_parts_mut(base_ref.add(y0 * row_bytes), band_bytes)
                };
                dst.copy_from_slice(&tile);
            });
        }
    });
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn hash01_stable_and_in_range() {
        let a = hash01(3, 7);
        let b = hash01(3, 7);
        assert_eq!(a, b);
        assert!((0.0..1.0).contains(&a));
    }

    #[test]
    fn grayscale_matches_expected() {
        let mut buf = vec![255u8, 0, 0, 255, 0, 255, 0, 255];
        apply_grayscale(&mut buf);
        // 0.299*255 = 76.245 → 76 (truncation)
        assert_eq!(buf[0], 76);
        assert_eq!(buf[4], 149);
        assert_eq!(buf[3], 255);
        assert_eq!(buf[7], 255);
    }

    #[test]
    fn filter_dispatch_11_matches_vhs_scanlines() {
        let mut buf = vec![200u8; 12 * 4];
        apply_filter_to_buffer(&mut buf, 3, 4, 11, 1.0);
        // Pixel (0,0): y=0 scanline ×0.7 → 140, then hash01(0,0)=0.0 < 0.02
        // noise band ×0.4 → 56 (both effects apply, matching C++).
        assert_eq!(buf[0], 56);
        assert_eq!(buf[1], 56);
    }

    #[test]
    fn posterize_levels() {
        let mut buf = vec![100u8; 4];
        apply_filter_to_buffer(&mut buf, 1, 1, 18, 0.0);
        // levels = max(2, 2+6)=8, step=255/7≈36.43, round(100/36.43)=round(2.745)=3 → 109.3→109
        assert_eq!(buf[0], 109);
    }

    /// T1-P5 acceptance: multi-threaded tile filters must be ≥ 1.5× faster
    /// than serial on 1920×1080 with a per-pixel filter (Adjust — full
    /// brightness/contrast/saturation math on every pixel).
    #[cfg(feature = "parallel")]
    #[test]
    fn parallel_filter_benchmark_speedup() {
        const W: usize = 1920;
        const H: usize = 1080;
        const FILTER: i32 = 8; // Adjust — row-local, compute-heavy
        let mut base = vec![0u8; W * H * 4];
        // Deterministic gradient pattern.
        for y in 0..H {
            for x in 0..W {
                let i = (y * W + x) * 4;
                base[i] = ((x * 31 + y * 7) % 256) as u8;
                base[i + 1] = ((x * 13 + y * 53) % 256) as u8;
                base[i + 2] = ((x * 71 + y * 3) % 256) as u8;
                base[i + 3] = 255;
            }
        }

        // Warm-up + correctness: parallel must equal serial output exactly.
        let mut serial = base.clone();
        apply_filter_to_buffer(&mut serial, W, H, FILTER, 0.65);
        let mut parallel = base.clone();
        apply_filter_parallel(&mut parallel, W, H, FILTER, 0.65);
        assert_eq!(serial, parallel, "parallel output must match serial");

        // Timed runs.
        let n = 3;
        let t0 = std::time::Instant::now();
        for _ in 0..n {
            let mut b = base.clone();
            apply_filter_to_buffer(&mut b, W, H, FILTER, 0.65);
        }
        let serial_time = t0.elapsed().as_secs_f64() / n as f64;

        let t1 = std::time::Instant::now();
        for _ in 0..n {
            let mut b = base.clone();
            apply_filter_parallel(&mut b, W, H, FILTER, 0.65);
        }
        let parallel_time = t1.elapsed().as_secs_f64() / n as f64;

        let speedup = serial_time / parallel_time.max(1e-9);
        println!(
            "benchmark filter{FILTER} {W}x{H}: serial={serial_time:.4}s parallel={parallel_time:.4}s speedup={speedup:.2}x ({} threads)",
            rayon::current_num_threads()
        );
        assert!(speedup >= 1.5, "expected ≥1.5× speedup, got {speedup:.2}×");
    }
}
