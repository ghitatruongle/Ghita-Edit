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

/**
 * @brief v0.7.9: Renders the frame at an explicit position without mutating
 * playback state — batch/thumbnail rendering from Dart.
 */
GHITA_API bool ghita_engine_render_frame_at(GhitaEngineContext* ctx, uint8_t* out_buffer, int width, int height, int64_t position_ms);

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

// ========== v0.4.5 New API ==========

/** @brief Returns media metadata as JSON string. */
GHITA_API const char* ghita_engine_get_media_info(GhitaEngineContext* ctx);

/** @brief Returns list of available filters as JSON string. */
GHITA_API const char* ghita_engine_get_available_filters(GhitaEngineContext* ctx);

/** @brief Extended export with codec/bitrate/audio control. */
GHITA_API int ghita_engine_start_export_ex(GhitaEngineContext* ctx, const char* output_path,
                                           int width, int height, int fps,
                                           const char* codec, int64_t bitrate, bool include_audio);

/** @brief Returns export output file size in bytes. */
GHITA_API int64_t ghita_engine_get_export_file_size(GhitaEngineContext* ctx);

/** @brief Adds a keyframe to a clip for animation. */
GHITA_API int ghita_engine_add_clip_keyframe(GhitaEngineContext* ctx, int clip_id, int64_t time_ms, float value);

/** @brief Clears all keyframes from a clip. */
GHITA_API int ghita_engine_clear_clip_keyframes(GhitaEngineContext* ctx, int clip_id);

/** @brief Returns whether FFmpeg is available in this build. */
GHITA_API bool ghita_engine_has_ffmpeg(GhitaEngineContext* ctx);

// ========== v0.5.5 New API ==========

/** @brief Sets playback rate multiplier (0.25 to 4.0). */
GHITA_API void ghita_engine_set_playback_rate(GhitaEngineContext* ctx, float rate);

/** @brief Gets current playback rate multiplier. */
GHITA_API float ghita_engine_get_playback_rate(GhitaEngineContext* ctx);

/** @brief Sets keyframe interpolation type for a clip.
 *  @return 0 on success, -1 on error. */
GHITA_API int ghita_engine_set_clip_keyframe_interpolation(GhitaEngineContext* ctx, int clipId, int interpolationType);

/** @brief Gets keyframe interpolation type for a clip. */
GHITA_API int ghita_engine_get_clip_keyframe_interpolation(GhitaEngineContext* ctx, int clipId);

/** @brief Renders a text overlay on the frame buffer (basic rasterizer stub). */
GHITA_API bool ghita_engine_render_text_overlay(GhitaEngineContext* ctx, uint8_t* outBuffer, int width, int height,
                                                  const char* text, int fontSize, float r, float g, float b, float a);

// ========== v0.8.0 New API ==========

/**
 * @brief Inserts or updates a timeline clip (full timeline sync).
 * @param clip_id Native clip id assigned by the caller (must be > 0).
 * @param kind 0=video, 1=audio, 2=image, 3=text, 4=sticker.
 * @return 1 on success, 0 on invalid parameters.
 */
GHITA_API int ghita_engine_upsert_clip(GhitaEngineContext* ctx, int clip_id, const char* file_path,
                                       int64_t start_ms, int64_t duration_ms, int64_t source_in_ms,
                                       int track_index, int kind, float volume, float opacity, float speed);

/** @brief Removes all clips and resets the timeline (new project/load). */
GHITA_API void ghita_engine_clear_clips(GhitaEngineContext* ctx);

/** @brief Sets mute/visible/volume for a track (muted/visible are 0/1). */
GHITA_API int ghita_engine_set_track_state(GhitaEngineContext* ctx, int track_index, int muted, int visible, float volume);

/** @brief Sets per-clip color correction (all values -1.0..1.0). */
GHITA_API int ghita_engine_set_clip_color_correction(GhitaEngineContext* ctx, int clip_id,
                                                     float exposure, float contrast, float saturation,
                                                     float temperature, float tint, float vibrance,
                                                     float highlights, float shadows);

/** @brief Sets text/sticker payload for a clip (text rendered via GDI). */
GHITA_API int ghita_engine_set_clip_text(GhitaEngineContext* ctx, int clip_id,
                                         const char* text, float font_size, uint32_t color_argb);

/** @brief Returns 1 if the clip exists in the native timeline. */
GHITA_API int ghita_engine_has_clip(GhitaEngineContext* ctx, int clip_id);

/** @brief Enables/disables audio preview during playback (1/0). */
GHITA_API void ghita_engine_set_audio_preview_enabled(GhitaEngineContext* ctx, int enabled);

/** @brief v1.0.3: Enables/disables noise suppression (DC blocker) in the
 *  preview audio mix ("làm rõ âm thanh"). 1/0. */
GHITA_API void ghita_engine_set_noise_suppress(GhitaEngineContext* ctx, int enabled);

// ========== v1.0.0 New & Extended API ==========

/** @brief Applies global color correction parameters. */
GHITA_API void ghita_engine_apply_color_correction(GhitaEngineContext* ctx, int clip_id,
                                                   float exposure, float contrast, float highlights, float shadows,
                                                   float temperature, float tint, float vibrance, float saturation);

/** @brief Sets Bezier control points for a clip keyframe. */
GHITA_API int ghita_engine_set_keyframe_bezier(GhitaEngineContext* ctx, int clip_id, int keyframe_index,
                                                float cp1x, float cp1y, float cp2x, float cp2y);

/** @brief Renders a picture-in-picture overlay clip. */
GHITA_API bool ghita_engine_render_pip(GhitaEngineContext* ctx, int overlay_clip_id,
                                       float x, float y, float width, float height, float rotation);

/** @brief Generates and extracts a thumbnail frame buffer for a clip. */
GHITA_API uint8_t* ghita_engine_get_thumbnail(GhitaEngineContext* ctx, int clip_id, int time_ms, int width, int height);

/** @brief Configures filter preset and intensity for a clip. */
GHITA_API void ghita_engine_set_filter_preset(GhitaEngineContext* ctx, int clip_id, int filter_type, float intensity);

/** @brief Extracts audio waveform peak amplitudes. */
GHITA_API bool ghita_engine_get_audio_waveform_peaks(GhitaEngineContext* ctx, float* out_samples, int sample_count);

/** @brief Mixes decoded audio from timeline clips over [start_ms, end_ms)
 *  into out_samples (interleaved stereo float @ 44100 Hz, clipped [-1,1]).
 *  Returns true when at least one clip contributed real decoded audio.
 *  This is the same mixer the audio preview loop plays through — unlike
 *  get_audio_waveform it reads the TIMELINE clip decoders, not the legacy
 *  single loadMedia() decoder, so it cannot report a synthetic fallback. */
GHITA_API bool ghita_engine_mix_audio_window(GhitaEngineContext* ctx, int64_t start_ms, int64_t end_ms, float* out_samples, int sample_count);

// ========== v1.1.0 New API (PLAN 3: Accuracy) ==========

/** @brief Keyframe-aware insertion. 0 on success, -1 on error.
 *  property: 0=opacity, 1=position offset (fraction of frame), 2=scale,
 *  3=rotation (stored), 4=filter intensity. interpolation: 0=linear, 1=step,
 *  2=bezier (control points normalized to the keyframe segment). */
GHITA_API int ghita_engine_add_keyframe_ex(GhitaEngineContext* ctx, int clip_id, int64_t time_ms,
                                           float value, int property, int interpolation,
                                           float cp1x, float cp1y, float cp2x, float cp2y);

/** @brief Number of keyframes on a clip (-1 when the clip does not exist). */
GHITA_API int ghita_engine_get_clip_keyframe_count(GhitaEngineContext* ctx, int clip_id);

/** @brief Sets picture-in-picture geometry (fractions of the frame). */
GHITA_API int ghita_engine_set_clip_pip(GhitaEngineContext* ctx, int clip_id,
                                        float x, float y, float w, float h, float rotation);

/** @brief Appends a speed-ramp point (t normalized 0..1). */
GHITA_API int ghita_engine_add_speed_ramp_point(GhitaEngineContext* ctx, int clip_id,
                                                float t, float speed);

/** @brief Clears the speed-ramp curve of a clip. */
GHITA_API int ghita_engine_clear_speed_curve(GhitaEngineContext* ctx, int clip_id);

/** @brief v1.1.0 (PLAN 3.5): Renders at an explicit position, optionally
 *  WITHOUT the effects (per-clip filter/cc + global filter) — the raw side
 *  of split view. apply_fx: 1 = normal, 0 = raw. */
GHITA_API bool ghita_engine_render_frame_at_ex(GhitaEngineContext* ctx, uint8_t* out_buffer,
                                               int width, int height, int64_t position_ms,
                                               int apply_fx);

/** @brief v1.1.0 (PLAN 3.7): Timeline waveform peaks (real mix pipeline).
 *  Returns true when any window produced audio. */
GHITA_API bool ghita_engine_get_timeline_waveform(GhitaEngineContext* ctx, float* out_samples,
                                                  int sample_count, int track_index);

#ifdef __cplusplus
}
#endif

#endif // GHITA_C_API_H
