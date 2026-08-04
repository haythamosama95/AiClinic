// Client architecture guard (R-12) — standalone Dart CI lint.
// Scans Flutter client sources for prompt-like strings, provider names, and
// model identifiers. Exits non-zero on any match. In clean-tree mode, asserts
// configured scan roots cover every client source path.

import 'dart:io';

/// Default clean-tree scan roots relative to [frontendRoot].
const defaultScanRoots = ['lib', 'test'];

/// Every client source directory whose Dart files must lie inside a scan root.
const clientSourceRoots = ['lib', 'test'];

/// Representative prompt-like patterns (not an exhaustive catalogue).
final _promptPatterns = [
  RegExp(r'You are a helpful assistant', caseSensitive: false),
  RegExp(r'You are an AI assistant', caseSensitive: false),
  RegExp(r'\bsystem prompt\b', caseSensitive: false),
  RegExp(r'"role"\s*:\s*"system"', caseSensitive: false),
  RegExp(r"'role'\s*:\s*'system'", caseSensitive: false),
];

/// Representative provider names (not an exhaustive catalogue).
final _providerPatterns = [
  RegExp(r'\bopenai\b', caseSensitive: false),
  RegExp(r'\banthropic\b', caseSensitive: false),
  RegExp(r'\bgemini\b', caseSensitive: false),
  RegExp(r'\bcohere\b', caseSensitive: false),
  RegExp(r'\bmistral\b', caseSensitive: false),
];

/// Representative model identifier patterns (not an exhaustive catalogue).
final _modelPatterns = [
  RegExp(r'\bgpt-\d', caseSensitive: false),
  RegExp(r'\bclaude-\d', caseSensitive: false),
  RegExp(r'\bgemini-\d', caseSensitive: false),
  RegExp(r'\bo\d-\w+', caseSensitive: false),
];

void main(List<String> args) {
  final frontendRoot = _resolveFrontendRoot();
  final scanRoots = _resolveScanRoots(args, frontendRoot);
  final assertCoverage = _shouldAssertCoverage(args, scanRoots, frontendRoot);

  final violations = <String>[];

  for (final root in scanRoots) {
    violations.addAll(_scanDirectory(Directory(root)));
  }

  if (violations.isNotEmpty) {
    stderr.writeln('architecture_guard: forbidden content detected:');
    for (final violation in violations) {
      stderr.writeln('  $violation');
    }
    exit(1);
  }

  if (assertCoverage) {
    final coverageErrors = _assertFullCoverage(scanRoots, frontendRoot);
    if (coverageErrors.isNotEmpty) {
      stderr.writeln('architecture_guard: client-source coverage gaps:');
      for (final error in coverageErrors) {
        stderr.writeln('  $error');
      }
      exit(1);
    }
  }

  stdout.writeln('architecture_guard: clean — no forbidden content detected.');
  exit(0);
}

Directory _resolveFrontendRoot() {
  final scriptDir = File(Platform.script.toFilePath()).parent;
  return scriptDir.parent.parent;
}

List<String> _resolveScanRoots(List<String> args, Directory frontendRoot) {
  final pathArgs = args.where((arg) => !arg.startsWith('--')).toList();

  if (pathArgs.isEmpty) {
    return defaultScanRoots
        .map((relative) => frontendRoot.uri.resolve(relative).toFilePath())
        .toList();
  }

  return pathArgs.map((arg) {
    final dir = Directory(arg);
    if (dir.isAbsolute) {
      return dir.path;
    }
    return frontendRoot.uri.resolve(arg).toFilePath();
  }).toList();
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

List<String> _scanDirectory(Directory dir) {
  if (!dir.existsSync()) {
    stderr.writeln('architecture_guard: scan root not found: ${dir.path}');
    exit(2);
  }

  final violations = <String>[];

  for (final entity in dir.listSync(recursive: true, followLinks: false)) {
    if (entity is! File || !entity.path.endsWith('.dart')) {
      continue;
    }

    final content = entity.readAsStringSync();
    final lines = content.split('\n');

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final lineNumber = i + 1;

      for (final pattern in _promptPatterns) {
        if (pattern.hasMatch(line)) {
          violations.add(
            '${entity.path}:$lineNumber: prompt-like string (${pattern.pattern})',
          );
        }
      }

      for (final pattern in _providerPatterns) {
        if (pattern.hasMatch(line)) {
          violations.add(
            '${entity.path}:$lineNumber: provider name (${pattern.pattern})',
          );
        }
      }

      for (final pattern in _modelPatterns) {
        if (pattern.hasMatch(line)) {
          violations.add(
            '${entity.path}:$lineNumber: model identifier (${pattern.pattern})',
          );
        }
      }
    }
  }

  return violations;
}

List<String> _assertFullCoverage(
  List<String> scanRoots,
  Directory frontendRoot,
) {
  final normalizedScanRoots = scanRoots
      .map((root) => _normalizePath(Directory(root).absolute.path))
      .toSet();

  final uncovered = <String>[];

  for (final relativeRoot in clientSourceRoots) {
    final sourceDir = Directory(
      frontendRoot.uri.resolve(relativeRoot).toFilePath(),
    );

    if (!sourceDir.existsSync()) {
      continue;
    }

    for (final entity
        in sourceDir.listSync(recursive: true, followLinks: false)) {
      if (entity is! File || !entity.path.endsWith('.dart')) {
        continue;
      }

      final normalizedFile = _normalizePath(entity.absolute.path);
      final covered = normalizedScanRoots.any(
        (root) =>
            normalizedFile.startsWith('$root/') || normalizedFile == root,
      );

      if (!covered) {
        uncovered.add(normalizedFile);
      }
    }
  }

  return uncovered;
}

String _normalizePath(String path) {
  return Directory(path).absolute.path.replaceAll('\\', '/');
}
