// Client architecture guard (R-12) — CI lint stub for Phase 1 Tests.
// Detection and coverage assertion are implemented in Phase 2 (T006).

import 'dart:io';

/// Default clean-tree scan roots relative to [frontendRoot].
const defaultScanRoots = ['lib', 'test'];

/// Every client source directory whose Dart files must lie inside a scan root.
const clientSourceRoots = ['lib', 'test'];

void main(List<String> args) {
  final frontendRoot = _resolveFrontendRoot();
  final scanRoots = _resolveScanRoots(args, frontendRoot);
  final assertCoverage = _shouldAssertCoverage(args, scanRoots, frontendRoot);

  // Stub: no forbidden-pattern detection yet — exits zero on all scans (T1–T3 red).
  if (assertCoverage) {
    // Stub: coverage assertion not implemented — always fails (T4–T5 red).
    stderr.writeln(
      'architecture_guard: client-source coverage assertion not implemented',
    );
    exit(1);
  }

  exit(0);
}

Directory _resolveFrontendRoot() {
  final scriptDir = File(Platform.script.toFilePath()).parent;
  return scriptDir.parent.parent;
}

List<String> _resolveScanRoots(List<String> args, Directory frontendRoot) {
  if (args.isEmpty) {
    return defaultScanRoots
        .map((relative) => frontendRoot.uri.resolve(relative).toFilePath())
        .toList();
  }

  return args
      .where((arg) => !arg.startsWith('--'))
      .map((arg) {
        final dir = Directory(arg);
        if (dir.isAbsolute) {
          return dir.path;
        }
        return frontendRoot.uri.resolve(arg).toFilePath();
      })
      .toList();
}

bool _shouldAssertCoverage(
  List<String> args,
  List<String> scanRoots,
  Directory frontendRoot,
) {
  if (args.contains('--assert-coverage')) {
    return true;
  }

  if (args.isEmpty) {
    return true;
  }

  final fixtureMarker = frontendRoot.uri
      .resolve('tool/architecture_guard/fixtures/')
      .toFilePath();

  final scanningFixturesOnly = scanRoots.every(
    (root) => root.replaceAll('\\', '/').contains(
          fixtureMarker.replaceAll('\\', '/'),
        ),
  );

  return !scanningFixturesOnly;
}
