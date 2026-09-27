// Centralized version constants for Ghita Edit.
// All version references in the codebase should use these constants.

const kAppName = 'Ghita Edit';
const kMajorVersion = 1;
const kMinorVersion = 5;
const kPatchVersion = 5;
const kBuildNumber = 0;

/// Pre-release suffix shown in the UI / commit naming only ('' | 'demo' |
/// 'beta1' | 'beta2' | 'beta3'). NEVER numeric — the CI consistency gates
/// read only the numeric constants above.
const kVersionSuffix = 'beta1';

/// Flutter/Dart app version string (e.g., '1.5.5+0' or '1.5.5-demo+0').
/// The suffix is display-only: pubspec.yaml and the CI gates stay numeric.
String get flutterVersion => '$kMajorVersion.$kMinorVersion.$kPatchVersion'
    '${kVersionSuffix.isEmpty ? '' : '-$kVersionSuffix'}+$kBuildNumber';

/// Native Rust/C++ engine version string (e.g., 'Ghita Core Engine v1.5.5 (Rust/Flutter)')
String get nativeEngineVersion => 'Ghita Core Engine v$kMajorVersion.$kMinorVersion.$kPatchVersion (Rust/Flutter)';

/// App version displayed in UI (e.g., 'v1.5.5-demo+0')
String get appVersion => 'v$flutterVersion';

/// Full version string for display in UI
String get fullAppVersion => '$appVersion ($nativeEngineVersion)';