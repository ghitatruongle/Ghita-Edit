// T2.P2 (v1.5.5-beta2): generate a synthetic .ghita project for CLI stress —
// N video clips back-to-back on the first video track plus an audio clip.
// Emits the JSON schema directly (models import dart:ui, unavailable to
// plain `dart run`); Clip.fromJson tolerates partial keys by design.
// Usage: dart run tool/gen_test_project.dart <out.ghita> [clipCount]
import 'dart:convert';
import 'dart:io';

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('usage: dart run tool/gen_test_project.dart <out.ghita> [clipCount=12]');
    exit(2);
  }
  final n = int.tryParse(args.length > 1 ? args[1] : '') ?? 12;
  const media = 'test_video.mp4';
  Map<String, dynamic> clip(String id, String path, String name, int start, int dur, int type) => {
        'id': id,
        'sourceFilePath': path,
        'displayName': name,
        'timelineStartMs': start,
        'durationMs': dur,
        'sourceInMs': 0,
        'type': type, // ClipType: video=0, audio=1
        'volume': 1.0,
        'opacity': 1.0,
        'speed': 1.0,
      };
  final videoClips = [for (var i = 0; i < n; i++) clip('c$i', media, 'seg$i', i * 2000, 2000, 0)];
  final audioClip = clip('audio', 'test_sine.wav', 'music', 0, n * 2000, 1);
  final doc = {
    'name': 'cli_stress',
    'tracks': [
      {'id': 'tr_v', 'name': 'V', 'type': 0, 'clips': videoClips, 'isMuted': false, 'isVisible': true, 'volume': 1.0},
      {'id': 'tr_a', 'name': 'A', 'type': 2, 'clips': [audioClip], 'isMuted': false, 'isVisible': true, 'volume': 1.0},
    ],
  };
  File(args[0]).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(doc));
  stderr.writeln('wrote ${args[0]}: $n video clips + 1 audio clip');
}
