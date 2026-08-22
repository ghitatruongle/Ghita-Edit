//! T3 video FX helpers: blend modes (#4) and geometric masks (#5) — used by
//! the compositor; kept here so the pixel math stays testable in isolation.

use crate::model::{BlendMode, MaskType};

/// Per-pixel blend mode result (before the alpha lerp).
pub fn blend_pixel_mode(dst: u8, src: u8, mode: BlendMode) -> u8 {
    match mode {
        BlendMode::Multiply => ((dst as u32 * src as u32) / 255) as u8,
        BlendMode::Screen => (255u32 - ((255 - dst as u32) * (255 - src as u32)) / 255) as u8,
        BlendMode::Overlay => {
            if dst < 128 {
                ((2 * dst as u32 * src as u32) / 255).min(255) as u8
            } else {
                (255 - (2 * (255 - dst as u32) * (255 - src as u32)) / 255) as u8
            }
        }
        BlendMode::Add => ((dst as u32 + src as u32).min(255)) as u8,
        BlendMode::Normal => src,
    }
}

/// Alpha blend with a blend mode — out = dst·(1−a) + mode(src,dst)·a.
pub fn blend_rgba_mode(dst: &mut [u8], src: &[u8], pixel_count: usize, alpha: f32, mode: BlendMode) {
    if alpha <= 0.0 {
        return;
    }
    if mode == BlendMode::Normal {
        crate::compositor::blend_rgba(dst, src, pixel_count, alpha);
        return;
    }
    if alpha >= 1.0 {
        for i in 0..pixel_count {
            let d = i * 4;
            dst[d] = blend_pixel_mode(dst[d], src[d], mode);
            dst[d + 1] = blend_pixel_mode(dst[d + 1], src[d + 1], mode);
            dst[d + 2] = blend_pixel_mode(dst[d + 2], src[d + 2], mode);
            dst[d + 3] = 255;
        }
        return;
    }
    let ia = 1.0 - alpha;
    for i in 0..pixel_count {
        let d = i * 4;
        dst[d] = (dst[d] as f32 * ia + blend_pixel_mode(dst[d], src[d], mode) as f32 * alpha) as u8;
        dst[d + 1] = (dst[d + 1] as f32 * ia + blend_pixel_mode(dst[d + 1], src[d + 1], mode) as f32 * alpha) as u8;
        dst[d + 2] = (dst[d + 2] as f32 * ia + blend_pixel_mode(dst[d + 2], src[d + 2], mode) as f32 * alpha) as u8;
        dst[d + 3] = 255;
    }
}

fn star_inside(x: f32, y: f32) -> bool {
    let mut best = f32::MAX;
    for k in 0..5 {
        let a0 = k as f32 * (2.0 * std::f32::consts::PI / 5.0) - std::f32::consts::PI / 2.0;
        let a1 = a0 + std::f32::consts::PI / 5.0;
        let (x0, y0) = (0.5 * a0.cos(), 0.5 * a0.sin());
        let (x1, y1) = (0.22 * a1.cos(), 0.22 * a1.sin());
        let cross = (x1 - x0) * (y - y0) - (y1 - y0) * (x - x0);
        best = best.min(cross);
    }
    best <= 0.0
}

/// Mask coverage in [0,1] at normalized (nx, ny) ∈ [0,1]².
/// `d` is a signed edge distance (<0 inside, >0 outside) for each shape.
/// Shapes live in a centered box of half-size 0.4 (80% of the frame), so the
/// mask actually cuts out the frame edges.
pub fn mask_coverage(mask: MaskType, nx: f32, ny: f32, feather: f32, stroke: f32) -> f32 {
    const HS: f32 = 0.4; // shape half-size (fraction of frame)
    let d: f32 = match mask {
        MaskType::None => return 1.0,
        MaskType::Rect => ((nx - 0.5).abs() / HS - 1.0).max((ny - 0.5).abs() / HS - 1.0),
        MaskType::Ellipse => {
            let dx = (nx - 0.5) / HS;
            let dy = (ny - 0.5) / HS;
            (dx * dx + dy * dy).sqrt() - 1.0
        }
        MaskType::Diamond => (nx - 0.5).abs() / HS + (ny - 0.5).abs() / HS - 1.0,
        MaskType::Star => {
            let x = (nx - 0.5) / HS;
            let y = (ny - 0.5) / HS;
            let mut best = f32::MAX;
            for k in 0..5 {
                let a0 = k as f32 * (2.0 * std::f32::consts::PI / 5.0) - std::f32::consts::PI / 2.0;
                let a1 = a0 + std::f32::consts::PI / 5.0;
                let (x0, y0) = (0.5 * a0.cos(), 0.5 * a0.sin());
                let (x1, y1) = (0.22 * a1.cos(), 0.22 * a1.sin());
                let (px, py) = (x - x0, y - y0);
                let (sx, sy) = (x1 - x0, y1 - y0);
                let len2 = sx * sx + sy * sy;
                let t = ((px * sx + py * sy) / len2).clamp(0.0, 1.0);
                let dx = px - t * sx;
                let dy = py - t * sy;
                best = best.min((dx * dx + dy * dy).sqrt());
            }
            if star_inside(x, y) { -best } else { best }
        }
        MaskType::Heart => {
            let x = (nx - 0.5) / HS * 0.9;
            let y = (ny - 0.5) / HS * 0.9;
            let v = (x * x + y * y - 1.0).powi(3) - x * x * y * y * y;
            if v <= 0.0 { -1.0 } else { 1.0 }
        }
        MaskType::CinematicBars => {
            // Letterbox: the top/bottom bands are HIDDEN (coverage 0 there).
            if ny < 0.125 || ny > 0.875 {
                let de = if ny < 0.125 { 0.125 - ny } else { ny - 0.875 };
                return (1.0 - de / (0.125 * feather.max(0.0001))).clamp(0.0, 1.0);
            }
            return 1.0;
        }
    };
    let f = feather.max(0.0001);
    if stroke > 0.0 {
        // Outline-only: coverage 1 inside the stroke band around the edge.
        let band = (d.abs() - stroke * 0.5) / (f * 0.5);
        (1.0 - band).clamp(0.0, 1.0)
    } else {
        // Filled shape with feathered edge.
        (0.5 - d / f).clamp(0.0, 1.0)
    }
}

/// Writes mask coverage into the alpha channel of [buf].
pub fn apply_mask_to_alpha(buf: &mut [u8], width: usize, height: usize, mask: MaskType, feather: f32, stroke: f32) {
    if mask == MaskType::None {
        return;
    }
    for y in 0..height {
        for x in 0..width {
            let nx = x as f32 / width as f32;
            let ny = y as f32 / height as f32;
            let c = mask_coverage(mask, nx, ny, feather, stroke);
            let i = (y * width + x) * 4;
            buf[i + 3] = (buf[i + 3] as f32 * c) as u8;
        }
    }
}

/// Blend with blend mode + optional source-alpha (masked) support.
pub fn blend_clip(dst: &mut [u8], src: &[u8], pixel_count: usize, alpha: f32, mode: BlendMode, use_src_alpha: bool) {
    if mode == BlendMode::Normal && !use_src_alpha {
        crate::compositor::blend_rgba(dst, src, pixel_count, alpha);
        return;
    }
    let ia = 1.0 - alpha;
    for i in 0..pixel_count {
        let d = i * 4;
        let sa = if use_src_alpha { src[d + 3] as f32 / 255.0 } else { 1.0 };
        let eff = alpha * sa;
        if eff <= 0.0 {
            continue;
        }
        let eia = 1.0 - eff;
        dst[d] = (dst[d] as f32 * eia + blend_pixel_mode(dst[d], src[d], mode) as f32 * eff) as u8;
        dst[d + 1] = (dst[d + 1] as f32 * eia + blend_pixel_mode(dst[d + 1], src[d + 1], mode) as f32 * eff) as u8;
        dst[d + 2] = (dst[d + 2] as f32 * eia + blend_pixel_mode(dst[d + 2], src[d + 2], mode) as f32 * eff) as u8;
        dst[d + 3] = 255;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn blend_modes_match_expected() {
        // Multiply: 128 * 200 / 255 = 100
        assert_eq!(blend_pixel_mode(128, 200, BlendMode::Multiply), 100);
        // Screen: 255 - (127*55)/255 = 255 - 27 = 228
        assert_eq!(blend_pixel_mode(128, 200, BlendMode::Screen), 228);
        // Add: 200 + 128 = 328 → 255
        assert_eq!(blend_pixel_mode(128, 200, BlendMode::Add), 255);
        // Overlay with dst < 128: 2*100*200/255 = 156
        assert_eq!(blend_pixel_mode(100, 200, BlendMode::Overlay), 156);
        // Normal passthrough
        assert_eq!(blend_pixel_mode(10, 200, BlendMode::Normal), 200);
    }

    #[test]
    fn mask_coverage_shapes() {
        // Rect center fully covered, corner outside.
        assert_eq!(mask_coverage(MaskType::Rect, 0.5, 0.5, 0.0, 0.0), 1.0);
        assert_eq!(mask_coverage(MaskType::Rect, 0.99, 0.99, 0.0, 0.0), 0.0);
        // Ellipse center in, corner out.
        assert_eq!(mask_coverage(MaskType::Ellipse, 0.5, 0.5, 0.0, 0.0), 1.0);
        assert_eq!(mask_coverage(MaskType::Ellipse, 0.99, 0.99, 0.0, 0.0), 0.0);
        // Cinematic bars: band area out, mid-frame in.
        assert_eq!(mask_coverage(MaskType::CinematicBars, 0.5, 0.05, 0.0, 0.0), 0.0);
        assert_eq!(mask_coverage(MaskType::CinematicBars, 0.5, 0.5, 0.0, 0.0), 1.0);
    }

    #[test]
    fn apply_mask_writes_alpha() {
        let mut buf = vec![100u8; 64 * 36 * 4];
        for px in buf.chunks_exact_mut(4) {
            px[3] = 255;
        }
        apply_mask_to_alpha(&mut buf, 64, 36, MaskType::Rect, 0.0, 0.0);
        // Center pixel keeps alpha, extreme corner gets 0.
        assert_eq!(buf[(18 * 64 + 32) * 4 + 3], 255);
        assert_eq!(buf[(35 * 64 + 63) * 4 + 3], 0);
    }
}
