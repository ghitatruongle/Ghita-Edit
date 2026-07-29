#include "ghita_c_api.h"
#include "ghita_engine.h"
#include <new>

struct GhitaEngineContext {
    GhitaEngine engine;
};

// Static string is safe to return because it lives for the process lifetime
static const char VERSION_STRING[] = "Ghita Core Engine v0.4.0 (C++/Flutter)";

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

}

