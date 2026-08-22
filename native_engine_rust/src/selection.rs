//! T6-P1: Pixel-level selection tools and layer mask operations.
//!
//! Provides rect/ellipse marquee, lasso (polygon fill), magic wand (flood fill),
//! and mask operations (add/subtract/intersect/invert/feather) on a per-clip
//! pixel mask buffer (u8 alpha channel: 0=unselected, 255=selected).

use std::collections::VecDeque;

/// Selection mode for combining with existing mask.
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum MaskOp {
    Replace,
    Add,
    Subtract,
    Intersect,
}

/// A pixel selection mask for a single clip.
#[derive(Debug, Clone)]
pub struct SelectionMask {
    pub width: u32,
    pub height: u32,
    /// Row-major u8 buffer. 0 = unselected, 255 = fully selected.
    pub data: Vec<u8>,
}

impl SelectionMask {
    pub fn new(width: u32, height: u32) -> Self {
        let size = (width as usize) * (height as usize);
        Self {
            width,
            height,
            data: vec![0u8; size],
        }
    }

    pub fn clear(&mut self) {
        self.data.fill(0);
    }

    pub fn get(&self, x: i32, y: i32) -> u8 {
        if x < 0 || y < 0 || x >= self.width as i32 || y >= self.height as i32 {
            return 0;
        }
        self.data[(y as usize) * (self.width as usize) + (x as usize)]
    }

    pub fn set(&mut self, x: i32, y: i32, val: u8) {
        if x >= 0 && y >= 0 && x < self.width as i32 && y < self.height as i32 {
            self.data[(y as usize) * (self.width as usize) + (x as usize)] = val;
        }
    }

    /// Apply a mask operation combining `other` into `self`.
    pub fn combine(&mut self, other: &SelectionMask, op: MaskOp) {
        assert_eq!(self.width, other.width);
        assert_eq!(self.height, other.height);
        for i in 0..self.data.len() {
            self.data[i] = match op {
                MaskOp::Replace => other.data[i],
                MaskOp::Add => self.data[i].saturating_add(other.data[i]),
                MaskOp::Subtract => self.data[i].saturating_sub(other.data[i]),
                MaskOp::Intersect => self.data[i].min(other.data[i]),
            };
        }
    }

    /// Invert the mask (swap selected/unselected).
    pub fn invert(&mut self) {
        for v in self.data.iter_mut() {
            *v = 255 - *v;
        }
    }

    /// Feather the mask edges by averaging with neighbors.
    /// `radius` controls how many pixels of blur are applied at boundaries.
    pub fn feather(&mut self, radius: u32) {
        if radius == 0 {
            return;
        }
        let w = self.width as usize;
        let h = self.height as usize;
        let r = radius as usize;
        let mut blurred = vec![0u8; w * h];

        for y in 0..h {
            for x in 0..w {
                // Only feather boundary pixels (where value transitions).
                let idx = y * w + x;
                let val = self.data[idx];
                if val == 0 || val == 255 {
                    // Check if any neighbor differs.
                    let is_boundary = [(-1i32, 0i32), (1, 0), (0, -1), (0, 1)]
                        .iter()
                        .any(|&(dx, dy)| {
                            let nx = x as i32 + dx;
                            let ny = y as i32 + dy;
                            if nx < 0 || ny < 0 || nx >= w as i32 || ny >= h as i32 {
                                return false;
                            }
                            self.data[(ny as usize) * w + (nx as usize)] != val
                        });
                    if !is_boundary {
                        blurred[idx] = val;
                        continue;
                    }
                }
                // Box blur within radius.
                let mut sum = 0u32;
                let mut count = 0u32;
                for dy in -(r as i32)..=(r as i32) {
                    for dx in -(r as i32)..=(r as i32) {
                        let nx = x as i32 + dx;
                        let ny = y as i32 + dy;
                        if nx >= 0 && ny >= 0 && nx < w as i32 && ny < h as i32 {
                            sum += self.data[(ny as usize) * w + (nx as usize)] as u32;
                            count += 1;
                        }
                    }
                }
                blurred[idx] = if count > 0 {
                    (sum / count) as u8
                } else {
                    val
                };
            }
        }
        self.data = blurred;
    }
}

/// Fill a rectangular region in the mask.
pub fn select_rect(mask: &mut SelectionMask, x: i32, y: i32, w: i32, h: i32, op: MaskOp) {
    let temp = make_rect_mask(mask.width, mask.height, x, y, w, h);
    mask.combine(&temp, op);
}

fn make_rect_mask(mw: u32, mh: u32, x: i32, y: i32, w: i32, h: i32) -> SelectionMask {
    let mut m = SelectionMask::new(mw, mh);
    let x0 = x.max(0) as u32;
    let y0 = y.max(0) as u32;
    let x1 = ((x + w) as u32).min(mw);
    let y1 = ((y + h) as u32).min(mh);
    for row in y0..y1 {
        for col in x0..x1 {
            m.data[(row as usize) * (mw as usize) + (col as usize)] = 255;
        }
    }
    m
}

/// Fill an elliptical region in the mask.
pub fn select_ellipse(mask: &mut SelectionMask, cx: i32, cy: i32, rx: i32, ry: i32, op: MaskOp) {
    let temp = make_ellipse_mask(mask.width, mask.height, cx, cy, rx, ry);
    mask.combine(&temp, op);
}

fn make_ellipse_mask(mw: u32, mh: u32, cx: i32, cy: i32, rx: i32, ry: i32) -> SelectionMask {
    let mut m = SelectionMask::new(mw, mh);
    if rx <= 0 || ry <= 0 {
        return m;
    }
    let rx2 = (rx as f64) * (rx as f64);
    let ry2 = (ry as f64) * (ry as f64);
    let x0 = (cx - rx).max(0) as u32;
    let y0 = (cy - ry).max(0) as u32;
    let x1 = ((cx + rx + 1) as u32).min(mw);
    let y1 = ((cy + ry + 1) as u32).min(mh);
    for row in y0..y1 {
        for col in x0..x1 {
            let dx = col as f64 - cx as f64;
            let dy = row as f64 - cy as f64;
            if (dx * dx) / rx2 + (dy * dy) / ry2 <= 1.0 {
                m.data[(row as usize) * (mw as usize) + (col as usize)] = 255;
            }
        }
    }
    m
}

/// Lasso selection: fill a polygon defined by points into the mask using scanline fill.
pub fn select_lasso(mask: &mut SelectionMask, points: &[(i32, i32)], op: MaskOp) {
    if points.len() < 3 {
        return;
    }
    let temp = make_polygon_mask(mask.width, mask.height, points);
    mask.combine(&temp, op);
}

fn make_polygon_mask(mw: u32, mh: u32, points: &[(i32, i32)]) -> SelectionMask {
    let mut m = SelectionMask::new(mw, mh);
    let w = mw as usize;
    let h = mh as usize;

    // Find bounding box.
    let min_y = points.iter().map(|p| p.1).min().unwrap_or(0).max(0) as usize;
    let max_y = points.iter().map(|p| p.1).max().unwrap_or(0).min(h as i32 - 1) as usize;

    // Scanline fill.
    for y in min_y..=max_y {
        let mut intersections = Vec::new();
        let n = points.len();
        for i in 0..n {
            let j = (i + 1) % n;
            let (x0, y0) = points[i];
            let (x1, y1) = points[j];
            let yf = y as f64 + 0.5;
            if (y0 as f64 <= yf && y1 as f64 > yf) || (y1 as f64 <= yf && y0 as f64 > yf) {
                let t = (yf - y0 as f64) / (y1 as f64 - y0 as f64);
                let x = x0 as f64 + t * (x1 as f64 - x0 as f64);
                intersections.push(x);
            }
        }
        intersections.sort_by(|a, b| a.partial_cmp(b).unwrap_or(std::cmp::Ordering::Equal));
        // Fill between pairs.
        let mut i = 0;
        while i + 1 < intersections.len() {
            let x_start = (intersections[i].round() as i32).max(0) as usize;
            let x_end = (intersections[i + 1].round() as i32).min(w as i32) as usize;
            for x in x_start..x_end {
                m.data[y * w + x] = 255;
            }
            i += 2;
        }
    }
    m
}

/// Magic wand: flood-fill from seed point with color distance tolerance.
/// `image` is RGBA row-major, `tolerance` is max Euclidean RGB distance (0-441).
pub fn select_magic_wand(
    mask: &mut SelectionMask,
    image: &[u8],
    seed_x: i32,
    seed_y: i32,
    tolerance: f64,
    op: MaskOp,
) {
    let w = mask.width as usize;
    let h = mask.height as usize;
    if seed_x < 0 || seed_y < 0 || seed_x >= w as i32 || seed_y >= h as i32 {
        return;
    }
    let seed_idx = (seed_y as usize) * w + (seed_x as usize);
    let seed_r = image[seed_idx * 4] as f64;
    let seed_g = image[seed_idx * 4 + 1] as f64;
    let seed_b = image[seed_idx * 4 + 2] as f64;
    let tol2 = tolerance * tolerance;

    let mut visited = vec![false; w * h];
    let mut queue = VecDeque::new();
    queue.push_back((seed_x, seed_y));
    visited[seed_idx] = true;

    let mut temp = SelectionMask::new(mask.width, mask.height);

    while let Some((x, y)) = queue.pop_front() {
        let idx = (y as usize) * w + (x as usize);
        let r = image[idx * 4] as f64;
        let g = image[idx * 4 + 1] as f64;
        let b = image[idx * 4 + 2] as f64;
        let dist2 = (r - seed_r).powi(2) + (g - seed_g).powi(2) + (b - seed_b).powi(2);
        if dist2 <= tol2 {
            temp.data[idx] = 255;
            // Enqueue 4-connected neighbors.
            for &(dx, dy) in &[(-1i32, 0i32), (1, 0), (0, -1), (0, 1)] {
                let nx = x + dx;
                let ny = y + dy;
                if nx >= 0 && ny >= 0 && nx < w as i32 && ny < h as i32 {
                    let ni = (ny as usize) * w + (nx as usize);
                    if !visited[ni] {
                        visited[ni] = true;
                        queue.push_back((nx, ny));
                    }
                }
            }
        }
    }
    mask.combine(&temp, op);
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rect_selection_fills_region() {
        let mut mask = SelectionMask::new(100, 100);
        select_rect(&mut mask, 10, 20, 30, 40, MaskOp::Replace);
        // Inside.
        assert_eq!(mask.get(25, 40), 255);
        // Outside.
        assert_eq!(mask.get(5, 10), 0);
        assert_eq!(mask.get(50, 70), 0);
        // Edge.
        assert_eq!(mask.get(10, 20), 255);
        assert_eq!(mask.get(39, 59), 255);
    }

    #[test]
    fn ellipse_selection_fills_region() {
        let mut mask = SelectionMask::new(100, 100);
        select_ellipse(&mut mask, 50, 50, 20, 10, MaskOp::Replace);
        // Center.
        assert_eq!(mask.get(50, 50), 255);
        // On horizontal axis.
        assert_eq!(mask.get(60, 50), 255);
        // Outside.
        assert_eq!(mask.get(80, 50), 0);
        assert_eq!(mask.get(50, 30), 0);
    }

    #[test]
    fn lasso_fills_triangle() {
        let mut mask = SelectionMask::new(100, 100);
        let points = [(10, 10), (90, 10), (50, 90)];
        select_lasso(&mut mask, &points, MaskOp::Replace);
        // Centroid should be inside.
        assert_eq!(mask.get(50, 37), 255);
        // Corner outside.
        assert_eq!(mask.get(0, 0), 0);
        assert_eq!(mask.get(99, 99), 0);
    }

    #[test]
    fn magic_wand_respects_tolerance() {
        let w = 10u32;
        let h = 10u32;
        // Create image: left half red, right half blue.
        let mut image = vec![0u8; (w * h * 4) as usize];
        for y in 0..h {
            for x in 0..w {
                let idx = ((y * w + x) * 4) as usize;
                if x < w / 2 {
                    image[idx] = 255; // R
                    image[idx + 1] = 0;
                    image[idx + 2] = 0;
                } else {
                    image[idx] = 0;
                    image[idx + 1] = 0;
                    image[idx + 2] = 255; // B
                }
                image[idx + 3] = 255; // A
            }
        }
        let mut mask = SelectionMask::new(w, h);
        // Low tolerance: only selects red region.
        select_magic_wand(&mut mask, &image, 2, 5, 10.0, MaskOp::Replace);
        assert_eq!(mask.get(2, 5), 255); // Red pixel selected.
        assert_eq!(mask.get(7, 5), 0); // Blue pixel not selected.

        // High tolerance: selects everything.
        let mut mask2 = SelectionMask::new(w, h);
        select_magic_wand(&mut mask2, &image, 2, 5, 500.0, MaskOp::Replace);
        assert_eq!(mask2.get(2, 5), 255);
        assert_eq!(mask2.get(7, 5), 255);
    }

    #[test]
    fn mask_operations() {
        let mut a = SelectionMask::new(10, 10);
        select_rect(&mut a, 0, 0, 5, 10, MaskOp::Replace);
        let mut b = SelectionMask::new(10, 10);
        select_rect(&mut b, 3, 0, 7, 10, MaskOp::Replace);

        // Add.
        let mut c = a.clone();
        c.combine(&b, MaskOp::Add);
        assert_eq!(c.get(1, 5), 255); // Only in A.
        assert_eq!(c.get(4, 5), 255); // In both, saturates to 255.
        assert_eq!(c.get(8, 5), 255); // Only in B.

        // Subtract.
        let mut d = a.clone();
        d.combine(&b, MaskOp::Subtract);
        assert_eq!(d.get(1, 5), 255); // Only in A remains.
        assert_eq!(d.get(4, 5), 0); // Overlap removed.

        // Intersect.
        let mut e = a.clone();
        e.combine(&b, MaskOp::Intersect);
        assert_eq!(e.get(1, 5), 0); // Only in A.
        assert_eq!(e.get(4, 5), 255); // Overlap kept.
        assert_eq!(e.get(8, 5), 0); // Only in B.
    }

    #[test]
    fn invert_swaps_selection() {
        let mut mask = SelectionMask::new(10, 10);
        select_rect(&mut mask, 0, 0, 5, 10, MaskOp::Replace);
        mask.invert();
        assert_eq!(mask.get(1, 5), 0);
        assert_eq!(mask.get(8, 5), 255);
    }

    #[test]
    fn feather_softens_edges() {
        let mut mask = SelectionMask::new(20, 20);
        select_rect(&mut mask, 5, 5, 10, 10, MaskOp::Replace);
        // Before feather: sharp edge.
        assert_eq!(mask.get(4, 10), 0);
        assert_eq!(mask.get(5, 10), 255);
        mask.feather(2);
        // After feather: boundary pixel should be intermediate.
        let edge_val = mask.get(5, 10);
        assert!(edge_val > 0 && edge_val < 255, "edge={} should be intermediate", edge_val);
    }
}

