import 'dart:io' show Directory;
import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../../controllers/editor_controller.dart';
import '../../models/clip.dart';
import '../theme/app_theme.dart';

/// v1.5.0 T4: Full DAW Studio Panel with real engine integration.
/// Effect chain, spectrogram, spectral brush, tempo/beats, recording,
/// loop region, label export, clip pitch, RMS meter.
class AudioDawPanel extends StatefulWidget {
  final EditorController controller;
  const AudioDawPanel({super.key, required this.controller});

  @override
  State<AudioDawPanel> createState() => _AudioDawPanelState();
}

class _AudioDawPanelState extends State<AudioDawPanel> {
  double _masterVolume = 1.0;
  bool _noiseReduction = false;
  bool _exporting = false;
  Timer? _exportTimer;
  Timer? _pollTimer;

  // Waveform / spectrogram cache
  Float32List _waveform = Float32List(0);
  int _waveformVersion = -1;
  Float32List _spectrogram = Float32List(0);
  int _specCols = 0;
  int _specBins = 0;
  int _spectrogramVersion = -1;

  // Effect chain
  final List<_EffectEntry> _effects = [];
  double _gainReductionDb = 0.0;

  // Tempo / beats
  int _detectedBpm = 0;
  int _timeSigNum = 4;
  int _timeSigDen = 4;
  List<int> _beatTimes = [];

  // Recording
  bool _recording = false;
  int _recMode = 0;
  int _recDurationMs = 0;
  DateTime? _recStartTime;

  // Loop region
  bool _loopEnabled = false;
  // v1.5.0-T5 (P6): editable loop bounds (were hardwired read-only values).
  int _loopStartMs = 0;
  int _loopEndMs = 5000;

  // Spectral brush
  bool _brushMode = false;

  // Clip pitch
  double _clipPitch = 0.0;
  bool _pitchPreserve = false;

  // RMS
  double _rmsLevel = 0.0;

  static const _effectNames = [
    'Compressor', 'Limiter', 'Noise Gate', 'Noise Reduction',
    'Bass & Treble', 'Distortion', 'Phaser', 'Reverb', 'Wah-Wah', 'Shelf Filter',
  ];

  @override
  void initState() {
    super.initState();
    _pollTimer = Timer.periodic(const Duration(milliseconds: 200), (_) => _poll());
  }

  @override
  void dispose() {
    _exportTimer?.cancel();
    _pollTimer?.cancel();
    // v1.5.0-T3 (P2): release the cached static spectrogram layer.
    _specStaticPicture?.dispose();
    _specStaticPicture = null;
    super.dispose();
  }

  void _poll() {
    if (!mounted) return;
    final e = widget.controller.engineService;
    if (!e.isReady) return;
    bool changed = false;
    final rec = e.isRecording();
    if (rec != _recording) {
      _recording = rec;
      _recStartTime = rec ? DateTime.now() : null;
      changed = true;
    }
    // Live duration from a local clock — the old "peek" called stopRecording()
    // every tick, which really killed the native recorder after ~200 ms.
    if (_recording && _recStartTime != null) {
      final elapsed = DateTime.now().difference(_recStartTime!).inMilliseconds;
      if (elapsed != _recDurationMs) {
        _recDurationMs = elapsed;
        changed = true;
      }
    }
    final gr = e.getGainReductionDb();
    if (gr != _gainReductionDb) { _gainReductionDb = gr; changed = true; }
    final rms = e.getTimelineRms(1, 0);
    if (rms.isNotEmpty && rms[0] != _rmsLevel) { _rmsLevel = rms[0]; changed = true; }
    if (changed) setState(() {});
  }

  Float32List _fetchWaveform() {
    final version = widget.controller.commandHistory.undoCount +
        widget.controller.project.allClips.length * 1000;
    if (version == _waveformVersion) return _waveform;
    _waveform = widget.controller.engineService.getTimelineWaveform(300, 0);
    _waveformVersion = version;
    return _waveform;
  }

  void _fetchSpectrogram() {
    final version = widget.controller.commandHistory.undoCount +
        widget.controller.project.allClips.length * 1000;
    if (version == _spectrogramVersion) return;
    const cols = 200;
    const bins = 64;
    final data = widget.controller.engineService.getSpectrogram(cols, bins, 0);
    if (data.isNotEmpty) {
      _spectrogram = Float32List.fromList(data);
      _specCols = cols;
      _specBins = bins;
      _spectrogramVersion = version;
    }
  }

  // v1.5.0-T3 (P2): the heavy static spectrogram layers (background, heat
  // map, waveform, beats, loop region) are recorded ONCE into a ui.Picture
  // per data/size change — playback ticks then cost one drawPicture + a
  // playhead line instead of ~12,800 drawRect allocations per repaint.
  ui.Picture? _specStaticPicture;
  int _specStaticKey = -1;

  void _ensureSpectrogramStaticLayer(double w, double h) {
    final durMs = widget.controller.durationMs;
    final key = Object.hash(
        _spectrogramVersion,
        _waveformVersion,
        _beatTimes.length,
        identityHashCode(_beatTimes),
        _loopEnabled,
        _loopStartMs,
        _loopEndMs,
        durMs,
        w.round(),
        h.round());
    if (key == _specStaticKey && _specStaticPicture != null) return;
    _specStaticKey = key;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    _SpectrogramStaticPainter(
      spectrogram: _spectrogram,
      cols: _specCols,
      bins: _specBins,
      waveform: _fetchWaveform(),
      beatTimes: _beatTimes,
      durationMs: durMs,
      loopEnabled: _loopEnabled,
      loopStartRatio: durMs > 0 ? _loopStartMs / durMs : 0.0,
      loopEndRatio: durMs > 0 ? _loopEndMs / durMs : 0.0,
    ).paint(canvas, Size(w, h));
    final picture = recorder.endRecording();
    _specStaticPicture?.dispose();
    _specStaticPicture = picture;
  }

  void _detectTempo() {
    final bpm = widget.controller.engineService.detectTempo();
    setState(() => _detectedBpm = bpm);
    if (bpm > 0) _refreshBeats();
  }

  void _refreshBeats() {
    _beatTimes = widget.controller.engineService.getBeatTimes(500);
  }

  Future<void> _exportMasteredAudio() async {
    final engine = widget.controller.engineService;
    final messenger = ScaffoldMessenger.of(context);
    if (!engine.isReady) {
      messenger.showSnackBar(const SnackBar(content: Text('Native engine not available.')));
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
      messenger.showSnackBar(const SnackBar(content: Text('Export failed to start.'), backgroundColor: Colors.red));
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
            : 'Export failed.'),
        backgroundColor: size > 0 ? Colors.green : Colors.red,
      ));
    });
  }

  Future<void> _pickAudioFile() async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['mp3', 'wav', 'flac', 'aac', 'ogg', 'm4a', 'mp4'],
    );
    if (result != null && result.files.single.path != null && mounted) {
      await widget.controller.importAudioToDaw(result.files.single.path!);
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('Imported: ${result.files.single.name}')));
    }
  }

  Future<void> _exportLabels() async {
    final result = await FilePicker.platform.saveFile(
      dialogTitle: 'Export Labels',
      fileName: 'labels.srt',
      type: FileType.custom,
      allowedExtensions: ['srt', 'vtt'],
    );
    if (result == null || !mounted) return;
    final format = result.endsWith('.vtt') ? 1 : 0;
    final ret = widget.controller.engineService.exportLabels(result, format);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ret >= 0 ? 'Labels exported.' : 'Export failed.'),
      backgroundColor: ret >= 0 ? Colors.green : Colors.red,
    ));
  }

  void _toggleRecording() {
    final e = widget.controller.engineService;
    if (!e.isReady) return;
    if (_recording) {
      e.stopRecording();
      setState(() => _recording = false);
    } else {
      final outPath = '${(widget.controller.project.filePath.isNotEmpty ? Directory(widget.controller.project.filePath).parent.path : '.')}/recording_${DateTime.now().millisecondsSinceEpoch}.wav';
      e.startRecording(outPath, _recMode, 0, 0, 0);
      _recStartTime = DateTime.now();
      _recDurationMs = 0;
      setState(() => _recording = true);
    }
  }

  void _addEffect(int type) {
    final ret = widget.controller.engineService.addAudioEffect(type, 0.5, 0.5, 0.5, 0.5);
    if (ret >= 0) {
      setState(() => _effects.add(_EffectEntry(type: type, index: ret)));
    }
  }

  void _removeEffect(int listIndex) {
    if (listIndex < 0 || listIndex >= _effects.length) return;
    final entry = _effects[listIndex];
    widget.controller.engineService.removeAudioEffect(entry.index);
    setState(() {
      // v1.5.0-T6 debug fix: the engine chain shifts later entries down by
      // one — mirror that locally or the param sliders (and close buttons)
      // retune the WRONG effect after any removal.
      for (final other in _effects) {
        if (other.index > entry.index) other.index--;
      }
      _effects.removeAt(listIndex);
    });
  }

  @override
  Widget build(BuildContext context) {
    _fetchSpectrogram();
    final audioClips = widget.controller.project.allClips
        .where((c) => c.type == ClipType.audio || c.type == ClipType.video)
        .toList();

    return Container(
      color: AppTheme.background,
      child: Column(
        children: [
          _buildHeader(audioClips),
          Expanded(
            child: Row(
              children: [
                _buildLeftSidebar(),
                Expanded(child: _buildCenterCanvas(audioClips)),
              ],
            ),
          ),
          _buildBottomBar(),
        ],
      ),
    );
  }

  Widget _buildHeader(List<Clip> audioClips) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        border: Border(bottom: BorderSide(color: AppTheme.divider)),
      ),
      child: Row(
        children: [
          const Icon(Icons.equalizer, color: AppTheme.primaryLight, size: 18),
          const SizedBox(width: 6),
          const Flexible(
            child: Text('🎙️ AUDIO DAW STUDIO', overflow: TextOverflow.ellipsis,
              style: TextStyle(color: AppTheme.textMain, fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 1.0)),
          ),
          const SizedBox(width: 12),
          ElevatedButton.icon(
            onPressed: _pickAudioFile,
            icon: const Icon(Icons.library_music_rounded, size: 13),
            label: const Text('Import', style: TextStyle(fontSize: 10)),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.card, foregroundColor: AppTheme.primaryLight,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              side: const BorderSide(color: AppTheme.primary),
            ),
          ),
          const SizedBox(width: 8),
          _RecordButton(recording: _recording, onPressed: _toggleRecording),
          const SizedBox(width: 8),
          _ToggleButton(
            label: 'Loop', active: _loopEnabled,
            onPressed: () {
              setState(() => _loopEnabled = !_loopEnabled);
              widget.controller.engineService.setLoopRegion(_loopStartMs, _loopEndMs, _loopEnabled);
            },
          ),
          // v1.5.0-T5 (P6): editable loop region — was hardwired 0..5000ms.
          if (_loopEnabled) ...[
            const SizedBox(width: 6),
            SizedBox(
              width: 120,
              child: Column(children: [
                SliderTheme(
                  data: const SliderThemeData(trackHeight: 2, thumbShape: RoundSliderThumbShape(enabledThumbRadius: 5)),
                  child: Slider(value: _loopStartMs.toDouble(), min: 0, max: (_loopEndMs - 100).clamp(100, 600000).toDouble(),
                    label: 'In ${_loopStartMs}ms',
                    onChanged: (v) {
                      setState(() => _loopStartMs = v.round());
                      widget.controller.engineService.setLoopRegion(_loopStartMs, _loopEndMs, true);
                    }),
                ),
                SliderTheme(
                  data: const SliderThemeData(trackHeight: 2, thumbShape: RoundSliderThumbShape(enabledThumbRadius: 5)),
                  child: Slider(value: _loopEndMs.toDouble(), min: (_loopStartMs + 100).clamp(100, 600000).toDouble(), max: 600000,
                    label: 'Out ${_loopEndMs}ms',
                    onChanged: (v) {
                      setState(() => _loopEndMs = v.round());
                      widget.controller.engineService.setLoopRegion(_loopStartMs, _loopEndMs, true);
                    }),
                ),
              ]),
            ),
          ],
          const SizedBox(width: 8),
          _ToggleButton(
            label: 'Brush', active: _brushMode,
            onPressed: () => setState(() => _brushMode = !_brushMode),
          ),
          const SizedBox(width: 8),
          TextButton.icon(
            onPressed: _exportLabels,
            icon: const Icon(Icons.subtitles, size: 13),
            label: const Text('Labels', style: TextStyle(fontSize: 10)),
          ),
          const Spacer(),
          if (_exporting)
            const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
          else
            ElevatedButton.icon(
              onPressed: _exportMasteredAudio,
              icon: const Icon(Icons.file_download, size: 13),
              label: const Text('Export MP3', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary, foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildLeftSidebar() {
    return Container(
      width: 260,
      padding: const EdgeInsets.all(12),
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        border: Border(right: BorderSide(color: AppTheme.divider)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('🎛️ EFFECT CHAIN', style: TextStyle(color: AppTheme.textMuted, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 1.0)),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.builder(
              itemCount: _effects.length,
              itemBuilder: (_, i) {
                final e = _effects[i];
                return ListTile(
                  dense: true, visualDensity: VisualDensity.compact,
                  leading: const Icon(Icons.audio_file, size: 14, color: AppTheme.primaryLight),
                  title: Text(_effectNames[e.type], style: const TextStyle(color: AppTheme.textMain, fontSize: 11)),
                  // v1.5.0-T5 (P6): live per-parameter editing (p0..p3) via
                  // ghita_engine_set_audio_effect_param — the chain entry no
                  // longer needs remove/re-add to change a value.
                  subtitle: SizedBox(
                    height: 22,
                    child: Row(children: List.generate(4, (pi) => Expanded(
                      child: Slider(
                        value: e.params[pi], min: 0, max: 1,
                        onChanged: (v) {
                          setState(() => e.params[pi] = v);
                          widget.controller.engineService.setAudioEffectParam(e.index, pi, v);
                        },
                      ),
                    ))),
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.close, size: 12), onPressed: () => _removeEffect(i),
                    color: AppTheme.textMuted, padding: EdgeInsets.zero, constraints: const BoxConstraints(),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<int>(
            decoration: const InputDecoration(
              labelText: 'Add Effect', labelStyle: TextStyle(color: AppTheme.textMuted, fontSize: 10),
              border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            ),
            dropdownColor: AppTheme.surface,
            style: const TextStyle(color: AppTheme.textMain, fontSize: 11),
            items: List.generate(_effectNames.length, (i) =>
              DropdownMenuItem(value: i, child: Text(_effectNames[i], style: const TextStyle(fontSize: 11)))),
            onChanged: (v) { if (v != null) _addEffect(v); },
          ),
          const SizedBox(height: 12),
          const Divider(color: AppTheme.divider, height: 1),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Gain Reduction', style: TextStyle(color: AppTheme.textMuted, fontSize: 10)),
              Text('${_gainReductionDb.toStringAsFixed(1)} dB',
                style: const TextStyle(color: AppTheme.primaryLight, fontSize: 10, fontFamily: 'monospace')),
            ],
          ),
          LinearProgressIndicator(
            value: (_gainReductionDb.abs() / 30.0).clamp(0.0, 1.0),
            backgroundColor: AppTheme.divider, color: AppTheme.primary, minHeight: 3,
          ),
          const SizedBox(height: 12),
          const Divider(color: AppTheme.divider, height: 1),
          const SizedBox(height: 8),
          const Text('Clip Pitch', style: TextStyle(color: AppTheme.textMuted, fontSize: 10)),
          SliderTheme(
            data: SliderThemeData(trackHeight: 2, thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
              activeTrackColor: AppTheme.primary, inactiveTrackColor: AppTheme.divider, thumbColor: AppTheme.primaryLight),
            child: Slider(value: _clipPitch, min: -12, max: 12,
              label: '${_clipPitch.toStringAsFixed(1)} st',
              onChanged: (v) {
                setState(() => _clipPitch = v);
                final selClip = widget.controller.selectedClip;
                if (selClip != null) {
                  // Clip ids are 'clip_<ts>_<n>' — resolve through the
                  // controller's native-id map (int.tryParse never matched).
                  final cid = widget.controller.nativeClipIdFor(selClip.id);
                  if (cid != null) widget.controller.engineService.setClipPitch(cid, v);
                }
              }),
          ),
          Material(type: MaterialType.transparency, child: SwitchListTile(
            value: _pitchPreserve, dense: true, visualDensity: VisualDensity.compact,
            contentPadding: EdgeInsets.zero,
            title: const Text('Pitch Preserve', style: TextStyle(color: AppTheme.textMain, fontSize: 10)),
            activeThumbColor: AppTheme.primary,
            onChanged: (v) {
              setState(() => _pitchPreserve = v);
              widget.controller.engineService.setPreviewPitchPreserve(v);
            },
          )),
          const SizedBox(height: 8),
          Material(type: MaterialType.transparency, child: SwitchListTile(
            value: _noiseReduction, dense: true, visualDensity: VisualDensity.compact,
            contentPadding: EdgeInsets.zero,
            title: const Text('Noise Suppress', style: TextStyle(color: AppTheme.textMain, fontSize: 10)),
            activeThumbColor: AppTheme.primary,
            onChanged: (v) {
              setState(() => _noiseReduction = v);
              widget.controller.setNoiseSuppress(v);
            },
          )),
          const SizedBox(height: 8),
          Row(children: [
            const Text('Master', style: TextStyle(color: AppTheme.textMuted, fontSize: 10)),
            Expanded(child: SliderTheme(
              data: SliderThemeData(trackHeight: 2, thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                activeTrackColor: AppTheme.primary, inactiveTrackColor: AppTheme.divider, thumbColor: AppTheme.primaryLight),
              child: Slider(value: _masterVolume, min: 0, max: 2,
                onChanged: (v) { setState(() => _masterVolume = v); widget.controller.setVolume(v); }),
            )),
            Text('${(_masterVolume * 100).toInt()}%', style: const TextStyle(color: AppTheme.primaryLight, fontSize: 9, fontFamily: 'monospace')),
          ]),
        ],
      ),
    );
  }

  Widget _buildCenterCanvas(List<Clip> audioClips) {
    return Container(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(
                '📊 SPECTROGRAM / WAVEFORM (${audioClips.length} tracks)',
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppTheme.textMuted, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.0),
              )),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: AppTheme.card, borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppTheme.divider),
              ),
              child: LayoutBuilder(builder: (_, constraints) {
                // v1.5.0-T3 (P2): record the heavy static layers ONCE per
                // data/size change; the per-tick paint is drawPicture + line.
                _ensureSpectrogramStaticLayer(
                    constraints.maxWidth, constraints.maxHeight);
                return GestureDetector(
                  onTapDown: _brushMode ? (d) => _onSpectrogramTap(d, constraints.maxWidth) : null,
                  onHorizontalDragUpdate: _brushMode ? (d) => _onSpectrogramTap(d, constraints.maxWidth) : null,
                  child: CustomPaint(
                    size: Size(constraints.maxWidth, constraints.maxHeight),
                    painter: _SpectrogramPainter(
                      staticLayer: _specStaticPicture,
                      spectrogram: _spectrogram, cols: _specCols, bins: _specBins,
                      waveform: _fetchWaveform(),
                      positionRatio: widget.controller.durationMs > 0
                          ? widget.controller.positionMs / widget.controller.durationMs : 0.0,
                      beatTimes: _beatTimes,
                      durationMs: widget.controller.durationMs,
                      loopEnabled: _loopEnabled,
                      loopStartRatio: widget.controller.durationMs > 0 ? _loopStartMs / widget.controller.durationMs : 0.0,
                      loopEndRatio: widget.controller.durationMs > 0 ? _loopEndMs / widget.controller.durationMs : 0.0,
                    ),
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }

  void _onSpectrogramTap(dynamic details, double canvasWidth) {
    final dx = details.localPosition.dx as double;
    final dur = widget.controller.durationMs;
    if (dur <= 0) return;
    final ms = (dx / canvasWidth * dur).round();
    const windowMs = 200;
    widget.controller.engineService.addSpectralEdit(
      (ms - windowMs ~/ 2).clamp(0, dur),
      (ms + windowMs ~/ 2).clamp(0, dur),
      100.0, 8000.0, -6.0,
    );
    setState(() {});
  }

  Widget _buildBottomBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        border: Border(top: BorderSide(color: AppTheme.divider)),
      ),
      child: Row(
        children: [
          const Icon(Icons.speed, size: 12, color: AppTheme.textMuted),
          const SizedBox(width: 4),
          Text(_detectedBpm > 0 ? '$_detectedBpm BPM' : '— BPM',
            style: const TextStyle(color: AppTheme.primaryLight, fontSize: 10, fontFamily: 'monospace')),
          const SizedBox(width: 12),
          TextButton(onPressed: _detectTempo,
            child: const Text('Detect', style: TextStyle(fontSize: 9))),
          const SizedBox(width: 12),
          const Text('Time Sig:', style: TextStyle(color: AppTheme.textMuted, fontSize: 9)),
          const SizedBox(width: 4),
          DropdownButton<int>(
            value: _timeSigNum, dropdownColor: AppTheme.surface,
            style: const TextStyle(color: AppTheme.textMain, fontSize: 10),
            underline: const SizedBox.shrink(),
            items: [2, 3, 4, 5, 6, 7].map((n) => DropdownMenuItem(value: n, child: Text('$n'))).toList(),
            onChanged: (v) {
              if (v != null) {
                setState(() => _timeSigNum = v);
                widget.controller.engineService.setTimeSignature(v, _timeSigDen);
                _refreshBeats();
              }
            },
          ),
          const Text('/', style: TextStyle(color: AppTheme.textMuted, fontSize: 10)),
          DropdownButton<int>(
            value: _timeSigDen, dropdownColor: AppTheme.surface,
            style: const TextStyle(color: AppTheme.textMain, fontSize: 10),
            underline: const SizedBox.shrink(),
            items: [2, 4, 8, 16].map((n) => DropdownMenuItem(value: n, child: Text('$n'))).toList(),
            onChanged: (v) {
              if (v != null) {
                setState(() => _timeSigDen = v);
                widget.controller.engineService.setTimeSignature(_timeSigNum, v);
                _refreshBeats();
              }
            },
          ),
          const SizedBox(width: 16),
          const Icon(Icons.graphic_eq, size: 12, color: AppTheme.textMuted),
          const SizedBox(width: 4),
          Container(width: 60, height: 8, decoration: BoxDecoration(color: AppTheme.divider, borderRadius: BorderRadius.circular(4)),
            child: FractionallySizedBox(widthFactor: _rmsLevel.clamp(0.0, 1.0),
              child: Container(decoration: BoxDecoration(color: AppTheme.primary, borderRadius: BorderRadius.circular(4))))),
          const Spacer(),
          if (_recording)
            Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.fiber_manual_record, color: Colors.red, size: 12),
              const SizedBox(width: 4),
              Text('REC', style: const TextStyle(color: Colors.red, fontSize: 10, fontWeight: FontWeight.bold)),
            ]),
          const SizedBox(width: 12),
          DropdownButton<int>(
            value: _recMode, dropdownColor: AppTheme.surface,
            style: const TextStyle(color: AppTheme.textMain, fontSize: 9),
            underline: const SizedBox.shrink(),
            items: const [
              DropdownMenuItem(value: 0, child: Text('Normal', style: TextStyle(fontSize: 9))),
              DropdownMenuItem(value: 1, child: Text('Punch-In', style: TextStyle(fontSize: 9))),
              DropdownMenuItem(value: 2, child: Text('Timer', style: TextStyle(fontSize: 9))),
            ],
            onChanged: (v) { if (v != null) setState(() => _recMode = v); },
          ),
        ],
      ),
    );
  }
}

class _EffectEntry {
  final int type;
  // v1.5.0-T6 debug fix: mutable — the engine chain shifts indices down on
  // remove, so entries must re-sync their chain position.
  int index;
  /// v1.5.0-T5 (P6): live p0..p3 values mirrored from the engine chain
  /// (engine defaults are 0.5) — edited via setAudioEffectParam.
  final List<double> params;
  _EffectEntry({required this.type, required this.index})
      : params = List.filled(4, 0.5);
}

class _RecordButton extends StatelessWidget {
  final bool recording;
  final VoidCallback onPressed;
  const _RecordButton({required this.recording, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        width: 28, height: 28,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: recording ? Colors.red : AppTheme.card,
          border: Border.all(color: recording ? Colors.red : AppTheme.primary),
        ),
        child: Icon(recording ? Icons.stop : Icons.fiber_manual_record,
          size: 14, color: recording ? Colors.white : Colors.red),
      ),
    );
  }
}

class _ToggleButton extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onPressed;
  const _ToggleButton({required this.label, required this.active, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: active ? AppTheme.primary.withValues(alpha: 0.2) : AppTheme.card,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: active ? AppTheme.primary : AppTheme.divider),
        ),
        child: Text(label, style: TextStyle(
          color: active ? AppTheme.primaryLight : AppTheme.textMuted,
          fontSize: 9, fontWeight: FontWeight.bold)),
      ),
    );
  }
}

/// v1.5.0-T3 (P2): heavy STATIC layers only — recorded into a ui.Picture by
/// the panel state, never repainted per tick.
class _SpectrogramStaticPainter extends CustomPainter {
  final Float32List spectrogram;
  final int cols;
  final int bins;
  final Float32List waveform;
  final List<int> beatTimes;
  final int durationMs;
  final bool loopEnabled;
  final double loopStartRatio;
  final double loopEndRatio;

  _SpectrogramStaticPainter({
    required this.spectrogram, required this.cols, required this.bins,
    required this.waveform,
    required this.beatTimes, required this.durationMs,
    required this.loopEnabled, required this.loopStartRatio, required this.loopEndRatio,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), Paint()..color = const Color(0xFF0F1119));

    // Loop region overlay
    if (loopEnabled && loopStartRatio < loopEndRatio) {
      canvas.drawRect(
        Rect.fromLTRB(loopStartRatio * size.width, 0, loopEndRatio * size.width, size.height),
        Paint()..color = const Color(0x203B82F6),
      );
    }

    // Spectrogram heat map
    if (spectrogram.isNotEmpty && cols > 0 && bins > 0) {
      final cellW = size.width / cols;
      final cellH = size.height / bins;
      for (int c = 0; c < cols; c++) {
        for (int b = 0; b < bins; b++) {
          final idx = c * bins + b;
          if (idx >= spectrogram.length) break;
          final mag = spectrogram[idx].clamp(0.0, 1.0);
          if (mag < 0.01) continue;
          canvas.drawRect(
            Rect.fromLTWH(c * cellW, size.height - (b + 1) * cellH, cellW + 0.5, cellH + 0.5),
            Paint()..color = _heatColor(mag),
          );
        }
      }
    }

    // Waveform overlay
    if (waveform.isNotEmpty) {
      final barW = size.width / waveform.length;
      final cy = size.height / 2;
      final paint = Paint()..color = const Color(0x803B82F6)..strokeWidth = 1.0;
      for (int i = 0; i < waveform.length; i++) {
        final s = waveform[i].clamp(0.0, 1.0);
        final h = s * size.height * 0.35;
        canvas.drawLine(Offset(i * barW, cy - h), Offset(i * barW, cy + h), paint);
      }
    }

    // Beat markers
    if (durationMs > 0 && beatTimes.isNotEmpty) {
      final paint = Paint()..color = const Color(0x40FFFFFF)..strokeWidth = 1.0;
      for (final bt in beatTimes) {
        final x = (bt / durationMs) * size.width;
        if (x >= 0 && x <= size.width) {
          canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
        }
      }
    }
  }

  Color _heatColor(double t) {
    if (t < 0.25) return Color.lerp(const Color(0xFF000000), const Color(0xFF0000FF), t / 0.25)!;
    if (t < 0.5) return Color.lerp(const Color(0xFF0000FF), const Color(0xFF00FFFF), (t - 0.25) / 0.25)!;
    if (t < 0.75) return Color.lerp(const Color(0xFF00FFFF), const Color(0xFFFFFF00), (t - 0.5) / 0.25)!;
    return Color.lerp(const Color(0xFFFFFF00), const Color(0xFFFF0000), (t - 0.75) / 0.25)!;
  }

  @override
  bool shouldRepaint(covariant _SpectrogramStaticPainter old) => true;
}

/// Per-frame layer: blits the cached static picture and draws the playhead.
class _SpectrogramPainter extends CustomPainter {
  final ui.Picture? staticLayer;
  final Float32List spectrogram;
  final int cols;
  final int bins;
  final Float32List waveform;
  final double positionRatio;
  final List<int> beatTimes;
  final int durationMs;
  final bool loopEnabled;
  final double loopStartRatio;
  final double loopEndRatio;

  _SpectrogramPainter({
    required this.staticLayer,
    required this.spectrogram, required this.cols, required this.bins,
    required this.waveform, required this.positionRatio,
    required this.beatTimes, required this.durationMs,
    required this.loopEnabled, required this.loopStartRatio, required this.loopEndRatio,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cached = staticLayer;
    if (cached != null) {
      canvas.drawPicture(cached);
    } else {
      // Fallback before the first recording — draw the static layers inline.
      _SpectrogramStaticPainter(
        spectrogram: spectrogram, cols: cols, bins: bins,
        waveform: waveform, beatTimes: beatTimes, durationMs: durationMs,
        loopEnabled: loopEnabled, loopStartRatio: loopStartRatio,
        loopEndRatio: loopEndRatio,
      ).paint(canvas, size);
    }

    // Playhead
    final px = positionRatio.clamp(0.0, 1.0) * size.width;
    canvas.drawLine(Offset(px, 0), Offset(px, size.height),
      Paint()..color = const Color(0xFFEC4899)..strokeWidth = 2.0);
  }

  @override
  bool shouldRepaint(covariant _SpectrogramPainter old) =>
      old.positionRatio != positionRatio || old.staticLayer != staticLayer;
}

