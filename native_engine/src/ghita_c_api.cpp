#include "ghita_c_api.h"
#include "ghita_engine.h"
#include <new>
#include <cstring>

struct GhitaEngineContext {
    GhitaEngine engine;
};

// Static string is safe to return because it lives for the process lifetime
static const char VERSION_STRING[] = "Ghita Core Engine v0.7.8 (C++/Flutter)";

// Thread-local buffer for JSON return values (FFI-safe)
static thread_local std::string t_jsonBuffer;

extern "C" {

GHITA_API GhitaEngineContext* ghita_engine_create(void) {
    return new (std::nothrow) GhitaEngineContext();
}

GHITA_API void ghita_engine_destroy(GhitaEngineContext* ctx) {
    if (ctx) {
        delete ctx;
    }
}

GHITA_API int ghita_engine_init(GhitaEngineContext* ctx) {
    if (!ctx) return -1;
    return ctx->engine.initialize() ? 0 : -1;
}

GHITA_API int ghita_engine_load_media(GhitaEngineContext* ctx, const char* file_path) {
    if (!ctx || !file_path) return -1;
    return ctx->engine.loadMedia(file_path) ? 0 : -1;
}

GHITA_API int64_t ghita_engine_get_duration_ms(GhitaEngineContext* ctx) {
    if (!ctx) return 0;
    return ctx->engine.getDurationMs();
}

GHITA_API int ghita_engine_get_media_width(GhitaEngineContext* ctx) {
    if (!ctx) return 0;
    return ctx->engine.getWidth();
}

GHITA_API int ghita_engine_get_media_height(GhitaEngineContext* ctx) {
    if (!ctx) return 0;
    return ctx->engine.getHeight();
}

GHITA_API void ghita_engine_play(GhitaEngineContext* ctx) {
    if (ctx) ctx->engine.play();
}

GHITA_API void ghita_engine_pause(GhitaEngineContext* ctx) {
    if (ctx) ctx->engine.pause();
}

GHITA_API bool ghita_engine_is_playing(GhitaEngineContext* ctx) {
    if (!ctx) return false;
    return ctx->engine.isPlaying();
}

GHITA_API void ghita_engine_seek(GhitaEngineContext* ctx, int64_t position_ms) {
    if (ctx) ctx->engine.seek(position_ms);
}

GHITA_API int64_t ghita_engine_get_position_ms(GhitaEngineContext* ctx) {
    if (!ctx) return 0;
    return ctx->engine.getPositionMs();
}

GHITA_API void ghita_engine_set_volume(GhitaEngineContext* ctx, float volume) {
    if (ctx) ctx->engine.setVolume(volume);
}

GHITA_API void ghita_engine_apply_filter(GhitaEngineContext* ctx, int filter_type, float intensity) {
    if (ctx) ctx->engine.applyFilter(filter_type, intensity);
}

GHITA_API bool ghita_engine_render_frame_rgba(GhitaEngineContext* ctx, uint8_t* out_buffer, int width, int height) {
    if (!ctx || !out_buffer) return false;
    return ctx->engine.renderFrameRGBA(out_buffer, width, height);
}

// ========== Timeline / Clip Operations (v0.2.0) ==========

GHITA_API int ghita_engine_add_clip(GhitaEngineContext* ctx, const char* file_path, int64_t start_ms, int64_t duration_ms, int track_index) {
    if (!ctx || !file_path) return -1;
    return ctx->engine.addClip(file_path, start_ms, duration_ms, track_index);
}

GHITA_API int ghita_engine_remove_clip(GhitaEngineContext* ctx, int clip_id) {
    if (!ctx) return -1;
    return ctx->engine.removeClip(clip_id) ? 0 : -1;
}

GHITA_API int ghita_engine_get_clip_count(GhitaEngineContext* ctx) {
    if (!ctx) return 0;
    return ctx->engine.getClipCount();
}

GHITA_API int ghita_engine_set_clip_position(GhitaEngineContext* ctx, int clip_id, int64_t start_ms) {
    if (!ctx) return -1;
    return ctx->engine.setClipPosition(clip_id, start_ms) ? 0 : -1;
}

GHITA_API int ghita_engine_set_clip_filter(GhitaEngineContext* ctx, int clip_id, int filter_type, float intensity) {
    if (!ctx) return -1;
    return ctx->engine.setClipFilter(clip_id, filter_type, intensity) ? 0 : -1;
}

// ========== Export Pipeline (v0.2.0) ==========

GHITA_API int ghita_engine_start_export(GhitaEngineContext* ctx, const char* output_path, int width, int height, int fps) {
    if (!ctx || !output_path) return -1;
    return ctx->engine.startExport(output_path, width, height, fps) ? 0 : -1;
}

GHITA_API float ghita_engine_get_export_progress(GhitaEngineContext* ctx) {
    if (!ctx) return 0.0f;
    return ctx->engine.getExportProgress();
}

GHITA_API bool ghita_engine_is_exporting(GhitaEngineContext* ctx) {
    if (!ctx) return false;
    return ctx->engine.isExporting();
}

GHITA_API void ghita_engine_cancel_export(GhitaEngineContext* ctx) {
    if (ctx) ctx->engine.cancelExport();
}

// Returns a static pointer that lives for the process lifetime — safe for FFI
GHITA_API const char* ghita_engine_get_version(void) {
    return VERSION_STRING;
}

GHITA_API bool ghita_engine_get_audio_waveform(GhitaEngineContext* ctx, float* out_samples, int sample_count) {
    if (!ctx || !out_samples || sample_count <= 0) return false;
    return ctx->engine.getAudioWaveform(out_samples, sample_count);
}

GHITA_API void ghita_engine_set_snapping_fps(GhitaEngineContext* ctx, int fps) {
    if (ctx) ctx->engine.setFrameSnappingFps(fps);
}

GHITA_API int ghita_engine_get_snapping_fps(GhitaEngineContext* ctx) {
    if (!ctx) return 30;
    return ctx->engine.getFrameSnappingFps();
}

GHITA_API bool ghita_engine_set_clip_transition(GhitaEngineContext* ctx, int clip_id, int transition_type, int duration_ms) {
    if (!ctx) return false;
    return ctx->engine.setClipTransition(clip_id, static_cast<TransitionType>(transition_type), duration_ms);
}

GHITA_API uint8_t* ghita_engine_get_direct_buffer(GhitaEngineContext* ctx, int* out_width, int* out_height) {
    if (!ctx) return nullptr;
    return ctx->engine.getFrameDirectBufferPointer(out_width, out_height);
}

// ========== v0.4.5 New API ==========

GHITA_API const char* ghita_engine_get_media_info(GhitaEngineContext* ctx) {
    if (!ctx) return "{}";
    t_jsonBuffer = ctx->engine.getMediaInfoJson();
    return t_jsonBuffer.c_str();
}

GHITA_API const char* ghita_engine_get_available_filters(GhitaEngineContext* ctx) {
    if (!ctx) return "[]";
    t_jsonBuffer = ctx->engine.getAvailableFiltersJson();
    return t_jsonBuffer.c_str();
}

GHITA_API int ghita_engine_start_export_ex(GhitaEngineContext* ctx, const char* output_path,
                                            int width, int height, int fps,
                                            const char* codec, int64_t bitrate, bool include_audio) {
    if (!ctx || !output_path || !codec) return -1;
    return ctx->engine.startExportEx(output_path, width, height, fps,
                                      codec, bitrate, include_audio) ? 0 : -1;
}

GHITA_API int64_t ghita_engine_get_export_file_size(GhitaEngineContext* ctx) {
    if (!ctx) return 0;
    return ctx->engine.getExportFileSize();
}

GHITA_API int ghita_engine_add_clip_keyframe(GhitaEngineContext* ctx, int clip_id, int64_t time_ms, float value) {
    if (!ctx) return -1;
    return ctx->engine.addClipKeyframe(clip_id, time_ms, value) ? 0 : -1;
}

GHITA_API int ghita_engine_clear_clip_keyframes(GhitaEngineContext* ctx, int clip_id) {
    if (!ctx) return -1;
    return ctx->engine.clearClipKeyframes(clip_id) ? 0 : -1;
}

GHITA_API bool ghita_engine_has_ffmpeg(GhitaEngineContext* ctx) {
    if (!ctx) return false;
    // Check if the decoder is using real FFmpeg
    // Return true if GHITA_HAS_FFMPEG was compiled in
#ifdef GHITA_HAS_FFMPEG
    return true;
#else
    return false;
#endif
}

// ========== v0.5.5 New API ==========

GHITA_API void ghita_engine_set_playback_rate(GhitaEngineContext* ctx, float rate) {
    if (ctx) ctx->engine.setPlaybackRate(rate);
}

GHITA_API float ghita_engine_get_playback_rate(GhitaEngineContext* ctx) {
    if (!ctx) return 1.0f;
    return ctx->engine.getPlaybackRate();
}

GHITA_API int ghita_engine_set_clip_keyframe_interpolation(GhitaEngineContext* ctx, int clip_id, int interpolation_type) {
    if (!ctx) return -1;
    return ctx->engine.setClipKeyframeInterpolation(clip_id, static_cast<KeyframeInterpolation>(interpolation_type)) ? 0 : -1;
}

GHITA_API int ghita_engine_get_clip_keyframe_interpolation(GhitaEngineContext* ctx, int clip_id) {
    if (!ctx) return 0;
    return static_cast<int>(ctx->engine.getClipKeyframeInterpolation(clip_id));
}

GHITA_API bool ghita_engine_render_text_overlay(GhitaEngineContext* ctx, uint8_t* out_buffer, int width, int height,
                                                  const char* text, int font_size, float r, float g, float b, float a) {
    if (!ctx || !out_buffer || !text || width <= 0 || height <= 0) return false;
    // v0.5.5: Basic text rasterizer stub — renders text as a solid color rectangle
    // with the text string encoded in the alpha channel of the top-left corner pixels.
    // A proper text rasterizer (FreeType/Harfbuzz) would be integrated in a future version.
    const int textLen = static_cast<int>(std::strlen(text));
    const int boxW = std::min(width, std::max(40, textLen * font_size / 2));
    const int boxH = std::min(height, font_size * 2);
    const int boxX = 20;
    // v0.7.8: Guard against underflow — a large font_size made boxY negative
    // and the loops wrote before the buffer (index < 0).
    const int boxY = std::max(0, height - boxH - 20);

    for (int y = boxY; y < boxY + boxH && y < height; ++y) {
        for (int x = boxX; x < boxX + boxW && x < width; ++x) {
            int idx = (y * width + x) * 4;
            out_buffer[idx]     = static_cast<uint8_t>(r * 255);
            out_buffer[idx + 1] = static_cast<uint8_t>(g * 255);
            out_buffer[idx + 2] = static_cast<uint8_t>(b * 255);
            out_buffer[idx + 3] = static_cast<uint8_t>(a * 255);
        }
    }

    // Encode text string in pixel data (for debugging / placeholder)
    for (int i = 0; i < textLen && (boxX + i) < boxX + boxW && boxY < height; ++i) {
        int idx = (boxY * width + boxX + i) * 4;
        out_buffer[idx]     = static_cast<uint8_t>(text[i] % 256);
        out_buffer[idx + 1] = static_cast<uint8_t>((text[i] >> 8) % 256);
        out_buffer[idx + 2] = static_cast<uint8_t>(font_size);
        out_buffer[idx + 3] = 200;
    }

    return true;
}

}
