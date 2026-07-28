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

/** Opaque handle to the C++ Ghita Engine context. */
typedef struct GhitaEngineContext GhitaEngineContext;

/** @brief Allocates and creates a new engine instance. */
GHITA_API GhitaEngineContext* ghita_engine_create(void);

/** @brief Destroys and frees an engine instance safely. */
GHITA_API void ghita_engine_destroy(GhitaEngineContext* ctx);

/** @brief Initializes state for the given engine context. */
GHITA_API int ghita_engine_init(GhitaEngineContext* ctx);

/** @brief Loads a media file into the engine context. */
GHITA_API int ghita_engine_load_media(GhitaEngineContext* ctx, const char* file_path);

/** @brief Returns total media duration in milliseconds. */
GHITA_API int64_t ghita_engine_get_duration_ms(GhitaEngineContext* ctx);

/** @brief Returns native media width. */
GHITA_API int ghita_engine_get_media_width(GhitaEngineContext* ctx);

/** @brief Returns native media height. */
GHITA_API int ghita_engine_get_media_height(GhitaEngineContext* ctx);

/** @brief Starts timeline playback. */
GHITA_API void ghita_engine_play(GhitaEngineContext* ctx);

/** @brief Pauses timeline playback. */
GHITA_API void ghita_engine_pause(GhitaEngineContext* ctx);

/** @brief Returns true if timeline playback is active. */
GHITA_API bool ghita_engine_is_playing(GhitaEngineContext* ctx);

/** @brief Seeks to target position in milliseconds. */
GHITA_API void ghita_engine_seek(GhitaEngineContext* ctx, int64_t position_ms);

/** @brief Returns current playback position in milliseconds. */
GHITA_API int64_t ghita_engine_get_position_ms(GhitaEngineContext* ctx);

/** @brief Sets master volume (0.0 to 2.0). */
GHITA_API void ghita_engine_set_volume(GhitaEngineContext* ctx, float volume);

/** @brief Applies active video filter type and intensity. */
GHITA_API void ghita_engine_apply_filter(GhitaEngineContext* ctx, int filter_type, float intensity);

/** @brief Renders an RGBA frame buffer for preview. */
GHITA_API bool ghita_engine_render_frame_rgba(GhitaEngineContext* ctx, uint8_t* out_buffer, int width, int height);

/** @brief Adds a clip to the native timeline. */
GHITA_API int ghita_engine_add_clip(GhitaEngineContext* ctx, const char* file_path, int64_t start_ms, int64_t duration_ms, int track_index);

/** @brief Removes a clip by ID. */
GHITA_API int ghita_engine_remove_clip(GhitaEngineContext* ctx, int clip_id);

/** @brief Gets count of clips on timeline. */
GHITA_API int ghita_engine_get_clip_count(GhitaEngineContext* ctx);

/** @brief Sets clip start position on timeline in milliseconds. */
GHITA_API int ghita_engine_set_clip_position(GhitaEngineContext* ctx, int clip_id, int64_t start_ms);

/** @brief Sets clip filter parameters. */
GHITA_API int ghita_engine_set_clip_filter(GhitaEngineContext* ctx, int clip_id, int filter_type, float intensity);

/** @brief Starts asynchronous export thread worker. */
GHITA_API int ghita_engine_start_export(GhitaEngineContext* ctx, const char* output_path, int width, int height, int fps);

/** @brief Gets current export progress (0.0 to 1.0). */
GHITA_API float ghita_engine_get_export_progress(GhitaEngineContext* ctx);

/** @brief Returns true if export worker is active. */
GHITA_API bool ghita_engine_is_exporting(GhitaEngineContext* ctx);

/** @brief Cancels ongoing export worker thread safely. */
GHITA_API void ghita_engine_cancel_export(GhitaEngineContext* ctx);

/** @brief Gets library version string. */
GHITA_API const char* ghita_engine_get_version(void);

/** @brief Extracts audio waveform amplitude samples. */
GHITA_API bool ghita_engine_get_audio_waveform(GhitaEngineContext* ctx, float* out_samples, int sample_count);

/** @brief Configures frame snapping FPS. */
GHITA_API void ghita_engine_set_snapping_fps(GhitaEngineContext* ctx, int fps);

/** @brief Gets frame snapping FPS. */
GHITA_API int ghita_engine_get_snapping_fps(GhitaEngineContext* ctx);

/** @brief Configures transition effect for a timeline clip. */
GHITA_API bool ghita_engine_set_clip_transition(GhitaEngineContext* ctx, int clip_id, int transition_type, int duration_ms);

/** @brief Returns pointer to direct frame buffer for zero-copy GPU texture sharing. */
GHITA_API uint8_t* ghita_engine_get_direct_buffer(GhitaEngineContext* ctx, int* out_width, int* out_height);

#ifdef __cplusplus
}
#endif

#endif // GHITA_C_API_H
