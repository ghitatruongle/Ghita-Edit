// v1.5.0-T1: generated ABI contract table — every symbol Dart binds via
// lookupFunction must have the SAME PARAMETER COUNT as the Rust export.
//
// The v1.5.0 T6 selection tools shipped with 4 signatures whose arity/order
// diverged between native_bindings.dart and c_api.rs (undefined behavior on
// every call, invisible to CI because nothing exercised them). This test
// parses both sources and fails on any drift so the bug class cannot recur.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  // Counts top-level parameters, tolerating trailing commas / line breaks.
  int paramCount(String raw) {
    final p = raw.trim();
    if (p.isEmpty) return 0;
    return p.split(',').where((t) => t.trim().isNotEmpty).length;
  }

  test('FFI arity contract: native_bindings.dart ↔ c_api.rs', () {
    final rustSrc = File('native_engine_rust/src/c_api.rs').readAsStringSync();
    final dartSrc =
        File('lib/src/ffi/native_bindings.dart').readAsStringSync();

    // Rust exports: #[no_mangle] pub unsafe extern "C" fn name(params)
    final rustRe = RegExp(
      r'no_mangle\]\s*pub (?:unsafe )?extern "C" fn\s+(\w+)\s*\(([^)]*)\)',
      dotAll: true,
    );
    final rustArity = <String, int>{};
    for (final m in rustRe.allMatches(rustSrc)) {
      rustArity[m.group(1)!] = paramCount(m.group(2)!);
    }
    expect(rustArity.length, greaterThan(90),
        reason: 'c_api.rs parse regressed — no exports found');

    // Dart C-side typedefs: typedef CName = Ret Function(params);
    final typedefRe = RegExp(
      r'typedef\s+(\w+)\s*=\s*[^=;]+?\bFunction\s*\(([^)]*)\)\s*;',
      dotAll: true,
    );
    final dartArity = <String, int>{};
    for (final m in typedefRe.allMatches(dartSrc)) {
      dartArity[m.group(1)!] = paramCount(m.group(2)!);
    }

    // Bind sites: lookupFunction<CType, DType>('symbol')
    final lookupRe = RegExp(
      r'''lookupFunction<\s*(\w+)\s*,\s*\w+\s*>\(\s*["'](\w+)["']''',
    );

    final mismatches = <String>[];
    final boundSymbols = <String>{};
    for (final m in lookupRe.allMatches(dartSrc)) {
      final cTypedef = m.group(1)!;
      final symbol = m.group(2)!;
      final rustN = rustArity[symbol];
      if (rustN == null) continue; // not a Rust-exported symbol
      boundSymbols.add(symbol);
      final dartN = dartArity[cTypedef];
      if (dartN == null) {
        mismatches.add('$symbol: typedef $cTypedef not found in bindings');
        continue;
      }
      if (dartN != rustN) {
        mismatches.add(
            '$symbol: Dart $cTypedef has $dartN params, Rust export has $rustN');
      }
    }

    // The four symbols that WERE broken must stay covered by this table.
    const t1Selection = [
      'ghita_engine_set_selection_rect',
      'ghita_engine_set_selection_ellipse',
      'ghita_engine_set_selection_lasso',
      'ghita_engine_set_selection_magic_wand',
    ];
    for (final s in t1Selection) {
      expect(boundSymbols.contains(s), isTrue,
          reason: '$s is no longer parsed by the contract table');
    }
    expect(rustArity['ghita_engine_set_selection_rect'], 7);
    expect(rustArity['ghita_engine_set_selection_magic_wand'], 7);

    expect(boundSymbols.length, greaterThan(40),
        reason: 'contract table too small — parser drift?');
    expect(mismatches, isEmpty, reason: mismatches.join('\n'));
  });
}
