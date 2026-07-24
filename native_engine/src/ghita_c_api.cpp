#include "ghita_c_api.h"
#include "ghita_engine.h"
#include <new>

struct GhitaEngineContext {
    GhitaEngine engine;
};

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
    return ctx ? ctx->engine.getDurationMs() : 0;
}

GHITA_API int ghita_engine_get_media_width(GhitaEngineContext* ctx) {
    return ctx ? ctx->engine.getWidth() : 0;
}

GHITA_API int ghita_engine_get_media_height(GhitaEngineContext* ctx) {
    return ctx ? ctx->engine.getHeight() : 0;
}

GHITA_API void ghita_engine_play(GhitaEngineContext* ctx) {
    if (ctx) ctx->engine.play();
}

GHITA_API void ghita_engine_pause(GhitaEngineContext* ctx) {
    if (ctx) ctx->engine.pause();
}

GHITA_API bool ghita_engine_is_playing(GhitaEngineContext* ctx) {
    return ctx ? ctx->engine.isPlaying() : false;
}

GHITA_API void ghita_engine_seek(GhitaEngineContext* ctx, int64_t position_ms) {
    if (ctx) ctx->engine.seek(position_ms);
}

GHITA_API int64_t ghita_engine_get_position_ms(GhitaEngineContext* ctx) {
    return ctx ? ctx->engine.getPositionMs() : 0;
}

GHITA_API void ghita_engine_set_volume(GhitaEngineContext* ctx, float volume) {
    if (ctx) ctx->engine.setVolume(volume);
}

GHITA_API void ghita_engine_apply_filter(GhitaEngineContext* ctx, int filter_type, float intensity) {
    if (ctx) ctx->engine.applyFilter(filter_type, intensity);
}

GHITA_API bool ghita_engine_render_frame_rgba(GhitaEngineContext* ctx, uint8_t* out_buffer, int width, int height) {
    if (!ctx) return false;
    return ctx->engine.renderFrameRGBA(out_buffer, width, height);
}

GHITA_API const char* ghita_engine_get_version(void) {
    return "Ghita Core Engine v0.1.0-alpha (C++/Flutter)";
}

}
