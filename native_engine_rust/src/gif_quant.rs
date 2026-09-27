//! v1.5.5-beta1 (T2): GIF palette quantization — median-cut over a 5-bit
//! color histogram, a 15-bit nearest-color cache, and Floyd–Steinberg
//! dithering. Pure Rust (no ffmpeg dep) so the unit tests run in the
//! default-feature test suite.
//!
//! Why this exists: the libavcodec GIF encoder ONLY accepts AV_PIX_FMT_PAL8.
//! The v1.1.0 path set pix_fmt = BGRA, `avcodec_open2` failed, and every GIF
//! export produced a 0-byte file (the "GIF export animated thật" claim in
//! CHANGELOG v1.0.0 never worked). This module supplies the missing
//! RGBA → indexed-color conversion.

/// A 256-entry RGBA palette plus a 32×32×32 (15-bit) nearest-color cache.
pub struct GifPalette {
    /// 256 RGBA entries (a = 255).
    pub entries: [[u8; 4]; 256],
    /// Cache mapping a 5-bit-per-channel color to its palette index.
    lut: Vec<u8>,
    /// Number of populated palette entries (median-cut may use fewer).
    pub used: usize,
}

const BINS: usize = 32 * 32 * 32;

impl GifPalette {
    /// Build a palette from sampled RGBA bytes (samples may be whole frames;
    /// the caller decides the stride). Deterministic: same input → same
    /// palette, so an export is byte-reproducible.
    pub fn build(rgba_samples: &[u8]) -> Self {
        let mut hist = [0u32; BINS];
        let mut sum_r = [0u32; BINS];
        let mut sum_g = [0u32; BINS];
        let mut sum_b = [0u32; BINS];
        let px_count = rgba_samples.len() / 4;
        for p in 0..px_count {
            let r = rgba_samples[p * 4] as u32;
            let g = rgba_samples[p * 4 + 1] as u32;
            let b = rgba_samples[p * 4 + 2] as u32;
            let bin = Self::bin_of(r, g, b);
            hist[bin] += 1;
            sum_r[bin] += r;
            sum_g[bin] += g;
            sum_b[bin] += b;
        }

        // Non-empty bins as median-cut boxes.
        let mut boxes: Vec<Box> = Vec::new();
        boxes.push(Box {
            lo: [0, 0, 0],
            hi: [31, 31, 31],
            start: 0,
            end: 0,
            pop: 0,
        });
        // Working set = the indices of populated bins (sorted per axis on split).
        let mut idx: Vec<u16> = (0..BINS as u16).filter(|b| hist[*b as usize] > 0).collect();
        boxes[0].start = 0;
        boxes[0].end = idx.len();

        while boxes.len() < 256 {
            // Split the box with the largest weighted volume first.
            let target = boxes
                .iter()
                .enumerate()
                .filter(|(_, bx)| bx.end > bx.start + 1)
                .max_by_key(|(_, bx)| (bx.pop, bx.longest_axis().1))
                .map(|(i, _)| i);
            let bi = match target {
                Some(i) => i,
                None => break,
            };
            let (axis, _) = boxes[bi].longest_axis();
            let (s, e) = (boxes[bi].start, boxes[bi].end);
            let axis_ref = axis;
            // Sort the box's bin indices along `axis` (only within the box).
            idx[s..e].sort_unstable_by_key(|b| match axis_ref {
                0 => (sum_r[*b as usize] / hist[*b as usize].max(1)) as u16,
                1 => (sum_g[*b as usize] / hist[*b as usize].max(1)) as u16,
                _ => (sum_b[*b as usize] / hist[*b as usize].max(1)) as u16,
            });
            // Split at the population median.
            let total: u32 = (s..e).map(|i| hist[idx[i] as usize]).sum();
            let mut acc = 0u32;
            let mut cut = s;
            for i in s..e {
                acc += hist[idx[i] as usize];
                cut = i + 1;
                if acc * 2 >= total {
                    break;
                }
            }
            if cut >= e {
                cut = e - 1;
            }
            let left_pop: u32 = (s..cut).map(|i| hist[idx[i] as usize]).sum();
            let right_pop: u32 = (cut..e).map(|i| hist[idx[i] as usize]).sum();
            let mut left = Box {
                lo: boxes[bi].lo,
                hi: boxes[bi].hi,
                start: s,
                end: cut,
                pop: left_pop,
            };
            let mut right = Box {
                lo: boxes[bi].lo,
                hi: boxes[bi].hi,
                start: cut,
                end: e,
                pop: right_pop,
            };
            // Shrink each child's bounds to the bins it actually owns.
            for b in [&mut left, &mut right] {
                let mut lo = [31u8; 3];
                let mut hi = [0u8; 3];
                for i in b.start..b.end {
                    let bin = idx[i];
                    let (cr, cg, cb) = Self::bin_rgb(bin);
                    let c = [cr, cg, cb];
                    for k in 0..3 {
                        lo[k] = lo[k].min(c[k]);
                        hi[k] = hi[k].max(c[k]);
                    }
                }
                b.lo = lo;
                b.hi = hi;
            }
            boxes[bi] = left;
            boxes.push(right);
        }

        // Representative color per box = population-weighted average.
        let mut entries = [[0u8, 0, 0, 255]; 256];
        let mut used = 0usize;
        for bx in &boxes {
            let mut r = 0u64;
            let mut g = 0u64;
            let mut b = 0u64;
            let mut n = 0u64;
            for i in bx.start..bx.end {
                let bin = idx[i] as usize;
                r += sum_r[bin] as u64;
                g += sum_g[bin] as u64;
                b += sum_b[bin] as u64;
                n += hist[bin] as u64;
            }
            if n == 0 {
                continue;
            }
            entries[used] = [
                (r / n) as u8,
                (g / n) as u8,
                (b / n) as u8,
                255,
            ];
            used += 1;
            if used == 256 {
                break;
            }
        }
        if used == 0 {
            // Degenerate input (empty) — black palette, single entry.
            entries[0] = [0, 0, 0, 255];
            used = 1;
        }

        // 15-bit nearest-color cache.
        let mut lut = vec![0u8; BINS];
        for bin in 0..BINS {
            let (r, g, b) = Self::bin_rgb(bin as u16);
            let mut best = 0usize;
            let mut best_d = u32::MAX;
            for (i, e) in entries.iter().enumerate().take(used) {
                let dr = r as i32 - e[0] as i32;
                let dg = g as i32 - e[1] as i32;
                let db = b as i32 - e[2] as i32;
                let d = (dr * dr + dg * dg + db * db) as u32;
                if d < best_d {
                    best_d = d;
                    best = i;
                }
            }
            lut[bin] = best as u8;
        }

        Self { entries, lut, used }
    }

    #[inline]
    fn bin_of(r: u32, g: u32, b: u32) -> usize {
        let r5 = (r >> 3).min(31) as usize;
        let g5 = (g >> 3).min(31) as usize;
        let b5 = (b >> 3).min(31) as usize;
        (r5 << 10) | (g5 << 5) | b5
    }

    #[inline]
    fn bin_rgb(bin: u16) -> (u8, u8, u8) {
        let b = (bin & 31) as u8;
        let g = ((bin >> 5) & 31) as u8;
        let r = ((bin >> 10) & 31) as u8;
        (r * 8 + 4, g * 8 + 4, b * 8 + 4)
    }

    #[inline]
    fn nearest(&self, r: u8, g: u8, b: u8) -> u8 {
        self.lut[Self::bin_of(r as u32, g as u32, b as u32)]
    }

    /// Quantize an RGBA frame into 8-bit palette indices.
    ///
    /// * `out` receives `stride` bytes per row (the AVFrame linesize[0]).
    /// * `dither` enables Floyd–Steinberg error diffusion (better gradients,
    ///   slower — off for tiny frames where banding is invisible).
    pub fn quantize_frame(
        &self,
        rgba: &[u8],
        width: usize,
        height: usize,
        out: &mut [u8],
        stride: usize,
        dither: bool,
    ) {
        debug_assert!(rgba.len() >= width * height * 4);
        if !dither {
            for y in 0..height {
                let src = y * width * 4;
                let dst = y * stride;
                for x in 0..width {
                    let s = src + x * 4;
                    out[dst + x] =
                        self.nearest(rgba[s], rgba[s + 1], rgba[s + 2]);
                }
            }
            return;
        }
        // Floyd–Steinberg with two rolling error rows. `cur`/`nxt` are
        // indexed (x + 1) * 3 so the x-1 neighbor slot exists at the left
        // border. Distribution per pixel: 7/16 right, 3/16 down-left,
        // 5/16 down, 1/16 down-right.
        let row = (width + 2) * 3;
        let mut cur = vec![0i16; row];
        let mut nxt = vec![0i16; row];
        for y in 0..height {
            for x in 0..width {
                let s = (y * width + x) * 4;
                let k = (x + 1) * 3;
                let r = (rgba[s] as i16 + cur[k]).clamp(0, 255) as u8;
                let g = (rgba[s + 1] as i16 + cur[k + 1]).clamp(0, 255) as u8;
                let b = (rgba[s + 2] as i16 + cur[k + 2]).clamp(0, 255) as u8;
                let idx = self.nearest(r, g, b);
                out[y * stride + x] = idx;
                let e = &self.entries[idx as usize];
                let er = r as i16 - e[0] as i16;
                let eg = g as i16 - e[1] as i16;
                let eb = b as i16 - e[2] as i16;
                // 7/16 → right (same row)
                cur[k + 3] += er * 7 / 16;
                cur[k + 4] += eg * 7 / 16;
                cur[k + 5] += eb * 7 / 16;
                // 3/16 → down-left, 5/16 → down, 1/16 → down-right
                nxt[k - 3] += er * 3 / 16;
                nxt[k - 2] += eg * 3 / 16;
                nxt[k - 1] += eb * 3 / 16;
                nxt[k] += er * 5 / 16;
                nxt[k + 1] += eg * 5 / 16;
                nxt[k + 2] += eb * 5 / 16;
                nxt[k + 3] += er / 16;
                nxt[k + 4] += eg / 16;
                nxt[k + 5] += eb / 16;
            }
            std::mem::swap(&mut cur, &mut nxt);
            nxt.iter_mut().for_each(|v| *v = 0);
        }
    }

    /// Palette bytes for the AVFrame `data[1]` plane (AVPALETTE_SIZE = 1024).
    ///
    /// Byte order is **BGRA**, not RGBA: the libavcodec GIF encoder consumes
    /// the palette plane as a BGR8-style table (it only swaps R/B for the
    /// RGB8 pix_fmt variant, and the export path runs PAL8). An RGBA-ordered
    /// palette renders every bar with red and blue exchanged — verified by
    /// decoding the exported GIF and sampling the source color bars.
    pub fn av_palette_bytes(&self) -> [u8; 1024] {
        let mut out = [0u8; 1024];
        for i in 0..256 {
            let e = self.entries[i];
            out[i * 4] = e[2];
            out[i * 4 + 1] = e[1];
            out[i * 4 + 2] = e[0];
            out[i * 4 + 3] = 255;
        }
        out
    }
}

/// Median-cut working box over histogram bins.
struct Box {
    lo: [u8; 3],
    hi: [u8; 3],
    start: usize,
    end: usize,
    pop: u32,
}

impl Box {
    /// The axis with the widest bin range (R, G, B) and its range.
    fn longest_axis(&self) -> (usize, u32) {
        let d = [
            (self.hi[0] - self.lo[0]) as u32,
            (self.hi[1] - self.lo[1]) as u32,
            (self.hi[2] - self.lo[2]) as u32,
        ];
        if d[0] >= d[1] && d[0] >= d[2] {
            (0, d[0])
        } else if d[1] >= d[2] {
            (1, d[1])
        } else {
            (2, d[2])
        }
    }
}

#[cfg(test)]
mod tests {
    use super::GifPalette;

    #[test]
    fn palette_never_exceeds_256_entries() {
        let mut data = Vec::new();
        for i in 0..5000u32 {
            data.push((i % 256) as u8);
            data.push(((i * 7) % 256) as u8);
            data.push(((i * 13) % 256) as u8);
            data.push(255);
        }
        let pal = GifPalette::build(&data);
        assert!(pal.used >= 1 && pal.used <= 256, "used={}", pal.used);
    }

    #[test]
    fn flat_gray_maps_to_exact_entry() {
        let data = vec![128u8, 128, 128, 255];
        let pal = GifPalette::build(&data);
        let mut out = [0u8; 1];
        pal.quantize_frame(&data, 1, 1, &mut out, 1, false);
        let e = pal.entries[out[0] as usize];
        assert!((e[0] as i32 - 128).abs() <= 2, "{e:?}");
    }

    #[test]
    fn quantize_without_dither_is_deterministic() {
        let mut data = vec![0u8; 64];
        for i in 0..16 {
            data[i * 4] = (i * 16) as u8;
            data[i * 4 + 1] = 255 - (i * 16) as u8;
            data[i * 4 + 2] = (i * 8) as u8;
            data[i * 4 + 3] = 255;
        }
        let pal = GifPalette::build(&data);
        let mut a = [0u8; 16];
        let mut b = [0u8; 16];
        pal.quantize_frame(&data, 4, 4, &mut a, 4, false);
        pal.quantize_frame(&data, 4, 4, &mut b, 4, false);
        assert_eq!(a, b);
    }

    #[test]
    fn av_palette_is_1024_bytes_bgra_opaque_alpha() {
        let pal = GifPalette::build(&[255, 0, 0, 255]); // pure red
        let bytes = pal.av_palette_bytes();
        assert_eq!(bytes.len(), 1024);
        // Entry 0 must be the red pixel in BGRA order.
        assert_eq!(bytes[0], 0, "B of pure red = 0");
        assert_eq!(bytes[1], 0, "G of pure red = 0");
        assert_eq!(bytes[2], 255, "R of pure red = 255");
        assert_eq!(bytes[3], 255, "alpha opaque");
    }

    #[test]
    fn empty_input_is_safe() {
        let pal = GifPalette::build(&[]);
        assert_eq!(pal.used, 1);
    }

    #[test]
    fn dithering_runs_and_lands_in_palette_range() {
        // Smooth gradient: the case that bands badly without dithering.
        let (w, h) = (32usize, 32usize);
        let mut data = vec![0u8; w * h * 4];
        for y in 0..h {
            for x in 0..w {
                let s = (y * w + x) * 4;
                data[s] = (x * 8) as u8;
                data[s + 1] = (y * 8) as u8;
                data[s + 2] = 128;
                data[s + 3] = 255;
            }
        }
        let pal = GifPalette::build(&data);
        let mut plain = vec![0u8; w * h];
        let mut dithered = vec![0u8; w * h];
        pal.quantize_frame(&data, w, h, &mut plain, w, false);
        pal.quantize_frame(&data, w, h, &mut dithered, w, true);
        // Every index must address a real palette entry.
        for &i in dithered.iter() {
            assert!((i as usize) < pal.used.max(1), "index {i} out of range");
        }
        // Dithering must actually change the output on a gradient.
        assert_ne!(plain, dithered, "Floyd–Steinberg had no effect");
    }

    #[test]
    fn quantize_respects_stride() {
        let w = 4usize;
        let h = 2usize;
        let data = vec![10u8, 20, 30, 255, 40, 50, 60, 255, 70, 80, 90, 255, 100, 110, 120, 255, 130, 140, 150, 255, 160, 170, 180, 255, 190, 200, 210, 255, 220, 230, 240, 255];
        let pal = GifPalette::build(&data);
        let stride = w + 3; // padded linesize
        let mut out = vec![0xAAu8; stride * h];
        pal.quantize_frame(&data, w, h, &mut out, stride, false);
        for y in 0..h {
            for x in stride - 3..stride {
                assert_eq!(out[y * stride + x], 0xAA, "padding must be untouched");
            }
        }
    }
}
