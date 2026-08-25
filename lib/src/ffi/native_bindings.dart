import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart' show debugPrint;

// Opaque struct pointer
base class GhitaEngineContext extends Opaque {}

// ========== C Function Signatures & Dart Types ==========

// Lifecycle
typedef CGhitaEngineCreate = Pointer<GhitaEngineContext> Function();
typedef DartGhitaEngineCreate = Pointer<GhitaEngineContext> Function();

typedef CGhitaEngineDestroy = Void Function(Pointer<GhitaEngineContext> ctx);
typedef DartGhitaEngineDestroy = void Function(Pointer<GhitaEngineContext> ctx);

typedef CGhitaEngineInit = Int32 Function(Pointer<GhitaEngineContext> ctx);
typedef DartGhitaEngineInit = int Function(Pointer<GhitaEngineContext> ctx);

// Media
typedef CGhitaEngineLoadMedia = Int32 Function(Pointer<GhitaEngineContext> ctx, Pointer<Utf8> filePath);
typedef DartGhitaEngineLoadMedia = int Function(Pointer<GhitaEngineContext> ctx, Pointer<Utf8> filePath);

typedef CGhitaEngineGetDurationMs = Int64 Function(Pointer<GhitaEngineContext> ctx);
typedef DartGhitaEngineGetDurationMs = int Function(Pointer<GhitaEngineContext> ctx);

typedef CGhitaEngineGetMediaWidth = Int32 Function(Pointer<GhitaEngineContext> ctx);
typedef DartGhitaEngineGetMediaWidth = int Function(Pointer<GhitaEngineContext> ctx);

typedef CGhitaEngineGetMediaHeight = Int32 Function(Pointer<GhitaEngineContext> ctx);
typedef DartGhitaEngineGetMediaHeight = int Function(Pointer<GhitaEngineContext> ctx);

// Playback
typedef CGhitaEnginePlay = Void Function(Pointer<GhitaEngineContext> ctx);
typedef DartGhitaEnginePlay = void Function(Pointer<GhitaEngineContext> ctx);

typedef CGhitaEnginePause = Void Function(Pointer<GhitaEngineContext> ctx);
typedef DartGhitaEnginePause = void Function(Pointer<GhitaEngineContext> ctx);

typedef CGhitaEngineIsPlaying = Bool Function(Pointer<GhitaEngineContext> ctx);
typedef DartGhitaEngineIsPlaying = bool Function(Pointer<GhitaEngineContext> ctx);

typedef CGhitaEngineSeek = Void Function(Pointer<GhitaEngineContext> ctx, Int64 positionMs);
typedef DartGhitaEngineSeek = void Function(Pointer<GhitaEngineContext> ctx, int positionMs);

typedef CGhitaEngineGetPositionMs = Int64 Function(Pointer<GhitaEngineContext> ctx);
typedef DartGhitaEngineGetPositionMs = int Function(Pointer<GhitaEngineContext> ctx);

// Audio & FX
typedef CGhitaEngineSetVolume = Void Function(Pointer<GhitaEngineContext> ctx, Float volume);
typedef DartGhitaEngineSetVolume = void Function(Pointer<GhitaEngineContext> ctx, double volume);

typedef CGhitaEngineApplyFilter = Void Function(Pointer<GhitaEngineContext> ctx, Int32 filterType, Float intensity);
typedef DartGhitaEngineApplyFilter = void Function(Pointer<GhitaEngineContext> ctx, int filterType, double intensity);

// Rendering
typedef CGhitaEngineRenderFrameRgba = Bool Function(Pointer<GhitaEngineContext> ctx, Pointer<Uint8> outBuffer, Int32 width, Int32 height);
typedef DartGhitaEngineRenderFrameRgba = bool Function(Pointer<GhitaEngineContext> ctx, Pointer<Uint8> outBuffer, int width, int height);

// v0.7.9: Render frame at an explicit position (batch/thumbnail foundation)
typedef CGhitaEngineRenderFrameAt = Bool Function(Pointer<GhitaEngineContext> ctx, Pointer<Uint8> outBuffer, Int32 width, Int32 height, Int64 positionMs);
typedef DartGhitaEngineRenderFrameAt = bool Function(Pointer<GhitaEngineContext> ctx, Pointer<Uint8> outBuffer, int width, int height, int positionMs);

// Version
typedef CGhitaEngineGetVersion = Pointer<Utf8> Function();
typedef DartGhitaEngineGetVersion = Pointer<Utf8> Function();

// ========== Timeline / Clip (v0.2.0) ==========
typedef CGhitaEngineAddClip = Int32 Function(Pointer<GhitaEngineContext> ctx, Pointer<Utf8> filePath, Int64 startMs, Int64 durationMs, Int32 trackIndex);
typedef DartGhitaEngineAddClip = int Function(Pointer<GhitaEngineContext> ctx, Pointer<Utf8> filePath, int startMs, int durationMs, int trackIndex);

typedef CGhitaEngineRemoveClip = Int32 Function(Pointer<GhitaEngineContext> ctx, Int32 clipId);
typedef DartGhitaEngineRemoveClip = int Function(Pointer<GhitaEngineContext> ctx, int clipId);

typedef CGhitaEngineGetClipCount = Int32 Function(Pointer<GhitaEngineContext> ctx);
typedef DartGhitaEngineGetClipCount = int Function(Pointer<GhitaEngineContext> ctx);

typedef CGhitaEngineSetClipPosition = Int32 Function(Pointer<GhitaEngineContext> ctx, Int32 clipId, Int64 startMs);
typedef DartGhitaEngineSetClipPosition = int Function(Pointer<GhitaEngineContext> ctx, int clipId, int startMs);

typedef CGhitaEngineSetClipFilter = Int32 Function(Pointer<GhitaEngineContext> ctx, Int32 clipId, Int32 filterType, Float intensity);
typedef DartGhitaEngineSetClipFilter = int Function(Pointer<GhitaEngineContext> ctx, int clipId, int filterType, double intensity);

typedef CGhitaEngineSetClipTransition = Bool Function(Pointer<GhitaEngineContext> ctx, Int32 clipId, Int32 transitionType, Int32 durationMs);
typedef DartGhitaEngineSetClipTransition = bool Function(Pointer<GhitaEngineContext> ctx, int clipId, int transitionType, int durationMs);

// ========== Export Pipeline (v0.2.0) ==========
typedef CGhitaEngineStartExport = Int32 Function(Pointer<GhitaEngineContext> ctx, Pointer<Utf8> outputPath, Int32 width, Int32 height, Int32 fps);
typedef DartGhitaEngineStartExport = int Function(Pointer<GhitaEngineContext> ctx, Pointer<Utf8> outputPath, int width, int height, int fps);

typedef CGhitaEngineGetExportProgress = Float Function(Pointer<GhitaEngineContext> ctx);
typedef DartGhitaEngineGetExportProgress = double Function(Pointer<GhitaEngineContext> ctx);

typedef CGhitaEngineIsExporting = Bool Function(Pointer<GhitaEngineContext> ctx);
typedef DartGhitaEngineIsExporting = bool Function(Pointer<GhitaEngineContext> ctx);

typedef CGhitaEngineCancelExport = Void Function(Pointer<GhitaEngineContext> ctx);
typedef DartGhitaEngineCancelExport = void Function(Pointer<GhitaEngineContext> ctx);

// Audio Waveform (v0.3.0)
typedef CGhitaEngineGetAudioWaveform = Bool Function(Pointer<GhitaEngineContext> ctx, Pointer<Float> outSamples, Int32 sampleCount);
typedef DartGhitaEngineGetAudioWaveform = bool Function(Pointer<GhitaEngineContext> ctx, Pointer<Float> outSamples, int sampleCount);

typedef CGhitaEngineSetNoiseSuppress = Void Function(Pointer<GhitaEngineContext> ctx, Int32 enabled);
typedef DartGhitaEngineSetNoiseSuppress = void Function(Pointer<GhitaEngineContext> ctx, int enabled);

// ========== v1.5.0 T3 (Video Features) ==========

typedef CGhitaEngineSetClipBlendMode = Int32 Function(Pointer<GhitaEngineContext> ctx, Int32 clipId, Int32 blendMode);
typedef DartGhitaEngineSetClipBlendMode = int Function(Pointer<GhitaEngineContext> ctx, int clipId, int blendMode);

typedef CGhitaEngineSetClipMask = Int32 Function(Pointer<GhitaEngineContext> ctx, Int32 clipId, Int32 maskType, Float feather, Float stroke);
typedef DartGhitaEngineSetClipMask = int Function(Pointer<GhitaEngineContext> ctx, int clipId, int maskType, double feather, double stroke);

typedef CGhitaEngineSetClipMaintainPitch = Int32 Function(Pointer<GhitaEngineContext> ctx, Int32 clipId, Int32 enabled);
typedef DartGhitaEngineSetClipMaintainPitch = int Function(Pointer<GhitaEngineContext> ctx, int clipId, int enabled);

typedef CGhitaEngineSetClipFont = Int32 Function(Pointer<GhitaEngineContext> ctx, Int32 clipId, Pointer<Utf8> family);
typedef DartGhitaEngineSetClipFont = int Function(Pointer<GhitaEngineContext> ctx, int clipId, Pointer<Utf8> family);

typedef CGhitaEngineSetCanvasBackground = Void Function(Pointer<GhitaEngineContext> ctx, Int32 kind, Uint32 color, Uint32 color2);
typedef DartGhitaEngineSetCanvasBackground = void Function(Pointer<GhitaEngineContext> ctx, int kind, int color, int color2);

typedef CGhitaEngineAddBookmark = Int32 Function(Pointer<GhitaEngineContext> ctx, Int64 timeMs, Uint32 color, Pointer<Utf8> note);
typedef DartGhitaEngineAddBookmark = int Function(Pointer<GhitaEngineContext> ctx, int timeMs, int color, Pointer<Utf8> note);

typedef CGhitaEngineRemoveBookmark = Int32 Function(Pointer<GhitaEngineContext> ctx, Int32 id);
typedef DartGhitaEngineRemoveBookmark = int Function(Pointer<GhitaEngineContext> ctx, int id);

typedef CGhitaEngineGetBookmarkCount = Int32 Function(Pointer<GhitaEngineContext> ctx);
typedef DartGhitaEngineGetBookmarkCount = int Function(Pointer<GhitaEngineContext> ctx);

typedef CGhitaEngineGetBookmarksJson = Pointer<Utf8> Function(Pointer<GhitaEngineContext> ctx);
typedef DartGhitaEngineGetBookmarksJson = Pointer<Utf8> Function(Pointer<GhitaEngineContext> ctx);

typedef CGhitaEngineCopyKeyframes = Int32 Function(Pointer<GhitaEngineContext> ctx, Int32 srcClip, Int32 dstClip);
typedef DartGhitaEngineCopyKeyframes = int Function(Pointer<GhitaEngineContext> ctx, int srcClip, int dstClip);

typedef CGhitaEngineImportTranscript = Int32 Function(Pointer<GhitaEngineContext> ctx, Pointer<Utf8> path, Int32 trackIndex);
typedef DartGhitaEngineImportTranscript = int Function(Pointer<GhitaEngineContext> ctx, Pointer<Utf8> path, int trackIndex);

// ========== v1.5.0 T4: Audio Features — defensive lookups (older DLLs degrade). ==========

typedef CGhitaEngineAddAudioEffect = Int32 Function(Pointer<GhitaEngineContext> ctx, Int32 effectType, Float p0, Float p1, Float p2, Float p3);
typedef DartGhitaEngineAddAudioEffect = int Function(Pointer<GhitaEngineContext> ctx, int effectType, double p0, double p1, double p2, double p3);

typedef CGhitaEngineRemoveAudioEffect = Int32 Function(Pointer<GhitaEngineContext> ctx, Int32 index);
typedef DartGhitaEngineRemoveAudioEffect = int Function(Pointer<GhitaEngineContext> ctx, int index);

typedef CGhitaEngineClearAudioEffects = Void Function(Pointer<GhitaEngineContext> ctx);
typedef DartGhitaEngineClearAudioEffects = void Function(Pointer<GhitaEngineContext> ctx);

typedef CGhitaEngineGetGainReductionDb = Float Function(Pointer<GhitaEngineContext> ctx);
typedef DartGhitaEngineGetGainReductionDb = double Function(Pointer<GhitaEngineContext> ctx);

typedef CGhitaEngineGetSpectrogram = Bool Function(Pointer<GhitaEngineContext> ctx, Pointer<Float> outMags, Int32 columns, Int32 bins, Int32 trackIndex);
typedef DartGhitaEngineGetSpectrogram = bool Function(Pointer<GhitaEngineContext> ctx, Pointer<Float> outMags, int columns, int bins, int trackIndex);

typedef CGhitaEngineAddSpectralEdit = Int32 Function(Pointer<GhitaEngineContext> ctx, Int64 startMs, Int64 endMs, Float loHz, Float hiHz, Float gainDb);
typedef DartGhitaEngineAddSpectralEdit = int Function(Pointer<GhitaEngineContext> ctx, int startMs, int endMs, double loHz, double hiHz, double gainDb);

typedef CGhitaEngineClearSpectralEdits = Void Function(Pointer<GhitaEngineContext> ctx);
typedef DartGhitaEngineClearSpectralEdits = void Function(Pointer<GhitaEngineContext> ctx);

typedef CGhitaEngineGetTimelineRms = Bool Function(Pointer<GhitaEngineContext> ctx, Pointer<Float> out, Int32 count, Int32 trackIndex);
typedef DartGhitaEngineGetTimelineRms = bool Function(Pointer<GhitaEngineContext> ctx, Pointer<Float> out, int count, int trackIndex);

typedef CGhitaEngineDetectTempo = Int32 Function(Pointer<GhitaEngineContext> ctx);
typedef DartGhitaEngineDetectTempo = int Function(Pointer<GhitaEngineContext> ctx);

typedef CGhitaEngineSetTimeSignature = Void Function(Pointer<GhitaEngineContext> ctx, Int32 num, Int32 den);
typedef DartGhitaEngineSetTimeSignature = void Function(Pointer<GhitaEngineContext> ctx, int num, int den);

typedef CGhitaEngineGetBeatTimes = Int32 Function(Pointer<GhitaEngineContext> ctx, Pointer<Int64> outMs, Int32 maxCount);
typedef DartGhitaEngineGetBeatTimes = int Function(Pointer<GhitaEngineContext> ctx, Pointer<Int64> outMs, int maxCount);

typedef CGhitaEngineSetLoopRegion = Void Function(Pointer<GhitaEngineContext> ctx, Int64 startMs, Int64 endMs, Int32 enabled);
typedef DartGhitaEngineSetLoopRegion = void Function(Pointer<GhitaEngineContext> ctx, int startMs, int endMs, int enabled);

// v1.5.0-T5 (P6): live effect-parameter editing.
typedef CGhitaEngineSetAudioEffectParam = Int32 Function(Pointer<GhitaEngineContext> ctx, Int32 index, Int32 param, Float value);
typedef DartGhitaEngineSetAudioEffectParam = int Function(Pointer<GhitaEngineContext> ctx, int index, int param, double value);

// v1.5.0-T5 (P5): sticker transform.
typedef CGhitaEngineSetClipStickerTransform = Int32 Function(Pointer<GhitaEngineContext> ctx, Int32 clipId, Float scale, Float rotationDeg);
typedef DartGhitaEngineSetClipStickerTransform = int Function(Pointer<GhitaEngineContext> ctx, int clipId, double scale, double rotationDeg);

// v1.5.0-T5 (P6): photo paint tools (ctx-less, caller-owned RGBA buffer).
typedef CGhitaEnginePaintClone = Int32 Function(Pointer<Uint8> buf, Int32 width, Int32 height, Int32 srcX, Int32 srcY, Int32 dstX, Int32 dstY, Int32 radius, Float opacity);
typedef DartGhitaEnginePaintClone = int Function(Pointer<Uint8> buf, int width, int height, int srcX, int srcY, int dstX, int dstY, int radius, double opacity);
typedef CGhitaEnginePaintHeal = Int32 Function(Pointer<Uint8> buf, Int32 width, Int32 height, Int32 cx, Int32 cy, Int32 radius);
typedef DartGhitaEnginePaintHeal = int Function(Pointer<Uint8> buf, int width, int height, int cx, int cy, int radius);
typedef CGhitaEnginePaintBrushStroke = Int32 Function(Pointer<Uint8> buf, Int32 width, Int32 height, Pointer<Float> pointsX, Pointer<Float> pointsY, Int32 count, Float size, Float hardness, Float opacity, Uint32 colorRgba);
typedef DartGhitaEnginePaintBrushStroke = int Function(Pointer<Uint8> buf, int width, int height, Pointer<Float> pointsX, Pointer<Float> pointsY, int count, double size, double hardness, double opacity, int colorRgba);

// v1.5.0-T5 (P2/P3): performance telemetry (JSON into thread-local buffer).
typedef CGhitaEngineCacheStats = Pointer<Utf8> Function(Pointer<GhitaEngineContext> ctx);
typedef DartGhitaEngineCacheStats = Pointer<Utf8> Function(Pointer<GhitaEngineContext> ctx);
typedef CGhitaEngineGpuStats = Pointer<Utf8> Function();
typedef DartGhitaEngineGpuStats = Pointer<Utf8> Function();

typedef CGhitaEngineSetClipPitch = Int32 Function(Pointer<GhitaEngineContext> ctx, Int32 clipId, Float semitones);
typedef DartGhitaEngineSetClipPitch = int Function(Pointer<GhitaEngineContext> ctx, int clipId, double semitones);

typedef CGhitaEngineSetPreviewPitchPreserve = Void Function(Pointer<GhitaEngineContext> ctx, Int32 enabled);
typedef DartGhitaEngineSetPreviewPitchPreserve = void Function(Pointer<GhitaEngineContext> ctx, int enabled);

typedef CGhitaEngineStartRecording = Int32 Function(Pointer<GhitaEngineContext> ctx, Pointer<Utf8> outPath, Int32 mode, Int64 preRollMs, Int64 delayMs, Int64 durationMs);
typedef DartGhitaEngineStartRecording = int Function(Pointer<GhitaEngineContext> ctx, Pointer<Utf8> outPath, int mode, int preRollMs, int delayMs, int durationMs);

typedef CGhitaEngineStopRecording = Int64 Function(Pointer<GhitaEngineContext> ctx);
typedef DartGhitaEngineStopRecording = int Function(Pointer<GhitaEngineContext> ctx);

typedef CGhitaEngineIsRecording = Bool Function(Pointer<GhitaEngineContext> ctx);
typedef DartGhitaEngineIsRecording = bool Function(Pointer<GhitaEngineContext> ctx);

typedef CGhitaEngineExportLabels = Int32 Function(Pointer<GhitaEngineContext> ctx, Pointer<Utf8> path, Int32 format);
typedef DartGhitaEngineExportLabels = int Function(Pointer<GhitaEngineContext> ctx, Pointer<Utf8> path, int format);

// ========== v1.5.0 T5: SQLite Project Database — defensive lookups (sqlite feature). ==========

typedef CGhitaProjectDbSave = Int32 Function(Pointer<Utf8> dbPath, Pointer<Utf8> name, Pointer<Utf8> jsonData);
typedef DartGhitaProjectDbSave = int Function(Pointer<Utf8> dbPath, Pointer<Utf8> name, Pointer<Utf8> jsonData);

typedef CGhitaProjectDbLoad = Pointer<Utf8> Function(Pointer<Utf8> dbPath, Pointer<Utf8> name);
typedef DartGhitaProjectDbLoad = Pointer<Utf8> Function(Pointer<Utf8> dbPath, Pointer<Utf8> name);

typedef CGhitaProjectDbList = Pointer<Utf8> Function(Pointer<Utf8> dbPath);
typedef DartGhitaProjectDbList = Pointer<Utf8> Function(Pointer<Utf8> dbPath);

typedef CGhitaProjectDbDelete = Int32 Function(Pointer<Utf8> dbPath, Pointer<Utf8> name);
typedef DartGhitaProjectDbDelete = int Function(Pointer<Utf8> dbPath, Pointer<Utf8> name);

typedef CGhitaProjectDbLibraryAdd = Int32 Function(Pointer<Utf8> dbPath, Pointer<Utf8> path, Pointer<Utf8> hash, Pointer<Utf8> metadataJson);
typedef DartGhitaProjectDbLibraryAdd = int Function(Pointer<Utf8> dbPath, Pointer<Utf8> path, Pointer<Utf8> hash, Pointer<Utf8> metadataJson);

typedef CGhitaProjectDbLibrarySearch = Pointer<Utf8> Function(Pointer<Utf8> dbPath, Pointer<Utf8> query, Int32 minRating);
typedef DartGhitaProjectDbLibrarySearch = Pointer<Utf8> Function(Pointer<Utf8> dbPath, Pointer<Utf8> query, int minRating);

typedef CGhitaProjectDbLibraryUpdateRating = Int32 Function(Pointer<Utf8> dbPath, Int64 id, Int32 rating);
typedef DartGhitaProjectDbLibraryUpdateRating = int Function(Pointer<Utf8> dbPath, int id, int rating);

typedef CGhitaProjectDbLibraryUpdateTags = Int32 Function(Pointer<Utf8> dbPath, Int64 id, Pointer<Utf8> tags);
typedef DartGhitaProjectDbLibraryUpdateTags = int Function(Pointer<Utf8> dbPath, int id, Pointer<Utf8> tags);

// ========== v1.5.0 T6: Selection Tools — defensive lookups. ==========

typedef CGhitaEngineSetSelectionRect = Int32 Function(Int32 width, Int32 height, Int32 x, Int32 y, Int32 w, Int32 h, Int32 op);
typedef DartGhitaEngineSetSelectionRect = int Function(int width, int height, int x, int y, int w, int h, int op);

typedef CGhitaEngineSetSelectionEllipse = Int32 Function(Int32 width, Int32 height, Int32 cx, Int32 cy, Int32 rx, Int32 ry, Int32 op);
typedef DartGhitaEngineSetSelectionEllipse = int Function(int width, int height, int cx, int cy, int rx, int ry, int op);

typedef CGhitaEngineSetSelectionLasso = Int32 Function(Int32 width, Int32 height, Pointer<Int32> pointsX, Pointer<Int32> pointsY, Int32 count, Int32 op);
typedef DartGhitaEngineSetSelectionLasso = int Function(int width, int height, Pointer<Int32> pointsX, Pointer<Int32> pointsY, int count, int op);

typedef CGhitaEngineSetSelectionMagicWand = Int32 Function(Int32 width, Int32 height, Int32 seedX, Int32 seedY, Float tolerance, Pointer<Uint8> imageData, Int32 op);
typedef DartGhitaEngineSetSelectionMagicWand = int Function(int width, int height, int seedX, int seedY, double tolerance, Pointer<Uint8> imageData, int op);

typedef CGhitaEngineModifyMask = Int32 Function(Int32 op);
typedef DartGhitaEngineModifyMask = int Function(int op);

typedef CGhitaEngineGetMaskBuffer = Int32 Function(Pointer<Uint8> outBuf, Int32 maxSize);
typedef DartGhitaEngineGetMaskBuffer = int Function(Pointer<Uint8> outBuf, int maxSize);

typedef CGhitaEngineClearSelection = Void Function();
typedef DartGhitaEngineClearSelection = void Function();

// ========== v1.1.0 New API (PLAN 3: Accuracy) ==========

// Keyframe-aware insertion (property/interpolation/bezier aware).
typedef CGhitaEngineAddKeyframeEx = Int32 Function(
  Pointer<GhitaEngineContext> ctx, Int32 clipId, Int64 timeMs, Float value,
  Int32 property, Int32 interpolation,
  Float cp1x, Float cp1y, Float cp2x, Float cp2y,
);
typedef DartGhitaEngineAddKeyframeEx = int Function(
  Pointer<GhitaEngineContext> ctx, int clipId, int timeMs, double value,
  int property, int interpolation,
  double cp1x, double cp1y, double cp2x, double cp2y,
);

typedef CGhitaEngineGetClipKeyframeCount = Int32 Function(Pointer<GhitaEngineContext> ctx, Int32 clipId);
typedef DartGhitaEngineGetClipKeyframeCount = int Function(Pointer<GhitaEngineContext> ctx, int clipId);

// Picture-in-picture geometry.
typedef CGhitaEngineSetClipPip = Int32 Function(
  Pointer<GhitaEngineContext> ctx, Int32 clipId,
  Float x, Float y, Float w, Float h, Float rotation,
);
typedef DartGhitaEngineSetClipPip = int Function(
  Pointer<GhitaEngineContext> ctx, int clipId,
  double x, double y, double w, double h, double rotation,
);

// Speed-ramp points.
typedef CGhitaEngineAddSpeedRampPoint = Int32 Function(
    Pointer<GhitaEngineContext> ctx, Int32 clipId, Float t, Float speed);
typedef DartGhitaEngineAddSpeedRampPoint = int Function(
    Pointer<GhitaEngineContext> ctx, int clipId, double t, double speed);

typedef CGhitaEngineClearSpeedCurve = Int32 Function(Pointer<GhitaEngineContext> ctx, Int32 clipId);
typedef DartGhitaEngineClearSpeedCurve = int Function(Pointer<GhitaEngineContext> ctx, int clipId);

// Raw (effects-free) render at an explicit position — split view "before".
typedef CGhitaEngineRenderFrameAtEx = Bool Function(
  Pointer<GhitaEngineContext> ctx, Pointer<Uint8> outBuffer,
  Int32 width, Int32 height, Int64 positionMs, Int32 applyFx,
);
typedef DartGhitaEngineRenderFrameAtEx = bool Function(
  Pointer<GhitaEngineContext> ctx, Pointer<Uint8> outBuffer,
  int width, int height, int positionMs, int applyFx,
);

// Real timeline waveform.
typedef CGhitaEngineGetTimelineWaveform = Bool Function(
    Pointer<GhitaEngineContext> ctx, Pointer<Float> outSamples, Int32 sampleCount, Int32 trackIndex);
typedef DartGhitaEngineGetTimelineWaveform = bool Function(
    Pointer<GhitaEngineContext> ctx, Pointer<Float> outSamples, int sampleCount, int trackIndex);

// ========== v0.4.5 New API ==========

// Media info
typedef CGhitaEngineGetMediaInfo = Pointer<Utf8> Function(Pointer<GhitaEngineContext> ctx);
typedef DartGhitaEngineGetMediaInfo = Pointer<Utf8> Function(Pointer<GhitaEngineContext> ctx);

// Available filters
typedef CGhitaEngineGetAvailableFilters = Pointer<Utf8> Function(Pointer<GhitaEngineContext> ctx);
typedef DartGhitaEngineGetAvailableFilters = Pointer<Utf8> Function(Pointer<GhitaEngineContext> ctx);

// Extended export
typedef CGhitaEngineStartExportEx = Int32 Function(
  Pointer<GhitaEngineContext> ctx,
  Pointer<Utf8> outputPath,
  Int32 width, Int32 height, Int32 fps,
  Pointer<Utf8> codec, Int64 bitrate, Bool includeAudio,
);
typedef DartGhitaEngineStartExportEx = int Function(
  Pointer<GhitaEngineContext> ctx,
  Pointer<Utf8> outputPath,
  int width, int height, int fps,
  Pointer<Utf8> codec, int bitrate, bool includeAudio,
);

// Export file size
typedef CGhitaEngineGetExportFileSize = Int64 Function(Pointer<GhitaEngineContext> ctx);
typedef DartGhitaEngineGetExportFileSize = int Function(Pointer<GhitaEngineContext> ctx);

// Keyframes
typedef CGhitaEngineAddClipKeyframe = Int32 Function(Pointer<GhitaEngineContext> ctx, Int32 clipId, Int64 timeMs, Float value);
typedef DartGhitaEngineAddClipKeyframe = int Function(Pointer<GhitaEngineContext> ctx, int clipId, int timeMs, double value);

typedef CGhitaEngineClearClipKeyframes = Int32 Function(Pointer<GhitaEngineContext> ctx, Int32 clipId);
typedef DartGhitaEngineClearClipKeyframes = int Function(Pointer<GhitaEngineContext> ctx, int clipId);

// FFmpeg availability
typedef CGhitaEngineHasFFmpeg = Bool Function(Pointer<GhitaEngineContext> ctx);
typedef DartGhitaEngineHasFFmpeg = bool Function(Pointer<GhitaEngineContext> ctx);

// ========== v0.5.5 New API ==========

// Playback rate
typedef CGhitaEngineSetPlaybackRate = Void Function(Pointer<GhitaEngineContext> ctx, Float rate);
typedef DartGhitaEngineSetPlaybackRate = void Function(Pointer<GhitaEngineContext> ctx, double rate);

typedef CGhitaEngineGetPlaybackRate = Float Function(Pointer<GhitaEngineContext> ctx);
typedef DartGhitaEngineGetPlaybackRate = double Function(Pointer<GhitaEngineContext> ctx);

// Keyframe interpolation
typedef CGhitaEngineSetClipKeyframeInterpolation = Int32 Function(Pointer<GhitaEngineContext> ctx, Int32 clipId, Int32 interpolationType);
typedef DartGhitaEngineSetClipKeyframeInterpolation = int Function(Pointer<GhitaEngineContext> ctx, int clipId, int interpolationType);

typedef CGhitaEngineGetClipKeyframeInterpolation = Int32 Function(Pointer<GhitaEngineContext> ctx, Int32 clipId);
typedef DartGhitaEngineGetClipKeyframeInterpolation = int Function(Pointer<GhitaEngineContext> ctx, int clipId);

// Text overlay rendering
typedef CGhitaEngineRenderTextOverlay = Bool Function(
  Pointer<GhitaEngineContext> ctx,
  Pointer<Uint8> outBuffer, Int32 width, Int32 height,
  Pointer<Utf8> text, Int32 fontSize, Float r, Float g, Float b, Float a
);
typedef DartGhitaEngineRenderTextOverlay = bool Function(
  Pointer<GhitaEngineContext> ctx,
  Pointer<Uint8> outBuffer, int width, int height,
  Pointer<Utf8> text, int fontSize, double r, double g, double b, double a
);

// ========== v0.7.0 New API ==========

// Color correction
typedef CGhitaEngineApplyColorCorrection = Void Function(
  Pointer<GhitaEngineContext> ctx, Int32 clipId,
  Float exposure, Float contrast, Float highlights, Float shadows,
  Float temperature, Float tint, Float vibrance, Float saturation
);
typedef DartGhitaEngineApplyColorCorrection = void Function(
  Pointer<GhitaEngineContext> ctx, int clipId,
  double exposure, double contrast, double highlights, double shadows,
  double temperature, double tint, double vibrance, double saturation
);

// Keyframe bezier
typedef CGhitaEngineSetKeyframeBezier = Int32 Function(
  Pointer<GhitaEngineContext> ctx, Int32 clipId, Int32 keyframeIndex,
  Float cp1x, Float cp1y, Float cp2x, Float cp2y
);
typedef DartGhitaEngineSetKeyframeBezier = int Function(
  Pointer<GhitaEngineContext> ctx, int clipId, int keyframeIndex,
  double cp1x, double cp1y, double cp2x, double cp2y
);

// PIP rendering
typedef CGhitaEngineRenderPip = Bool Function(
  Pointer<GhitaEngineContext> ctx, Int32 overlayClipId,
  Float x, Float y, Float width, Float height, Float rotation
);
typedef DartGhitaEngineRenderPip = bool Function(
  Pointer<GhitaEngineContext> ctx, int overlayClipId,
  double x, double y, double width, double height, double rotation
);

// Thumbnail extraction
typedef CGhitaEngineGetThumbnail = Pointer<Uint8> Function(
  Pointer<GhitaEngineContext> ctx, Int32 clipId, Int32 timeMs, Int32 width, Int32 height
);
typedef DartGhitaEngineGetThumbnail = Pointer<Uint8> Function(
  Pointer<GhitaEngineContext> ctx, int clipId, int timeMs, int width, int height
);

// New filter types (v0.7.0)
typedef CGhitaEngineSetFilterPreset = Void Function(
  Pointer<GhitaEngineContext> ctx, Int32 clipId, Int32 filterType, Float intensity
);
typedef DartGhitaEngineSetFilterPreset = void Function(
  Pointer<GhitaEngineContext> ctx, int clipId, int filterType, double intensity
);

// Audio waveform peaks for timeline
typedef CGhitaEngineGetAudioWaveformPeaks = Bool Function(
  Pointer<GhitaEngineContext> ctx, Pointer<Float> outSamples, Int32 sampleCount
);
typedef DartGhitaEngineGetAudioWaveformPeaks = bool Function(
  Pointer<GhitaEngineContext> ctx, Pointer<Float> outSamples, int sampleCount
);

// ========== v0.8.0 New API ==========

// Full timeline sync — insert or update a clip.
// kind: 0=video, 1=audio, 2=image, 3=text, 4=sticker
typedef CGhitaEngineUpsertClip = Int32 Function(
  Pointer<GhitaEngineContext> ctx,
  Int32 clipId, Pointer<Utf8> filePath,
  Int64 startMs, Int64 durationMs, Int64 sourceInMs,
  Int32 trackIndex, Int32 kind, Float volume, Float opacity, Float speed
);
typedef DartGhitaEngineUpsertClip = int Function(
  Pointer<GhitaEngineContext> ctx,
  int clipId, Pointer<Utf8> filePath,
  int startMs, int durationMs, int sourceInMs,
  int trackIndex, int kind, double volume, double opacity, double speed
);

typedef CGhitaEngineClearClips = Void Function(Pointer<GhitaEngineContext> ctx);
typedef DartGhitaEngineClearClips = void Function(Pointer<GhitaEngineContext> ctx);

typedef CGhitaEngineSetTrackState = Int32 Function(
  Pointer<GhitaEngineContext> ctx, Int32 trackIndex, Int32 muted, Int32 visible, Float volume
);
typedef DartGhitaEngineSetTrackState = int Function(
  Pointer<GhitaEngineContext> ctx, int trackIndex, int muted, int visible, double volume
);

typedef CGhitaEngineSetClipColorCorrection = Int32 Function(
  Pointer<GhitaEngineContext> ctx, Int32 clipId,
  Float exposure, Float contrast, Float saturation,
  Float temperature, Float tint, Float vibrance, Float highlights, Float shadows
);
typedef DartGhitaEngineSetClipColorCorrection = int Function(
  Pointer<GhitaEngineContext> ctx, int clipId,
  double exposure, double contrast, double saturation,
  double temperature, double tint, double vibrance, double highlights, double shadows
);

typedef CGhitaEngineSetClipText = Int32 Function(
  Pointer<GhitaEngineContext> ctx, Int32 clipId, Pointer<Utf8> text, Float fontSize, Uint32 colorArgb
);
typedef DartGhitaEngineSetClipText = int Function(
  Pointer<GhitaEngineContext> ctx, int clipId, Pointer<Utf8> text, double fontSize, int colorArgb
);

typedef CGhitaEngineHasClip = Int32 Function(Pointer<GhitaEngineContext> ctx, Int32 clipId);
typedef DartGhitaEngineHasClip = int Function(Pointer<GhitaEngineContext> ctx, int clipId);

// ========== Bindings Class ==========

class GhitaNativeBindings {
  static final GhitaNativeBindings instance = GhitaNativeBindings._internal();
  late DynamicLibrary _lib;
  bool _initialized = false;

  // Lifecycle
  late DartGhitaEngineCreate createEngine;
  late DartGhitaEngineDestroy destroyEngine;
  late DartGhitaEngineInit initEngine;

  // Media
  late DartGhitaEngineLoadMedia loadMedia;
  late DartGhitaEngineGetDurationMs getDurationMs;
  late DartGhitaEngineGetMediaWidth getMediaWidth;
  late DartGhitaEngineGetMediaHeight getMediaHeight;

  // Playback
  late DartGhitaEnginePlay play;
  late DartGhitaEnginePause pause;
  late DartGhitaEngineIsPlaying isPlaying;
  late DartGhitaEngineSeek seek;
  late DartGhitaEngineGetPositionMs getPositionMs;

  // Audio & FX
  late DartGhitaEngineSetVolume setVolume;
  late DartGhitaEngineApplyFilter applyFilter;

  // Rendering
  late DartGhitaEngineRenderFrameRgba renderFrameRgba;
  // v0.7.9: Nullable — present in the 0.7.9 DLL, absent in older DLLs.
  DartGhitaEngineRenderFrameAt? renderFrameAt;

  // Version
  late DartGhitaEngineGetVersion getVersion;

  // Timeline / Clip (v0.2.0)
  late DartGhitaEngineAddClip addClip;
  late DartGhitaEngineRemoveClip removeClip;
  late DartGhitaEngineGetClipCount getClipCount;
  late DartGhitaEngineSetClipPosition setClipPosition;
  late DartGhitaEngineSetClipFilter setClipFilter;

  // Timeline / Clip — Transitions (v0.4.0)
  late DartGhitaEngineSetClipTransition setClipTransition;

  // Export (v0.2.0)
  late DartGhitaEngineStartExport startExport;
  late DartGhitaEngineGetExportProgress getExportProgress;
  late DartGhitaEngineIsExporting isExporting;
  late DartGhitaEngineCancelExport cancelExport;

  // Audio Waveform (v0.3.0)
  late DartGhitaEngineGetAudioWaveform getAudioWaveform;

  // v0.4.5 New bindings
  late DartGhitaEngineGetMediaInfo getMediaInfo;
  late DartGhitaEngineGetAvailableFilters getAvailableFilters;
  late DartGhitaEngineStartExportEx startExportEx;
  late DartGhitaEngineGetExportFileSize getExportFileSize;
  late DartGhitaEngineAddClipKeyframe addClipKeyframe;
  late DartGhitaEngineClearClipKeyframes clearClipKeyframes;
  late DartGhitaEngineHasFFmpeg hasFFmpeg;

  // v0.5.5 New bindings
  late DartGhitaEngineSetPlaybackRate setPlaybackRate;
  late DartGhitaEngineGetPlaybackRate getPlaybackRate;
  late DartGhitaEngineSetClipKeyframeInterpolation setClipKeyframeInterpolation;
  late DartGhitaEngineGetClipKeyframeInterpolation getClipKeyframeInterpolation;
  late DartGhitaEngineRenderTextOverlay renderTextOverlay;

  // v0.7.0 New bindings
  // v0.7.8: Nullable — these symbols were never implemented in the C++ engine.
  // Previously a hard lookup here threw inside _bindFunctions, which silently
  // disabled the ENTIRE native engine (permanent Demo Mode despite the DLL).
  DartGhitaEngineApplyColorCorrection? applyColorCorrection;
  DartGhitaEngineSetKeyframeBezier? setKeyframeBezier;
  DartGhitaEngineRenderPip? renderPip;
  DartGhitaEngineGetThumbnail? getThumbnail;
  DartGhitaEngineSetFilterPreset? setFilterPreset;
  DartGhitaEngineGetAudioWaveformPeaks? getAudioWaveformPeaks;

  // v0.8.0 New bindings — v1.0.1: nullable with stub fallbacks so an older
  // DLL missing these symbols degrades gracefully instead of crashing.
  DartGhitaEngineUpsertClip? upsertClip;
  DartGhitaEngineClearClips? clearClips;
  DartGhitaEngineSetTrackState? setTrackState;
  DartGhitaEngineSetClipColorCorrection? setClipColorCorrection;
  DartGhitaEngineSetClipText? setClipText;
  DartGhitaEngineHasClip? hasClip;

  // v1.0.3: Noise suppression ("làm rõ âm thanh") — optional, missing on
  // older DLLs.
  DartGhitaEngineSetNoiseSuppress? setNoiseSuppress;

  // v1.1.0 (PLAN 3): Accuracy features — nullable; features degrade to
  // no-ops on older DLLs (pattern v1.0.1).
  DartGhitaEngineAddKeyframeEx? addKeyframeEx;
  DartGhitaEngineGetClipKeyframeCount? getClipKeyframeCount;
  DartGhitaEngineSetClipPip? setClipPip;
  DartGhitaEngineAddSpeedRampPoint? addSpeedRampPoint;
  DartGhitaEngineClearSpeedCurve? clearSpeedCurve;
  DartGhitaEngineRenderFrameAtEx? renderFrameAtEx;
  DartGhitaEngineGetTimelineWaveform? getTimelineWaveform;

  // v1.5.0 T3: Video Features — nullable (additive, older DLLs degrade).
  DartGhitaEngineSetClipBlendMode? setClipBlendMode;
  DartGhitaEngineSetClipMask? setClipMask;
  DartGhitaEngineSetClipMaintainPitch? setClipMaintainPitch;
  DartGhitaEngineSetClipFont? setClipFont;
  DartGhitaEngineSetCanvasBackground? setCanvasBackground;
  DartGhitaEngineAddBookmark? addBookmark;
  DartGhitaEngineRemoveBookmark? removeBookmark;
  DartGhitaEngineGetBookmarkCount? getBookmarkCount;
  DartGhitaEngineGetBookmarksJson? getBookmarksJson;
  DartGhitaEngineCopyKeyframes? copyKeyframes;
  DartGhitaEngineImportTranscript? importTranscript;

  // v1.5.0 T4: Audio Features — defensive lookups (older DLLs degrade).
  DartGhitaEngineAddAudioEffect? addAudioEffect;
  DartGhitaEngineRemoveAudioEffect? removeAudioEffect;
  DartGhitaEngineClearAudioEffects? clearAudioEffects;
  DartGhitaEngineGetGainReductionDb? getGainReductionDb;
  DartGhitaEngineGetSpectrogram? getSpectrogram;
  DartGhitaEngineAddSpectralEdit? addSpectralEdit;
  DartGhitaEngineClearSpectralEdits? clearSpectralEdits;
  DartGhitaEngineGetTimelineRms? getTimelineRms;
  DartGhitaEngineDetectTempo? detectTempo;
  DartGhitaEngineSetTimeSignature? setTimeSignature;
  DartGhitaEngineGetBeatTimes? getBeatTimes;
  DartGhitaEngineSetLoopRegion? setLoopRegion;
  DartGhitaEngineSetClipPitch? setClipPitch;
  DartGhitaEngineSetPreviewPitchPreserve? setPreviewPitchPreserve;
  DartGhitaEngineStartRecording? startRecording;
  DartGhitaEngineStopRecording? stopRecording;
  DartGhitaEngineIsRecording? isRecording;
  DartGhitaEngineExportLabels? exportLabels;
  // v1.5.0-T5: effect-param live edit + performance telemetry.
  DartGhitaEngineSetAudioEffectParam? setAudioEffectParam;
  DartGhitaEngineCacheStats? getCacheStats;
  DartGhitaEngineGpuStats? getGpuStats;
  DartGhitaEngineSetClipStickerTransform? setClipStickerTransform;
  // v1.5.0-T5 (P6): photo paint tools.
  DartGhitaEnginePaintClone? paintClone;
  DartGhitaEnginePaintHeal? paintHeal;
  DartGhitaEnginePaintBrushStroke? paintBrushStroke;

  // ========== v1.5.0 T5: SQLite Project Database — defensive lookups (sqlite feature). ==========
  DartGhitaProjectDbSave? projectDbSave;
  DartGhitaProjectDbLoad? projectDbLoad;
  DartGhitaProjectDbList? projectDbList;
  DartGhitaProjectDbDelete? projectDbDelete;
  DartGhitaProjectDbLibraryAdd? projectDbLibraryAdd;
  DartGhitaProjectDbLibrarySearch? projectDbLibrarySearch;
  DartGhitaProjectDbLibraryUpdateRating? projectDbLibraryUpdateRating;
  DartGhitaProjectDbLibraryUpdateTags? projectDbLibraryUpdateTags;

  // ========== v1.5.0 T6: Selection Tools — defensive lookups. ==========
  DartGhitaEngineSetSelectionRect? setSelectionRect;
  DartGhitaEngineSetSelectionEllipse? setSelectionEllipse;
  DartGhitaEngineSetSelectionLasso? setSelectionLasso;
  DartGhitaEngineSetSelectionMagicWand? setSelectionMagicWand;
  DartGhitaEngineModifyMask? modifyMask;
  DartGhitaEngineGetMaskBuffer? getMaskBuffer;
  DartGhitaEngineClearSelection? clearSelection;

  GhitaNativeBindings._internal() {
    _loadLibrary();
  }

  void _loadLibrary() {
    if (_initialized) return;

    try {
      _lib = _resolveLibraryPath();
    } catch (_) {
      try {
        _lib = DynamicLibrary.process();
      } catch (e) {
        throw StateError('Cannot open ghita_engine native library: $e');
      }
    }

    _bindFunctions();
    _initialized = true;
  }

  DynamicLibrary _resolveLibraryPath() {
    if (Platform.isWindows) {
      final candidates = <String>[
        'ghita_engine.dll',
        'libghita_engine.dll',
        '${Directory.current.path}\\native_engine\\build\\libghita_engine.dll',
        '${Directory.current.path}\\build\\windows\\x64\\runner\\Debug\\ghita_engine.dll',
        '${Directory.current.path}\\build\\windows\\x64\\runner\\Release\\ghita_engine.dll',
        '${Directory(Platform.resolvedExecutable).parent.path}\\ghita_engine.dll',
        '${Directory(Platform.resolvedExecutable).parent.path}\\libghita_engine.dll',
      ];
      for (final path in candidates) {
        try {
          return DynamicLibrary.open(path);
        } catch (_) {
          continue;
        }
      }
      throw StateError('ghita_engine.dll not found in any expected location');
    } else if (Platform.isAndroid) {
      return DynamicLibrary.open('libghita_engine.so');
    } else if (Platform.isMacOS) {
      final candidates = <String>[
        'libghita_engine.dylib',
        '${Directory.current.path}/native_engine/build/libghita_engine.dylib',
        '${Directory(Platform.resolvedExecutable).parent.path}/libghita_engine.dylib',
        '/usr/local/lib/libghita_engine.dylib',
      ];
      for (final path in candidates) {
        try {
          return DynamicLibrary.open(path);
        } catch (_) {
          continue;
        }
      }
      throw StateError('libghita_engine.dylib not found in any expected location');
    } else if (Platform.isLinux) {
      final candidates = <String>[
        'libghita_engine.so',
        '${Directory.current.path}/native_engine/build/libghita_engine.so',
        '${Directory(Platform.resolvedExecutable).parent.path}/libghita_engine.so',
        '/usr/local/lib/libghita_engine.so',
      ];
      for (final path in candidates) {
        try {
          return DynamicLibrary.open(path);
        } catch (_) {
          continue;
        }
      }
      throw StateError('libghita_engine.so not found in any expected location');
    }
    throw UnsupportedError('Unsupported platform: ${Platform.operatingSystem}');
  }

  void _bindFunctions() {
    // v1.5.0-T2 (P2): a hard lookup failure must name the offending symbol
    // instead of a bare ArgumentError that upstream code swallows into
    // silent Demo Mode.
    try {
      _bindFunctionsInner();
    } on ArgumentError catch (e) {
      throw StateError('Engine DLL rejected a required FFI symbol: $e');
    }
  }

  void _bindFunctionsInner() {
    // Lifecycle
    createEngine = _lib.lookupFunction<CGhitaEngineCreate, DartGhitaEngineCreate>('ghita_engine_create');
    destroyEngine = _lib.lookupFunction<CGhitaEngineDestroy, DartGhitaEngineDestroy>('ghita_engine_destroy');
    initEngine = _lib.lookupFunction<CGhitaEngineInit, DartGhitaEngineInit>('ghita_engine_init');

    // Media
    loadMedia = _lib.lookupFunction<CGhitaEngineLoadMedia, DartGhitaEngineLoadMedia>('ghita_engine_load_media');
    getDurationMs = _lib.lookupFunction<CGhitaEngineGetDurationMs, DartGhitaEngineGetDurationMs>('ghita_engine_get_duration_ms');
    getMediaWidth = _lib.lookupFunction<CGhitaEngineGetMediaWidth, DartGhitaEngineGetMediaWidth>('ghita_engine_get_media_width');
    getMediaHeight = _lib.lookupFunction<CGhitaEngineGetMediaHeight, DartGhitaEngineGetMediaHeight>('ghita_engine_get_media_height');

    // Playback
    play = _lib.lookupFunction<CGhitaEnginePlay, DartGhitaEnginePlay>('ghita_engine_play');
    pause = _lib.lookupFunction<CGhitaEnginePause, DartGhitaEnginePause>('ghita_engine_pause');
    isPlaying = _lib.lookupFunction<CGhitaEngineIsPlaying, DartGhitaEngineIsPlaying>('ghita_engine_is_playing');
    seek = _lib.lookupFunction<CGhitaEngineSeek, DartGhitaEngineSeek>('ghita_engine_seek');
    getPositionMs = _lib.lookupFunction<CGhitaEngineGetPositionMs, DartGhitaEngineGetPositionMs>('ghita_engine_get_position_ms');

    // Audio & FX
    setVolume = _lib.lookupFunction<CGhitaEngineSetVolume, DartGhitaEngineSetVolume>('ghita_engine_set_volume');
    applyFilter = _lib.lookupFunction<CGhitaEngineApplyFilter, DartGhitaEngineApplyFilter>('ghita_engine_apply_filter');

    // Rendering
    renderFrameRgba = _lib.lookupFunction<CGhitaEngineRenderFrameRgba, DartGhitaEngineRenderFrameRgba>('ghita_engine_render_frame_rgba');
    renderFrameAt = _tryLookup('ghita_engine_render_frame_at', () => _lib.lookupFunction<CGhitaEngineRenderFrameAt, DartGhitaEngineRenderFrameAt>('ghita_engine_render_frame_at'));

    // Version
    getVersion = _lib.lookupFunction<CGhitaEngineGetVersion, DartGhitaEngineGetVersion>('ghita_engine_get_version');

    // Timeline / Clip (v0.2.0)
    addClip = _lib.lookupFunction<CGhitaEngineAddClip, DartGhitaEngineAddClip>('ghita_engine_add_clip');
    removeClip = _lib.lookupFunction<CGhitaEngineRemoveClip, DartGhitaEngineRemoveClip>('ghita_engine_remove_clip');
    getClipCount = _lib.lookupFunction<CGhitaEngineGetClipCount, DartGhitaEngineGetClipCount>('ghita_engine_get_clip_count');
    setClipPosition = _lib.lookupFunction<CGhitaEngineSetClipPosition, DartGhitaEngineSetClipPosition>('ghita_engine_set_clip_position');
    setClipFilter = _lib.lookupFunction<CGhitaEngineSetClipFilter, DartGhitaEngineSetClipFilter>('ghita_engine_set_clip_filter');

    // Timeline / Clip — Transitions (v0.4.0)
    setClipTransition = _lib.lookupFunction<CGhitaEngineSetClipTransition, DartGhitaEngineSetClipTransition>('ghita_engine_set_clip_transition');

    // Export (v0.2.0)
    startExport = _lib.lookupFunction<CGhitaEngineStartExport, DartGhitaEngineStartExport>('ghita_engine_start_export');
    getExportProgress = _lib.lookupFunction<CGhitaEngineGetExportProgress, DartGhitaEngineGetExportProgress>('ghita_engine_get_export_progress');
    isExporting = _lib.lookupFunction<CGhitaEngineIsExporting, DartGhitaEngineIsExporting>('ghita_engine_is_exporting');
    cancelExport = _lib.lookupFunction<CGhitaEngineCancelExport, DartGhitaEngineCancelExport>('ghita_engine_cancel_export');

    // Audio Waveform (v0.3.0)
    getAudioWaveform = _lib.lookupFunction<CGhitaEngineGetAudioWaveform, DartGhitaEngineGetAudioWaveform>('ghita_engine_get_audio_waveform');

    // v0.4.5 New bindings
    getMediaInfo = _lib.lookupFunction<CGhitaEngineGetMediaInfo, DartGhitaEngineGetMediaInfo>('ghita_engine_get_media_info');
    getAvailableFilters = _lib.lookupFunction<CGhitaEngineGetAvailableFilters, DartGhitaEngineGetAvailableFilters>('ghita_engine_get_available_filters');
    startExportEx = _lib.lookupFunction<CGhitaEngineStartExportEx, DartGhitaEngineStartExportEx>('ghita_engine_start_export_ex');
    getExportFileSize = _lib.lookupFunction<CGhitaEngineGetExportFileSize, DartGhitaEngineGetExportFileSize>('ghita_engine_get_export_file_size');
    addClipKeyframe = _lib.lookupFunction<CGhitaEngineAddClipKeyframe, DartGhitaEngineAddClipKeyframe>('ghita_engine_add_clip_keyframe');
    clearClipKeyframes = _lib.lookupFunction<CGhitaEngineClearClipKeyframes, DartGhitaEngineClearClipKeyframes>('ghita_engine_clear_clip_keyframes');
    hasFFmpeg = _lib.lookupFunction<CGhitaEngineHasFFmpeg, DartGhitaEngineHasFFmpeg>('ghita_engine_has_ffmpeg');

    // v0.5.5 New bindings
    setPlaybackRate = _lib.lookupFunction<CGhitaEngineSetPlaybackRate, DartGhitaEngineSetPlaybackRate>('ghita_engine_set_playback_rate');
    getPlaybackRate = _lib.lookupFunction<CGhitaEngineGetPlaybackRate, DartGhitaEngineGetPlaybackRate>('ghita_engine_get_playback_rate');
    setClipKeyframeInterpolation = _lib.lookupFunction<CGhitaEngineSetClipKeyframeInterpolation, DartGhitaEngineSetClipKeyframeInterpolation>('ghita_engine_set_clip_keyframe_interpolation');
    getClipKeyframeInterpolation = _lib.lookupFunction<CGhitaEngineGetClipKeyframeInterpolation, DartGhitaEngineGetClipKeyframeInterpolation>('ghita_engine_get_clip_keyframe_interpolation');
    renderTextOverlay = _lib.lookupFunction<CGhitaEngineRenderTextOverlay, DartGhitaEngineRenderTextOverlay>('ghita_engine_render_text_overlay');

    // v0.7.0 New bindings
    // v0.7.8: Defensive lookups — a missing symbol no longer kills the whole
    // engine; the feature just reports unavailable (see _tryLookup).
    applyColorCorrection = _tryLookup('ghita_engine_apply_color_correction', () => _lib.lookupFunction<CGhitaEngineApplyColorCorrection, DartGhitaEngineApplyColorCorrection>('ghita_engine_apply_color_correction'));
    setKeyframeBezier = _tryLookup('ghita_engine_set_keyframe_bezier', () => _lib.lookupFunction<CGhitaEngineSetKeyframeBezier, DartGhitaEngineSetKeyframeBezier>('ghita_engine_set_keyframe_bezier'));
    renderPip = _tryLookup('ghita_engine_render_pip', () => _lib.lookupFunction<CGhitaEngineRenderPip, DartGhitaEngineRenderPip>('ghita_engine_render_pip'));
    getThumbnail = _tryLookup('ghita_engine_get_thumbnail', () => _lib.lookupFunction<CGhitaEngineGetThumbnail, DartGhitaEngineGetThumbnail>('ghita_engine_get_thumbnail'));
    setFilterPreset = _tryLookup('ghita_engine_set_filter_preset', () => _lib.lookupFunction<CGhitaEngineSetFilterPreset, DartGhitaEngineSetFilterPreset>('ghita_engine_set_filter_preset'));
    getAudioWaveformPeaks = _tryLookup('ghita_engine_get_audio_waveform_peaks', () => _lib.lookupFunction<CGhitaEngineGetAudioWaveformPeaks, DartGhitaEngineGetAudioWaveformPeaks>('ghita_engine_get_audio_waveform_peaks'));

    // v0.8.0 New bindings
    // v1.0.1: Use defensive lookups — a missing symbol in an older DLL
    // must NOT silently disable the entire native engine (the v0.7.0
    // pattern). Each binding that reports nullable is gracefully degraded.
    upsertClip = _tryLookup('ghita_engine_upsert_clip', () => _lib.lookupFunction<CGhitaEngineUpsertClip, DartGhitaEngineUpsertClip>('ghita_engine_upsert_clip')) ?? _upsertClipStub;
    clearClips = _tryLookup('ghita_engine_clear_clips', () => _lib.lookupFunction<CGhitaEngineClearClips, DartGhitaEngineClearClips>('ghita_engine_clear_clips')) ?? _clearClipsStub;
    setTrackState = _tryLookup('ghita_engine_set_track_state', () => _lib.lookupFunction<CGhitaEngineSetTrackState, DartGhitaEngineSetTrackState>('ghita_engine_set_track_state')) ?? _setTrackStateStub;
    setClipColorCorrection = _tryLookup('ghita_engine_set_clip_color_correction', () => _lib.lookupFunction<CGhitaEngineSetClipColorCorrection, DartGhitaEngineSetClipColorCorrection>('ghita_engine_set_clip_color_correction')) ?? _setClipColorCorrectionStub;
    setClipText = _tryLookup('ghita_engine_set_clip_text', () => _lib.lookupFunction<CGhitaEngineSetClipText, DartGhitaEngineSetClipText>('ghita_engine_set_clip_text')) ?? _setClipTextStub;
    hasClip = _tryLookup('ghita_engine_has_clip', () => _lib.lookupFunction<CGhitaEngineHasClip, DartGhitaEngineHasClip>('ghita_engine_has_clip')) ?? _hasClipStub;
    setNoiseSuppress = _tryLookup('ghita_engine_set_noise_suppress', () => _lib.lookupFunction<CGhitaEngineSetNoiseSuppress, DartGhitaEngineSetNoiseSuppress>('ghita_engine_set_noise_suppress'));

    // v1.1.0 (PLAN 3): Accuracy features — defensive lookups.
    addKeyframeEx = _tryLookup('ghita_engine_add_keyframe_ex', () => _lib.lookupFunction<CGhitaEngineAddKeyframeEx, DartGhitaEngineAddKeyframeEx>('ghita_engine_add_keyframe_ex'));
    getClipKeyframeCount = _tryLookup('ghita_engine_get_clip_keyframe_count', () => _lib.lookupFunction<CGhitaEngineGetClipKeyframeCount, DartGhitaEngineGetClipKeyframeCount>('ghita_engine_get_clip_keyframe_count'));
    setClipPip = _tryLookup('ghita_engine_set_clip_pip', () => _lib.lookupFunction<CGhitaEngineSetClipPip, DartGhitaEngineSetClipPip>('ghita_engine_set_clip_pip'));
    addSpeedRampPoint = _tryLookup('ghita_engine_add_speed_ramp_point', () => _lib.lookupFunction<CGhitaEngineAddSpeedRampPoint, DartGhitaEngineAddSpeedRampPoint>('ghita_engine_add_speed_ramp_point'));
    clearSpeedCurve = _tryLookup('ghita_engine_clear_speed_curve', () => _lib.lookupFunction<CGhitaEngineClearSpeedCurve, DartGhitaEngineClearSpeedCurve>('ghita_engine_clear_speed_curve'));
    renderFrameAtEx = _tryLookup('ghita_engine_render_frame_at_ex', () => _lib.lookupFunction<CGhitaEngineRenderFrameAtEx, DartGhitaEngineRenderFrameAtEx>('ghita_engine_render_frame_at_ex'));
    getTimelineWaveform = _tryLookup('ghita_engine_get_timeline_waveform', () => _lib.lookupFunction<CGhitaEngineGetTimelineWaveform, DartGhitaEngineGetTimelineWaveform>('ghita_engine_get_timeline_waveform'));

    // v1.5.0 T3: Video Features — defensive lookups (older DLLs degrade).
    setClipBlendMode = _tryLookup('ghita_engine_set_clip_blend_mode', () => _lib.lookupFunction<CGhitaEngineSetClipBlendMode, DartGhitaEngineSetClipBlendMode>('ghita_engine_set_clip_blend_mode'));
    setClipMask = _tryLookup('ghita_engine_set_clip_mask', () => _lib.lookupFunction<CGhitaEngineSetClipMask, DartGhitaEngineSetClipMask>('ghita_engine_set_clip_mask'));
    setClipMaintainPitch = _tryLookup('ghita_engine_set_clip_maintain_pitch', () => _lib.lookupFunction<CGhitaEngineSetClipMaintainPitch, DartGhitaEngineSetClipMaintainPitch>('ghita_engine_set_clip_maintain_pitch'));
    setClipFont = _tryLookup('ghita_engine_set_clip_font', () => _lib.lookupFunction<CGhitaEngineSetClipFont, DartGhitaEngineSetClipFont>('ghita_engine_set_clip_font'));
    setCanvasBackground = _tryLookup('ghita_engine_set_canvas_background', () => _lib.lookupFunction<CGhitaEngineSetCanvasBackground, DartGhitaEngineSetCanvasBackground>('ghita_engine_set_canvas_background'));
    addBookmark = _tryLookup('ghita_engine_add_bookmark', () => _lib.lookupFunction<CGhitaEngineAddBookmark, DartGhitaEngineAddBookmark>('ghita_engine_add_bookmark'));
    removeBookmark = _tryLookup('ghita_engine_remove_bookmark', () => _lib.lookupFunction<CGhitaEngineRemoveBookmark, DartGhitaEngineRemoveBookmark>('ghita_engine_remove_bookmark'));
    getBookmarkCount = _tryLookup('ghita_engine_get_bookmark_count', () => _lib.lookupFunction<CGhitaEngineGetBookmarkCount, DartGhitaEngineGetBookmarkCount>('ghita_engine_get_bookmark_count'));
    getBookmarksJson = _tryLookup('ghita_engine_get_bookmarks_json', () => _lib.lookupFunction<CGhitaEngineGetBookmarksJson, DartGhitaEngineGetBookmarksJson>('ghita_engine_get_bookmarks_json'));
    copyKeyframes = _tryLookup('ghita_engine_copy_keyframes', () => _lib.lookupFunction<CGhitaEngineCopyKeyframes, DartGhitaEngineCopyKeyframes>('ghita_engine_copy_keyframes'));
    importTranscript = _tryLookup('ghita_engine_import_transcript', () => _lib.lookupFunction<CGhitaEngineImportTranscript, DartGhitaEngineImportTranscript>('ghita_engine_import_transcript'));

    // v1.5.0 T4: Audio Features — defensive lookups (older DLLs degrade).
    addAudioEffect = _tryLookup('ghita_engine_add_audio_effect', () => _lib.lookupFunction<CGhitaEngineAddAudioEffect, DartGhitaEngineAddAudioEffect>('ghita_engine_add_audio_effect'));
    removeAudioEffect = _tryLookup('ghita_engine_remove_audio_effect', () => _lib.lookupFunction<CGhitaEngineRemoveAudioEffect, DartGhitaEngineRemoveAudioEffect>('ghita_engine_remove_audio_effect'));
    clearAudioEffects = _tryLookup('ghita_engine_clear_audio_effects', () => _lib.lookupFunction<CGhitaEngineClearAudioEffects, DartGhitaEngineClearAudioEffects>('ghita_engine_clear_audio_effects'));
    getGainReductionDb = _tryLookup('ghita_engine_get_gain_reduction_db', () => _lib.lookupFunction<CGhitaEngineGetGainReductionDb, DartGhitaEngineGetGainReductionDb>('ghita_engine_get_gain_reduction_db'));
    getSpectrogram = _tryLookup('ghita_engine_get_spectrogram', () => _lib.lookupFunction<CGhitaEngineGetSpectrogram, DartGhitaEngineGetSpectrogram>('ghita_engine_get_spectrogram'));
    addSpectralEdit = _tryLookup('ghita_engine_add_spectral_edit', () => _lib.lookupFunction<CGhitaEngineAddSpectralEdit, DartGhitaEngineAddSpectralEdit>('ghita_engine_add_spectral_edit'));
    clearSpectralEdits = _tryLookup('ghita_engine_clear_spectral_edits', () => _lib.lookupFunction<CGhitaEngineClearSpectralEdits, DartGhitaEngineClearSpectralEdits>('ghita_engine_clear_spectral_edits'));
    getTimelineRms = _tryLookup('ghita_engine_get_timeline_rms', () => _lib.lookupFunction<CGhitaEngineGetTimelineRms, DartGhitaEngineGetTimelineRms>('ghita_engine_get_timeline_rms'));
    detectTempo = _tryLookup('ghita_engine_detect_tempo', () => _lib.lookupFunction<CGhitaEngineDetectTempo, DartGhitaEngineDetectTempo>('ghita_engine_detect_tempo'));
    setTimeSignature = _tryLookup('ghita_engine_set_time_signature', () => _lib.lookupFunction<CGhitaEngineSetTimeSignature, DartGhitaEngineSetTimeSignature>('ghita_engine_set_time_signature'));
    getBeatTimes = _tryLookup('ghita_engine_get_beat_times', () => _lib.lookupFunction<CGhitaEngineGetBeatTimes, DartGhitaEngineGetBeatTimes>('ghita_engine_get_beat_times'));
    setLoopRegion = _tryLookup('ghita_engine_set_loop_region', () => _lib.lookupFunction<CGhitaEngineSetLoopRegion, DartGhitaEngineSetLoopRegion>('ghita_engine_set_loop_region'));
    setClipPitch = _tryLookup('ghita_engine_set_clip_pitch', () => _lib.lookupFunction<CGhitaEngineSetClipPitch, DartGhitaEngineSetClipPitch>('ghita_engine_set_clip_pitch'));
    setPreviewPitchPreserve = _tryLookup('ghita_engine_set_preview_pitch_preserve', () => _lib.lookupFunction<CGhitaEngineSetPreviewPitchPreserve, DartGhitaEngineSetPreviewPitchPreserve>('ghita_engine_set_preview_pitch_preserve'));
    startRecording = _tryLookup('ghita_engine_start_recording', () => _lib.lookupFunction<CGhitaEngineStartRecording, DartGhitaEngineStartRecording>('ghita_engine_start_recording'));
    stopRecording = _tryLookup('ghita_engine_stop_recording', () => _lib.lookupFunction<CGhitaEngineStopRecording, DartGhitaEngineStopRecording>('ghita_engine_stop_recording'));
    isRecording = _tryLookup('ghita_engine_is_recording', () => _lib.lookupFunction<CGhitaEngineIsRecording, DartGhitaEngineIsRecording>('ghita_engine_is_recording'));
    exportLabels = _tryLookup('ghita_engine_export_labels', () => _lib.lookupFunction<CGhitaEngineExportLabels, DartGhitaEngineExportLabels>('ghita_engine_export_labels'));
    // v1.5.0-T5: effect-param live edit + performance telemetry.
    setAudioEffectParam = _tryLookup('ghita_engine_set_audio_effect_param', () => _lib.lookupFunction<CGhitaEngineSetAudioEffectParam, DartGhitaEngineSetAudioEffectParam>('ghita_engine_set_audio_effect_param'));
    getCacheStats = _tryLookup('ghita_engine_cache_stats', () => _lib.lookupFunction<CGhitaEngineCacheStats, DartGhitaEngineCacheStats>('ghita_engine_cache_stats'));
    getGpuStats = _tryLookup('ghita_engine_gpu_stats', () => _lib.lookupFunction<CGhitaEngineGpuStats, DartGhitaEngineGpuStats>('ghita_engine_gpu_stats'));
    setClipStickerTransform = _tryLookup('ghita_engine_set_clip_sticker_transform', () => _lib.lookupFunction<CGhitaEngineSetClipStickerTransform, DartGhitaEngineSetClipStickerTransform>('ghita_engine_set_clip_sticker_transform'));
    paintClone = _tryLookup('ghita_engine_paint_clone', () => _lib.lookupFunction<CGhitaEnginePaintClone, DartGhitaEnginePaintClone>('ghita_engine_paint_clone'));
    paintHeal = _tryLookup('ghita_engine_paint_heal', () => _lib.lookupFunction<CGhitaEnginePaintHeal, DartGhitaEnginePaintHeal>('ghita_engine_paint_heal'));
    paintBrushStroke = _tryLookup('ghita_engine_paint_brush_stroke', () => _lib.lookupFunction<CGhitaEnginePaintBrushStroke, DartGhitaEnginePaintBrushStroke>('ghita_engine_paint_brush_stroke'));

    // ========== v1.5.0 T5: SQLite Project Database — defensive lookups (sqlite feature). ==========
    projectDbSave = _tryLookup('ghita_project_db_save', () => _lib.lookupFunction<CGhitaProjectDbSave, DartGhitaProjectDbSave>('ghita_project_db_save'));
    projectDbLoad = _tryLookup('ghita_project_db_load', () => _lib.lookupFunction<CGhitaProjectDbLoad, DartGhitaProjectDbLoad>('ghita_project_db_load'));
    projectDbList = _tryLookup('ghita_project_db_list', () => _lib.lookupFunction<CGhitaProjectDbList, DartGhitaProjectDbList>('ghita_project_db_list'));
    projectDbDelete = _tryLookup('ghita_project_db_delete', () => _lib.lookupFunction<CGhitaProjectDbDelete, DartGhitaProjectDbDelete>('ghita_project_db_delete'));
    projectDbLibraryAdd = _tryLookup('ghita_project_db_library_add', () => _lib.lookupFunction<CGhitaProjectDbLibraryAdd, DartGhitaProjectDbLibraryAdd>('ghita_project_db_library_add'));
    projectDbLibrarySearch = _tryLookup('ghita_project_db_library_search', () => _lib.lookupFunction<CGhitaProjectDbLibrarySearch, DartGhitaProjectDbLibrarySearch>('ghita_project_db_library_search'));
    projectDbLibraryUpdateRating = _tryLookup('ghita_project_db_library_update_rating', () => _lib.lookupFunction<CGhitaProjectDbLibraryUpdateRating, DartGhitaProjectDbLibraryUpdateRating>('ghita_project_db_library_update_rating'));
    projectDbLibraryUpdateTags = _tryLookup('ghita_project_db_library_update_tags', () => _lib.lookupFunction<CGhitaProjectDbLibraryUpdateTags, DartGhitaProjectDbLibraryUpdateTags>('ghita_project_db_library_update_tags'));

    // ========== v1.5.0 T6: Selection Tools — defensive lookups. ==========
    setSelectionRect = _tryLookup('ghita_engine_set_selection_rect', () => _lib.lookupFunction<CGhitaEngineSetSelectionRect, DartGhitaEngineSetSelectionRect>('ghita_engine_set_selection_rect'));
    setSelectionEllipse = _tryLookup('ghita_engine_set_selection_ellipse', () => _lib.lookupFunction<CGhitaEngineSetSelectionEllipse, DartGhitaEngineSetSelectionEllipse>('ghita_engine_set_selection_ellipse'));
    setSelectionLasso = _tryLookup('ghita_engine_set_selection_lasso', () => _lib.lookupFunction<CGhitaEngineSetSelectionLasso, DartGhitaEngineSetSelectionLasso>('ghita_engine_set_selection_lasso'));
    setSelectionMagicWand = _tryLookup('ghita_engine_set_selection_magic_wand', () => _lib.lookupFunction<CGhitaEngineSetSelectionMagicWand, DartGhitaEngineSetSelectionMagicWand>('ghita_engine_set_selection_magic_wand'));
    modifyMask = _tryLookup('ghita_engine_modify_mask', () => _lib.lookupFunction<CGhitaEngineModifyMask, DartGhitaEngineModifyMask>('ghita_engine_modify_mask'));
    getMaskBuffer = _tryLookup('ghita_engine_get_mask_buffer', () => _lib.lookupFunction<CGhitaEngineGetMaskBuffer, DartGhitaEngineGetMaskBuffer>('ghita_engine_get_mask_buffer'));
    clearSelection = _tryLookup('ghita_engine_clear_selection', () => _lib.lookupFunction<CGhitaEngineClearSelection, DartGhitaEngineClearSelection>('ghita_engine_clear_selection'));
  }

  // v1.0.1: Stub implementations for v0.8.0 bindings that may be absent
  // from older DLLs. Each stub matches the native function signature and
  // returns a "not available" sentinel so callers can degrade gracefully.
  static int _upsertClipStub(Pointer<GhitaEngineContext> ctx, int clipId, Pointer<Utf8> filePath, int startMs, int durationMs, int sourceInMs, int trackIndex, int kind, double volume, double opacity, double speed) => 0;
  static void _clearClipsStub(Pointer<GhitaEngineContext> ctx) {}
  static int _setTrackStateStub(Pointer<GhitaEngineContext> ctx, int trackIndex, int muted, int visible, double volume) => 0;
  static int _setClipColorCorrectionStub(Pointer<GhitaEngineContext> ctx, int clipId, double exposure, double contrast, double saturation, double temperature, double tint, double vibrance, double highlights, double shadows) => 0;
  static int _setClipTextStub(Pointer<GhitaEngineContext> ctx, int clipId, Pointer<Utf8> text, double fontSize, int colorArgb) => 0;
  static int _hasClipStub(Pointer<GhitaEngineContext> ctx, int clipId) => 0;

  /// v0.7.8: Resolve a symbol defensively — returns null instead of throwing
  /// when the DLL doesn't export it. Without this, one stale binding silently
  /// disabled the entire native engine (Demo Mode even with DLL present).
  /// v1.0.2: Catch the full exception family (ArgumentError for missing
  /// symbols, plus any other FFI errors) so a single bad lookup can never
  /// take down the whole binding layer.
  T? _tryLookup<T extends Function>(String symbol, T Function() doLookup) {
    try {
      return doLookup();
    } on ArgumentError {
      debugPrint('FFI: missing symbol in engine DLL: $symbol (feature disabled)');
      return null;
    } on Exception catch (e) {
      debugPrint('FFI: error resolving symbol $symbol: $e (feature disabled)');
      return null;
    } on Error catch (e) {
      debugPrint('FFI: error resolving symbol $symbol: $e (feature disabled)');
      return null;
    }
  }
}
