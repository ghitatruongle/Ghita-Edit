import 'package:flutter/material.dart';
import '../../controllers/editor_controller.dart';
import '../theme/app_theme.dart';

// ============================================================
// VoiceoverRecorder — v0.7.0 Audio Recording Widget
// ============================================================
// Note: Full recording requires the 'record' package (Android/iOS only).
// On unsupported platforms, this widget shows a stub message.

class VoiceoverRecorder extends StatefulWidget {
  final EditorController controller;

  const VoiceoverRecorder({super.key, required this.controller});

  @override
  State<VoiceoverRecorder> createState() => _VoiceoverRecorderState();
}

class _VoiceoverRecorderState extends State<VoiceoverRecorder> {
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
              const Icon(Icons.mic_off, color: AppTheme.clipAudio, size: 14),
              const SizedBox(width: 6),
              const Text('VOICEOVER', style: TextStyle(color: AppTheme.textMain, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppTheme.background,
              borderRadius: BorderRadius.circular(AppTheme.radiusSm),
              border: Border.all(color: AppTheme.divider),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 16, color: AppTheme.accent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Voiceover recording is available on mobile (Android/iOS). Add the record package to enable.',
                    style: TextStyle(color: AppTheme.textMuted, fontSize: 11),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
