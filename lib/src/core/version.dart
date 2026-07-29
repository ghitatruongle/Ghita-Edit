// Centralized version constants for Ghita Edit.
// All version references in the codebase should use these constants.

const kAppName = 'Ghita Edit';
const kMajorVersion = 0;
const kMinorVersion = 3;
const kPatchVersion = 7;
const kBuildNumber = 3;

/// Flutter/Dart app version string (e.g., '0.3.1+2')
String get flutterVersion => '$kMajorVersion.$kMinorVersion.$kPatchVersion+$kBuildNumber';

/// Native C++ engine version string (e.g., 'Ghita Core Engine v0.3.1 (C++/Flutter)')
String get nativeEngineVersion => 'Ghita Core Engine v$kMajorVersion.$kMinorVersion.$kPatchVersion (C++/Flutter)';

/// App version displayed in UI (e.g., 'v0.3.1+2')
String get appVersion => 'v$flutterVersion';