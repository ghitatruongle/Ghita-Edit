//! Real FFmpeg media decoder (feature `ffmpeg`) — byte-faithful port of the
//! C++ `RealFFmpegMediaDecoder` (ghita_engine.cpp): open/find-streams,
//! seek+flush decode with still-image cache, WAV/PCM direct-file reader,
//! and the segment decoder with sample-skip + resampler drain + continuity.
//!
//! SAFETY: every access is serialized by the engine's render mutex (same
//! invariant as the C++ m_renderMutex), so the raw FFmpeg contexts are only
//! ever touched by one thread at a time.

use std::ffi::{c_int, c_void, CStr, CString};
use std::fs::File;
use std::io::{Read, Seek, SeekFrom};

use ffmpeg_sys_next as ffi;
use ffmpeg_sys_next::AVChannelOrder::*;
use ffmpeg_sys_next::AVMediaType::*;
use ffmpeg_sys_next::AVPixelFormat::*;
use ffmpeg_sys_next::AVCodecID::*;
use ffmpeg_sys_next::AVSampleFormat::*;

use crate::filters::apply_filter_to_buffer;
use crate::model::MediaInfo;

/// Port of `RealFFmpegMediaDecoder`. Not thread-safe by itself — the engine
/// holds it under the render mutex (exactly like C++).
pub struct FfmpegDecoder {
    pub file_path: String,
    pub duration_ms: i64,
    pub width: i32,
    pub height: i32,
    pub has_ffmpeg: bool,
    pub media_info: MediaInfo,

    fmt_ctx: *mut ffi::AVFormatContext,
    video_codec_ctx: *mut ffi::AVCodecContext,
    audio_codec_ctx: *mut ffi::AVCodecContext,
    sws_ctx: *mut ffi::SwsContext,
    swr_ctx: *mut ffi::SwrContext,
    mix_swr_ctx: *mut ffi::SwrContext,
    seg_continuity_ms: i64,

    video_stream_idx: c_int,
    audio_stream_idx: c_int,
    packet: *mut ffi::AVPacket,
    frame: *mut ffi::AVFrame,
    rgb_frame: *mut ffi::AVFrame,
    rgb_buffer: *mut u8,
    rgb_buffer_size: c_int,

    still_cache: Vec<u8>,
    still_cache_w: i32,
    still_cache_h: i32,

    // WAV/PCM direct-file reader state.
    pcm_path: String,
    pcm_data_offset: i64,
    pcm_data_bytes: i64,
    pcm_src_ch: c_int,
    pcm_src_rate: c_int,
    pcm_src_float: bool,
    pcm_cached: bool,
    pcm_file: Option<File>,
    pcm_i16_buf: Vec<i16>,
    pcm_f32_buf: Vec<f32>,
    audio_conv_buf: Vec<f32>,
}

// SAFETY: serialized by the render mutex — same contract as the C++ decoder.
unsafe impl Send for FfmpegDecoder {}

fn stereo_layout() -> ffi::AVChannelLayout {
    let mut l = ffi::AVChannelLayout {
        order: AV_CHANNEL_ORDER_NATIVE,
        nb_channels: 2,
        u: ffi::AVChannelLayout__bindgen_ty_1 { mask: ffi::AV_CH_LAYOUT_STEREO as u64 },
        opaque: std::ptr::null_mut(),
    };
    let _ = &mut l;
    l
}

fn av_q2d(q: ffi::AVRational) -> f64 {
    if q.den == 0 {
        0.0
    } else {
        q.num as f64 / q.den as f64
    }
}

impl FfmpegDecoder {
    pub fn new() -> Self {
        FfmpegDecoder {
            file_path: String::new(),
            duration_ms: 60000,
            width: 1920,
            height: 1080,
            has_ffmpeg: false,
            media_info: MediaInfo::default(),
            fmt_ctx: std::ptr::null_mut(),
            video_codec_ctx: std::ptr::null_mut(),
            audio_codec_ctx: std::ptr::null_mut(),
            sws_ctx: std::ptr::null_mut(),
            swr_ctx: std::ptr::null_mut(),
            mix_swr_ctx: std::ptr::null_mut(),
            seg_continuity_ms: -1,
            video_stream_idx: -1,
            audio_stream_idx: -1,
            packet: std::ptr::null_mut(),
            frame: std::ptr::null_mut(),
            rgb_frame: std::ptr::null_mut(),
            rgb_buffer: std::ptr::null_mut(),
            rgb_buffer_size: 0,
            still_cache: Vec::new(),
            still_cache_w: 0,
            still_cache_h: 0,
            pcm_path: String::new(),
            pcm_data_offset: 0,
            pcm_data_bytes: 0,
            pcm_src_ch: 0,
            pcm_src_rate: 0,
            pcm_src_float: false,
            pcm_cached: false,
            pcm_file: None,
            pcm_i16_buf: Vec::new(),
            pcm_f32_buf: Vec::new(),
            audio_conv_buf: Vec::new(),
        }
    }

    pub fn has_video_ctx(&self) -> bool {
        self.has_ffmpeg && !self.video_codec_ctx.is_null()
    }

    pub fn has_audio_stream(&self) -> bool {
        self.has_ffmpeg && self.audio_stream_idx >= 0
    }

    /// True when the audio codec context is live (usable for PCM extraction).
    pub fn audio_ctx_ready(&self) -> bool {
        self.has_ffmpeg && !self.audio_codec_ctx.is_null()
    }

    /// RealFFmpegMediaDecoder::open — FFmpeg init or transparent fallback.
    pub fn open(&mut self, file_path: &str) -> bool {
        self.file_path = file_path.to_string();
        unsafe {
            if self.init_ffmpeg_contexts() {
                self.has_ffmpeg = true;
                self.media_info = self.build_media_info();
                self.duration_ms = self.media_info.duration_ms;
                self.width = self.media_info.width;
                self.height = self.media_info.height;
                return true;
            }
            self.destroy_ffmpeg_contexts();
        }
        // Fallback: synthetic decoder values (1920×1080 / 60s).
        self.duration_ms = 60000;
        self.width = 1920;
        self.height = 1080;
        self.has_ffmpeg = false;
        true
    }

    /// Decodes an RGBA frame; falls back to the synthetic pattern when the
    /// file has no decodable video stream.
    pub fn decode_frame(
        &mut self,
        out: &mut [u8],
        width: usize,
        height: usize,
        time_ms: i64,
        filter_type: i32,
        filter_intensity: f32,
    ) -> bool {
        if self.has_video_ctx() {
            unsafe {
                return self.decode_video_frame_at(out, width, height, time_ms, filter_type, filter_intensity);
            }
        }
        crate::synth::render_synthetic(out, width, height, time_ms);
        apply_filter_to_buffer(out, width, height, filter_type, filter_intensity);
        true
    }

    /// MediaInfo — the FFmpeg-built one when available.
    pub fn media_info(&self) -> MediaInfo {
        if self.has_ffmpeg && !self.media_info.file_path.is_empty() {
            return self.media_info.clone();
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

    /// extractPcmAudioSamples — real PCM (WAV direct or whole-file decode) or
    /// the rectified synthetic fallback.
    pub fn extract_pcm_audio_samples(&mut self, out: &mut [f32], volume: f32) -> bool {
        if self.has_ffmpeg && !self.audio_codec_ctx.is_null() {
            if self.pcm_cached {
                return self.read_pcm_from_cache(0, out, volume);
            }
            return unsafe { self.decode_audio_samples(out, volume) };
        }
        let len = out.len();
        for (i, o) in out.iter_mut().enumerate() {
            let phase = i as f32 / len as f32;
            let fundamental = (phase * 15.707f32).sin() * 0.5f32;
            let harmonic2 = (phase * 31.415f32).sin() * 0.3f32;
            let harmonic4 = (phase * 62.831f32).cos() * 0.2f32;
            *o = (fundamental + harmonic2 + harmonic4).abs() * volume;
        }
        true
    }

    /// decodeAudioSegment — the mixer path (interleaved FLT stereo @ 44100).
    pub fn decode_audio_segment(&mut self, start_ms: i64, out: &mut [f32], count: usize, volume: f32) -> bool {
        if out.is_empty() || count == 0 {
            return false;
        }
        if self.pcm_cached {
            return self.read_pcm_from_cache(start_ms, out, volume);
        }
        if self.fmt_ctx.is_null() || self.audio_stream_idx < 0 || self.audio_codec_ctx.is_null()
            || self.packet.is_null() || self.frame.is_null()
        {
            return false;
        }
        unsafe {
            // Dedicated resampler: source layout → interleaved FLT stereo @ 44100.
            if self.mix_swr_ctx.is_null() {
                let stereo = stereo_layout();
                let ret = ffi::swr_alloc_set_opts2(
                    &mut self.mix_swr_ctx,
                    &stereo,
                    AV_SAMPLE_FMT_FLT,
                    44100,
                    &(*self.audio_codec_ctx).ch_layout,
                    (*self.audio_codec_ctx).sample_fmt,
                    (*self.audio_codec_ctx).sample_rate,
                    0,
                    std::ptr::null_mut(),
                );
                if ret < 0 || self.mix_swr_ctx.is_null() {
                    return false;
                }
                if ffi::swr_init(self.mix_swr_ctx) < 0 {
                    ffi::swr_free(&mut self.mix_swr_ctx);
                    return false;
                }
            }

            let stream = *(*self.fmt_ctx).streams.add(self.audio_stream_idx as usize);
            let time_base = av_q2d((*stream).time_base);
            let target_pts = ((start_ms as f64 / 1000.0) / time_base) as i64;
            // v1.0.2: sample-count based skip; v1.1.0 (PLAN 2.6/C5): fast
            // continuation for non-PCM formats only.
            let contiguous = start_ms == self.seg_continuity_ms;
            let target_samples = if (*self.audio_codec_ctx).sample_rate > 0 {
                ((start_ms as f64 / 1000.0) * (*self.audio_codec_ctx).sample_rate as f64) as i64
            } else {
                0
            };

            if !contiguous {
                let seek_window_samples = (count / 2) as i64;
                let seek_max = target_pts
                    + (seek_window_samples as f64
                        / ((*self.audio_codec_ctx).sample_rate.max(1) as f64)
                        * time_base
                        * 1000.0
                        + 1000.0) as i64;
                if ffi::avformat_seek_file(self.fmt_ctx, self.audio_stream_idx, i64::MIN, target_pts, seek_max, 0) < 0 {
                    return false;
                }
                ffi::avcodec_flush_buffers(self.audio_codec_ctx);
            }

            // v1.1.0 (PLAN 2.9): grow-only conversion buffer.
            self.audio_conv_buf.resize(16384 * 2, 0.0);
            let conv_buf = &mut self.audio_conv_buf;
            let mut collected = 0usize;
            let mut decoded_samples: i64 = 0;
            let src_planar = ffi::av_sample_fmt_is_planar((*self.audio_codec_ctx).sample_fmt) != 0;
            let src_fmt_bytes = ffi::av_get_bytes_per_sample((*self.audio_codec_ctx).sample_fmt);
            let n_ch = (*self.audio_codec_ctx).ch_layout.nb_channels.max(1);

            loop {
                let read_ret = ffi::av_read_frame(self.fmt_ctx, self.packet);
                if read_ret < 0 {
                    break; // EOF / transient failure — mixer handles short reads
                }
                if (*self.packet).stream_index == self.audio_stream_idx {
                    if ffi::avcodec_send_packet(self.audio_codec_ctx, self.packet) == 0 {
                        let ret = ffi::avcodec_receive_frame(self.audio_codec_ctx, self.frame);
                        if ret == 0 && !(*self.frame).data[0].is_null() && (*self.frame).nb_samples > 0 {
                            let nb = (*self.frame).nb_samples as i64;
                            let mut skip = 0i64;
                            if !contiguous {
                                if decoded_samples + nb <= target_samples {
                                    decoded_samples += nb;
                                    ffi::av_packet_unref(self.packet);
                                    continue;
                                }
                                if decoded_samples < target_samples {
                                    skip = target_samples - decoded_samples;
                                }
                            }
                            decoded_samples += nb;

                            let mut in_planes: [*mut u8; 8] = [std::ptr::null_mut(); 8];
                            for ch in 0..n_ch.min(8) {
                                let base = if !(*self.frame).extended_data.is_null()
                                    && !(*self.frame).extended_data.add(ch as usize).is_null()
                                {
                                    *(*self.frame).extended_data.add(ch as usize)
                                } else {
                                    (*self.frame).data[0]
                                };
                                if src_planar {
                                    in_planes[ch as usize] = base.add((skip * src_fmt_bytes as i64) as usize);
                                } else {
                                    in_planes[ch as usize] = base.add((skip * src_fmt_bytes as i64 * n_ch as i64) as usize);
                                }
                            }
                            let out_plane: *mut u8 = conv_buf.as_mut_ptr() as *mut u8;
                            let out_frames = ffi::swr_convert(
                                self.mix_swr_ctx,
                                &out_plane as *const *mut u8,
                                (conv_buf.len() / 2) as c_int,
                                in_planes.as_ptr() as *const *const u8,
                                (nb - skip) as c_int,
                            );
                            if out_frames > 0 {
                                let to_copy = ((out_frames as usize) * 2).min(count - collected);
                                for i in 0..to_copy {
                                    out[collected + i] = conv_buf[i] * volume;
                                }
                                collected += to_copy;
                            }
                        }
                    }
                }
                ffi::av_packet_unref(self.packet);
            }

            // v1.0.2b: drain the resampler's internal buffer.
            if collected < count {
                loop {
                    let out_plane: *mut u8 = conv_buf.as_mut_ptr() as *mut u8;
                    let drain = ffi::swr_convert(
                        self.mix_swr_ctx,
                        &out_plane as *const *mut u8,
                        (conv_buf.len() / 2) as c_int,
                        std::ptr::null(),
                        0,
                    );
                    if drain > 0 {
                        let to_copy = ((drain as usize) * 2).min(count - collected);
                        for i in 0..to_copy {
                            out[collected + i] = conv_buf[i] * volume;
                        }
                        collected += to_copy;
                    } else {
                        break;
                    }
                    if collected >= count {
                        break;
                    }
                }
            }
            // v1.0.2b: record where this call ended so the next contiguous
            // chunk continues without a seek.
            if collected > 0 {
                self.seg_continuity_ms = start_ms + (count / 2) as i64 * 1000 / 44100;
            } else {
                self.seg_continuity_ms = -1;
            }
            collected > 0
        }
    }

    // ------------------------------------------------------------------
    // init / destroy
    // ------------------------------------------------------------------

    unsafe fn init_ffmpeg_contexts(&mut self) -> bool {
        self.destroy_ffmpeg_contexts();

        let mut fmt: *mut ffi::AVFormatContext = std::ptr::null_mut();
        let path = CString::new(self.file_path.clone()).unwrap_or_default();
        if ffi::avformat_open_input(&mut fmt, path.as_ptr(), std::ptr::null_mut(), std::ptr::null_mut()) != 0 {
            return false;
        }
        self.fmt_ctx = fmt;
        if ffi::avformat_find_stream_info(fmt, std::ptr::null_mut()) < 0 {
            return false;
        }

        self.video_stream_idx = -1;
        self.audio_stream_idx = -1;
        let nb = (*fmt).nb_streams;
        for i in 0..nb {
            let st = *(*fmt).streams.add(i as usize);
            let params = (*st).codecpar;
            if (*params).codec_type == AVMEDIA_TYPE_VIDEO && self.video_stream_idx < 0 {
                self.video_stream_idx = i as c_int;
            } else if (*params).codec_type == AVMEDIA_TYPE_AUDIO && self.audio_stream_idx < 0 {
                self.audio_stream_idx = i as c_int;
            }
        }
        if self.video_stream_idx < 0 && self.audio_stream_idx < 0 {
            return false;
        }

        // Open video decoder.
        if self.video_stream_idx >= 0 {
            let params = (*(*(*fmt).streams.add(self.video_stream_idx as usize))).codecpar;
            let codec = ffi::avcodec_find_decoder((*params).codec_id);
            if codec.is_null() {
                return false;
            }
            self.video_codec_ctx = ffi::avcodec_alloc_context3(codec);
            if self.video_codec_ctx.is_null()
                || ffi::avcodec_parameters_to_context(self.video_codec_ctx, params) < 0
                || ffi::avcodec_open2(self.video_codec_ctx, codec, std::ptr::null_mut()) < 0
            {
                return false;
            }
        }

        // Open audio decoder.
        if self.audio_stream_idx >= 0 {
            let params = (*(*(*fmt).streams.add(self.audio_stream_idx as usize))).codecpar;
            let codec = ffi::avcodec_find_decoder((*params).codec_id);
            if codec.is_null() {
                return false;
            }
            self.audio_codec_ctx = ffi::avcodec_alloc_context3(codec);
            if self.audio_codec_ctx.is_null()
                || ffi::avcodec_parameters_to_context(self.audio_codec_ctx, params) < 0
                || ffi::avcodec_open2(self.audio_codec_ctx, codec, std::ptr::null_mut()) < 0
            {
                return false;
            }
        }

        self.packet = ffi::av_packet_alloc();
        self.frame = ffi::av_frame_alloc();
        self.rgb_frame = ffi::av_frame_alloc();
        if self.packet.is_null() || self.frame.is_null() || self.rgb_frame.is_null() {
            return false;
        }

        // RGB buffer for sws_scale.
        if !self.video_codec_ctx.is_null() {
            let vc = self.video_codec_ctx;
            self.rgb_buffer_size = ffi::av_image_get_buffer_size(AV_PIX_FMT_RGBA, (*vc).width, (*vc).height, 1);
            self.rgb_buffer = ffi::av_malloc(self.rgb_buffer_size as usize) as *mut u8;
            let mut data: [*mut u8; 8] = [std::ptr::null_mut(); 8];
            let mut linesize: [c_int; 8] = [0; 8];
            ffi::av_image_fill_arrays(
                data.as_mut_ptr(),
                linesize.as_mut_ptr(),
                self.rgb_buffer,
                AV_PIX_FMT_RGBA,
                (*vc).width,
                (*vc).height,
                1,
            );
            (*self.rgb_frame).data[0] = data[0];
            (*self.rgb_frame).linesize[0] = linesize[0];
            self.sws_ctx = ffi::sws_getContext(
                (*vc).width,
                (*vc).height,
                (*vc).pix_fmt,
                (*vc).width,
                (*vc).height,
                AV_PIX_FMT_RGBA,
                ffi::SwsFlags::SWS_BILINEAR as c_int,
                std::ptr::null_mut(),
                std::ptr::null_mut(),
                std::ptr::null_mut(),
            );
        }

        // SWR context for audio resampling (waveform path).
        if !self.audio_codec_ctx.is_null() {
            let ac = self.audio_codec_ctx;
            let ret = ffi::swr_alloc_set_opts2(
                &mut self.swr_ctx,
                &(*ac).ch_layout,
                AV_SAMPLE_FMT_FLT,
                (*ac).sample_rate,
                &(*ac).ch_layout,
                (*ac).sample_fmt,
                (*ac).sample_rate,
                0,
                std::ptr::null_mut(),
            );
            if ret < 0 || (self.swr_ctx.is_null() == false && ffi::swr_init(self.swr_ctx) < 0) {
                ffi::swr_free(&mut self.swr_ctx);
            }
        }

        // Build media info (v1.0.2: reset stale metadata from a previous open).
        self.media_info = MediaInfo::default();
        self.media_info.file_path = self.file_path.clone();
        self.media_info.has_video = self.video_stream_idx >= 0;
        self.media_info.has_audio = self.audio_stream_idx >= 0;

        if self.video_stream_idx >= 0 {
            let vs = *(*fmt).streams.add(self.video_stream_idx as usize);
            let time_base = av_q2d((*vs).time_base);
            let stream_duration_ms = ((*vs).duration as f64 * time_base * 1000.0) as i64;
            let fmt_duration_ms = if (*fmt).duration > 0 { (*fmt).duration / 1000 } else { 60000 };
            self.media_info.duration_ms = if stream_duration_ms > 0 { stream_duration_ms } else { fmt_duration_ms };
            self.media_info.width = (*self.video_codec_ctx).width;
            self.media_info.height = (*self.video_codec_ctx).height;
            let mut fps = av_q2d((*vs).avg_frame_rate);
            if fps <= 0.0 {
                fps = av_q2d((*vs).r_frame_rate);
            }
            self.media_info.fps = fps;
            self.media_info.bitrate = (*fmt).bit_rate;
        }
        if self.video_stream_idx >= 0 && !self.video_codec_ctx.is_null() && !(*self.video_codec_ctx).codec.is_null() {
            let name = (*((*self.video_codec_ctx).codec)).name;
            if !name.is_null() {
                self.media_info.video_codec = CStr::from_ptr(name).to_string_lossy().into_owned();
            }
        }
        if self.audio_stream_idx >= 0 && !self.audio_codec_ctx.is_null() && !(*self.audio_codec_ctx).codec.is_null() {
            let name = (*((*self.audio_codec_ctx).codec)).name;
            if !name.is_null() {
                self.media_info.audio_codec = CStr::from_ptr(name).to_string_lossy().into_owned();
            }
            self.media_info.audio_sample_rate = (*self.audio_codec_ctx).sample_rate;
            self.media_info.audio_channels = (*self.audio_codec_ctx).ch_layout.nb_channels;
        }
        if self.media_info.duration_ms <= 0 {
            self.media_info.duration_ms = 60000;
        }

        // v1.0.2d: pre-parse PCM/WAV streams for the direct-file reader.
        if self.audio_stream_idx >= 0 && !self.audio_codec_ctx.is_null() {
            let id = (*self.audio_codec_ctx).codec_id;
            if id == AV_CODEC_ID_PCM_S16LE || id == AV_CODEC_ID_PCM_F32LE {
                self.pcm_cache_audio();
            }
        }
        true
    }

    unsafe fn destroy_ffmpeg_contexts(&mut self) {
        if !self.sws_ctx.is_null() {
            ffi::sws_freeContext(self.sws_ctx);
            self.sws_ctx = std::ptr::null_mut();
        }
        if !self.swr_ctx.is_null() {
            ffi::swr_free(&mut self.swr_ctx);
        }
        if !self.mix_swr_ctx.is_null() {
            ffi::swr_free(&mut self.mix_swr_ctx);
        }
        if !self.rgb_buffer.is_null() {
            ffi::av_free(self.rgb_buffer as *mut c_void);
            self.rgb_buffer = std::ptr::null_mut();
        }
        if !self.rgb_frame.is_null() {
            ffi::av_frame_free(&mut self.rgb_frame);
        }
        if !self.frame.is_null() {
            ffi::av_frame_free(&mut self.frame);
        }
        if !self.packet.is_null() {
            ffi::av_packet_free(&mut self.packet);
        }
        if !self.video_codec_ctx.is_null() {
            ffi::avcodec_free_context(&mut self.video_codec_ctx);
        }
        if !self.audio_codec_ctx.is_null() {
            ffi::avcodec_free_context(&mut self.audio_codec_ctx);
        }
        if !self.fmt_ctx.is_null() {
            ffi::avformat_close_input(&mut self.fmt_ctx);
        }
        self.pcm_path.clear();
        self.pcm_data_offset = 0;
        self.pcm_data_bytes = 0;
        self.pcm_src_ch = 0;
        self.pcm_src_rate = 0;
        self.pcm_src_float = false;
        self.pcm_cached = false;
        self.pcm_file = None;
        self.still_cache.clear();
        self.still_cache_w = 0;
        self.still_cache_h = 0;
        self.seg_continuity_ms = -1;
    }

    fn build_media_info(&self) -> MediaInfo {
        self.media_info.clone()
    }

    // ------------------------------------------------------------------
    // decodeVideoFrameAt
    // ------------------------------------------------------------------

    unsafe fn decode_video_frame_at(
        &mut self,
        out: &mut [u8],
        out_width: usize,
        out_height: usize,
        time_ms: i64,
        filter_type: i32,
        filter_intensity: f32,
    ) -> bool {
        if self.fmt_ctx.is_null() || self.video_stream_idx < 0 || self.video_codec_ctx.is_null()
            || self.packet.is_null() || self.frame.is_null()
        {
            return false;
        }
        let stream = *(*self.fmt_ctx).streams.add(self.video_stream_idx as usize);
        let mut time_base = av_q2d((*stream).time_base);
        if time_base <= 0.000001 || time_base.is_nan() || time_base.is_infinite() {
            time_base = 1.0 / 90000.0;
        }
        let mut target_sec = time_ms as f64 / 1000.0;
        if target_sec < 0.0 {
            target_sec = 0.0;
        }
        let mut target_pts = (target_sec / time_base) as i64;
        if target_pts < 0 {
            target_pts = 0;
        }

        // v1.0.3: detect single-frame streams (stills).
        let nb_frames = (*stream).nb_frames;
        let stream_ms = if (*stream).duration > 0 {
            (*stream).duration as f64 * av_q2d((*stream).time_base) * 1000.0
        } else {
            0.0
        };
        let likely_still = nb_frames == 1
            || ((*stream).duration <= 0 && nb_frames <= 0)
            || (stream_ms > 0.0 && stream_ms < 100.0)
            || (*stream).duration == 1;

        // Serve the cached still when the same output size is requested.
        if likely_still && !self.still_cache.is_empty()
            && self.still_cache_w == out_width as i32 && self.still_cache_h == out_height as i32
        {
            out[..out_width * out_height * 4].copy_from_slice(&self.still_cache);
            apply_filter_to_buffer(out, out_width, out_height, filter_type, filter_intensity);
            return true;
        }

        let seek_ret = ffi::av_seek_frame(self.fmt_ctx, self.video_stream_idx, target_pts, ffi::AVSEEK_FLAG_BACKWARD);
        if seek_ret < 0 {
            ffi::av_seek_frame(self.fmt_ctx, self.video_stream_idx, 0, ffi::AVSEEK_FLAG_BACKWARD);
        }
        ffi::avcodec_flush_buffers(self.video_codec_ctx);

        // The read+decode loop, used twice (after seek, and after a fresh
        // demuxer open for image2-style stills).
        macro_rules! read_loop {
            () => {{
                let mut decoded = false;
                loop {
                    let r = ffi::av_read_frame(self.fmt_ctx, self.packet);
                    if r < 0 {
                        break;
                    }
                    if (*self.packet).stream_index == self.video_stream_idx {
                        if ffi::avcodec_send_packet(self.video_codec_ctx, self.packet) == 0 {
                            let ret = ffi::avcodec_receive_frame(self.video_codec_ctx, self.frame);
                            if ret == 0 {
                                let mut frame_pts = (*self.frame).pts;
                                if frame_pts == i64::MIN {
                                    frame_pts = 0;
                                }
                                if frame_pts >= target_pts {
                                    ffi::av_packet_unref(self.packet);
                                    decoded = true;
                                    break;
                                }
                                if likely_still {
                                    ffi::av_packet_unref(self.packet);
                                    decoded = true;
                                    break;
                                }
                            }
                        }
                    }
                    ffi::av_packet_unref(self.packet);
                }
                decoded
            }};
        }

        let mut frame_decoded = read_loop!();
        // v1.0.3: fresh demuxer open for image pipes that consume their
        // single packet during find_stream_info.
        if !frame_decoded {
            let mut fresh: *mut ffi::AVFormatContext = std::ptr::null_mut();
            let path = CString::new(self.file_path.clone()).unwrap_or_default();
            if ffi::avformat_open_input(&mut fresh, path.as_ptr(), std::ptr::null_mut(), std::ptr::null_mut()) == 0
                && ffi::avformat_find_stream_info(fresh, std::ptr::null_mut()) >= 0
            {
                ffi::avformat_close_input(&mut self.fmt_ctx);
                self.fmt_ctx = fresh;
                ffi::avcodec_flush_buffers(self.video_codec_ctx);
                frame_decoded = read_loop!();
            } else if !fresh.is_null() {
                ffi::avformat_close_input(&mut fresh);
            }
        }
        if !frame_decoded {
            return false;
        }

        // Convert to RGBA.
        if !self.sws_ctx.is_null() {
            ffi::sws_scale(
                self.sws_ctx,
                (*self.frame).data.as_ptr() as *const *const u8,
                (*self.frame).linesize.as_ptr(),
                0,
                (*self.video_codec_ctx).height,
                (*self.rgb_frame).data.as_ptr(),
                (*self.rgb_frame).linesize.as_ptr(),
            );
        }

        let vw = (*self.video_codec_ctx).width as usize;
        let vh = (*self.video_codec_ctx).height as usize;
        let rgb = std::slice::from_raw_parts(self.rgb_buffer, (vw * vh * 4).max(0));
        if vw == out_width && vh == out_height {
            out[..out_width * out_height * 4].copy_from_slice(&rgb[..out_width * out_height * 4]);
        } else {
            // Simple bilinear resize (nearest sampling, matching C++).
            let scale_x = vw as f32 / out_width as f32;
            let scale_y = vh as f32 / out_height as f32;
            for y in 0..out_height {
                let src_y = ((y as f32 * scale_y) as usize).min(vh - 1);
                for x in 0..out_width {
                    let src_x = ((x as f32 * scale_x) as usize).min(vw - 1);
                    let src_idx = (src_y * vw + src_x) * 4;
                    let dst_idx = (y * out_width + x) * 4;
                    out[dst_idx] = rgb[src_idx];
                    out[dst_idx + 1] = rgb[src_idx + 1];
                    out[dst_idx + 2] = rgb[src_idx + 2];
                    out[dst_idx + 3] = 255;
                }
            }
        }

        apply_filter_to_buffer(out, out_width, out_height, filter_type, filter_intensity);

        // v1.0.3: cache the still frame at the requested output size.
        if likely_still {
            self.still_cache = out[..out_width * out_height * 4].to_vec();
            self.still_cache_w = out_width as i32;
            self.still_cache_h = out_height as i32;
        }
        true
    }

    // ------------------------------------------------------------------
    // decodeAudioSamples (waveform — whole file from the start)
    // ------------------------------------------------------------------

    unsafe fn decode_audio_samples(&mut self, out: &mut [f32], volume: f32) -> bool {
        let sample_count = out.len();
        let mut accum = vec![0.0f32; sample_count];
        let mut samples_collected = 0usize;
        let mut conv_buffer = vec![0.0f32; sample_count];

        if ffi::av_seek_frame(self.fmt_ctx, self.audio_stream_idx, 0, ffi::AVSEEK_FLAG_BACKWARD) < 0 {
            return false;
        }
        ffi::avcodec_flush_buffers(self.audio_codec_ctx);

        loop {
            if ffi::av_read_frame(self.fmt_ctx, self.packet) < 0 || samples_collected >= sample_count {
                break;
            }
            if (*self.packet).stream_index == self.audio_stream_idx {
                if ffi::avcodec_send_packet(self.audio_codec_ctx, self.packet) == 0 {
                    let ret = ffi::avcodec_receive_frame(self.audio_codec_ctx, self.frame);
                    if ret == 0 && !(*self.frame).data[0].is_null() {
                        let mut float_data = (*self.frame).data[0] as *mut f32;
                        let mut frames = (*self.frame).nb_samples as usize;
                        if (*self.audio_codec_ctx).sample_fmt != AV_SAMPLE_FMT_FLT && !self.swr_ctx.is_null() {
                            let conv_out: [*mut u8; 1] = [conv_buffer.as_mut_ptr() as *mut u8];
                            let requested = frames.min(sample_count);
                            let out_frames = ffi::swr_convert(
                                self.swr_ctx,
                                conv_out.as_ptr(),
                                requested as c_int,
                                (*self.frame).data.as_ptr() as *const *const u8,
                                frames as c_int,
                            );
                            if out_frames > 0 {
                                float_data = conv_out[0] as *mut f32;
                                frames = (out_frames as usize).min(requested);
                            }
                        }
                        let to_copy = frames.min(sample_count - samples_collected);
                        for i in 0..to_copy {
                            accum[samples_collected + i] += *float_data.add(i) * volume;
                        }
                        samples_collected += to_copy;
                    }
                }
            }
            ffi::av_packet_unref(self.packet);
        }

        if samples_collected == 0 {
            return false;
        }
        for i in 0..sample_count {
            out[i] = accum[i].abs();
        }
        true
    }

    // ------------------------------------------------------------------
    // WAV/PCM direct-file reader (v1.0.2d → v1.0.3)
    // ------------------------------------------------------------------

    // Free helpers for the RIFF walk (no closure capture conflicts).
    fn read32(f: &mut File, at: i64) -> u32 {
        let mut b = [0u8; 4];
        let _ = f.seek(SeekFrom::Start(at as u64));
        if f.read_exact(&mut b).is_err() {
            return 0;
        }
        u32::from_le_bytes(b)
    }
    fn read16_at(f: &mut File, at: i64) -> u16 {
        let mut b = [0u8; 2];
        let _ = f.seek(SeekFrom::Start(at as u64));
        if f.read_exact(&mut b).is_err() {
            return 0;
        }
        u16::from_le_bytes(b)
    }
    fn read_tag(f: &mut File, at: i64, out: &mut [u8; 4]) -> bool {
        let _ = f.seek(SeekFrom::Start(at as u64));
        f.read_exact(out).is_ok()
    }

    unsafe fn pcm_cache_audio(&mut self) -> bool {
        if self.fmt_ctx.is_null() || self.audio_stream_idx < 0 || self.audio_codec_ctx.is_null() {
            return false;
        }
        let params = (*(*(*self.fmt_ctx).streams.add(self.audio_stream_idx as usize))).codecpar;
        if (*params).format != AV_SAMPLE_FMT_S16 as c_int
            && (*params).format != AV_SAMPLE_FMT_S16P as c_int
            && (*params).format != AV_SAMPLE_FMT_FLT as c_int
            && (*params).format != AV_SAMPLE_FMT_FLTP as c_int
        {
            return false; // only integer/float PCM is byte-addressable
        }

        // Parse the RIFF container directly: 'fmt ' → tag/channels/rate;
        // 'data' → sample byte range. Then every mix window reads the exact
        // byte range straight from the file.
        let mut f = match File::open(&self.file_path) {
            Ok(f) => f,
            Err(_) => return false,
        };

        let mut riff = [0u8; 4];
        if !Self::read_tag(&mut f, 0, &mut riff) || &riff != b"RIFF" {
            return false;
        }
        let mut wave = [0u8; 4];
        if !Self::read_tag(&mut f, 8, &mut wave) || &wave != b"WAVE" {
            return false;
        }

        let file_len = f.seek(SeekFrom::End(0)).unwrap_or(0) as i64;
        let mut pos = 12i64;
        let mut fmt_tag = -1i32;
        let mut fmt_ch: i64 = 0;
        let mut fmt_rate = 0i32;
        let mut fmt_bits = 0i32;
        let mut data_off = -1i64;
        let mut data_len = 0i64;

        while pos + 8 <= file_len {
            let mut cid = [0u8; 4];
            if !Self::read_tag(&mut f, pos, &mut cid) {
                break;
            }
            let csize = Self::read32(&mut f, pos + 4) as i64;
            if &cid == b"fmt " {
                fmt_tag = Self::read16_at(&mut f, pos + 8) as i32;
                fmt_ch = Self::read16_at(&mut f, pos + 10) as i64;
                fmt_rate = Self::read32(&mut f, pos + 12) as i32;
                fmt_bits = Self::read16_at(&mut f, pos + 22) as i32;
            } else if &cid == b"data" {
                data_off = pos + 8;
                data_len = csize;
            }
            pos += 8 + csize;
        }

        let fmt_ok = fmt_tag == 1 || fmt_tag == 3;
        if !fmt_ok || fmt_ch < 1 || fmt_ch > 2 || fmt_rate <= 0 || data_off < 0 || data_len <= 0 {
            return false;
        }
        let is_float = fmt_tag == 3;
        let bytes_per_sample: i64 = if is_float { 4 } else { 2 };
        data_len = (data_len / (bytes_per_sample * fmt_ch)) * bytes_per_sample * fmt_ch;

        self.pcm_path = self.file_path.clone();
        self.pcm_data_offset = data_off;
        self.pcm_data_bytes = data_len;
        self.pcm_src_ch = fmt_ch as i32;
        self.pcm_src_rate = fmt_rate;
        self.pcm_src_float = is_float;
        self.pcm_cached = true;
        self.pcm_file = Some(f);
        true
    }

    fn read_pcm_from_cache(&mut self, start_ms: i64, out: &mut [f32], volume: f32) -> bool {
        if !self.pcm_cached {
            return false;
        }
        let count = out.len();
        let dst_ch = 2usize;
        let frames_needed = count / dst_ch;
        for o in out.iter_mut() {
            *o = 0.0;
        }
        if frames_needed == 0 {
            return true;
        }

        let src_rate = self.pcm_src_rate as f64;
        let start_frame = (start_ms as f64 / 1000.0 * src_rate) as i64;
        let bytes_per_frame = (self.pcm_src_ch * if self.pcm_src_float { 4 } else { 2 }) as i64;
        let total_frames = if bytes_per_frame > 0 { self.pcm_data_bytes / bytes_per_frame } else { 0 };
        if start_frame < 0 || start_frame >= total_frames || total_frames <= 0 {
            return true; // silence, but valid (window past EOF)
        }

        let end_frame = total_frames.min(
            start_frame
                + ((frames_needed as f64 * src_rate / 44100.0).ceil() as i64)
                + 1,
        );
        let need_frames = end_frame - start_frame;
        let byte_off = (self.pcm_data_offset + start_frame * bytes_per_frame) as u64;
        let byte_len = (need_frames * bytes_per_frame) as usize;

        let f = match self.pcm_file.as_mut() {
            Some(f) => f,
            None => return true,
        };
        let _ = f.seek(SeekFrom::Start(byte_off));

        if self.pcm_src_float {
            self.pcm_f32_buf.resize(byte_len / 4, 0.0);
            if f.read_exact(bytemuck_u8(&mut self.pcm_f32_buf)).is_err() {
                return true; // short read → silence
            }
        } else {
            self.pcm_i16_buf.resize(byte_len / 2, 0);
            if f.read_exact(bytemuck_u8(&mut self.pcm_i16_buf)).is_err() {
                return true;
            }
        }

        let step = src_rate / 44100.0;
        let g = volume;
        for i in 0..frames_needed {
            let src_pos = i as f64 * step;
            let mut sf = src_pos as i64;
            if sf >= need_frames - 1 {
                sf = need_frames - 1;
            }
            let get_sample = |buf: &[f32], ibuf: &[i16], frame_idx: i64, ch: i32| -> f32 {
                if frame_idx < 0 || frame_idx >= need_frames {
                    return 0.0;
                }
                let s_idx = (frame_idx * self.pcm_src_ch as i64 + ch as i64) as usize;
                if self.pcm_src_float {
                    buf.get(s_idx).copied().unwrap_or(0.0)
                } else {
                    ibuf.get(s_idx).map(|v| *v as f32 / 32768.0).unwrap_or(0.0)
                }
            };
            let (l, r): (f32, f32) = if self.pcm_src_ch == 1 {
                let l0 = get_sample(&self.pcm_f32_buf, &self.pcm_i16_buf, sf, 0);
                let l1 = get_sample(&self.pcm_f32_buf, &self.pcm_i16_buf, sf + 1, 0);
                let interp = l0 + (src_pos - sf as f64) as f32 * (l1 - l0);
                (interp, interp)
            } else {
                let l0 = get_sample(&self.pcm_f32_buf, &self.pcm_i16_buf, sf, 0);
                let l1 = get_sample(&self.pcm_f32_buf, &self.pcm_i16_buf, sf + 1, 0);
                let r0 = get_sample(&self.pcm_f32_buf, &self.pcm_i16_buf, sf, 1);
                let r1 = get_sample(&self.pcm_f32_buf, &self.pcm_i16_buf, sf + 1, 1);
                let t = (src_pos - sf as f64) as f32;
                (l0 + t * (l1 - l0), r0 + t * (r1 - r0))
            };
            out[i * 2] = l * g;
            out[i * 2 + 1] = r * g;
        }
        true
    }
}

impl Drop for FfmpegDecoder {
    fn drop(&mut self) {
        unsafe {
            self.destroy_ffmpeg_contexts();
        }
    }
}

fn bytemuck_u8<T: Copy>(v: &mut [T]) -> &mut [u8] {
    unsafe { std::slice::from_raw_parts_mut(v.as_mut_ptr() as *mut u8, std::mem::size_of_val(v)) }
}
