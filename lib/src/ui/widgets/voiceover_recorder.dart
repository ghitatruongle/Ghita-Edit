import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../../controllers/editor_controller.dart';
import '../theme/app_theme.dart';

// ============================================================
// VoiceoverRecorder — v0.8.0: Real implementation using the
// `record` package (record_windows supports Windows since 2.x).
// Records a WAV file and imports it as an audio clip on the
// audio track, undoable via the normal AddClipCommand.
// ============================================================

class VoiceoverRecorder extends StatefulWidget {
  final EditorController controller;

  const VoiceoverRecorder({super.key, required this.controller});

  @override
  State<VoiceoverRecorder> createState() => _VoiceoverRecorderState();
}

class _VoiceoverRecorderState extends State<VoiceoverRecorder> {
  final AudioRecorder _recorder = AudioRecorder();
  bool _isRecording = false;
  bool _isSaving = false;
  Timer? _ticker;
  int _elapsedSeconds = 0;

  @override
  void dispose() {
    _ticker?.cancel();
    _recorder.dispose();
    super.dispose();
  }

  String _formatElapsed(int seconds) {
    final min = seconds ~/ 60;
    final sec = seconds % 60;
    return '${min.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
  }

  Future<String> _recordingPath() async {
    final dir = await getApplicationSupportDirectory();
    final stamp = DateTime.now().millisecondsSinceEpoch;
    return '${dir.path}${Platform.pathSeparator}voiceover_$stamp.wav';
  }

  Future<void> _startRecording() async {
    try {
      final hasPermission = await _recorder.hasPermission();
      if (!hasPermission) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Microphone permission denied')),
          );
        }
        return;
      }
      final path = await _recordingPath();
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 44100,
          numChannels: 2,
          bitRate: 128000,
        ),
        path: path,
      );
      _elapsedSeconds = 0;
      _ticker?.cancel();
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() => _elapsedSeconds++);
      });
      if (mounted) setState(() => _isRecording = true);
    } catch (e) {
      debugPrint('[Voiceover] Failed to start recording: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Recording failed: $e')),
        );
      }
    }
  }

  Future<void> _stopRecording() async {
    _ticker?.cancel();
    try {
      _isSaving = true;
      if (mounted) setState(() {});
      final path = await _recorder.stop();
      _isSaving = false;
      if (!mounted) return;

      if (path == null || !File(path).existsSync() || File(path).lengthSync() == 0) {
        setState(() => _isRecording = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Recording was empty — nothing imported')),
        );
        return;
      }

      // v0.8.0: Import the WAV as an undoable audio clip on the audio track.
      widget.controller.importMedia(path);
      setState(() {
        _isRecording = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Voiceover recorded (${_formatElapsed(_elapsedSeconds)}) — added to timeline'),
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e) {
      debugPrint('[Voiceover] Failed to stop recording: $e');
      _isSaving = false;
      if (mounted) {
        setState(() => _isRecording = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save recording: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                _isRecording ? Icons.mic_rounded : Icons.mic_none_rounded,
                color: _isRecording ? AppTheme.warning : AppTheme.clipAudio,
                size: 14,
              ),
              const SizedBox(width: 6),
              const Text(
                'VOICEOVER',
                style: TextStyle(
                  color: AppTheme.textMain,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
              const Spacer(),
              if (_isRecording)
                Text(
                  _formatElapsed(_elapsedSeconds),
                  style: const TextStyle(
                    color: AppTheme.warning,
                    fontSize: 12,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _isSaving
                      ? null
                      : (_isRecording ? _stopRecording : _startRecording),
                  icon: Icon(
                    _isRecording ? Icons.stop_rounded : Icons.fiber_manual_record_rounded,
                    size: 16,
                  ),
                  label: Text(_isSaving
                      ? 'Saving…'
                      : (_isRecording ? 'Stop & Add to Timeline' : 'Record Voiceover')),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isRecording ? AppTheme.warning : AppTheme.accent,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Records WAV (44.1 kHz) into the app folder and adds it as an audio clip. Use Ctrl+Z to undo.',
            style: TextStyle(color: AppTheme.textMuted, fontSize: 10),
          ),
        ],
      ),
    );
  }
}
