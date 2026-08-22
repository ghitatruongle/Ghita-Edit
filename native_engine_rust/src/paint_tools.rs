/// Paint tools for T6-P2: clone stamp, heal spot, bezier path.

/// Copies pixels from a source region to a destination buffer with circular falloff.
pub fn clone_stamp(
    src: &[u8],
    dst: &mut [u8],
    width: u32,
    height: u32,
    src_x: i32,
    src_y: i32,
    dst_x: i32,
    dst_y: i32,
    radius: u32,
    opacity: f32,
) {
    let w = width as i32;
    let h = height as i32;
    let r = radius as i32;
    let r_sq = (radius as f32) * (radius as f32);
    let opacity = opacity.clamp(0.0, 1.0);

    for dy in -r..=r {
        for dx in -r..=r {
            let dist_sq = (dx * dx + dy * dy) as f32;
            if dist_sq > r_sq {
                continue;
            }

            let dst_px = dst_x + dx;
            let dst_py = dst_y + dy;
            let src_px = src_x + dx;
            let src_py = src_y + dy;

            if dst_px < 0 || dst_px >= w || dst_py < 0 || dst_py >= h {
                continue;
            }
            if src_px < 0 || src_px >= w || src_py < 0 || src_py >= h {
                continue;
            }

            let falloff = 1.0 - (dist_sq / r_sq).sqrt();
            let alpha = opacity * falloff;

            let dst_idx = ((dst_py * w + dst_px) as usize) * 4;
            let src_idx = ((src_py * w + src_px) as usize) * 4;

            for c in 0..4 {
                let s = src[src_idx + c] as f32;
                let d = dst[dst_idx + c] as f32;
                dst[dst_idx + c] = (d * (1.0 - alpha) + s * alpha).round() as u8;
            }
        }
    }
}

/// Blends surrounding pixels over a target area using weighted average of neighbors.
pub fn heal_spot(buf: &mut [u8], width: u32, height: u32, cx: i32, cy: i32, radius: u32) {
    let w = width as i32;
    let h = height as i32;
    let r = radius as i32;
    let r_sq = (radius as f32) * (radius as f32);
    let border_width: i32 = 2;

    let mut border_pixels: Vec<([u8; 4], f32)> = Vec::new();

    for dy in -(r + border_width)..=(r + border_width) {
        for dx in -(r + border_width)..=(r + border_width) {
            let dist_sq = (dx * dx + dy * dy) as f32;
            let px = cx + dx;
            let py = cy + dy;
            if px < 0 || px >= w || py < 0 || py >= h {
                continue;
            }
            if dist_sq > r_sq && dist_sq <= (r + border_width) as f32 * (r + border_width) as f32 {
                let idx = ((py * w + px) as usize) * 4;
                let pixel = [buf[idx], buf[idx + 1], buf[idx + 2], buf[idx + 3]];
                let dist = dist_sq.sqrt();
                border_pixels.push((pixel, dist));
            }
        }
    }

    if border_pixels.is_empty() {
        return;
    }

    let mut new_pixels: Vec<(usize, [u8; 4])> = Vec::new();

    for dy in -r..=r {
        for dx in -r..=r {
            let dist_sq = (dx * dx + dy * dy) as f32;
            if dist_sq > r_sq {
                continue;
            }
            let px = cx + dx;
            let py = cy + dy;
            if px < 0 || px >= w || py < 0 || py >= h {
                continue;
            }

            let mut sum = [0.0f32; 4];
            let mut weight_total = 0.0f32;

            for &(ref bp, bdist) in &border_pixels {
                let weight = 1.0 / (bdist + 0.001);
                for c in 0..4 {
                    sum[c] += bp[c] as f32 * weight;
                }
                weight_total += weight;
            }

            let mut pixel = [0u8; 4];
            for c in 0..4 {
                pixel[c] = (sum[c] / weight_total).round() as u8;
            }

            let idx = ((py * w + px) as usize) * 4;
            new_pixels.push((idx, pixel));
        }
    }

    for (idx, pixel) in new_pixels {
        for c in 0..4 {
            buf[idx + c] = pixel[c];
        }
    }
}

/// Evaluates a cubic Bezier curve at parameter t (0.0-1.0).
pub fn bezier_point(
    t: f32,
    p0: (f32, f32),
    p1: (f32, f32),
    p2: (f32, f32),
    p3: (f32, f32),
) -> (f32, f32) {
    let t = t.clamp(0.0, 1.0);
    let mt = 1.0 - t;
    let mt2 = mt * mt;
    let mt3 = mt2 * mt;
    let t2 = t * t;
    let t3 = t2 * t;

    let x = mt3 * p0.0 + 3.0 * mt2 * t * p1.0 + 3.0 * mt * t2 * p2.0 + t3 * p3.0;
    let y = mt3 * p0.1 + 3.0 * mt2 * t * p1.1 + 3.0 * mt * t2 * p2.1 + t3 * p3.1;

    (x, y)
}

/// Rasterizes a cubic Bezier curve onto an RGBA buffer.
pub fn rasterize_bezier(
    buf: &mut [u8],
    width: u32,
    height: u32,
    points: &[(f32, f32); 4],
    color: [u8; 4],
    steps: u32,
) {
    let w = width as i32;
    let h = height as i32;
    let steps = steps.max(1);

    let mut prev: Option<(i32, i32)> = None;

    for i in 0..=steps {
        let t = i as f32 / steps as f32;
        let (fx, fy) = bezier_point(t, points[0], points[1], points[2], points[3]);
        let px = fx.round() as i32;
        let py = fy.round() as i32;

        if let Some((px0, py0)) = prev {
            draw_line(buf, w, h, px0, py0, px, py, color);
        } else {
            set_pixel(buf, w, h, px, py, color);
        }
        prev = Some((px, py));
    }
}

fn set_pixel(buf: &mut [u8], w: i32, h: i32, x: i32, y: i32, color: [u8; 4]) {
    if x >= 0 && x < w && y >= 0 && y < h {
        let idx = ((y * w + x) as usize) * 4;
        buf[idx..idx + 4].copy_from_slice(&color);
    }
}

fn draw_line(buf: &mut [u8], w: i32, h: i32, x0: i32, y0: i32, x1: i32, y1: i32, color: [u8; 4]) {
    let dx = (x1 - x0).abs();
    let dy = -(y1 - y0).abs();
    let sx: i32 = if x0 < x1 { 1 } else { -1 };
    let sy: i32 = if y0 < y1 { 1 } else { -1 };
    let mut err = dx + dy;

    let mut x = x0;
    let mut y = y0;

    loop {
        set_pixel(buf, w, h, x, y, color);
        if x == x1 && y == y1 {
            break;
        }
        let e2 = 2 * err;
        if e2 >= dy {
            err += dy;
            x += sx;
        }
        if e2 <= dx {
            err += dx;
            y += sy;
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn make_buf(width: u32, height: u32, fill: [u8; 4]) -> Vec<u8> {
        let len = (width * height) as usize * 4;
        let mut buf = vec![0u8; len];
        for i in 0..(width * height) as usize {
            buf[i * 4..i * 4 + 4].copy_from_slice(&fill);
        }
        buf
    }

    #[test]
    fn clone_copies_region() {
        let width = 20u32;
        let height = 20u32;
        let src = make_buf(width, height, [255, 0, 0, 255]);
        let mut dst = make_buf(width, height, [0, 0, 255, 255]);
        let radius = 5u32;

        clone_stamp(&src, &mut dst, width, height, 10, 10, 10, 10, radius, 1.0);

        let center_idx = ((10 * width as i32 + 10) as usize) * 4;
        assert_eq!(dst[center_idx], 255, "Red channel at center should be 255");
        assert_eq!(dst[center_idx + 1], 0, "Green channel at center should be 0");
        assert_eq!(dst[center_idx + 2], 0, "Blue channel at center should be 0");
        assert_eq!(dst[center_idx + 3], 255, "Alpha at center should be 255");

        let far_idx = 0usize * 4;
        assert_eq!(dst[far_idx], 0, "Red at far corner should be 0");
        assert_eq!(dst[far_idx + 2], 255, "Blue at far corner should be 255");
    }

    #[test]
    fn heal_blends_with_surroundings() {
        let width = 30u32;
        let height = 30u32;
        let mut buf = make_buf(width, height, [0, 200, 0, 255]);
        let cx = 15i32;
        let cy = 15i32;
        let radius = 4u32;

        for dy in -(radius as i32)..=(radius as i32) {
            for dx in -(radius as i32)..=(radius as i32) {
                if dx * dx + dy * dy <= (radius * radius) as i32 {
                    let px = cx + dx;
                    let py = cy + dy;
                    let idx = ((py * width as i32 + px) as usize) * 4;
                    buf[idx] = 255;
                    buf[idx + 1] = 0;
                    buf[idx + 2] = 0;
                }
            }
        }

        let center_idx = ((cy * width as i32 + cx) as usize) * 4;
        let orig_r = buf[center_idx];

        heal_spot(&mut buf, width, height, cx, cy, radius);

        let healed_r = buf[center_idx];
        let healed_g = buf[center_idx + 1];

        assert_ne!(healed_r, orig_r, "Healed red channel should differ from original");
        assert!(healed_g > 0, "Healed pixel should have some green from surroundings");
    }

    #[test]
    fn bezier_endpoints() {
        let p0 = (0.0, 0.0);
        let p1 = (1.0, 2.0);
        let p2 = (3.0, 2.0);
        let p3 = (4.0, 0.0);

        let start = bezier_point(0.0, p0, p1, p2, p3);
        assert!(
            (start.0 - p0.0).abs() < 1e-5 && (start.1 - p0.1).abs() < 1e-5,
            "t=0 should return p0"
        );

        let end = bezier_point(1.0, p0, p1, p2, p3);
        assert!(
            (end.0 - p3.0).abs() < 1e-5 && (end.1 - p3.1).abs() < 1e-5,
            "t=1 should return p3"
        );
    }

    #[test]
    fn rasterize_draws_pixels() {
        let width = 50u32;
        let height = 50u32;
        let mut buf = make_buf(width, height, [0, 0, 0, 0]);
        let points: [(f32, f32); 4] = [(5.0, 25.0), (15.0, 5.0), (35.0, 45.0), (45.0, 25.0)];
        let color = [255, 255, 255, 255];

        rasterize_bezier(&mut buf, width, height, &points, color, 100);

        let start_idx = ((25 * width as i32 + 5) as usize) * 4;
        assert_eq!(buf[start_idx], 255, "Start point should be drawn");

        let end_idx = ((25 * width as i32 + 45) as usize) * 4;
        assert_eq!(buf[end_idx], 255, "End point should be drawn");

        let mut drawn_count = 0u32;
        for i in 0..(width * height) as usize {
            if buf[i * 4] != 0 || buf[i * 4 + 1] != 0 || buf[i * 4 + 2] != 0 {
                drawn_count += 1;
            }
        }
        assert!(drawn_count > 10, "Should draw more than 10 pixels, got {}", drawn_count);
    }
}
