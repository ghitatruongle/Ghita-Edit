// Centralized version constants for Ghita Edit.
// All version references in the codebase should use these constants.

const kAppName = 'Ghita Edit';
const kMajorVersion = 1;
const kMinorVersion = 5;
const kPatchVersion = 0;
const kBuildNumber = 0;

/// Flutter/Dart app version string (e.g., '0.7.8+0')
String get flutterVersion => '$kMajorVersion.$kMinorVersion.$kPatchVersion+$kBuildNumber';

/// Native C++ engine version string (e.g., 'Ghita Core Engine v0.7.8 (C++/Flutter)')
String get nativeEngineVersion => 'Ghita Core Engine v$kMajorVersion.$kMinorVersion.$kPatchVersion (C++/Flutter)';

/// App version displayed in UI (e.g., 'v0.7.8+0')
String get appVersion => 'v$flutterVersion';

/// Full version string for display in UI
String get fullAppVersion => '$appVersion ($nativeEngineVersion)';