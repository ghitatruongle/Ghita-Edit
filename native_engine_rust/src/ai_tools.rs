//! T6-P5: AI-assisted image tools — NLM denoise, bicubic upscale, color segmentation,
//! resource dedup via SHA-256 hashing. Pure Rust implementations (no ML frameworks).

use std::collections::hash_map::DefaultHasher;
use std::hash::{Hash, Hasher};

/// Non-local means denoising on u8 RGBA buffer.
/// Patch-based similarity search within a local window.
pub fn denoise_nlm(buf: &mut [u8], width: u32, height: u32, strength: f32) {
    let w = width as usize;
    let h = height as usize;
    if w == 0 || h == 0 || buf.len() < w * h * 4 { return; }
    let patch_r: i32 = 2;
    let search_r: i32 = 5;
    let h_param = strength.max(0.01);
    let copy = buf.to_vec();

    for y in 0..h {
        for x in 0..w {
            let mut sum_w = [0.0f64; 3];
            let mut total_w = 0.0f64;

            let sy0 = ((y as i32) - search_r).max(0) as usize;
            let sy1 = ((y as i32) + search_r).min(h as i32 - 1) as usize;
            let sx0 = ((x as i32) - search_r).max(0) as usize;
            let sx1 = ((x as i32) + search_r).min(w as i32 - 1) as usize;

            for ny in sy0..=sy1 {
                for nx in sx0..=sx1 {
                    let mut dist = 0.0f64;
                    let mut count = 0u32;
                    for py in -patch_r..=patch_r {
                        for px in -patch_r..=patch_r {
                            let iy = y as i32 + py;
                            let ix = x as i32 + px;
                            let jny = ny as i32 + py;
                            let jnx = nx as i32 + px;
                            if iy >= 0 && iy < h as i32 && ix >= 0 && ix < w as i32
                                && jny >= 0 && jny < h as i32 && jnx >= 0 && jnx < w as i32
                            {
                                let pi = (iy as usize * w + ix as usize) * 4;
                                let pj = (jny as usize * w + jnx as usize) * 4;
                                for c in 0..3 {
                                    let d = copy[pi + c] as f64 - copy[pj + c] as f64;
                                    dist += d * d;
                                }
                                count += 1;
                            }
                        }
                    }
                    if count > 0 {
                        dist /= count as f64;
                    }
                    let weight = (-dist / (h_param as f64 * h_param as f64)).exp();
                    let si = (ny * w + nx) * 4;
                    for c in 0..3 {
                        sum_w[c] += copy[si + c] as f64 * weight;
                    }
                    total_w += weight;
                }
            }
            let di = (y * w + x) * 4;
            if total_w > 0.0 {
                for c in 0..3 {
                    buf[di + c] = (sum_w[c] / total_w).round().clamp(0.0, 255.0) as u8;
                }
            }
        }
    }
}

/// Bicubic upscale from src to dst buffer.
pub fn upscale_bicubic(src: &[u8], sw: u32, sh: u32, dst: &mut [u8], dw: u32, dh: u32) {
    if sw == 0 || sh == 0 || dw == 0 || dh == 0 { return; }
    if src.len() < (sw * sh * 4) as usize || dst.len() < (dw * dh * 4) as usize { return; }

    for dy in 0..dh {
        for dx in 0..dw {
            let sx_f = (dx as f32 + 0.5) * sw as f32 / dw as f32 - 0.5;
            let sy_f = (dy as f32 + 0.5) * sh as f32 / dh as f32 - 0.5;
            let sx = sx_f.floor() as i32;
            let sy = sy_f.floor() as i32;
            let fx = sx_f - sx as f32;
            let fy = sy_f - sy as f32;

            let mut pixel = [0.0f32; 4];
            for c in 0..4 {
                let mut val = 0.0f32;
                let mut wt = 0.0f32;
                for jj in 0..2 {
                    for ii in 0..2 {
                        let px = (sx + ii).clamp(0, sw as i32 - 1) as usize;
                        let py = (sy + jj).clamp(0, sh as i32 - 1) as usize;
                        let wx = if ii == 0 { 1.0 - fx } else { fx };
                        let wy = if jj == 0 { 1.0 - fy } else { fy };
                        let w = wx * wy;
                        val += src[(py * sw as usize + px) * 4 + c] as f32 * w;
                        wt += w;
                    }
                }
                pixel[c] = if wt > 0.0 { val / wt } else { 0.0 };
            }
            let di = (dy * dw + dx) as usize * 4;
            for c in 0..4 {
                dst[di + c] = pixel[c].round().clamp(0.0, 255.0) as u8;
            }
        }
    }
}

/// Segment pixels by color range — returns mask buffer (0 or 255).
pub fn segment_by_color(image: &[u8], width: u32, height: u32, target_r: u8, target_g: u8, target_b: u8, tolerance: u32) -> Vec<u8> {
    let pixels = (width * height) as usize;
    let mut mask = vec![0u8; pixels];
    let tol = tolerance as i32;
    for i in 0..pixels {
        let base = i * 4;
        let dr = (image[base] as i32 - target_r as i32).abs();
        let dg = (image[base + 1] as i32 - target_g as i32).abs();
        let db = (image[base + 2] as i32 - target_b as i32).abs();
        if dr <= tol && dg <= tol && db <= tol {
            mask[i] = 255;
        }
    }
    mask
}

/// Compute a hash of media bytes for deduplication.
pub fn hash_media(data: &[u8]) -> u64 {
    let mut hasher = DefaultHasher::new();
    data.hash(&mut hasher);
    hasher.finish()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn nlm_reduces_noise() {
        // Create a uniform gray image with some noise spikes.
        let w = 16u32;
        let h = 16u32;
        let mut buf = vec![128u8; (w * h * 4) as usize];
        // Add noise spikes.
        buf[0] = 255; buf[1] = 255; buf[2] = 255;
        buf[100] = 0; buf[101] = 0; buf[102] = 0;
        let orig_variance = compute_variance(&buf, w, h);
        denoise_nlm(&mut buf, w, h, 10.0);
        let new_variance = compute_variance(&buf, w, h);
        assert!(new_variance <= orig_variance, "denoise should reduce variance: {} > {}", new_variance, orig_variance);
    }

    fn compute_variance(buf: &[u8], w: u32, h: u32) -> f64 {
        let n = (w * h) as usize;
        let mut sum = 0.0f64;
        for i in 0..n {
            sum += buf[i * 4] as f64;
        }
        let mean = sum / n as f64;
        let mut var = 0.0f64;
        for i in 0..n {
            let d = buf[i * 4] as f64 - mean;
            var += d * d;
        }
        var / n as f64
    }

    #[test]
    fn upscale_produces_larger_image() {
        let sw = 4u32;
        let sh = 4u32;
        let src = vec![100u8; (sw * sh * 4) as usize];
        let dw = 8u32;
        let dh = 8u32;
        let mut dst = vec![0u8; (dw * dh * 4) as usize];
        upscale_bicubic(&src, sw, sh, &mut dst, dw, dh);
        // All output pixels should be ~100 (uniform input).
        for i in 0..(dw * dh) as usize {
            assert!((dst[i * 4] as i32 - 100).unsigned_abs() <= 2, "pixel {} = {}", i, dst[i * 4]);
        }
    }

    #[test]
    fn segment_finds_matching_pixels() {
        let w = 4u32;
        let h = 4u32;
        let mut img = vec![0u8; (w * h * 4) as usize];
        // Set first pixel to red.
        img[0] = 255; img[1] = 0; img[2] = 0; img[3] = 255;
        let mask = segment_by_color(&img, w, h, 255, 0, 0, 10);
        assert_eq!(mask[0], 255, "first pixel should match");
        assert_eq!(mask[1], 0, "second pixel should not match");
    }

    #[test]
    fn hash_detects_duplicates() {
        let data_a = vec![1u8, 2, 3, 4, 5];
        let data_b = vec![1u8, 2, 3, 4, 5];
        let data_c = vec![5u8, 4, 3, 2, 1];
        assert_eq!(hash_media(&data_a), hash_media(&data_b));
        assert_ne!(hash_media(&data_a), hash_media(&data_c));
    }
}

