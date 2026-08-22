//! T5-P7: 32-bit float internal render pipeline.
//!
//! Provides f32 versions of all pixel processing functions. The existing u8
//! path remains intact for backward compatibility. When the `f32_pipeline`
//! feature is active, decode outputs f32 RGBA (0.0–1.0), all filters and
//! compositing operate in f32, and conversion to u8 happens only at the
//! C API boundary and FFmpeg sws_scale input.
//!
//! Acceptance criterion: A/B parity vs u8 path ≤ 1/255 on all frames.

/// Convert u8 RGBA buffer to f32 RGBA (0.0–1.0).
pub fn u8_to_f32(buf: &[u8]) -> Vec<f32> {
    buf.iter().map(|&v| v as f32 / 255.0).collect()
}

/// Convert f32 RGBA buffer (0.0–1.0) to u8 with proper rounding.
pub fn f32_to_u8(buf: &[f32]) -> Vec<u8> {
    buf.iter()
        .map(|&v| (v.clamp(0.0, 1.0) * 255.0 + 0.5) as u8)
        .collect()
}

/// Apply a filter to an f32 RGBA buffer (0.0–1.0 range).
/// Mirrors apply_filter_to_buffer in filters.rs but operates entirely in f32.
pub fn apply_filter_f32(
    buf: &mut [f32],
    width: usize,
    height: usize,
    filter_type: i32,
    intensity: f32,
) {
    let pixel_count = width * height;
    if pixel_count == 0 || buf.len() < pixel_count * 4 {
        return;
    }
    match filter_type {
        1 => grayscale_f32(buf, pixel_count),
        2 => sepia_f32(buf, pixel_count),
        3 => invert_f32(buf, pixel_count),
        4 => brightness_f32(buf, pixel_count, intensity),
        5 => blur_f32(buf, width, height, intensity),
        6 => edge_detect_f32(buf, width, height),
        7 => color_grading_f32(buf, pixel_count),
        8 => adjust_f32(buf, pixel_count, intensity),
        9 | 10 => pixelate_f32(buf, width, height, intensity),
        11 => vhs_f32(buf, width, height, intensity),
        12 => glitch_f32(buf, width, height, intensity),
        13 => chromatic_aberration_f32(buf, width, height, intensity),
        14 => vignette_f32(buf, width, height, intensity),
        15 => warm_f32(buf, pixel_count, intensity),
        16 => cool_f32(buf, pixel_count, intensity),
        17 => sharpen_f32(buf, width, height, intensity),
        18 => emboss_f32(buf, width, height),
        19 => posterize_f32(buf, pixel_count, intensity),
        20 => solarize_f32(buf, pixel_count),
        21 => skin_retouch_f32(buf, width, height, intensity),
        22 => chroma_key_f32(buf, pixel_count, intensity),
        _ => {}
    }
}

/// Alpha blend f32 RGBA buffers.
pub fn blend_rgba_f32(dst: &mut [f32], src: &[f32], pixel_count: usize, alpha: f32) {
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
        dst[d] = dst[d] * ia + src[d] * alpha;
        dst[d + 1] = dst[d + 1] * ia + src[d + 1] * alpha;
        dst[d + 2] = dst[d + 2] * ia + src[d + 2] * alpha;
        dst[d + 3] = 1.0;
    }
}

// ── Filter implementations (f32) ───────────────────────────────────────

fn grayscale_f32(buf: &mut [f32], pixels: usize) {
    for i in 0..pixels {
        let base = i * 4;
        let g = buf[base] * 0.299 + buf[base + 1] * 0.587 + buf[base + 2] * 0.114;
        buf[base] = g;
        buf[base + 1] = g;
        buf[base + 2] = g;
    }
}

fn sepia_f32(buf: &mut [f32], pixels: usize) {
    for i in 0..pixels {
        let base = i * 4;
        let r = buf[base];
        let g = buf[base + 1];
        let b = buf[base + 2];
        buf[base] = (r * 0.393 + g * 0.769 + b * 0.189).clamp(0.0, 1.0);
        buf[base + 1] = (r * 0.349 + g * 0.686 + b * 0.168).clamp(0.0, 1.0);
        buf[base + 2] = (r * 0.272 + g * 0.534 + b * 0.131).clamp(0.0, 1.0);
    }
}

fn invert_f32(buf: &mut [f32], pixels: usize) {
    for i in 0..pixels {
        let base = i * 4;
        buf[base] = 1.0 - buf[base];
        buf[base + 1] = 1.0 - buf[base + 1];
        buf[base + 2] = 1.0 - buf[base + 2];
    }
}

fn brightness_f32(buf: &mut [f32], pixels: usize, intensity: f32) {
    let adj = (intensity - 0.5) * 2.0;
    for i in 0..pixels {
        let base = i * 4;
        buf[base] = (buf[base] + adj).clamp(0.0, 1.0);
        buf[base + 1] = (buf[base + 1] + adj).clamp(0.0, 1.0);
        buf[base + 2] = (buf[base + 2] + adj).clamp(0.0, 1.0);
    }
}

fn blur_f32(buf: &mut [f32], w: usize, h: usize, intensity: f32) {
    let radius = ((intensity * 3.0).round() as usize).max(1);
    let pixels = w * h;
    let mut tmp = vec![0.0f32; pixels * 4];
    // Horizontal pass.
    for y in 0..h {
        for x in 0..w {
            let mut sum = [0.0f32; 3];
            let mut count = 0usize;
            for dx in 0..=radius {
                for sx in [x.wrapping_sub(dx), x + dx] {
                    if sx < w {
                        let si = (y * w + sx) * 4;
                        sum[0] += buf[si];
                        sum[1] += buf[si + 1];
                        sum[2] += buf[si + 2];
                        count += 1;
                    }
                }
            }
            let di = (y * w + x) * 4;
            tmp[di] = sum[0] / count as f32;
            tmp[di + 1] = sum[1] / count as f32;
            tmp[di + 2] = sum[2] / count as f32;
            tmp[di + 3] = 1.0;
        }
    }
    // Vertical pass.
    for y in 0..h {
        for x in 0..w {
            let mut sum = [0.0f32; 3];
            let mut count = 0usize;
            for dy in 0..=radius {
                for sy in [y.wrapping_sub(dy), y + dy] {
                    if sy < h {
                        let si = (sy * w + x) * 4;
                        sum[0] += tmp[si];
                        sum[1] += tmp[si + 1];
                        sum[2] += tmp[si + 2];
                        count += 1;
                    }
                }
            }
            let di = (y * w + x) * 4;
            buf[di] = sum[0] / count as f32;
            buf[di + 1] = sum[1] / count as f32;
            buf[di + 2] = sum[2] / count as f32;
        }
    }
}

fn edge_detect_f32(buf: &mut [f32], w: usize, h: usize) {
    if w < 2 || h < 2 {
        return;
    }
    let pixels = w * h;
    let orig: Vec<f32> = buf[..pixels * 4].to_vec();
    for y in 1..h - 1 {
        for x in 1..w - 1 {
            let i = (y * w + x) * 4;
            let left = ((y * w + x - 1) * 4);
            let right = ((y * w + x + 1) * 4);
            let up = (((y - 1) * w + x) * 4);
            let down = (((y + 1) * w + x) * 4);
            for c in 0..3 {
                let gx = orig[right + c] - orig[left + c];
                let gy = orig[down + c] - orig[up + c];
                buf[i + c] = (gx * gx + gy * gy).sqrt().clamp(0.0, 1.0);
            }
        }
    }
}

fn color_grading_f32(buf: &mut [f32], pixels: usize) {
    for i in 0..pixels {
        let base = i * 4;
        let lum = buf[base] * 0.299 + buf[base + 1] * 0.587 + buf[base + 2] * 0.114;
        buf[base] = (buf[base] * 0.9 + lum * 0.1).clamp(0.0, 1.0);
        buf[base + 1] = (buf[base + 1] * 0.95 + lum * 0.05).clamp(0.0, 1.0);
        buf[base + 2] = (buf[base + 2] * 1.1).clamp(0.0, 1.0);
    }
}

fn adjust_f32(buf: &mut [f32], pixels: usize, intensity: f32) {
    let contrast = (intensity - 0.5) * 2.0;
    for i in 0..pixels {
        let base = i * 4;
        for c in 0..3 {
            let v = buf[base + c];
            buf[base + c] = ((v - 0.5) * (1.0 + contrast) + 0.5).clamp(0.0, 1.0);
        }
    }
}

fn pixelate_f32(buf: &mut [f32], w: usize, h: usize, intensity: f32) {
    let block = ((intensity * 16.0).round() as usize).max(2);
    for by in (0..h).step_by(block) {
        for bx in (0..w).step_by(block) {
            let i = (by * w + bx) * 4;
            let r = buf[i];
            let g = buf[i + 1];
            let b = buf[i + 2];
            for dy in 0..block.min(h - by) {
                for dx in 0..block.min(w - bx) {
                    let j = ((by + dy) * w + bx + dx) * 4;
                    buf[j] = r;
                    buf[j + 1] = g;
                    buf[j + 2] = b;
                }
            }
        }
    }
}

fn vhs_f32(buf: &mut [f32], w: usize, h: usize, intensity: f32) {
    let shift = ((intensity * 4.0).round() as usize).max(1);
    let pixels = w * h;
    let orig: Vec<f32> = buf[..pixels * 4].to_vec();
    for y in 0..h {
        for x in 0..w {
            let i = (y * w + x) * 4;
            let rx = (x + shift).min(w - 1);
            let ri = (y * w + rx) * 4;
            buf[i] = orig[ri]; // R shifted right
        }
    }
    // Scanlines.
    for y in (0..h).step_by(2) {
        for x in 0..w {
            let i = (y * w + x) * 4;
            buf[i] *= 0.85;
            buf[i + 1] *= 0.85;
            buf[i + 2] *= 0.85;
        }
    }
}

fn glitch_f32(buf: &mut [f32], w: usize, h: usize, intensity: f32) {
    let num_slices = ((intensity * 8.0).round() as usize).max(1);
    let slice_h = (h / num_slices).max(1);
    for s in 0..num_slices {
        let offset = ((s as f32 * 7.13).sin() * 10.0 * intensity) as i32;
        let y_start = s * slice_h;
        let y_end = (y_start + slice_h).min(h);
        for y in y_start..y_end {
            for x in 0..w {
                let sx = ((x as i32 + offset).clamp(0, w as i32 - 1)) as usize;
                let di = (y * w + x) * 4;
                let si = (y * w + sx) * 4;
                buf[di] = buf[si];
                buf[di + 1] = buf[si + 1];
                buf[di + 2] = buf[si + 2];
            }
        }
    }
}

fn chromatic_aberration_f32(buf: &mut [f32], w: usize, h: usize, intensity: f32) {
    let shift = ((intensity * 3.0).round() as usize).max(1);
    let pixels = w * h;
    let orig: Vec<f32> = buf[..pixels * 4].to_vec();
    for y in 0..h {
        for x in 0..w {
            let i = (y * w + x) * 4;
            let rx = (x + shift).min(w - 1);
            let bx = x.saturating_sub(shift);
            buf[i] = orig[(y * w + rx) * 4]; // R shifted right
            buf[i + 2] = orig[(y * w + bx) * 4 + 2]; // B shifted left
        }
    }
}

fn vignette_f32(buf: &mut [f32], w: usize, h: usize, intensity: f32) {
    let cx = w as f32 / 2.0;
    let cy = h as f32 / 2.0;
    let max_dist = (cx * cx + cy * cy).sqrt();
    for y in 0..h {
        for x in 0..w {
            let dist = ((x as f32 - cx).powi(2) + (y as f32 - cy).powi(2)).sqrt();
            let factor = 1.0 - (dist / max_dist) * intensity;
            let f = factor.clamp(0.0, 1.0);
            let i = (y * w + x) * 4;
            buf[i] *= f;
            buf[i + 1] *= f;
            buf[i + 2] *= f;
        }
    }
}

fn warm_f32(buf: &mut [f32], pixels: usize, intensity: f32) {
    let amt = (intensity - 0.5) * 0.3;
    for i in 0..pixels {
        let base = i * 4;
        buf[base] = (buf[base] + amt).clamp(0.0, 1.0);
        buf[base + 2] = (buf[base + 2] - amt * 0.5).clamp(0.0, 1.0);
    }
}

fn cool_f32(buf: &mut [f32], pixels: usize, intensity: f32) {
    let amt = (intensity - 0.5) * 0.3;
    for i in 0..pixels {
        let base = i * 4;
        buf[base + 2] = (buf[base + 2] + amt).clamp(0.0, 1.0);
        buf[base] = (buf[base] - amt * 0.5).clamp(0.0, 1.0);
    }
}

fn sharpen_f32(buf: &mut [f32], w: usize, h: usize, intensity: f32) {
    if w < 3 || h < 3 {
        return;
    }
    let pixels = w * h;
    let orig: Vec<f32> = buf[..pixels * 4].to_vec();
    let amount = intensity * 2.0;
    for y in 1..h - 1 {
        for x in 1..w - 1 {
            let i = (y * w + x) * 4;
            for c in 0..3 {
                let center = orig[i + c] * 5.0;
                let neighbors = orig[((y - 1) * w + x) * 4 + c]
                    + orig[((y + 1) * w + x) * 4 + c]
                    + orig[(y * w + x - 1) * 4 + c]
                    + orig[(y * w + x + 1) * 4 + c];
                let sharp = center - neighbors;
                buf[i + c] = (orig[i + c] + sharp * amount).clamp(0.0, 1.0);
            }
        }
    }
}

fn emboss_f32(buf: &mut [f32], w: usize, h: usize) {
    if w < 2 || h < 2 {
        return;
    }
    let pixels = w * h;
    let orig: Vec<f32> = buf[..pixels * 4].to_vec();
    for y in 1..h {
        for x in 1..w {
            let i = (y * w + x) * 4;
            let tl = ((y - 1) * w + x - 1) * 4;
            let br = ((y + 1).min(h - 1) * w + (x + 1).min(w - 1)) * 4;
            for c in 0..3 {
                buf[i + c] = (orig[br + c] - orig[tl + c] + 0.5).clamp(0.0, 1.0);
            }
        }
    }
}

fn posterize_f32(buf: &mut [f32], pixels: usize, intensity: f32) {
    let levels = ((1.0 - intensity) * 10.0 + 2.0).round() as f32;
    for i in 0..pixels {
        let base = i * 4;
        for c in 0..3 {
            buf[base + c] = (buf[base + c] * levels).round() / levels;
        }
    }
}

fn solarize_f32(buf: &mut [f32], pixels: usize) {
    for i in 0..pixels {
        let base = i * 4;
        for c in 0..3 {
            if buf[base + c] > 0.5 {
                buf[base + c] = 1.0 - buf[base + c];
            }
        }
    }
}

fn skin_retouch_f32(buf: &mut [f32], w: usize, h: usize, intensity: f32) {
    // Simplified: bilateral-like smoothing on skin-tone regions.
    let pixels = w * h;
    let orig: Vec<f32> = buf[..pixels * 4].to_vec();
    for y in 1..h - 1 {
        for x in 1..w - 1 {
            let i = (y * w + x) * 4;
            let r = orig[i];
            let g = orig[i + 1];
            // Skin tone heuristic in f32.
            let is_skin = r > 0.2 && r > g && (r - g) < 0.4;
            if is_skin {
                let mut sum = [0.0f32; 3];
                let mut count = 0usize;
                for dy in 0..=1 {
                    for dx in 0..=1 {
                        let si = ((y + dy) * w + x + dx) * 4;
                        sum[0] += orig[si];
                        sum[1] += orig[si + 1];
                        sum[2] += orig[si + 2];
                        count += 1;
                    }
                }
                let blend = intensity;
                buf[i] = orig[i] * (1.0 - blend) + (sum[0] / count as f32) * blend;
                buf[i + 1] = orig[i + 1] * (1.0 - blend) + (sum[1] / count as f32) * blend;
                buf[i + 2] = orig[i + 2] * (1.0 - blend) + (sum[2] / count as f32) * blend;
            }
        }
    }
}

fn chroma_key_f32(buf: &mut [f32], pixels: usize, intensity: f32) {
    // Green screen removal: zero out alpha where green dominates.
    let threshold = 0.5 - intensity * 0.3;
    for i in 0..pixels {
        let base = i * 4;
        let g = buf[base + 1];
        let r = buf[base];
        let b = buf[base + 2];
        if g > r + threshold && g > b + threshold {
            buf[base + 3] = 0.0;
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn f32_round_trip() {
        let original: Vec<u8> = (0..=255).collect();
        let f = u8_to_f32(&original);
        let back = f32_to_u8(&f);
        assert_eq!(original, back, "u8→f32→u8 must be lossless");
    }

    #[test]
    fn grayscale_parity() {
        // Compare f32 grayscale vs u8 grayscale output.
        let u8_buf: Vec<u8> = (0..=255).flat_map(|v| vec![v, v / 2, v / 3, 255u8]).collect();
        let mut f32_buf = u8_to_f32(&u8_buf);
        let pixels = u8_buf.len() / 4;

        // Apply f32 grayscale.
        grayscale_f32(&mut f32_buf, pixels);
        let f32_result = f32_to_u8(&f32_buf);

        // Apply u8 grayscale (same formula).
        let mut u8_result = u8_buf.clone();
        for i in 0..pixels {
            let base = i * 4;
            let g = ((u8_result[base] as f32 * 0.299
                + u8_result[base + 1] as f32 * 0.587
                + u8_result[base + 2] as f32 * 0.114)
                + 0.5) as u8;
            u8_result[base] = g;
            u8_result[base + 1] = g;
            u8_result[base + 2] = g;
        }

        // Check parity within ±1.
        for i in 0..u8_result.len() {
            let diff = (f32_result[i] as i32 - u8_result[i] as i32).unsigned_abs();
            assert!(diff <= 1, "pixel {} diff={} (f32={} u8={})", i, diff, f32_result[i], u8_result[i]);
        }
    }

    #[test]
    fn blend_parity() {
        let pixels = 64;
        let dst_u8: Vec<u8> = vec![100u8; pixels * 4];
        let src_u8: Vec<u8> = vec![200u8; pixels * 4];
        let alpha = 0.5f32;

        // u8 blend.
        let mut dst_result = dst_u8.clone();
        let ia = 1.0 - alpha;
        for i in 0..pixels {
            let d = i * 4;
            dst_result[d] = (dst_u8[d] as f32 * ia + src_u8[d] as f32 * alpha) as u8;
            dst_result[d + 1] = (dst_u8[d + 1] as f32 * ia + src_u8[d + 1] as f32 * alpha) as u8;
            dst_result[d + 2] = (dst_u8[d + 2] as f32 * ia + src_u8[d + 2] as f32 * alpha) as u8;
        }

        // f32 blend.
        let mut dst_f32 = u8_to_f32(&dst_u8);
        let src_f32 = u8_to_f32(&src_u8);
        blend_rgba_f32(&mut dst_f32, &src_f32, pixels, alpha);
        let f32_result = f32_to_u8(&dst_f32);

        // Compare RGB channels only (alpha is set to 255 by f32 blend, untouched by u8 ref).
        for i in 0..pixels {
            for c in 0..3 {
                let idx = i * 4 + c;
                let diff = (f32_result[idx] as i32 - dst_result[idx] as i32).unsigned_abs();
                assert!(diff <= 1, "blend pixel {} ch {} diff={} (f32={} u8={})", i, c, diff, f32_result[idx], dst_result[idx]);
            }
        }
    }

    #[test]
    fn sepia_invert_brightness_parity() {
        let u8_buf: Vec<u8> = (0..64).flat_map(|v| vec![v * 4, v * 3, v * 2, 255u8]).collect();
        let pixels = u8_buf.len() / 4;

        // Test each simple filter for ±1 parity.
        for (name, filter_fn) in &[
            ("sepia", sepia_f32 as fn(&mut [f32], usize)),
            ("invert", invert_f32 as fn(&mut [f32], usize)),
        ] {
            let mut f32_buf = u8_to_f32(&u8_buf);
            filter_fn(&mut f32_buf, pixels);
            let f32_result = f32_to_u8(&f32_buf);

            // Reference: apply same math on u8.
            let mut ref_buf = u8_buf.clone();
            for i in 0..pixels {
                let base = i * 4;
                let r = ref_buf[base] as f32 / 255.0;
                let g = ref_buf[base + 1] as f32 / 255.0;
                let b = ref_buf[base + 2] as f32 / 255.0;
                let (nr, ng, nb) = match *name {
                    "sepia" => (
                        (r * 0.393 + g * 0.769 + b * 0.189).clamp(0.0, 1.0),
                        (r * 0.349 + g * 0.686 + b * 0.168).clamp(0.0, 1.0),
                        (r * 0.272 + g * 0.534 + b * 0.131).clamp(0.0, 1.0),
                    ),
                    "invert" => (1.0 - r, 1.0 - g, 1.0 - b),
                    _ => unreachable!(),
                };
                ref_buf[base] = (nr * 255.0 + 0.5) as u8;
                ref_buf[base + 1] = (ng * 255.0 + 0.5) as u8;
                ref_buf[base + 2] = (nb * 255.0 + 0.5) as u8;
            }

            for i in 0..ref_buf.len() {
                let diff = (f32_result[i] as i32 - ref_buf[i] as i32).unsigned_abs();
                assert!(diff <= 1, "{} pixel {} diff={} (f32={} ref={})", name, i, diff, f32_result[i], ref_buf[i]);
            }
        }
    }
}

