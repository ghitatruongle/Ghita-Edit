//! T6-P3: Color management — sRGB/linear transfer functions, HDR tone mapping,
//! film simulation presets, HSL conversion.

/// sRGB → linear (standard IEC 61966-2-1 transfer function).
pub fn srgb_to_linear(v: f32) -> f32 {
    let v = v.clamp(0.0, 1.0);
    if v <= 0.04045 {
        v / 12.92
    } else {
        ((v + 0.055) / 1.055).powf(2.4)
    }
}

/// Linear → sRGB.
pub fn linear_to_srgb(v: f32) -> f32 {
    let v = v.clamp(0.0, 1.0);
    if v <= 0.0031308 {
        v * 12.92
    } else {
        1.055 * v.powf(1.0 / 2.4) - 0.055
    }
}

/// Reinhard tone mapping on f32 RGBA buffer (in-place, RGB channels only).
pub fn apply_hdr_tonemap_reinhard(buf: &mut [f32], pixel_count: usize, white_point: f32) {
    let wp2 = white_point * white_point;
    for i in 0..pixel_count {
        let base = i * 4;
        for c in 0..3 {
            let lum = buf[base + c];
            buf[base + c] = lum / (1.0 + lum / wp2);
        }
    }
}

/// Film simulation presets.
#[derive(Debug, Clone, Copy)]
pub enum FilmPreset {
    Portra,   // Warm, desaturated shadows
    Velvia,   // High saturation, vivid
    Cinematic, // Teal-orange, lifted blacks
}

/// Apply a film simulation preset to u8 RGBA buffer.
pub fn apply_film_sim(buf: &mut [u8], pixel_count: usize, preset: FilmPreset) {
    for i in 0..pixel_count {
        let base = i * 4;
        let r = buf[base] as f32 / 255.0;
        let g = buf[base + 1] as f32 / 255.0;
        let b = buf[base + 2] as f32 / 255.0;

        let (nr, ng, nb) = match preset {
            FilmPreset::Portra => {
                // Warm shift, slight shadow desaturation
                let lum = 0.299 * r + 0.587 * g + 0.114 * b;
                let sat = 0.85;
                let dr = lum + (r - lum) * sat + 0.03;
                let dg = lum + (g - lum) * sat + 0.01;
                let db = lum + (b - lum) * sat - 0.02;
                (dr, dg, db)
            }
            FilmPreset::Velvia => {
                // High saturation boost
                let lum = 0.299 * r + 0.587 * g + 0.114 * b;
                let sat = 1.4;
                let dr = lum + (r - lum) * sat;
                let dg = lum + (g - lum) * sat;
                let db = lum + (b - lum) * sat;
                (dr, dg, db)
            }
            FilmPreset::Cinematic => {
                // Teal shadows, orange highlights, lifted blacks
                let lum = 0.299 * r + 0.587 * g + 0.114 * b;
                let shadow = (1.0 - lum).max(0.0);
                let highlight = lum.max(0.0);
                let dr = r + highlight * 0.08 - shadow * 0.02 + 0.02;
                let dg = g + highlight * 0.02 + shadow * 0.03 + 0.02;
                let db = b - highlight * 0.04 + shadow * 0.08 + 0.02;
                (dr, dg, db)
            }
        };

        buf[base] = (nr.clamp(0.0, 1.0) * 255.0 + 0.5) as u8;
        buf[base + 1] = (ng.clamp(0.0, 1.0) * 255.0 + 0.5) as u8;
        buf[base + 2] = (nb.clamp(0.0, 1.0) * 255.0 + 0.5) as u8;
    }
}

/// RGB → HSL (all values 0.0–1.0).
pub fn rgb_to_hsl(r: f32, g: f32, b: f32) -> (f32, f32, f32) {
    let max = r.max(g).max(b);
    let min = r.min(g).min(b);
    let l = (max + min) / 2.0;

    if (max - min).abs() < 1e-6 {
        return (0.0, 0.0, l);
    }

    let d = max - min;
    let s = if l > 0.5 { d / (2.0 - max - min) } else { d / (max + min) };

    let h = if (r - max).abs() < 1e-6 {
        let mut h = (g - b) / d;
        if g < b { h += 6.0; }
        h / 6.0
    } else if (g - max).abs() < 1e-6 {
        ((b - r) / d + 2.0) / 6.0
    } else {
        ((r - g) / d + 4.0) / 6.0
    };

    (h, s, l)
}

/// HSL → RGB (all values 0.0–1.0).
pub fn hsl_to_rgb(h: f32, s: f32, l: f32) -> (f32, f32, f32) {
    if s.abs() < 1e-6 {
        return (l, l, l);
    }

    let q = if l < 0.5 { l * (1.0 + s) } else { l + s - l * s };
    let p = 2.0 * l - q;

    let hue_to_rgb = |t: f32| -> f32 {
        let mut t = t;
        if t < 0.0 { t += 1.0; }
        if t > 1.0 { t -= 1.0; }
        if t < 1.0 / 6.0 { return p + (q - p) * 6.0 * t; }
        if t < 1.0 / 2.0 { return q; }
        if t < 2.0 / 3.0 { return p + (q - p) * (2.0 / 3.0 - t) * 6.0; }
        p
    };

    (hue_to_rgb(h + 1.0 / 3.0), hue_to_rgb(h), hue_to_rgb(h - 1.0 / 3.0))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn srgb_linear_round_trip() {
        for v in [0.0, 0.1, 0.25, 0.5, 0.75, 0.9, 1.0] {
            let rt = linear_to_srgb(srgb_to_linear(v));
            assert!((rt - v).abs() < 0.001, "sRGB round-trip failed at {}: got {}", v, rt);
        }
    }

    #[test]
    fn reinhard_preserves_highlights() {
        // Use values above white_point to ensure visible compression.
        let mut buf = vec![2.0f32, 2.0, 2.0, 1.0, 0.1, 0.1, 0.1, 1.0];
        let orig_bright = buf[0];
        apply_hdr_tonemap_reinhard(&mut buf, 2, 1.0);
        // Bright value should be compressed but still > dark value.
        assert!(buf[0] > buf[4], "bright={} should exceed dark={}", buf[0], buf[4]);
        assert!(buf[0] < orig_bright, "tonemapped={} should be less than original={}", buf[0], orig_bright);
    }

    #[test]
    fn film_sim_changes_colors() {
        let mut buf = vec![128u8, 128, 128, 255, 128, 128, 128, 255];
        let orig = buf[0];
        apply_film_sim(&mut buf, 2, FilmPreset::Velvia);
        // Velvia boosts saturation — neutral gray stays gray, but let's test with colored input.
        let mut buf2 = vec![200u8, 100, 50, 255, 200, 100, 50, 255];
        let orig_r = buf2[0];
        apply_film_sim(&mut buf2, 2, FilmPreset::Velvia);
        assert_ne!(buf2[0], orig_r, "Velvia should modify colored pixels");
    }

    #[test]
    fn hsl_round_trip() {
        for (r, g, b) in [(1.0, 0.0, 0.0), (0.0, 1.0, 0.0), (0.0, 0.0, 1.0), (0.5, 0.3, 0.8)] {
            let (h, s, l) = rgb_to_hsl(r, g, b);
            let (nr, ng, nb) = hsl_to_rgb(h, s, l);
            assert!((nr - r).abs() < 0.01 && (ng - g).abs() < 0.01 && (nb - b).abs() < 0.01,
                "HSL round-trip failed: ({},{},{}) -> ({},{},{}) -> ({},{},{})", r, g, b, h, s, l, nr, ng, nb);
        }
    }
}

