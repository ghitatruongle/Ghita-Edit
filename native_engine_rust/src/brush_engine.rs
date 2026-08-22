//! T6-P4: Brush engines — pixel brush, smudge, stroke stabilizer.

/// Brush parameters.
#[derive(Debug, Clone)]
pub struct BrushParams {
    pub size: f32,
    pub hardness: f32,
    pub opacity: f32,
    pub flow: f32,
}

impl Default for BrushParams {
    fn default() -> Self {
        Self { size: 10.0, hardness: 0.5, opacity: 1.0, flow: 1.0 }
    }
}

/// Paint a single circular brush dab onto an RGBA buffer.
pub fn brush_stamp(
    buf: &mut [u8], width: u32, height: u32,
    cx: f32, cy: f32, params: &BrushParams, color: [u8; 4],
) {
    let r = params.size / 2.0;
    let r2 = r * r;
    let inner = r * params.hardness;
    let x0 = ((cx - r).floor() as i32).max(0);
    let x1 = ((cx + r).ceil() as i32).min(width as i32 - 1);
    let y0 = ((cy - r).floor() as i32).max(0);
    let y1 = ((cy + r).ceil() as i32).min(height as i32 - 1);

    for y in y0..=y1 {
        for x in x0..=x1 {
            let dx = x as f32 - cx;
            let dy = y as f32 - cy;
            let d2 = dx * dx + dy * dy;
            if d2 > r2 { continue; }
            let dist = d2.sqrt();
            let alpha = if dist <= inner {
                1.0
            } else {
                1.0 - (dist - inner) / (r - inner + 0.001)
            };
            let a = (alpha * params.opacity * params.flow).clamp(0.0, 1.0);
            let idx = (y as usize * width as usize + x as usize) * 4;
            for c in 0..3 {
                let src = color[c] as f32 / 255.0;
                let dst = buf[idx + c] as f32 / 255.0;
                buf[idx + c] = ((dst * (1.0 - a) + src * a) * 255.0 + 0.5) as u8;
            }
            // Alpha channel: max of existing and brush alpha.
            buf[idx + 3] = buf[idx + 3].max((a * 255.0 + 0.5) as u8);
        }
    }
}

/// Paint a stroke by interpolating between points and stamping along the path.
pub fn brush_stroke(
    buf: &mut [u8], width: u32, height: u32,
    points: &[(f32, f32)], params: &BrushParams, color: [u8; 4],
) {
    if points.is_empty() { return; }
    if points.len() == 1 {
        brush_stamp(buf, width, height, points[0].0, points[0].1, params, color);
        return;
    }
    let spacing = (params.size * 0.25).max(1.0);
    for w in points.windows(2) {
        let (x0, y0) = w[0];
        let (x1, y1) = w[1];
        let dx = x1 - x0;
        let dy = y1 - y0;
        let dist = (dx * dx + dy * dy).sqrt();
        let steps = (dist / spacing).ceil() as u32;
        for s in 0..=steps {
            let t = if steps == 0 { 0.0 } else { s as f32 / steps as f32 };
            brush_stamp(buf, width, height, x0 + dx * t, y0 + dy * t, params, color);
        }
    }
}

/// Smudge stroke: blend neighboring pixels along a path.
pub fn smudge_stroke(
    buf: &mut [u8], width: u32, height: u32,
    points: &[(f32, f32)], radius: u32, strength: f32,
) {
    if points.len() < 2 { return; }
    let w = width as usize;
    for pair in points.windows(2) {
        let (x0, y0) = pair[0];
        let (x1, y1) = pair[1];
        let cx = ((x0 + x1) / 2.0) as i32;
        let cy = ((y0 + y1) / 2.0) as i32;
        let r = radius as i32;
        for dy in -r..=r {
            for dx in -r..=r {
                if dx * dx + dy * dy > r * r { continue; }
                let px = cx + dx;
                let py = cy + dy;
                if px < 1 || px >= width as i32 - 1 || py < 1 || py >= height as i32 - 1 { continue; }
                let idx = (py as usize * w + px as usize) * 4;
                // Average of 4-connected neighbors.
                let up = ((py as usize - 1) * w + px as usize) * 4;
                let dn = ((py as usize + 1) * w + px as usize) * 4;
                let lt = (py as usize * w + px as usize - 1) * 4;
                let rt = (py as usize * w + px as usize + 1) * 4;
                for c in 0..3 {
                    let avg = (buf[up + c] as f32 + buf[dn + c] as f32 + buf[lt + c] as f32 + buf[rt + c] as f32) / 4.0;
                    let cur = buf[idx + c] as f32;
                    buf[idx + c] = (cur * (1.0 - strength) + avg * strength + 0.5) as u8;
                }
            }
        }
    }
}

/// Moving-average stroke stabilizer.
pub fn stabilize_points(points: &[(f32, f32)], factor: usize) -> Vec<(f32, f32)> {
    if factor <= 1 || points.is_empty() { return points.to_vec(); }
    let mut out = Vec::with_capacity(points.len());
    for i in 0..points.len() {
        let start = i.saturating_sub(factor - 1);
        let window = &points[start..=i];
        let sx: f32 = window.iter().map(|p| p.0).sum();
        let sy: f32 = window.iter().map(|p| p.1).sum();
        let n = window.len() as f32;
        out.push((sx / n, sy / n));
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn stamp_modifies_pixels() {
        let mut buf = vec![0u8; 20 * 20 * 4];
        let params = BrushParams { size: 10.0, hardness: 0.8, opacity: 1.0, flow: 1.0 };
        brush_stamp(&mut buf, 20, 20, 10.0, 10.0, &params, [255, 0, 0, 255]);
        // Center pixel should be red.
        let idx = (10 * 20 + 10) * 4;
        assert_eq!(buf[idx], 255, "center R should be 255");
        assert_eq!(buf[idx + 1], 0, "center G should be 0");
    }

    #[test]
    fn stroke_connects_points() {
        let mut buf = vec![0u8; 40 * 40 * 4];
        let params = BrushParams { size: 6.0, hardness: 1.0, opacity: 1.0, flow: 1.0 };
        brush_stroke(&mut buf, 40, 40, &[(5.0, 20.0), (35.0, 20.0)], &params, [0, 255, 0, 255]);
        // Midpoint should have green.
        let idx = (20 * 40 + 20) * 4;
        assert!(buf[idx + 1] > 100, "midpoint G={} should be painted", buf[idx + 1]);
    }

    #[test]
    fn smudge_blends() {
        let mut buf = vec![128u8; 20 * 20 * 4];
        // Create a bright spot.
        let idx = (10 * 20 + 10) * 4;
        buf[idx] = 255; buf[idx + 1] = 255; buf[idx + 2] = 255;
        let orig = buf[idx];
        smudge_stroke(&mut buf, 20, 20, &[(8.0, 10.0), (12.0, 10.0)], 3, 0.5);
        assert_ne!(buf[idx], orig, "smudge should modify the bright pixel");
    }

    #[test]
    fn stabilize_smooths() {
        let pts = vec![(0.0, 0.0), (10.0, 0.0), (10.0, 10.0), (0.0, 10.0)];
        let stable = stabilize_points(&pts, 3);
        // Stabilized path should have smaller total angular change.
        assert_eq!(stable.len(), pts.len());
        // Last point should be averaged with predecessors.
        assert!(stable[3].0 > pts[3].0, "stabilized x should shift toward mean");
    }
}

