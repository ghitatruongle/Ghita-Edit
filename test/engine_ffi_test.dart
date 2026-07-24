import 'package:flutter_test/flutter_test.dart';
import 'package:ghita_edit/src/controllers/editor_controller.dart';

void main() {
  test('EditorController initializes C++ Engine context and tick loop', () {
    final controller = EditorController();
    expect(controller.isPlaying, isFalse);
    expect(controller.positionMs, equals(0));
    expect(controller.volume, equals(1.0));
    
    controller.togglePlayPause();
    expect(controller.isPlaying, isTrue);

    controller.seek(15000);
    expect(controller.positionMs, equals(15000));

    controller.setFilter(2, 0.8);
    expect(controller.activeFilterType, equals(2));
    expect(controller.filterIntensity, equals(0.8));

    controller.dispose();
  });
}
