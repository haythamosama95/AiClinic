import 'dart:io' show Platform;

/// VM/desktop/mobile: Flutter test runner sets FLUTTER_TEST=true.
bool isFlutterTestRuntimeFromEnvironment() => Platform.environment['FLUTTER_TEST'] == 'true';
