//! T4 audio DSP: realtime effect chain (#24/#25/#26/#27/#28) — per-window
//! processing of the mixed stereo bus (44.1 kHz interleaved). All processors
//! are pure Rust (std only), sample-accurate, and unit-testable in isolation.
//!
//! Effects are applied AFTER mixing (preview + export share the chain), so a
//! chain entry sounds identical in both paths.

/// Effect type ids (stable ABI — mirrors the Dart enum).
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
#[repr(i32)]
pub enum AudioEffectType {
    Compressor = 0,
    Limiter = 1,
    NoiseGate = 2,
    NoiseReduction = 3,
    BassTreble = 4,
    Distortion = 5,
    Phaser = 6,
    Reverb = 7,
    WahWah = 8,
    ShelfFilter = 9,
}

impl AudioEffectType {
    pub fn from_i32(v: i32) -> Option<Self> {
        Some(match v {
            0 => AudioEffectType::Compressor,
            1 => AudioEffectType::Limiter,
            2 => AudioEffectType::NoiseGate,
            3 => AudioEffectType::NoiseReduction,
            4 => AudioEffectType::BassTreble,
            5 => AudioEffectType::Distortion,
            6 => AudioEffectType::Phaser,
            7 => AudioEffectType::Reverb,
            8 => AudioEffectType::WahWah,
            9 => AudioEffectType::ShelfFilter,
            _ => return None,
        })
    }
}

/// One chain entry: type + 4 generic params (meaning per type, documented
/// per processor) + the processor state.
pub struct AudioEffect {
    pub kind: AudioEffectType,
    pub p: [f32; 4],
    state: EffectState,
    /// Last gain-reduction in dB (compressor/limiter/gate) — UI history.
    pub gain_reduction_db: f32,
}

#[derive(Default)]
struct EffectState {
    // Envelope followers (per channel).
    env: [f32; 2],
    // Biquad states: [channel][0..5] = b0..b2, a1, a2 history (x1,x2,y1,y2).
    bq: [[BiquadState; 2]; 3],
    // Dedicated 4-stage allpass chain for the phaser — aliasing stages onto
    // `bq` corrupted the EQ/distortion filters and collided stages 3→slot 1.
    phaser: [[BiquadState; 2]; 4],
    // LFO phase (phaser/wahwah).
    lfo_phase: f32,
    // Schroeder reverb: 4 combs + 3 allpasses per channel.
    comb: [Vec<f32>; 8],
    // Freeverb one-pole damping state per comb line (feedback lowpass).
    comb_damp: [f32; 8],
    comb_idx: usize,
    allp: [Vec<f32>; 6],
    allp_idx: usize,
    // Residue buffer for noise reduction (last noise profile).
    noise_floor: f32,
    // Gate hold timer (frames).
    hold: i32,
    gate_open: bool,
}

#[derive(Clone, Copy, Default)]
struct BiquadState {
    x1: f32,
    x2: f32,
    y1: f32,
    y2: f32,
}

impl BiquadState {
    #[inline]
    fn process(&mut self, x: f32, b0: f32, b1: f32, b2: f32, a1: f32, a2: f32) -> f32 {
        let y = b0 * x + b1 * self.x1 + b2 * self.x2 - a1 * self.y1 - a2 * self.y2;
        self.x2 = self.x1;
        self.x1 = x;
        self.y2 = self.y1;
        self.y1 = y;
        y
    }
}

impl AudioEffect {
    pub fn new(kind: AudioEffectType, p: [f32; 4]) -> Self {
        AudioEffect {
            kind,
            p,
            state: EffectState::default(),
            gain_reduction_db: 0.0,
        }
    }

    /// Processes an interleaved stereo window in place.
    pub fn process(&mut self, buf: &mut [f32], sample_rate: f32) {
        let frames = buf.len() / 2;
        for i in 0..frames {
            let l = buf[i * 2];
            let r = buf[i * 2 + 1];
            let (nl, nr) = self.process_sample(l, r, sample_rate);
            buf[i * 2] = nl;
            buf[i * 2 + 1] = nr;
        }
    }

    fn process_sample(&mut self, l: f32, r: f32, sr: f32) -> (f32, f32) {
        match self.kind {
            AudioEffectType::Compressor => {
                // p0 = threshold dB (-60..0), p1 = ratio (1..20),
                // p2 = attack ms, p3 = release ms.
                let thr = db_to_lin(self.p[0]);
                let ratio = self.p[1].max(1.0);
                let atk = (1.0 - (-1.0 / (self.p[2].max(0.1) * sr / 1000.0)).exp()) as f32;
                let rel = (1.0 - (-1.0 / (self.p[3].max(0.1) * sr / 1000.0)).exp()) as f32;
                let peak = l.abs().max(r.abs());
                let target = if peak > thr {
                    let over_db = lin_to_db(peak) - self.p[0];
                    let gr_db = over_db - over_db / ratio;
                    -gr_db
                } else {
                    0.0
                };
                let cur_db = self.state.env[0];
                let coef = if target < cur_db { atk } else { rel };
                let new_db = cur_db + (target - cur_db) * coef;
                self.state.env[0] = new_db;
                self.gain_reduction_db = -new_db;
                let g = db_to_lin(new_db);
                (l * g, r * g)
            }
            AudioEffectType::Limiter => {
                // Hard ceiling at p0 dB with fast attack; reports GR.
                let ceil = db_to_lin(self.p[0]);
                let peak = l.abs().max(r.abs());
                let target = if peak > ceil { -(lin_to_db(peak) - self.p[0]) } else { 0.0 };
                let atk = (1.0 - (-1.0 / (0.1 * sr / 1000.0)).exp()) as f32;
                let rel = (1.0 - (-1.0 / (50.0 * sr / 1000.0)).exp()) as f32;
                let cur = self.state.env[0];
                let new = cur + (target - cur) * if target < cur { atk } else { rel };
                self.state.env[0] = new;
                self.gain_reduction_db = -new;
                let g = db_to_lin(new);
                (l * g, r * g)
            }
            AudioEffectType::NoiseGate => {
                // p0 = threshold dB, p1 = attack ms, p2 = hold ms, p3 = release ms.
                let thr = db_to_lin(self.p[0]);
                let peak = l.abs().max(r.abs());
                if peak > thr {
                    self.state.gate_open = true;
                    self.state.hold = (self.p[2].max(0.0) * sr / 1000.0) as i32;
                } else if self.state.hold > 0 {
                    self.state.hold -= 1;
                } else {
                    self.state.gate_open = false;
                }
                let target = if self.state.gate_open { 1.0 } else { 0.0 };
                let coef = if self.state.gate_open {
                    (1.0 - (-1.0 / (self.p[1].max(0.1) * sr / 1000.0)).exp()) as f32
                } else {
                    (1.0 - (-1.0 / (self.p[3].max(0.1) * sr / 1000.0)).exp()) as f32
                };
                let g = self.state.env[0] + (target - self.state.env[0]) * coef;
                self.state.env[0] = g;
                self.gain_reduction_db = if self.state.gate_open { 0.0 } else { 60.0 };
                (l * g, r * g)
            }
            AudioEffectType::NoiseReduction => {
                // Expander below threshold with residual output when p3>0.5
                // ("residue" mode keeps the removed noise audible).
                let thr = db_to_lin(self.p[0]); // floor dB (-80..-20)
                let amount = self.p[1].clamp(0.0, 1.0);
                let residue = self.p[3] > 0.5;
                let peak = l.abs().max(r.abs());
                self.state.noise_floor = self.state.noise_floor * 0.999 + peak * 0.001;
                let ref_level = if self.state.noise_floor > thr { peak } else { self.state.noise_floor.max(thr) };
                let below = (peak < thr).then_some(1.0).unwrap_or(0.0);
                let g = 1.0 - below * amount * (1.0 - ref_level.max(1e-6) / peak.max(1e-6)).clamp(0.0, 1.0);
                let g = g.clamp(0.0, 1.0);
                self.gain_reduction_db = -lin_to_db(g.max(1e-6));
                if residue {
                    // Residue: output what was removed (peak − reduced).
                    let kept = (l * g, r * g);
                    (l - kept.0, r - kept.1)
                } else {
                    (l * g, r * g)
                }
            }
            AudioEffectType::BassTreble => {
                // p0 = bass dB (-15..15) at low shelf (200 Hz),
                // p1 = treble dB at high shelf (3 kHz).
                let (bl0, bl1, bl2, al1, al2) = low_shelf(200.0, sr, db_to_lin(self.p[0]));
                let (bh0, bh1, bh2, ah1, ah2) = high_shelf(3000.0, sr, db_to_lin(self.p[1]));
                let mut lo = self.state.bq[0];
                let mut hi = self.state.bq[1];
                let l2 = lo[0].process(l, bl0, bl1, bl2, al1, al2);
                let r2 = lo[1].process(r, bl0, bl1, bl2, al1, al2);
                let l3 = hi[0].process(l2, bh0, bh1, bh2, ah1, ah2);
                let r3 = hi[1].process(r2, bh0, bh1, bh2, ah1, ah2);
                self.state.bq[0] = lo;
                self.state.bq[1] = hi;
                (l3, r3)
            }
            AudioEffectType::Distortion => {
                // p0 = drive (1..30), p1 = output level 0..1, p2 = tone LP Hz.
                let drive = self.p[0].max(1.0);
                let out = self.p[1].clamp(0.0, 1.0);
                let dl = (l * drive).tanh() * out;
                let dr = (r * drive).tanh() * out;
                let (b0, b1, b2, a1, a2) = one_pole_lp(self.p[2].clamp(500.0, 12000.0), sr);
                let lp = &mut self.state.bq[2];
                (
                    lp[0].process(dl, b0, b1, b2, a1, a2),
                    lp[1].process(dr, b0, b1, b2, a1, a2),
                )
            }
            AudioEffectType::Phaser => {
                // 4-stage allpass modulated by p0 Hz LFO, p1 = depth, p2 = mix.
                let rate = self.p[0].clamp(0.05, 8.0);
                let depth = self.p[1].clamp(0.0, 1.0);
                let mix = self.p[2].clamp(0.0, 1.0);
                self.state.lfo_phase += 2.0 * std::f32::consts::PI * rate / sr;
                if self.state.lfo_phase > 2.0 * std::f32::consts::PI {
                    self.state.lfo_phase -= 2.0 * std::f32::consts::PI;
                }
                let mod_freq = 300.0 + 1200.0 * (0.5 + 0.5 * self.state.lfo_phase.sin()) * depth;
                let mut xl = l;
                let mut xr = r;
                for stage in 0..4 {
                    let (b0, b1, b2, a1, a2) = allpass(mod_freq * (1.0 + 0.25 * stage as f32), sr);
                    let st = &mut self.state.phaser[stage];
                    xl = st[0].process(xl, b0, b1, b2, a1, a2);
                    xr = st[1].process(xr, b0, b1, b2, a1, a2);
                }
                (l * (1.0 - mix) + xl * mix, r * (1.0 - mix) + xr * mix)
            }
            AudioEffectType::Reverb => {
                // Schroeder: 4 combs (29.7/37.1/41.1/43.7 ms) + 3 allpasses.
                let mix = self.p[0].clamp(0.0, 1.0); // wet
                let damp = self.p[1].clamp(0.0, 1.0);
                let decay = self.p[2].clamp(0.1, 0.99);
                if self.state.comb[0].is_empty() {
                    self.state.comb_damp = [0.0; 8];
                    for (i, ms) in [29.7f32, 37.1, 41.1, 43.7].iter().enumerate() {
                        let len = (*ms * sr / 1000.0) as usize;
                        self.state.comb[i] = vec![0.0; len];
                        self.state.comb[i + 4] = vec![0.0; len];
                    }
                    for (i, ms) in [5.0f32, 1.7, 0.6].iter().enumerate() {
                        let len = (*ms * sr / 1000.0) as usize;
                        self.state.allp[i] = vec![0.0; len];
                        self.state.allp[i + 3] = vec![0.0; len];
                    }
                }
                let wetl = schroeder(&mut self.state, l, 0, damp, decay);
                let wetr = schroeder(&mut self.state, r, 4, damp, decay);
                (l * (1.0 - mix) + wetl * mix, r * (1.0 - mix) + wetr * mix)
            }
            AudioEffectType::WahWah => {
                // Bandpass sweep: p0 = LFO Hz, p1 = depth, p2 = mix.
                let rate = self.p[0].clamp(0.05, 8.0);
                let depth = self.p[1].clamp(0.0, 1.0);
                let mix = self.p[2].clamp(0.0, 1.0);
                self.state.lfo_phase += 2.0 * std::f32::consts::PI * rate / sr;
                if self.state.lfo_phase > 2.0 * std::f32::consts::PI {
                    self.state.lfo_phase -= 2.0 * std::f32::consts::PI;
                }
                let f = 400.0 + 1600.0 * (0.5 + 0.5 * self.state.lfo_phase.sin()) * depth;
                let q = 3.0;
                let w = 2.0 * std::f32::consts::PI * f / sr;
                let alpha = w.sin() / (2.0 * q);
                let cw = w.cos();
                let a0 = 1.0 + alpha;
                let b0 = alpha / a0;
                let b2 = -alpha / a0;
                let a1 = -2.0 * cw / a0;
                let a2 = (1.0 - alpha) / a0;
                let bq = &mut self.state.bq[0];
                let wl = bq[0].process(l, b0, 0.0, b2, a1, a2);
                let wr = bq[1].process(r, b0, 0.0, b2, a1, a2);
                (l * (1.0 - mix) + wl * mix * 2.0, r * (1.0 - mix) + wr * mix * 2.0)
            }
            AudioEffectType::ShelfFilter => {
                // p0 = cutoff Hz, p1 = gain dB, p2 = kind (0 low, 1 high).
                if self.p[2] < 0.5 {
                    let (b0, b1, b2, a1, a2) = low_shelf(self.p[0].clamp(20.0, 8000.0), sr, db_to_lin(self.p[1]));
                    let bq = &mut self.state.bq[0];
                    (bq[0].process(l, b0, b1, b2, a1, a2), bq[1].process(r, b0, b1, b2, a1, a2))
                } else {
                    let (b0, b1, b2, a1, a2) = high_shelf(self.p[0].clamp(1000.0, 16000.0), sr, db_to_lin(self.p[1]));
                    let bq = &mut self.state.bq[0];
                    (bq[0].process(l, b0, b1, b2, a1, a2), bq[1].process(r, b0, b1, b2, a1, a2))
                }
            }
        }
    }
}

#[inline]
fn db_to_lin(db: f32) -> f32 {
    10.0f32.powf(db / 20.0)
}

#[inline]
fn lin_to_db(lin: f32) -> f32 {
    20.0 * lin.max(1e-9).log10()
}

fn low_shelf(freq: f32, sr: f32, gain: f32) -> (f32, f32, f32, f32, f32) {
    let a = gain.sqrt();
    let w = 2.0 * std::f32::consts::PI * freq / sr;
    let cw = w.cos();
    let t = (w / 2.0).sin();
    // RBJ low shelf.
    let b0 = a * ((a + 1.0) - (a - 1.0) * cw + 2.0 * a.sqrt() * t);
    let b1 = 2.0 * a * ((a - 1.0) - (a + 1.0) * cw);
    let b2 = a * ((a + 1.0) - (a - 1.0) * cw - 2.0 * a.sqrt() * t);
    let a0 = (a + 1.0) + (a - 1.0) * cw + 2.0 * a.sqrt() * t;
    let a1 = -2.0 * ((a - 1.0) + (a + 1.0) * cw);
    let a2 = (a + 1.0) + (a - 1.0) * cw - 2.0 * a.sqrt() * t;
    (b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0)
}

fn high_shelf(freq: f32, sr: f32, gain: f32) -> (f32, f32, f32, f32, f32) {
    let a = gain.sqrt();
    let w = 2.0 * std::f32::consts::PI * freq / sr;
    let cw = w.cos();
    let t = (w / 2.0).sin();
    let b0 = a * ((a + 1.0) + (a - 1.0) * cw + 2.0 * a.sqrt() * t);
    let b1 = -2.0 * a * ((a - 1.0) + (a + 1.0) * cw);
    let b2 = a * ((a + 1.0) + (a - 1.0) * cw - 2.0 * a.sqrt() * t);
    let a0 = (a + 1.0) - (a - 1.0) * cw + 2.0 * a.sqrt() * t;
    let a1 = 2.0 * ((a - 1.0) - (a + 1.0) * cw);
    let a2 = (a + 1.0) - (a - 1.0) * cw - 2.0 * a.sqrt() * t;
    (b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0)
}

fn allpass(freq: f32, sr: f32) -> (f32, f32, f32, f32, f32) {
    // First-order allpass: y[n] = c·x[n] + x[n−1] − c·y[n−1].
    let w = 2.0 * std::f32::consts::PI * freq / sr;
    let c = (std::f32::consts::PI - w).tan() / ((std::f32::consts::PI - w).tan() + w.tan());
    (c, 1.0, 0.0, c, 0.0)
}

fn one_pole_lp(freq: f32, sr: f32) -> (f32, f32, f32, f32, f32) {
    let a = (-2.0 * std::f32::consts::PI * freq / sr).exp();
    let g = 1.0 - a;
    (g, 0.0, 0.0, a, 0.0)
}

/// Schroeder reverb processing for one channel block (comb base + allpass).
fn schroeder(st: &mut EffectState, input: f32, comb_base: usize, damp: f32, decay: f32) -> f32 {
    let mut out = 0.0;
    for i in 0..4 {
        let idx = comb_base + i;
        let len = st.comb[idx].len().max(1);
        let ci = st.comb_idx % len;
        let cur = st.comb[idx][ci];
        // Freeverb comb: one-pole damp on the feedback path, with per-line
        // filter state — `cur*(1-damp) + cur*damp` (the old line) cancels
        // algebraically and left the damp parameter doing nothing.
        let fs = &mut st.comb_damp[idx];
        *fs = cur * (1.0 - damp) + *fs * damp;
        st.comb[idx][ci] = input + *fs * decay;
        out += cur;
    }
    let mut y = out * 0.25;
    for i in 0..3 {
        let idx = i + comb_base / 4 * 3;
        let len = st.allp[idx].len().max(1);
        let ai = st.allp_idx % len;
        let c = 0.5;
        let buf_out = st.allp[idx][ai];
        let delayed_in = st.allp[idx][ai];
        st.allp[idx][ai] = y + buf_out * c;
        y = delayed_in - c * st.allp[idx][ai];
    }
    st.comb_idx = st.comb_idx.wrapping_add(1);
    st.allp_idx = st.allp_idx.wrapping_add(1);
    y
}

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

    fn peak(buf: &[f32]) -> f32 {
        buf.iter().fold(0.0f32, |m, v| m.max(v.abs()))
    }

    #[test]
    fn compressor_reduces_loud_signal() {
        let mut fx = AudioEffect::new(AudioEffectType::Compressor, [-12.0, 4.0, 5.0, 100.0]);
        let mut loud = sine(4410, 440.0, 0.9);
        let before = peak(&loud);
        fx.process(&mut loud, 44100.0);
        // Measure the tail (the first ms is the attack transient).
        let after = peak(&loud[loud.len() / 2..]);
        assert!(after < before * 0.8, "compressor must reduce: {before} -> {after}");
        assert!(fx.gain_reduction_db > 3.0, "GR history: {} dB", fx.gain_reduction_db);
        // Quiet signal stays untouched.
        let mut quiet = sine(4410, 440.0, 0.05);
        let q_before = peak(&quiet);
        fx.process(&mut quiet, 44100.0);
        assert!((peak(&quiet) - q_before).abs() < 0.02, "below threshold ~ passthrough");
    }

    #[test]
    fn limiter_caps_peak() {
        let mut fx = AudioEffect::new(AudioEffectType::Limiter, [-3.0, 0.0, 0.0, 0.0]);
        let mut buf = sine(4410, 440.0, 0.95);
        fx.process(&mut buf, 44100.0);
        assert!(peak(&buf[buf.len() / 2..]) < 0.75, "limiter cap: {}", peak(&buf[buf.len() / 2..]));
    }

    #[test]
    fn gate_silences_quiet_keeps_loud() {
        let mut fx = AudioEffect::new(AudioEffectType::NoiseGate, [-30.0, 1.0, 50.0, 50.0]);
        let mut buf = sine(8820, 440.0, 0.005); // very quiet
        fx.process(&mut buf, 44100.0);
        assert!(peak(&buf[4410 * 2..]) < 0.001, "gate must close on quiet");
        let mut loud = sine(4410, 440.0, 0.5);
        fx.process(&mut loud, 44100.0);
        assert!(peak(&loud) > 0.3, "gate stays open on loud");
    }

    #[test]
    fn reverb_adds_tail_energy() {
        let mut fx = AudioEffect::new(AudioEffectType::Reverb, [0.4, 0.3, 0.85, 0.0]);
        // Impulse.
        let mut buf = vec![0.0f32; 44100 * 2];
        buf[0] = 1.0;
        buf[1] = 1.0;
        fx.process(&mut buf, 44100.0);
        let tail = peak(&buf[22050 * 2..]);
        assert!(tail > 0.0005, "reverb tail energy: {tail}");
    }

    #[test]
    fn bass_treble_changes_spectrum_balance() {
        // Bass +12 must raise low-band energy relative to high.
        let mut fx = AudioEffect::new(AudioEffectType::BassTreble, [12.0, -12.0, 0.0, 0.0]);
        let low = sine(4410, 100.0, 0.5);
        let mut low2 = low.clone();
        fx.process(&mut low2, 44100.0);
        assert!(peak(&low2[low2.len() / 2..]) > peak(&low) * 1.2, "bass boost raises lows");
        let high = sine(4410, 8000.0, 0.5);
        let mut high2 = high.clone();
        fx.process(&mut high2, 44100.0);
        assert!(peak(&high2[high2.len() / 2..]) < peak(&high), "treble cut lowers highs");
    }

    #[test]
    fn distortion_saturates() {
        let mut fx = AudioEffect::new(AudioEffectType::Distortion, [10.0, 0.5, 8000.0, 0.0]);
        let mut buf = sine(4410, 440.0, 0.9);
        fx.process(&mut buf, 44100.0);
        // tanh + out gain 0.5 → peak well below linear 0.45.
        assert!(peak(&buf) < 0.5 && peak(&buf) > 0.1);
    }

    #[test]
    fn shelf_low_boosts_bass() {
        let mut fx = AudioEffect::new(AudioEffectType::ShelfFilter, [200.0, 9.0, 0.0, 0.0]);
        let low = sine(4410, 80.0, 0.5);
        let mut out = low.clone();
        fx.process(&mut out, 44100.0);
        assert!(peak(&out) > peak(&low) * 1.3, "low shelf boost: {}", peak(&out));
    }
}
