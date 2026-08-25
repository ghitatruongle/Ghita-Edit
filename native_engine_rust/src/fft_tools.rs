//! T4 FFT tools (feature `ffmpeg`): spectrogram (#15), spectral editing
//! (#16), tempo detection (#31), per-window RMS (#5 / opt), and beat grid
//! (#32). Built on rustfft with a Hann window STFT over the mix pipeline.

use rustfft::num_complex::Complex;
use rustfft::{Fft, FftPlanner, FftDirection};
use std::sync::{Arc, OnceLock};

pub const FFT_SIZE: usize = 1024;
pub const HOP_SIZE: usize = 256;

// v1.5.0-T4 (P5): the Hann window and FFT plans are pure functions of
// FFT_SIZE — build them ONCE per process instead of on every mix window
// while spectral edits/spectrogram calls are active.
fn cached_window() -> &'static [f32] {
    static WINDOW: OnceLock<Vec<f32>> = OnceLock::new();
    WINDOW.get_or_init(|| hann(FFT_SIZE))
}

fn forward_plan() -> Arc<dyn Fft<f32>> {
    static PLAN: OnceLock<Arc<dyn Fft<f32>>> = OnceLock::new();
    PLAN.get_or_init(|| {
        let mut planner = FftPlanner::<f32>::new();
        planner.plan_fft_forward(FFT_SIZE)
    })
    .clone()
}

fn inverse_plan() -> Arc<dyn Fft<f32>> {
    static PLAN: OnceLock<Arc<dyn Fft<f32>>> = OnceLock::new();
    PLAN.get_or_init(|| {
        let mut planner = FftPlanner::<f32>::new();
        planner.plan_fft_inverse(FFT_SIZE)
    })
    .clone()
}

/// Computes a magnitude spectrogram: [columns × (bins)] row-major, each bin
/// normalized to 0..1 (log scale). Audio is interleaved stereo — mono-mixed.
pub fn spectrogram(audio: &[f32], columns: usize, bins: usize) -> Vec<f32> {
    let mut out = vec![0.0f32; columns * bins];
    if audio.len() < FFT_SIZE * 2 || columns == 0 || bins == 0 {
        return out;
    }
    let frames = audio.len() / 2;
    let window = cached_window();
    let fft = forward_plan();
    let mut buf = vec![Complex { re: 0.0, im: 0.0 }; FFT_SIZE];

    let total_hops = (frames.saturating_sub(FFT_SIZE)) / HOP_SIZE + 1;
    for col in 0..columns {
        // Sample hop positions evenly across the audio.
        let hop = if columns <= 1 {
            0
        } else {
            (total_hops - 1) * col / (columns - 1)
        };
        let start = hop * HOP_SIZE;
        for i in 0..FFT_SIZE {
            let s = audio.get((start + i) * 2).copied().unwrap_or(0.0) * 0.5
                + audio.get((start + i) * 2 + 1).copied().unwrap_or(0.0) * 0.5;
            buf[i] = Complex { re: s * window[i], im: 0.0 };
        }
        fft.process(&mut buf);
        for b in 0..bins.min(FFT_SIZE / 2) {
            let mag = buf[b].norm() / (FFT_SIZE as f32 / 8.0);
            // Log scale to 0..1 (−60 dB..0 dBFS).
            let v = ((20.0 * mag.max(1e-6).log10() + 60.0) / 60.0).clamp(0.0, 1.0);
            out[col * bins + b] = v;
        }
    }
    out
}

/// A spectral edit region: time range (ms) × freq range (Hz) × gain (dB).
#[derive(Clone, Copy, Debug)]
pub struct SpectralEdit {
    pub start_ms: i64,
    pub end_ms: i64,
    pub lo_hz: f32,
    pub hi_hz: f32,
    pub gain_db: f32,
}

/// Applies edit regions to a window via STFT bin masking (in place).
pub fn apply_spectral_edits(
    audio: &mut [f32],
    start_ms: i64,
    edits: &[SpectralEdit],
    sample_rate: f32,
) {
    if edits.is_empty() || audio.len() < FFT_SIZE * 2 {
        return;
    }
    let frames = audio.len() / 2;
    let end_ms = start_ms + (frames as f64 * 1000.0 / sample_rate as f64) as i64;
    let active: Vec<&SpectralEdit> = edits
        .iter()
        .filter(|e| e.end_ms > start_ms && e.start_ms < end_ms)
        .collect();
    if active.is_empty() {
        return;
    }
    let window = cached_window();
    let fwd = forward_plan();
    let inv = inverse_plan();
    let bin_hz = sample_rate / FFT_SIZE as f32;

    // v1.5.0-T4 (P5): two reusable STFT scratch buffers (was a fresh
    // Vec<Complex> per channel per 256-sample hop inside the mix loop).
    let mut buf_ch0 = vec![Complex { re: 0.0, im: 0.0 }; FFT_SIZE];
    let mut buf_ch1 = vec![Complex { re: 0.0, im: 0.0 }; FFT_SIZE];

    let mut pos = 0usize;
    while pos + FFT_SIZE <= frames {
        let hop_ms = start_ms + (pos as f64 * 1000.0 / sample_rate as f64) as i64;
        // Per-channel STFT.
        for ch in 0..2 {
            let buf = match ch {
                0 => &mut buf_ch0,
                _ => &mut buf_ch1,
            };
            for i in 0..FFT_SIZE {
                let s = audio[(pos + i) * 2 + ch] * window[i];
                buf[i] = Complex { re: s, im: 0.0 };
            }
            fwd.process(buf);
            let mut changed = false;
            for b in 0..FFT_SIZE / 2 {
                let hz = b as f32 * bin_hz;
                for e in &active {
                    if hz >= e.lo_hz && hz <= e.hi_hz {
                        // Overlap-add weighting by time overlap fraction.
                        let ov = overlap_fraction(hop_ms, e.start_ms, e.end_ms, FFT_SIZE, sample_rate);
                        if ov > 0.0 {
                            let g = 10.0f32.powf(e.gain_db / 20.0);
                            let blend = 1.0 + (g - 1.0) * ov;
                            buf[b] = buf[b] * blend;
                            let mi = FFT_SIZE - b;
                            if mi != b {
                                buf[mi] = buf[mi] * blend;
                            }
                            changed = true;
                        }
                    }
                }
            }
            if changed {
                inv.process(buf);
                let norm = 1.0 / FFT_SIZE as f32;
                for i in 0..FFT_SIZE {
                    let out = (buf[i].re * norm * window[i]).clamp(-1.0, 1.0);
                    // Crossfade the tail to avoid block boundaries.
                    audio[(pos + i) * 2 + ch] = audio[(pos + i) * 2 + ch] * 0.5 + out * 0.5;
                }
            }
        }
        pos += HOP_SIZE;
    }
}

fn overlap_fraction(hop_ms: i64, es: i64, ee: i64, fft: usize, sr: f32) -> f32 {
    let win_ms = (fft as f32 * 1000.0 / sr) as i64;
    let he = hop_ms + win_ms;
    let ov = (ee.min(he) - es.max(hop_ms)).max(0);
    if win_ms <= 0 {
        0.0
    } else {
        ov as f32 / win_ms as f32
    }
}

/// Tempo detection (#31): onset-energy autocorrelation over 60–180 BPM.
/// Returns BPM (0.0 on failure).
pub fn detect_tempo_bpm(audio: &[f32], sample_rate: f32) -> f32 {
    if audio.len() < sample_rate as usize * 4 {
        return 0.0;
    }
    let frames = audio.len() / 2;
    // Onset envelope: per-window spectral flux (cheap: RMS delta).
    let win = (sample_rate * 0.01) as usize; // 10 ms
    let mut env = Vec::with_capacity(frames / win);
    let mut prev_rms = 0.0f32;
    for start in (0..frames - win).step_by(win) {
        let mut sum = 0.0f32;
        for i in 0..win {
            let m = (audio[(start + i) * 2] + audio[(start + i) * 2 + 1]) * 0.5;
            sum += m * m;
        }
        let rms = (sum / win as f32).sqrt();
        let flux = (rms - prev_rms).max(0.0);
        env.push(flux);
        prev_rms = rms;
    }
    // Autocorrelation over BPM 60..180.
    let hop_s = 0.01f32;
    let mut best_bpm = 0.0f32;
    let mut best_score = 0.0f32;
    for bpm in 60..=180 {
        let lag = (60.0 / bpm as f32 / hop_s) as usize;
        if lag >= env.len() / 2 {
            continue;
        }
        let mut score = 0.0f32;
        for i in 0..env.len() - lag {
            score += env[i] * env[i + lag];
        }
        // Slight preference for 100–140 BPM (common music).
        let prior = 1.0 - ((bpm as f32 - 120.0).abs() / 300.0);
        score *= prior;
        if score > best_score {
            best_score = score;
            best_bpm = bpm as f32;
        }
    }
    best_bpm
}

/// Per-window RMS values (#5/opt): normalized 0..1.
pub fn rms_windows(audio: &[f32], out: &mut [f32]) {
    if audio.len() < 2 || out.is_empty() {
        return;
    }
    let frames = audio.len() / 2;
    let win = (frames / out.len()).max(1);
    for (i, o) in out.iter_mut().enumerate() {
        let start = i * win;
        if start >= frames {
            *o = 0.0;
            continue;
        }
        let mut sum = 0.0f32;
        for k in 0..win {
            let idx = (start + k) * 2;
            if idx + 1 >= audio.len() {
                break;
            }
            let m = (audio[idx] + audio[idx + 1]) * 0.5;
            sum += m * m;
        }
        *o = (sum / win as f32).sqrt().clamp(0.0, 1.0);
    }
}

/// Beat times in ms for a BPM + time signature (#32).
pub fn beat_times(duration_ms: i64, bpm: f32, beats_per_bar: i32, out: &mut [i64]) -> usize {
    if bpm <= 0.0 || duration_ms <= 0 || out.is_empty() {
        return 0;
    }
    let beat_ms = 60_000.0 / bpm;
    let total = (duration_ms as f32 / beat_ms) as usize;
    let mut n = 0usize;
    let mut i = 0usize;
    while i < total && n < out.len() {
        // Downbeat (bar start) every beats_per_bar beats.
        let is_down = i % beats_per_bar.max(1) as usize == 0;
        out[n] = (i as f32 * beat_ms) as i64;
        let _ = is_down;
        n += 1;
        i += 1;
    }
    n
}

fn hann(n: usize) -> Vec<f32> {
    (0..n)
        .map(|i| 0.5 * (1.0 - (2.0 * std::f32::consts::PI * i as f32 / n as f32).cos()))
        .collect()
}

#[allow(dead_code)]
fn _direction_hint(_: FftDirection) {}

#[cfg(test)]
mod tests {
    use super::*;

    fn sine(frames: usize, freq: f32, amp: f32) -> Vec<f32> {
        let mut buf = vec![0.0f32; frames * 2];
        for i in 0..frames {
            let v = (2.0 * std::f32::consts::PI * freq * i as f32 / 44100.0).sin() * amp;
            buf[i * 2] = v;
            buf[i * 2 + 1] = v;
        }
        buf
    }

    #[test]
    fn spectrogram_bins_detect_tone() {
        // 440 Hz tone → energy concentrated near bin 440/43 ≈ 10.
        let audio = sine(FFT_SIZE * 8, 440.0, 0.8);
        let bins = 64;
        let spec = spectrogram(&audio, 8, bins);
        // Find the peak bin.
        let mut best = 0usize;
        let mut best_v = 0.0f32;
        for b in 0..bins {
            let v = spec[b]; // first column
            if v > best_v {
                best_v = v;
                best = b;
            }
        }
        let expected = (440.0 / (44100.0 / FFT_SIZE as f32)) as usize;
        assert!(
            (best as i32 - expected as i32).abs() <= 2,
            "peak bin {best} vs expected {expected}"
        );
        assert!(best_v > 0.5, "tone bin must be hot: {best_v}");
    }

    #[test]
    fn spectral_edit_attenuates_band() {
        // Two tones: 440 Hz + 5 kHz. Cut 5 kHz by −40 dB; 440 must survive.
        let mut audio = vec![0.0f32; FFT_SIZE * 8 * 2];
        for i in 0..(FFT_SIZE * 8) {
            let v = (2.0 * std::f32::consts::PI * 440.0 * i as f32 / 44100.0).sin() * 0.5
                + (2.0 * std::f32::consts::PI * 5000.0 * i as f32 / 44100.0).sin() * 0.5;
            audio[i * 2] = v;
            audio[i * 2 + 1] = v;
        }
        let spec0 = spectrogram(&audio, 4, 256);
        let bin5k = (5000.0 / (44100.0 / FFT_SIZE as f32)) as usize; // ~116
        let hi_before: f32 = (0..4).map(|c| spec0[c * 256 + bin5k.min(255)]).sum();
        let edits = [SpectralEdit {
            start_ms: 0,
            end_ms: 10_000,
            lo_hz: 4000.0,
            hi_hz: 6000.0,
            gain_db: -40.0,
        }];
        apply_spectral_edits(&mut audio, 0, &edits, 44100.0);
        let spec1 = spectrogram(&audio, 4, 256);
        let hi_after: f32 = (0..4).map(|c| spec1[c * 256 + bin5k.min(255)]).sum();
        assert!(hi_after < hi_before * 0.7, "5k cut: {hi_before} -> {hi_after}");
    }

    #[test]
    fn tempo_detection_beat_tone() {
        // Click track at 120 BPM: click every 500 ms.
        let mut audio = vec![0.0f32; (44100 * 6) * 2];
        let click_len = 400usize;
        for beat in 0..12 {
            let start = beat * 500 * 44100 / 1000;
            for i in 0..click_len {
                if start + i >= audio.len() / 2 {
                    break;
                }
                let env = (1.0 - i as f32 / click_len as f32) * (1.0 - i as f32 / click_len as f32);
                let v = (2.0 * std::f32::consts::PI * 1000.0 * i as f32 / 44100.0).sin() * env;
                audio[(start + i) * 2] = v;
                audio[(start + i) * 2 + 1] = v;
            }
        }
        let bpm = detect_tempo_bpm(&audio, 44100.0);
        assert!((bpm - 120.0).abs() <= 3.0, "tempo: {bpm}");
    }

    #[test]
    fn rms_windows_sine_is_high_silence_low() {
        let audio = sine(4410, 440.0, 0.5);
        let mut rms = vec![0.0f32; 10];
        rms_windows(&audio, &mut rms);
        assert!(rms.iter().all(|v| *v > 0.2), "sine RMS: {rms:?}");
        let silence = vec![0.0f32; 4410 * 2];
        let mut rms2 = vec![0.0f32; 10];
        rms_windows(&silence, &mut rms2);
        assert!(rms2.iter().all(|v| *v == 0.0));
    }

    #[test]
    fn beat_times_grid() {
        let mut beats = [0i64; 64];
        let n = beat_times(4000, 120.0, 4, &mut beats);
        assert_eq!(n, 8); // 4000 ms at 500 ms/beat
        assert_eq!(beats[0], 0);
        assert_eq!(beats[1], 500);
        assert_eq!(beats[7], 3500);
    }
}
