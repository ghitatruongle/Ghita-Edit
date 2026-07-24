#ifndef GHITA_C_API_H
#define GHITA_C_API_H

#include <stdint.h>
#include <stdbool.h>

#if defined(_WIN32)
    #if defined(GHITA_ENGINE_EXPORTS)
        #define GHITA_API __declspec(dllexport)
    #else
        #define GHITA_API __declspec(dllimport)
    #endif
#else
    #define GHITA_API __attribute__((visibility("default")))
#endif

#ifdef __cplusplus
extern "C" {
#endif

typedef struct GhitaEngineContext GhitaEngineContext;

// Life cycle
GHITA_API GhitaEngineContext* ghita_engine_create(void);
GHITA_API void ghita_engine_destroy(GhitaEngineContext* ctx);
GHITA_API int ghita_engine_init(GhitaEngineContext* ctx);

// Media Management
GHITA_API int ghita_engine_load_media(GhitaEngineContext* ctx, const char* file_path);
GHITA_API int64_t ghita_engine_get_duration_ms(GhitaEngineContext* ctx);
GHITA_API int ghita_engine_get_media_width(GhitaEngineContext* ctx);
GHITA_API int ghita_engine_get_media_height(GhitaEngineContext* ctx);

// Playback Control
GHITA_API void ghita_engine_play(GhitaEngineContext* ctx);
GHITA_API void ghita_engine_pause(GhitaEngineContext* ctx);
GHITA_API bool ghita_engine_is_playing(GhitaEngineContext* ctx);
GHITA_API void ghita_engine_seek(GhitaEngineContext* ctx, int64_t position_ms);
GHITA_API int64_t ghita_engine_get_position_ms(GhitaEngineContext* ctx);

// Audio & FX Control
GHITA_API void ghita_engine_set_volume(GhitaEngineContext* ctx, float volume);
GHITA_API void ghita_engine_apply_filter(GhitaEngineContext* ctx, int filter_type, float intensity);

// Frame Rendering (Populates RGBA buffer for preview)
GHITA_API bool ghita_engine_render_frame_rgba(GhitaEngineContext* ctx, uint8_t* out_buffer, int width, int height);

// Version info
GHITA_API const char* ghita_engine_get_version(void);

#ifdef __cplusplus
}
#endif

#endif // GHITA_C_API_H
