// v1.5.0-T2 (P3): controllers coverage gate.
//
// Parses coverage/lcov.info (produced by `flutter test --coverage`) and
// fails when the line hit-rate across lib/src/controllers drops below the
// threshold. CI runs this right after the Flutter test suite.
//
// Usage: dart run tool/coverage_gate.dart [threshold]
import 'dart:io';

void main(List<String> args) {
  final threshold = double.tryParse(args.isNotEmpty ? args[0] : '') ?? 0.60;
  final file = File('coverage/lcov.info');
  if (!file.existsSync()) {
    stderr.writeln(
        'coverage/lcov.info not found — run `flutter test --coverage` first');
    exit(2);
  }

  var found = 0;
  var hit = 0;
  var inControllers = false;
  for (final raw in file.readAsLinesSync()) {
    if (raw.startsWith('SF:')) {
      inControllers = raw.substring(3).replaceAll('\\', '/').contains('lib/src/controllers/');
    } else if (raw.startsWith('DA:') && inControllers) {
      final parts = raw.substring(3).split(',');
      if (parts.length < 2) continue;
      final hits = int.tryParse(parts[1].trim());
      if (hits == null) continue;
      found++;
      if (hits > 0) hit++;
    }
  }

  if (found == 0) {
    stderr.writeln(
        'No controller lines found in lcov output — check the SF paths');
    exit(2);
  }

  final rate = hit / found;
  final pct = (rate * 100).toStringAsFixed(1);
  stdout.writeln(
      'lib/src/controllers coverage: $hit/$found lines = $pct% '
      '(gate ${(threshold * 100).toStringAsFixed(0)}%)');
  if (rate < threshold) {
    stderr.writeln('== COVERAGE GATE FAILED ==');
    exit(1);
  }
  stdout.writeln('== COVERAGE GATE PASSED ==');
}
