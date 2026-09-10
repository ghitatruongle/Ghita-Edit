import 'package:flutter_test/flutter_test.dart';
import 'package:ghita_edit/src/models/clip.dart';

// v1.5.5-demo (B3): adjustment-graph persistence tests — the chain rides in
// the clip JSON (graphNodes) so save/load round-trips and old project files
// load unchanged.
void main() {
  Clip makeClip() => Clip(
        id: 'clip_test_1',
        sourceFilePath: 'C:/media/a.mp4',
        displayName: 'A',
        timelineStartMs: 0,
        durationMs: 5000,
      );

  test('Clip graphNodes round-trips through toJson/fromJson', () {
    final clip = makeClip().copyWith(graphNodes: const [
      GraphNodeData(type: 0, value: 0.25),
      GraphNodeData(type: 1, value: -0.5),
      GraphNodeData(type: 2, value: 1.0),
    ]);
    final restored = Clip.fromJson(clip.toJson());
    expect(restored.graphNodes.length, 3);
    expect(restored.graphNodes[0].type, 0);
    expect(restored.graphNodes[0].value, 0.25);
    expect(restored.graphNodes[1].type, 1);
    expect(restored.graphNodes[1].value, -0.5);
    expect(restored.graphNodes[2].type, 2);
    expect(restored.graphNodes[2].value, 1.0);
  });

  test('Project files without graphNodes load with an empty chain', () {
    final json = makeClip().toJson()..remove('graphNodes');
    final restored = Clip.fromJson(json);
    expect(restored.graphNodes, isEmpty);
  });

  test('copyWith preserves the graph chain unless overridden', () {
    final clip = makeClip().copyWith(graphNodes: const [
      GraphNodeData(type: 0, value: 0.1),
    ]);
    final copy = clip.copyWith(durationMs: 9000);
    expect(copy.graphNodes.length, 1);
    expect(copy.graphNodes[0].value, 0.1);
    final replaced = clip.copyWith(graphNodes: const []);
    expect(replaced.graphNodes, isEmpty);
  });

  test('GraphNodeData tolerates missing/corrupt JSON fields', () {
    final node = GraphNodeData.fromJson(<String, dynamic>{});
    expect(node.type, 0);
    expect(node.value, 0.0);
  });
}
