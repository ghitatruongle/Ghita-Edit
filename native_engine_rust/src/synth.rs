//! Media decoder wrapper. Without the `ffmpeg` feature this is purely the
//! synthetic fallback (behavior identical to a C++ build without FFmpeg).
//! With `ffmpeg`, `FfmpegDecoder` (media.rs) handles real media first and the
//! synthetic path stays as the transparent fallback for missing files —
//! mirroring `RealFFmpegMediaDecoder`.

use crate::filters::apply_filter_to_buffer;
#[cfg(feature = "parallel")]
use crate::filters::apply_filter_parallel;
use crate::model::MediaInfo;

#[cfg(feature = "ffmpeg")]
use crate::media::FfmpegDecoder;

/// The synthetic sine-field pattern (shared with media.rs fallback).
pub fn render_synthetic(out: &mut [u8], width: usize, height: usize, time_ms: i64) {
    let t = time_ms as f32 / 1000.0f32;
    let cx = 0.5f32 + 0.3f32 * (t * 0.5f32).sin();
    let cy = 0.5f32 + 0.3f32 * (t * 0.3f32).cos();
    for y in 0..height {
        for x in 0..width {
            let nx = x as f32 / width as f32;
            let ny = y as f32 / height as f32;
            let dx = nx - cx;
            let dy = ny - cy;
            let dist = (dx * dx + dy * dy).sqrt();

            let (r, g, b): (u8, u8, u8) = if dist < 0.05f32 {
                (255, 255, 0) // Yellow moving dot
            } else {
                (
                    (128.0f32 + 127.0f32 * (nx * 10.0f32 + t * 2.0f32).sin()) as u8,
                    (128.0f32 + 127.0f32 * (ny * 10.0f32 + t * 1.5f32).sin()) as u8,
                    (128.0f32 + 127.0f32 * ((nx + ny) * 8.0f32 + t * 1.0f32).sin()) as u8,
                )
            };
            let idx = (y * width + x) * 4;
            out[idx] = r;
            out[idx + 1] = g;
            out[idx + 2] = b;
            out[idx + 3] = 255;
        }
    }
}

/// Production-shaped decoder. Without the `ffmpeg` feature this always takes
/// the synthetic-fallback branch, exactly like a C++ build without FFmpeg.
pub struct MediaDecoder {
    pub file_path: String,
    pub duration_ms: i64,
    pub width: i32,
    pub height: i32,
    pub has_ffmpeg: bool,
    pub still_cache: Vec<u8>,
    pub still_cache_w: i32,
    pub still_cache_h: i32,
    #[cfg(feature = "ffmpeg")]
    pub ffmpeg: Option<FfmpegDecoder>,
}

impl MediaDecoder {
    pub fn new() -> Self {
        MediaDecoder {
            file_path: String::new(),
            duration_ms: 60000,
            width: 1920,
            height: 1080,
            has_ffmpeg: false,
            still_cache: Vec::new(),
            still_cache_w: 0,
            still_cache_h: 0,
            #[cfg(feature = "ffmpeg")]
            ffmpeg: None,
        }
    }

    /// Opens the media file. Returns true even when decoding will fall back
    /// to synthetic content (mirrors the C++ transparent-fallback contract).
    pub fn open(&mut self, file_path: &str) -> bool {
        self.file_path = file_path.to_string();
        self.still_cache.clear();
        self.still_cache_w = 0;
        self.still_cache_h = 0;
        #[cfg(feature = "ffmpeg")]
        {
            let mut fd = FfmpegDecoder::new();
            fd.open(file_path);
            self.has_ffmpeg = fd.has_ffmpeg;
            self.duration_ms = fd.duration_ms;
            self.width = fd.width;
            self.height = fd.height;
            self.ffmpeg = Some(fd);
            return true;
        }
        #[cfg(not(feature = "ffmpeg"))]
        {
            // Fallback: synthetic decoder values — 1920×1080 / 60 s / no ffmpeg.
            self.duration_ms = 60000;
            self.width = 1920;
            self.height = 1080;
            self.has_ffmpeg = false;
            true
        }
    }

    /// True when a decodable audio stream exists (used by the mixer to skip
    /// silent sources).
    pub fn has_audio_stream(&self) -> bool {
        #[cfg(feature = "ffmpeg")]
        {
            self.ffmpeg.as_ref().map(|f| f.has_audio_stream()).unwrap_or(false)
        }
        #[cfg(not(feature = "ffmpeg"))]
        {
            false
        }
    }

    /// Decodes an RGBA frame at the given source time.
    pub fn decode_frame(
        &mut self,
        out: &mut [u8],
        width: usize,
        height: usize,
        time_ms: i64,
        filter_type: i32,
        filter_intensity: f32,
    ) -> bool {
        if out.len() < width * height * 4 || width == 0 || height == 0 {
            return false;
        }
        #[cfg(feature = "ffmpeg")]
        if let Some(fd) = self.ffmpeg.as_mut() {
            if fd.has_video_ctx() {
                return fd.decode_frame(out, width, height, time_ms, filter_type, filter_intensity);
            }
        }
        render_synthetic(out, width, height, time_ms);
        #[cfg(feature = "parallel")]
        apply_filter_parallel(out, width, height, filter_type, filter_intensity);
        #[cfg(not(feature = "parallel"))]
        apply_filter_to_buffer(out, width, height, filter_type, filter_intensity);
        true
    }

    /// decodeAudioSegment — mixer path, real PCM when FFmpeg decoded the file.
    #[cfg(feature = "ffmpeg")]
    pub fn decode_audio_segment(&mut self, start_ms: i64, out: &mut [f32], count: usize, volume: f32) -> bool {
        if let Some(fd) = self.ffmpeg.as_mut() {
            if fd.audio_ctx_ready() {
                return fd.decode_audio_segment(start_ms, out, count, volume);
            }
            // FFmpeg is unavailable (file fell back) → no audio stream.
            return false;
        }
        false
    }

    /// MediaInfo with fallback labels — mirrors RealFFmpegMediaDecoder.
    pub fn media_info(&self) -> MediaInfo {
        #[cfg(feature = "ffmpeg")]
        if let Some(fd) = self.ffmpeg.as_ref() {
            return fd.media_info();
        }
        MediaInfo {
            file_path: self.file_path.clone(),
            duration_ms: self.duration_ms,
            width: self.width,
            height: self.height,
            fps: 30.0,
            bitrate: 5000000,
            video_codec: if self.has_ffmpeg { "ffmpeg" } else { "synthetic (fallback)" }.to_string(),
            audio_codec: if self.has_ffmpeg { "ffmpeg" } else { "synthetic (fallback)" }.to_string(),
            audio_sample_rate: 44100,
            audio_channels: 2,
            has_video: true,
            has_audio: true,
        }
    }

    /// Waveform samples — real PCM (WAV direct or whole-file decode) when
    /// FFmpeg decoded the file, rectified synthetic otherwise.
    pub fn extract_pcm_audio_samples(&mut self, out: &mut [f32], volume: f32) -> bool {
        #[cfg(feature = "ffmpeg")]
        {
            if let Some(fd) = self.ffmpeg.as_mut() {
                if fd.audio_ctx_ready() {
                    return fd.extract_pcm_audio_samples(out, volume);
                }
            }
        }
        let len = out.len();
        for (i, o) in out.iter_mut().enumerate() {
            let phase = i as f32 / len as f32;
            let fundamental = (phase * 15.707f32).sin() * 0.5f32;
            let harmonic2 = (phase * 31.415f32).sin() * 0.3f32;
            let harmonic4 = (phase * 62.831f32).cos() * 0.2f32;
            let raw = fundamental + harmonic2 + harmonic4;
            *o = raw.abs() * volume;
        }
        true
    }
}

impl Default for MediaDecoder {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn open_falls_back_to_synthetic_metadata() {
        let mut d = MediaDecoder::new();
        assert!(d.open("missing.mp4"));
        #[cfg(feature = "ffmpeg")]
        assert!(!d.has_ffmpeg);
        #[cfg(not(feature = "ffmpeg"))]
        assert!(!d.has_ffmpeg);
        assert_eq!(d.duration_ms, 60000);
        assert_eq!(d.width, 1920);
        assert_eq!(d.height, 1080);
    }

    #[test]
    fn synthetic_frame_is_opaque_rgba() {
        let mut d = MediaDecoder::new();
        d.open("missing.mp4");
        let mut buf = vec![0u8; 64 * 36 * 4];
        assert!(d.decode_frame(&mut buf, 64, 36, 1000, 0, 0.0));
        assert_eq!(buf[3], 255); // alpha opaque
    }

    #[test]
    fn media_info_json_fallback_labels() {
        let mut d = MediaDecoder::new();
        d.open("missing.mp4");
        let info = d.media_info();
        assert_eq!(info.video_codec, "synthetic (fallback)");
        assert!(info.to_json().contains("\"width\":1920"));
    }

    #[test]
    fn pcm_fallback_rectified_and_volumed() {
        let mut d = MediaDecoder::new();
        let mut out = vec![0f32; 100];
        assert!(d.extract_pcm_audio_samples(&mut out, 0.5));
        for v in &out {
            assert!(*v >= 0.0 && *v <= 0.5);
        }
    }

    /// T2-P1: real media decode — test_video.mp4 must open via FFmpeg, report
    /// real metadata and render real frames (not synthetic).
    #[cfg(feature = "ffmpeg")]
    #[test]
    fn ffmpeg_opens_real_media() {
        let path = "../test_video.mp4";
        if !std::path::Path::new(path).exists() {
            eprintln!("SKIP: test_video.mp4 missing");
            return;
        }
        let mut d = MediaDecoder::new();
        assert!(d.open(path));
        assert!(d.has_ffmpeg, "test_video.mp4 must decode with FFmpeg");
        assert!(d.width > 0 && d.height > 0);
        let info = d.media_info();
        assert_eq!(info.video_codec, "h264");
        let mut buf = vec![0u8; 64 * 36 * 4];
        assert!(d.decode_frame(&mut buf, 64, 36, 100, 0, 0.0));
        assert_eq!(buf[3], 255);
    }

    /// T2-P1: WAV direct reader — test_sine.wav must serve real PCM.
    #[cfg(feature = "ffmpeg")]
    #[test]
    fn ffmpeg_wav_direct_reader() {
        let path = "../test_sine.wav";
        if !std::path::Path::new(path).exists() {
            eprintln!("SKIP: test_sine.wav missing");
            return;
        }
        let mut d = MediaDecoder::new();
        assert!(d.open(path));
        assert!(d.has_ffmpeg);
        assert!(d.has_audio_stream(), "WAV must report an audio stream");
        let mut out = vec![0f32; 882];
        assert!(d.decode_audio_segment(0, &mut out, 882, 1.0), "first window must decode");
        let mut nonzero = 0;
        for v in &out {
            if v.abs() > 1e-4 {
                nonzero += 1;
            }
        }
        assert!(
            nonzero > 882 / 2,
            "a 440 Hz sine window must be mostly non-silent (got {nonzero}/882)"
        );
        // Continuity: an overlapping window must not be silent either.
        let mut out2 = vec![0f32; 882];
        assert!(d.decode_audio_segment(10, &mut out2, 882, 1.0));
        assert!(out2.iter().any(|v| v.abs() > 1e-4));
    }
}