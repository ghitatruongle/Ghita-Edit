import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:ffi/ffi.dart';
import '../../controllers/editor_controller.dart';
import '../../models/clip.dart';
import '../theme/app_theme.dart';
import '../../ffi/native_bindings.dart';


/// Photoshop-style Pro Photo & Graphic Editor Studio Panel v1.0.0.
class PhotoEditorPanel extends StatefulWidget {
  final EditorController controller;

  const PhotoEditorPanel({
    super.key,
    required this.controller,
  });

  @override
  State<PhotoEditorPanel> createState() => _PhotoEditorPanelState();
}

class _PhotoEditorPanelState extends State<PhotoEditorPanel> {
  double _exposure = 0.0;
  double _contrast = 0.0;
  double _saturation = 0.0;
  double _vibrance = 0.0;
  double _temperature = 0.0;
  bool _bgRemoved = false;
  // v1.1.0 (PLAN 3.9): Real rendered preview frame + export state.
  Uint8List? _previewBytes;
  bool _exporting = false;
  // v1.0.1: Track which clip the local slider values belong to so we can
  // reset them when a different clip is selected.
  String? _activeClipId;

  // v1.5.0 T6-P6: Photo tools state.
  String _selectionTool = 'none';
  bool _cloneMode = false;
  bool _healMode = false;
  bool _brushMode = false;
  String _filmSim = 'none';

  // v1.5.0-T5 (P6): lasso drag points in canvas space (x,y interleaved,
  // canvas = the 560×360 preview).
  final List<double> _lassoPts = [];

  void _lassoStart(PointerDownEvent e) {
    _lassoPts
      ..clear()
      ..addAll([e.localPosition.dx, e.localPosition.dy]);
    setState(() {});
  }

  void _lassoMove(PointerMoveEvent e) {
    if (_lassoPts.isEmpty) return;
    setState(() => _lassoPts.addAll([e.localPosition.dx, e.localPosition.dy]));
  }

  void _lassoEnd(PointerUpEvent e) {
    final n = _lassoPts.length ~/ 2;
    if (n < 3) {
      _lassoPts.clear();
      return;
    }
    final b = GhitaNativeBindings.instance;
    final xs = calloc<Int32>(n);
    final ys = calloc<Int32>(n);
    for (var i = 0; i < n; i++) {
      xs[i] = _lassoPts[i * 2].round().clamp(0, 559);
      ys[i] = _lassoPts[i * 2 + 1].round().clamp(0, 359);
    }
    try {
      b.setSelectionLasso?.call(560, 360, xs, ys, n, 0);
    } catch (_) {}
    calloc.free(xs);
    calloc.free(ys);
    setState(() {});
  }

  void _wandTap(TapUpDetails d) {
    final bytes = _previewBytes;
    if (bytes == null || bytes.length < 560 * 360 * 4) return;
    final p = calloc<Uint8>(bytes.length);
    p.asTypedList(bytes.length).setAll(0, bytes);
    try {
      GhitaNativeBindings.instance.setSelectionMagicWand?.call(
        560,
        360,
        d.localPosition.dx.round().clamp(0, 559),
        d.localPosition.dy.round().clamp(0, 359),
        32,
        p,
        0,
      );
    } catch (_) {} finally {
      calloc.free(p);
    }
  }

  // v1.5.0-T5 (P6): Clone/Heal/Brush — real paint-tool FFI on the preview
  // buffer. Clone samples a source point on pointer-down, then paints with
  // the preserved delta while dragging.
  Offset? _cloneSample;
  Offset? _clonePaintOrigin;
  final List<Offset> _brushPts = [];

  void _refreshPreviewBytes(Uint8List updated) {
    setState(() => _previewBytes = Uint8List.fromList(updated));
  }

  void _withPreviewBuffer(void Function(Pointer<Uint8> buf) fn) {
    final bytes = _previewBytes;
    if (bytes == null || bytes.length < 560 * 360 * 4) return;
    final p = calloc<Uint8>(bytes.length);
    p.asTypedList(bytes.length).setAll(0, bytes);
    try {
      fn(p);
      _refreshPreviewBytes(p.asTypedList(bytes.length));
    } catch (_) {} finally {
      calloc.free(p);
    }
  }

  void _canvasPointerDown(PointerDownEvent e) {
    final pos = e.localPosition;
    if (_selectionTool == 'lasso') {
      _lassoStart(e);
    } else if (_cloneMode) {
      _cloneSample = pos;
      _clonePaintOrigin = pos;
      _applyCloneAt(pos);
    } else if (_healMode) {
      _applyHealAt(pos);
    } else if (_brushMode) {
      _brushPts..clear()..add(pos);
    }
  }

  void _canvasPointerMove(PointerMoveEvent e) {
    final pos = e.localPosition;
    if (_selectionTool == 'lasso') {
      _lassoMove(e);
    } else if (_cloneMode && _cloneSample != null && _clonePaintOrigin != null) {
      _applyCloneAt(pos);
    } else if (_healMode) {
      _applyHealAt(pos);
    } else if (_brushMode) {
      _brushPts.add(pos);
    }
  }

  void _canvasPointerUp(PointerUpEvent e) {
    if (_selectionTool == 'lasso') {
      _lassoEnd(e);
      return;
    }
    if (_brushMode && _brushPts.isNotEmpty) {
      _withPreviewBuffer((buf) {
        final n = _brushPts.length;
        final px = calloc<Float>(n);
        final py = calloc<Float>(n);
        for (var i = 0; i < n; i++) {
          px[i] = _brushPts[i].dx.clamp(0, 559);
          py[i] = _brushPts[i].dy.clamp(0, 359);
        }
        try {
          // Accent-pink stroke matching the panel highlight color.
          // v1.5.0-T6 debug fix: Rust packs color_rgba little-endian as
          // [R,G,B,A] — pass (A<<24)|(B<<16)|(G<<8)|R so the stroke is
          // #EC4899, not the R/B-swapped violet.
          const strokeColor = 0xFF9948EC;
          GhitaNativeBindings.instance.paintBrushStroke?.call(
            buf, 560, 360, px, py, n, 28.0, 0.6, 0.7, strokeColor);
        } catch (_) {} finally {
          calloc.free(px);
          calloc.free(py);
        }
      });
      _brushPts.clear();
    }
  }

  void _applyCloneAt(Offset dst) {
    final sample = _cloneSample;
    final origin = _clonePaintOrigin;
    if (sample == null || origin == null) return;
    final srcDx = (sample.dx - (origin.dx - dst.dx)).clamp(0.0, 559.0);
    final srcDy = (sample.dy - (origin.dy - dst.dy)).clamp(0.0, 359.0);
    _withPreviewBuffer((buf) {
      GhitaNativeBindings.instance.paintClone?.call(
        buf, 560, 360,
        srcDx.round(), srcDy.round(),
        dst.dx.round().clamp(0, 559), dst.dy.round().clamp(0, 359),
        24, 0.9);
    });
  }

  void _applyHealAt(Offset pos) {
    _withPreviewBuffer((buf) {
      GhitaNativeBindings.instance.paintHeal?.call(
        buf, 560, 360,
        pos.dx.round().clamp(0, 559), pos.dy.round().clamp(0, 359), 18);
    });
  }


  // v1.1.0 (PLAN 3.9): Render the selected clip's frame at its timeline
  // position (with filters/cc applied) into the canvas — the v1.0.0 canvas
  // was a fake placeholder icon.
  Future<void> _refreshPreview() async {
    final controller = widget.controller;
    final engine = controller.engineService;
    final clip = controller.selectedClip ?? controller.project.allClips.firstOrNull;
    if (!engine.isReady || clip == null) {
      if (mounted) setState(() => _previewBytes = null);
      return;
    }
    // Give the deferred engine sync a chance to register the clip.
    var nativeId = controller.nativeClipIdFor(clip.id);
    if (nativeId == null) {
      await Future<void>.delayed(const Duration(milliseconds: 300));
      nativeId = controller.nativeClipIdFor(clip.id);
    }
    if (nativeId == null || !mounted) return;
    final bytes = engine.renderFrameAt(clip.timelineStartMs, width: 560, height: 360);
    if (bytes == null || !mounted) return;
    setState(() => _previewBytes = bytes);
  }

  // v1.1.0 (PLAN 3.9): REAL PNG export — captures the rendered frame and
  // encodes it (the v1.0.0 button only claimed success in a snackbar).
  Future<void> _exportPng() async {
    final messenger = ScaffoldMessenger.of(context);
    final bytes = _previewBytes;
    if (bytes == null) {
      messenger.showSnackBar(const SnackBar(
          content: Text('No image loaded yet — import a photo first.')));
      return;
    }
    final result = await FilePicker.platform.saveFile(
      dialogTitle: 'Export Image',
      fileName: 'GhitaEdit_Photo.png',
      type: FileType.custom,
      allowedExtensions: ['png'],
    );
    if (result == null || !mounted) return;

    setState(() => _exporting = true);
    try {
      final completer = Completer<Uint8List>();
      ui.decodeImageFromPixels(
        bytes,
        560,
        360,
        ui.PixelFormat.rgba8888,
        (ui.Image img) async {
          try {
            final data = await img.toByteData(format: ui.ImageByteFormat.png);
            img.dispose();
            completer.complete(data!.buffer.asUint8List());
          } catch (e) {
            img.dispose();
            completer.completeError(e);
          }
        },
      );
      final png = await completer.future;
      await File(result).writeAsBytes(png);
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
        content: Text('Exported PNG (${(png.length / 1024).toStringAsFixed(0)} KB)'),
        backgroundColor: Colors.green,
      ));
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(
            content: Text('Export failed: $e'), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _pickImageFile() async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['png', 'jpg', 'jpeg', 'bmp', 'webp', 'gif'],
    );
    if (result != null && result.files.single.path != null && mounted) {
      await widget.controller.importPhotoToStudio(result.files.single.path!);
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Imported Photo Layer: ${result.files.single.name}')),
      );
    }
  }

  void _applyColorCorrection() {
    final sel = widget.controller.selectedClip ?? widget.controller.project.allClips.firstOrNull;
    if (sel != null) {
      // v1.0.2: NO beginPropertyGesture() here — it was called on every
      // slider tick, giving each tick a fresh gestureId so coalescing never
      // engaged and a single drag pushed dozens of undo entries (evicting
      // older commands from the 100-entry stack). The gesture now opens once
      // per drag via the slider's onChangeStart (see _buildSlider).
      widget.controller.setClipColorCorrection(
        sel.id,
        exposure: _exposure,
        contrast: _contrast,
        saturation: _saturation,
        vibrance: _vibrance,
        temperature: _temperature,
      );
    }
  }

  void _toggleBackgroundRemoval(bool value) {
    setState(() => _bgRemoved = value);
    final sel = widget.controller.selectedClip ?? widget.controller.project.allClips.firstOrNull;
    if (sel != null) {
      // Filter 22 is CapCut Chroma Key / BG Removal
      widget.controller.setClipFilter(sel.id, value ? 22 : 0, value ? 0.75 : 0.0);
    }
  }


  Widget _toolBtn(String label, IconData icon, bool active, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Tooltip(
        message: label,
        child: IconButton(
          onPressed: onTap,
          icon: Icon(icon, size: 18, color: active ? AppTheme.primary : AppTheme.textMuted),
          style: IconButton.styleFrom(
            backgroundColor: active ? AppTheme.primary.withValues(alpha: 0.15) : null,
            padding: const EdgeInsets.all(6),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final clips = widget.controller.project.allClips;
    final activeClip = widget.controller.selectedClip ?? clips.firstOrNull;

    // v1.0.1: When the selected clip changes, reset the local slider state
    // to reflect the new clip's actual color correction values. Previously
    // the sliders kept showing the previous clip's values.
    if (activeClip?.id != _activeClipId) {
      _activeClipId = activeClip?.id;
      if (activeClip != null) {
        _exposure = activeClip.colorExposure;
        _contrast = activeClip.colorContrast;
        _saturation = activeClip.colorSaturation;
        _vibrance = activeClip.colorVibrance;
        _temperature = activeClip.colorTemperature;
        _bgRemoved = activeClip.filterType == 22;
      }
      // v1.1.0 (PLAN 3.9): Render the real frame for the canvas.
      _refreshPreview();
    }

    return Container(
      color: AppTheme.background,
      child: Column(
        children: [
          // Header Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: const BoxDecoration(
              color: AppTheme.surface,
              border: Border(bottom: BorderSide(color: AppTheme.divider)),
            ),
            child: Row(
              children: [
                const Icon(Icons.photo_filter, color: AppTheme.accentLight, size: 20),
                const SizedBox(width: 8),
                // v1.1.0 (PLAN_REVIEW A.2): Flexible + ellipsis — the header
                // overflowed 245px on narrow panels.
                const Flexible(
                  child: Text(
                    '🎨 PHOTO EDITOR STUDIO (PHOTOSHOP MODE)',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppTheme.textMain,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      letterSpacing: 1.0,
                    ),
                  ),
                ),
                const Spacer(),

                // Import Image File Button
                ElevatedButton.icon(
                  onPressed: _pickImageFile,
                  icon: const Icon(Icons.add_photo_alternate_rounded, size: 14),
                  label: const Text('📥 Import Photo Layer', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.card,
                    foregroundColor: AppTheme.accentLight,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    side: const BorderSide(color: AppTheme.accent),
                  ),
                ),
                const SizedBox(width: 12),

                ElevatedButton.icon(
                  // v1.1.0 (PLAN 3.9): REAL PNG export.
                  onPressed: _exporting ? null : _exportPng,
                  icon: _exporting
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.file_download, size: 14),
                  label: Text(_exporting ? 'EXPORTING…' : 'EXPORT PNG',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 11)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.accent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6)),
                  ),
                ),
              ],
            ),
          ),

          // Main Studio Body
          // v1.5.0 T6-P6: Photo Tools Toolbar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: const BoxDecoration(
              color: AppTheme.surface,
              border: Border(bottom: BorderSide(color: AppTheme.divider)),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  const Text('Tools:', style: TextStyle(color: AppTheme.textMuted, fontSize: 10, fontWeight: FontWeight.bold)),
                  const SizedBox(width: 6),
                  _toolBtn('Rect', Icons.crop_square_outlined, _selectionTool == 'rect', () {
                    setState(() => _selectionTool = _selectionTool == 'rect' ? 'none' : 'rect');
                    try { GhitaNativeBindings.instance.setSelectionRect?.call(560, 360, 0, 0, 100, 100, 0); } catch (_) {}
                  }),
                  _toolBtn('Ellipse', Icons.circle_outlined, _selectionTool == 'ellipse', () {
                    setState(() => _selectionTool = _selectionTool == 'ellipse' ? 'none' : 'ellipse');
                    try { GhitaNativeBindings.instance.setSelectionEllipse?.call(560, 360, 50, 50, 40, 40, 0); } catch (_) {}
                  }),
                  _toolBtn('Lasso', Icons.gesture_outlined, _selectionTool == 'lasso', () {
                    setState(() => _selectionTool = _selectionTool == 'lasso' ? 'none' : 'lasso');
                  }),
                  _toolBtn('Wand', Icons.auto_fix_high_outlined, _selectionTool == 'wand', () {
                    setState(() => _selectionTool = _selectionTool == 'wand' ? 'none' : 'wand');
                  }),
                  const SizedBox(width: 8),
                  const SizedBox(width: 1, height: 20, child: ColoredBox(color: AppTheme.divider)),
                  const SizedBox(width: 8),
                  _toolBtn('Clone', Icons.copy_outlined, _cloneMode, () => setState(() => _cloneMode = !_cloneMode)),
                  _toolBtn('Heal', Icons.healing_outlined, _healMode, () => setState(() => _healMode = !_healMode)),
                  _toolBtn('Brush', Icons.brush_outlined, _brushMode, () => setState(() => _brushMode = !_brushMode)),
                  const SizedBox(width: 8),
                  const SizedBox(width: 1, height: 20, child: ColoredBox(color: AppTheme.divider)),
                  const SizedBox(width: 8),
                  SizedBox(
                    height: 28,
                    child: OutlinedButton.icon(
                      onPressed: () { try { GhitaNativeBindings.instance.clearSelection?.call(); } catch (_) {} },
                      icon: const Icon(Icons.clear, size: 14),
                      label: const Text('Clear', style: TextStyle(fontSize: 10)),
                      style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8), side: const BorderSide(color: AppTheme.divider)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  DropdownButton<String>(
                    value: _filmSim,
                    dropdownColor: AppTheme.surface,
                    style: const TextStyle(color: AppTheme.textMain, fontSize: 10),
                    underline: const SizedBox.shrink(),
                    items: ['none','Portra','Velvia','Cinematic'].map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                    onChanged: (v) => setState(() => _filmSim = v ?? 'none'),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: Row(
              children: [
                // Left Photo Tools & Adjustments
                Container(
                  width: 320,
                  padding: const EdgeInsets.all(16),
                  decoration: const BoxDecoration(
                    color: AppTheme.surface,
                    border: Border(right: BorderSide(color: AppTheme.divider)),
                  ),
                  child: ListView(
                    children: [
                      Text(
                        activeClip != null
                            ? '🎚️ COLOR & EXPOSURE (${activeClip.displayName})'
                            : '🎚️ COLOR & EXPOSURE ADJUSTMENTS',
                        style: const TextStyle(color: AppTheme.textMuted, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.0),
                      ),
                      const SizedBox(height: 16),

                      _buildSlider('Exposure', _exposure, -1.0, 1.0, (v) {
                        setState(() => _exposure = v);
                        _applyColorCorrection();
                      }, onChangeStart: (_) => widget.controller.beginPropertyGesture()),
                      _buildSlider('Contrast', _contrast, -1.0, 1.0, (v) {
                        setState(() => _contrast = v);
                        _applyColorCorrection();
                      }, onChangeStart: (_) => widget.controller.beginPropertyGesture()),
                      _buildSlider('Saturation', _saturation, -1.0, 1.0, (v) {
                        setState(() => _saturation = v);
                        _applyColorCorrection();
                      }, onChangeStart: (_) => widget.controller.beginPropertyGesture()),
                      _buildSlider('Vibrance', _vibrance, -1.0, 1.0, (v) {
                        setState(() => _vibrance = v);
                        _applyColorCorrection();
                      }, onChangeStart: (_) => widget.controller.beginPropertyGesture()),
                      _buildSlider('Temperature', _temperature, -1.0, 1.0, (v) {
                        setState(() => _temperature = v);
                        _applyColorCorrection();
                      }, onChangeStart: (_) => widget.controller.beginPropertyGesture()),

                      const SizedBox(height: 16),
                      const Divider(color: AppTheme.divider),
                      const SizedBox(height: 12),

                      const Text(
                        '🪄 AI PHOTO TOOLS',
                        style: TextStyle(color: AppTheme.textMuted, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.0),
                      ),
                      const SizedBox(height: 8),

                      // v1.1.0 (PLAN_REVIEW A.2): wrap in a transparent Material — the ListTile
                      // assertion requires it (parent Container paints a bg).
                      Material(
                        type: MaterialType.transparency,
                        child: SwitchListTile(
                          value: _bgRemoved,
                          onChanged: _toggleBackgroundRemoval,
                          activeThumbColor: AppTheme.accent,
                          title: const Text('Magic Cutout (Remove Background)', style: TextStyle(color: AppTheme.textMain, fontSize: 11, fontWeight: FontWeight.bold)),
                          subtitle: const Text('AI color distance transparency mask', style: TextStyle(color: AppTheme.textMuted, fontSize: 9)),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ],
                  ),
                ),

                // Center Image Canvas View
                Expanded(
                  child: Container(
                    color: const Color(0xFF0F1117),
                    child: Center(
                      child: Container(
                        width: 560,
                        height: 360,
                        decoration: BoxDecoration(
                          color: _bgRemoved ? Colors.transparent : Colors.black,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppTheme.primaryLight, width: 2),
                          boxShadow: AppTheme.shadowLg,
                        ),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            // v1.1.0 (PLAN 3.9): REAL rendered frame — the
                            // v1.0.0 canvas was a placeholder icon.
                            if (_previewBytes != null)
                              ClipRect(
                                // v1.5.0-T5 (P6): lasso drag-capture and
                                // magic-wand seeding now drive the REAL
                                // engine selection FFI (fixed in T1-P1);
                                // Clone/Heal/Brush drive the paint-tool FFI.
                                child: Listener(
                                  behavior: HitTestBehavior.translucent,
                                  onPointerDown: _canvasPointerDown,
                                  onPointerMove: _canvasPointerMove,
                                  onPointerUp: _canvasPointerUp,
                                  child: GestureDetector(
                                    behavior: HitTestBehavior.translucent,
                                    onTapUp: _selectionTool == 'wand' ? _wandTap : null,
                                    child: Image.memory(
                                      _previewBytes!,
                                      fit: BoxFit.contain,
                                      gaplessPlayback: true,
                                    ),
                                  ),
                                ),
                              )
                            else
                              Center(
                                child: Icon(
                                  activeClip?.type == ClipType.image
                                      ? Icons.image
                                      : Icons.videocam,
                                  size: 80,
                                  color: AppTheme.textMuted,
                                ),
                              ),
                            Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const SizedBox(height: 90),
                                  Text(
                                    activeClip != null
                                        ? '📷 EDITING: ${activeClip.displayName}'
                                        : 'PHOTOSHOP IMAGE CANVAS (4K READY)',
                                    style: const TextStyle(
                                        color: AppTheme.textMain,
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _bgRemoved
                                        ? '✨ BACKGROUND REMOVED (TRANSPARENT PNG)'
                                        : 'Color Correction & Layer FX Applied',
                                    style: const TextStyle(
                                        color: AppTheme.accentLight,
                                        fontSize: 10),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                // Right Layers Panel
                Container(
                  width: 260,
                  padding: const EdgeInsets.all(12),
                  decoration: const BoxDecoration(
                    color: AppTheme.surface,
                    border: Border(left: BorderSide(color: AppTheme.divider)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          // v1.1.0 (PLAN_REVIEW A.2): Flexible + ellipsis —
                          // long "LAYERS STACK (n)" text overflowed narrow
                          // right panels.
                          Flexible(
                            child: Text(
                              '🥞 LAYERS STACK (${clips.length})',
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: AppTheme.textMuted, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.0),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.add_a_photo_outlined, size: 16, color: AppTheme.accentLight),
                            onPressed: _pickImageFile,
                            tooltip: 'Add Photo Layer',
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: clips.isEmpty
                            ? Center(
                                child: TextButton.icon(
                                  onPressed: _pickImageFile,
                                  icon: const Icon(Icons.add_photo_alternate, size: 16),
                                  label: const Text('Add Image Layer', style: TextStyle(fontSize: 11)),
                                ),
                              )
                            : ListView.separated(
                                itemCount: clips.length,
                                separatorBuilder: (_, __) => const SizedBox(height: 6),
                                itemBuilder: (context, idx) {
                                  final clip = clips[idx];
                                  final isSelected = activeClip?.id == clip.id;
                                  return InkWell(
                                    onTap: () {
                                      widget.controller.project.selectClip(clip.id);
                                      setState(() {});
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                      decoration: BoxDecoration(
                                        color: isSelected ? AppTheme.accent.withValues(alpha: 0.2) : AppTheme.card,
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(color: isSelected ? AppTheme.accent : AppTheme.divider),
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(
                                            clip.type == ClipType.image ? Icons.image : Icons.movie,
                                            size: 14,
                                            color: isSelected ? AppTheme.accentLight : AppTheme.textMuted,
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              clip.displayName,
                                              style: TextStyle(
                                                color: isSelected ? AppTheme.textMain : AppTheme.textMuted,
                                                fontSize: 11,
                                                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSlider(String label, double val, double min, double max, ValueChanged<double> onChanged, {ValueChanged<double>? onChangeStart}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(color: AppTheme.textMain, fontSize: 11)),
            Text(val.toStringAsFixed(2), style: const TextStyle(color: AppTheme.accentLight, fontSize: 10, fontFamily: 'monospace')),
          ],
        ),
        SliderTheme(
          data: SliderThemeData(
            trackHeight: 2,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
            activeTrackColor: AppTheme.accent,
            inactiveTrackColor: AppTheme.divider,
            thumbColor: AppTheme.accentLight,
          ),
          child: Slider(
            value: val.clamp(min, max),
            min: min,
            max: max,
            onChanged: onChanged,
            // v1.0.2: Open the undo gesture once at drag start so all ticks
            // of one drag coalesce into a single undo entry.
            onChangeStart: onChangeStart,
          ),
        ),
      ],
    );
  }
}
