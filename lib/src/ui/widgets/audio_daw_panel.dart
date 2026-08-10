import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../../controllers/editor_controller.dart';
import '../../models/clip.dart';
import '../theme/app_theme.dart';

/// Audacity & Adobe Audition style Pro Audio DAW Studio Panel v1.0.0.
class AudioDawPanel extends StatefulWidget {
  final EditorController controller;

  const AudioDawPanel({
    super.key,
    required this.controller,
  });

  @override
  State<AudioDawPanel> createState() => _AudioDawPanelState();
}

class _AudioDawPanelState extends State<AudioDawPanel> {
  double _masterVolume = 1.0;
  // v1.1.0 (PLAN 3.12): EQ + presets disabled (not wired) — kept as const-ish
  // display state per the honest-label approach.
  final double _bassGain = 0.0;
  final double _trebleGain = 0.0;
  bool _noiseReduction = false;
  final String _activePreset = 'Vocal Polish';
  // v1.1.0 (PLAN 3.8): Real MP3 export state + timer.
  bool _exporting = false;
  Timer? _exportTimer;

  // v1.1.0 (PLAN 3.8): REAL timeline waveform samples (from the engine mix
  // pipeline, not the fake pattern the v1.0.0 painter drew).
  Float32List _waveform = Float32List(0);
  int _waveformVersion = -1;

  @override
  void dispose() {
    _exportTimer?.cancel();
    super.dispose();
  }

  // v1.1.0 (PLAN 3.8): Fetch the real timeline waveform — the engine-side
  // cache makes repeated builds cheap; invalidated on timeline changes.
  Float32List _fetchWaveform() {
    final version = widget.controller.commandHistory.undoCount +
        widget.controller.project.allClips.length * 1000;
    if (version == _waveformVersion) return _waveform;
    final samples =
        widget.controller.engineService.getTimelineWaveform(240, 0);
    _waveform = samples;
    _waveformVersion = version;
    return _waveform;
  }

  // v1.1.0 (PLAN 3.8): REAL MP3 export through the native engine — the
  // v1.0.0 button only showed a fake "Mastered & Ready" snackbar.
  Future<void> _exportMasteredAudio() async {
    final engine = widget.controller.engineService;
    final messenger = ScaffoldMessenger.of(context);
    if (!engine.isReady) {
      messenger.showSnackBar(
          const SnackBar(content: Text('Native engine not available.')));
      return;
    }
    final result = await FilePicker.platform.saveFile(
      dialogTitle: 'Export Mastered Audio',
      fileName: 'GhitaEdit_Mastered.mp3',
      type: FileType.custom,
      allowedExtensions: ['mp3'],
    );
    if (result == null || !mounted) return;

    final ok = engine.startExportEx(result, 0, 0, 0, 'mp3', 192000, true);
    if (!ok) {
      messenger.showSnackBar(const SnackBar(
          content: Text('Export failed to start.'), backgroundColor: Colors.red));
      return;
    }
    setState(() => _exporting = true);
    _exportTimer?.cancel();
    _exportTimer = Timer.periodic(const Duration(milliseconds: 150), (timer) {
      if (engine.isExporting) return;
      timer.cancel();
      if (!mounted) return;
      final size = engine.getExportFileSize();
      setState(() => _exporting = false);
      messenger.showSnackBar(SnackBar(
        content: Text(size > 0
            ? 'Exported MP3 (${(size / (1024 * 1024)).toStringAsFixed(1)} MB)'
            : 'Export failed — check the output path.'),
        backgroundColor: size > 0 ? Colors.green : Colors.red,
      ));
    });
  }

  static const _presets = [
    'Default (Flat)',
    'Vocal Polish',
    'Bass Boost',
    'Podcast Clarity',
    'Studio Warmth',
    'Noise Suppress',
  ];

  Future<void> _pickAudioFile() async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['mp3', 'wav', 'flac', 'aac', 'ogg', 'm4a', 'mp4'],
    );
    if (result != null && result.files.single.path != null && mounted) {
      await widget.controller.importAudioToDaw(result.files.single.path!);
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Imported Audio: ${result.files.single.name}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final audioClips = widget.controller.project.allClips
        .where((c) => c.type == ClipType.audio || c.type == ClipType.video)
        .toList();

    return Container(
      color: AppTheme.background,
      child: Column(
        children: [
          // DAW Header Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: const BoxDecoration(
              color: AppTheme.surface,
              border: Border(bottom: BorderSide(color: AppTheme.divider)),
            ),
            child: Row(
              children: [
                const Icon(Icons.equalizer, color: AppTheme.primaryLight, size: 20),
                const SizedBox(width: 8),
                // v1.1.0 (PLAN_REVIEW A.2): Flexible + ellipsis — the header
                // overflowed 154px on narrow panels (RenderFlex overflow).
                const Flexible(
                  child: Text(
                    '🎙️ AUDIO DAW STUDIO',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppTheme.textMain,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      letterSpacing: 1.0,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                // v1.1.0 (PLAN_REVIEW A.2): Flexible — badge must ellipsize on narrow panels.
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: AppTheme.primary.withValues(alpha: 0.3)),
                    ),
                    child: Text(
                      // v1.0.0: Be honest — this panel does preview/editing only,
                      // no actual DSP/effects yet (EQ/noise reduction are local
                      // params in this build). Real sample-accurate processing
                      // is on the Phase 3 roadmap.
                      'Audio Editor Preview',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: AppTheme.primaryLight, fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                const Spacer(),

                // Import Audio File Button
                ElevatedButton.icon(
                  onPressed: _pickAudioFile,
                  icon: const Icon(Icons.library_music_rounded, size: 14),
                  label: const Text('📥 Import Audio', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.card,
                    foregroundColor: AppTheme.primaryLight,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    side: const BorderSide(color: AppTheme.primary),
                  ),
                ),
                const SizedBox(width: 12),

                // Presets Dropdown — v1.1.0 (PLAN 3.12): DISABLED — selecting a preset
                // never applied any DSP (the engine has no EQ); honest
                // until presets are wired to real processing.
                DropdownButton<String>(
                  value: _activePreset,
                  dropdownColor: AppTheme.surface,
                  style: const TextStyle(color: AppTheme.textMain, fontSize: 11),
                  underline: const SizedBox.shrink(),
                  icon: const Icon(Icons.arrow_drop_down, color: AppTheme.textMuted),
                  items: _presets
                      .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                      .toList(),
                  onChanged: null,
                ),
              ],
            ),
          ),

          // Main DAW Body
          Expanded(
            child: Row(
              children: [
                // Left Controls: Parametric EQ & DSP Controls
                Container(
                  width: 320,
                  padding: const EdgeInsets.all(16),
                  decoration: const BoxDecoration(
                    color: AppTheme.surface,
                    border: Border(right: BorderSide(color: AppTheme.divider)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '🎛️ STUDIO DSP FX PROCESSOR',
                        style: TextStyle(color: AppTheme.textMuted, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.0),
                      ),
                      const SizedBox(height: 16),

                      // Master Gain Slider
                      _buildSliderRow('Master Gain', _masterVolume, 0.0, 2.0, (val) {
                        setState(() => _masterVolume = val);
                        widget.controller.setVolume(val);
                      }, suffix: '${(_masterVolume * 100).toInt()}%'),

                      const SizedBox(height: 12),

                      // Bass Boost Slider
                      // v1.1.0 (PLAN 3.8): Honest label — the EQ is NOT
                      // wired to the mixer yet (no DSP in the engine); the
                      // sliders are disabled instead of pretending to work.
                      _buildSliderRow('Bass Boost (Low EQ)', _bassGain, -12.0, 12.0, null,
                          suffix: '${_bassGain > 0 ? "+" : ""}${_bassGain.toStringAsFixed(1)} dB',
                          disabledNote: 'EQ not wired yet (DSP roadmap)'),

                      const SizedBox(height: 12),

                      // Treble Slider
                      _buildSliderRow('Treble (High EQ)', _trebleGain, -12.0, 12.0, null,
                          suffix: '${_trebleGain > 0 ? "+" : ""}${_trebleGain.toStringAsFixed(1)} dB',
                          disabledNote: 'EQ not wired yet (DSP roadmap)'),

                      const SizedBox(height: 20),
                      const Divider(color: AppTheme.divider),
                      const SizedBox(height: 12),

                      // Spectral Noise Reduction Switch
                      // v1.0.3: Now WIRED to the native mixer — previously a
                      // UI-only toggle that did nothing ("làm rõ âm thanh ko
                      // hoạt động"). The engine applies a DC blocker/low-cut
                      // to the preview mix when enabled.
                      // v1.1.0 (PLAN_REVIEW A.2): wrapped in a transparent
                      // Material — the ListTile assertion requires it (the
                      // parent Container paints a background).
                      Material(
                        type: MaterialType.transparency,
                        child: SwitchListTile(
                          value: _noiseReduction,
                          onChanged: (val) {
                            setState(() => _noiseReduction = val);
                            widget.controller.setNoiseSuppress(val);
                          },
                          activeThumbColor: AppTheme.primary,
                          title: const Text('Spectral Noise Reduction', style: TextStyle(color: AppTheme.textMain, fontSize: 12, fontWeight: FontWeight.bold)),
                          subtitle: const Text('Suppress mic hum & ambient noise', style: TextStyle(color: AppTheme.textMuted, fontSize: 10)),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),

                      const Spacer(),

                      // Export Audio Action Button
                      // v1.1.0 (PLAN 3.8): REAL export through the engine.
                      SizedBox(
                        width: double.infinity,
                        height: 38,
                        child: ElevatedButton.icon(
                          onPressed: _exporting ? null : _exportMasteredAudio,
                          icon: _exporting
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white))
                              : const Icon(Icons.file_download, size: 16),
                          label: Text(
                              _exporting ? 'EXPORTING…' : 'EXPORT MASTERED AUDIO (MP3)',
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 11)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primary,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(6)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Right Area: Multi-Track DAW Visualizer
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            // v1.1.0 (PLAN_REVIEW A.2): Expanded — the long
                            // header text overflowed 565px on narrow panels.
                            Expanded(
                              child: Text(
                                '📊 MULTI-TRACK AUDIO WAVEFORM SPECTRUM (${audioClips.length} Audio/Video Track Clips)',
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: AppTheme.textMuted, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.0),
                              ),
                            ),
                            if (audioClips.isEmpty)
                              TextButton.icon(
                                onPressed: _pickAudioFile,
                                icon: const Icon(Icons.add, size: 14),
                                label: const Text('Add Audio Track', style: TextStyle(fontSize: 11)),
                              ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              color: AppTheme.card,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: AppTheme.divider),
                            ),
                            child: Stack(
                              children: [
                                CustomPainterWidget(
                                  painter: _DawWaveformPainter(
                                    // v1.1.0 (PLAN 3.8): REAL waveform data.
                                    samples: _fetchWaveform(),
                                    positionRatio: widget.controller.durationMs > 0
                                        ? widget.controller.positionMs / widget.controller.durationMs
                                        : 0.0,
                                  ),
                                ),
                                if (audioClips.isEmpty)
                                  Center(
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        const Icon(Icons.audiotrack_rounded, color: AppTheme.textMuted, size: 48),
                                        const SizedBox(height: 12),
                                        const Text('No Audio Clips in Project', style: TextStyle(color: AppTheme.textMain, fontWeight: FontWeight.bold)),
                                        const SizedBox(height: 4),
                                        const Text('Click "Import Audio" to load music, voiceover or sound FX', style: TextStyle(color: AppTheme.textMuted, fontSize: 11)),
                                        const SizedBox(height: 16),
                                        ElevatedButton.icon(
                                          onPressed: _pickAudioFile,
                                          icon: const Icon(Icons.file_open_rounded, size: 14),
                                          label: const Text('Browse Audio Files'),
                                        ),
                                      ],
                                    ),
                                  )
                                else
                                  Positioned(
                                    top: 12,
                                    left: 12,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: Colors.black87,
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(color: AppTheme.primary),
                                      ),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: audioClips.take(4).map((c) => Text(
                                          '🎵 ${c.displayName} (${(c.durationMs / 1000).toStringAsFixed(1)}s)',
                                          style: const TextStyle(color: AppTheme.primaryLight, fontSize: 10, fontFamily: 'monospace'),
                                        )).toList(),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSliderRow(String label, double val, double min, double max,
      ValueChanged<double>? onChanged,
      {required String suffix, String disabledNote = ''}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.max,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(color: AppTheme.textMain, fontSize: 11, fontWeight: FontWeight.w600)),
            Text(suffix, style: const TextStyle(color: AppTheme.primaryLight, fontSize: 11, fontWeight: FontWeight.bold, fontFamily: 'monospace')),
          ],
        ),
        SliderTheme(
          data: SliderThemeData(
            trackHeight: 3,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            activeTrackColor: AppTheme.primary,
            inactiveTrackColor: AppTheme.divider,
            thumbColor: AppTheme.primaryLight,
          ),
          child: Slider(
            value: val.clamp(min, max),
            min: min,
            max: max,
            onChanged: onChanged, // null → disabled (honest: not wired yet)
          ),
        ),
        if (disabledNote.isNotEmpty)
          Text(disabledNote,
              style: const TextStyle(color: AppTheme.textMuted, fontSize: 9, fontStyle: FontStyle.italic)),
      ],
    );
  }
}

class CustomPainterWidget extends StatelessWidget {
  final CustomPainter painter;

  const CustomPainterWidget({super.key, required this.painter});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: painter,
      size: Size.infinite,
    );
  }
}

class _DawWaveformPainter extends CustomPainter {
  final Float32List samples;
  final double positionRatio;

  _DawWaveformPainter({required this.samples, required this.positionRatio});

  @override
  void paint(Canvas canvas, Size size) {
    final bgPaint = Paint()..color = const Color(0xFF14161F);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);

    final linePaint = Paint()
      ..color = const Color(0xFF3B82F6)
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;

    // v1.1.0 (PLAN 3.8): REAL waveform peaks from the engine mix pipeline.
    // The v1.0.0 painter drew a decorative repeating pattern (i % 7) that
    // had nothing to do with the audio.
    if (samples.isEmpty) return;

    final barWidth = 3.0;
    final centerY = size.height / 2;
    final n = samples.length;
    for (int i = 0; i < n; ++i) {
      final x = i * ((size.width - barWidth) / n);
      final s = samples[i].clamp(0.0, 1.0);
      final height = s * (size.height * 0.45);
      canvas.drawLine(
        Offset(x, centerY - height),
        Offset(x, centerY + height),
        linePaint,
      );
    }

    // Playhead line
    final playheadX = positionRatio * size.width;
    final playheadPaint = Paint()
      ..color = const Color(0xFFEC4899)
      ..strokeWidth = 2.0;
    canvas.drawLine(Offset(playheadX, 0), Offset(playheadX, size.height), playheadPaint);
  }

  @override
  bool shouldRepaint(covariant _DawWaveformPainter oldDelegate) {
    return oldDelegate.positionRatio != positionRatio ||
        oldDelegate.samples != samples;
  }
}
