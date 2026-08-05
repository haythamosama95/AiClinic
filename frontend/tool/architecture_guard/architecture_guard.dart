// Client architecture guard (R-12) — standalone Dart CI lint.
// Scans Flutter client sources for prompt-like strings, provider names, and
// model identifiers. Exit codes:
//   0 — clean (and coverage OK when asserted)
//   1 — violations detected, or coverage gaps
//   2 — operator / configuration error (missing scan root, etc.)
//
// Residual evasion (accepted by representative-catalogue scope): adjacent string
// literals, explicit concatenation, and interpolation that assemble a forbidden
// phrase from parts without leaving a contiguous match in source. Whole-file
// whitespace-tolerant matching closes multi-line string splits.

import 'dart:io';

/// Default clean-tree scan roots relative to [frontendRoot].
const defaultScanRoots = ['lib', 'test', 'windows', 'linux', 'web'];

/// Filename suffixes the content scanner reads under each scan root.
const scannedExtensions = [
  '.dart',
  '.cpp',
  '.cc',
  '.c',
  '.h',
  '.hpp',
  '.html',
  '.json',
  '.js',
  '.css',
  '.cmake',
  '.rc',
  '.manifest',
  '.arb',
  '.md',
  '.txt',
  '.yaml',
  '.yml',
];

/// Basenames always treated as scannable text (extension-less / dotfiles).
const scannedBasenames = {'CMakeLists.txt', '.gitignore'};

/// Placeholder / empty marker files that carry no client source content.
const ignorableBasenames = {'.gitkeep'};

/// Binary / opaque extensions that never need content scanning or coverage.
const ignorableExtensions = {
  '.png',
  '.ico',
  '.jpg',
  '.jpeg',
  '.gif',
  '.webp',
  '.so',
  '.dll',
  '.dylib',
  '.dat',
  '.bin',
  '.exe',
  '.pdb',
  '.obj',
  '.o',
  '.a',
  '.lib',
  '.lock',
  '.ttf',
  '.otf',
  '.woff',
  '.woff2',
};

/// Relative prefixes under frontend/ excluded from coverage discovery.
const coverageExcludedPrefixes = [
  'build/',
  '.dart_tool/',
  'tool/',
  'test-results/',
  'docs/',
  'assets/',
  'config/',
  'linux/flutter/ephemeral/',
  'windows/flutter/ephemeral/',
];

/// Exact relative paths under frontend/ excluded from coverage discovery.
const coverageExcludedExact = {
  'analysis_options.yaml',
  'dart_test.yaml',
  'devtools_options.yaml',
  'l10n.yaml',
  'pubspec.yaml',
  'README.md',
  '.gitignore',
  '.metadata',
  '.flutter-plugins-dependencies',
};

/// Representative prompt-like patterns (not an exhaustive catalogue).
/// Matched against whitespace-normalized full-file content.
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
  RegExp(r'\bdeepseek\b', caseSensitive: false),
];

/// Representative model identifier patterns (not an exhaustive catalogue).
final _modelPatterns = [
  RegExp(r'\bgpt-\d', caseSensitive: false),
  RegExp(r'\bclaude-[\w.-]+', caseSensitive: false),
  RegExp(r'\bgemini-[\w.-]+', caseSensitive: false),
  RegExp(r'\bo\d-\w+', caseSensitive: false),
  RegExp(r'\bdeepseek-\w+', caseSensitive: false),
];

void main(List<String> args) {
  final frontendRoot = _resolveFrontendRoot();
  final scanRoots = _resolveScanRoots(args, frontendRoot);
  final assertCoverage = _shouldAssertCoverage(args);

  final missingRoots = <String>[];
  for (final root in scanRoots) {
    if (!Directory(root).existsSync()) {
      missingRoots.add(root);
    }
  }
  if (missingRoots.isNotEmpty) {
    stderr.writeln(
      'architecture_guard: scan root(s) not found:',
    );
    for (final root in missingRoots) {
      stderr.writeln('  $root');
    }
    exit(2);
  }

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

bool _shouldAssertCoverage(List<String> args) {
  if (args.contains('--assert-coverage')) {
    return true;
  }

  // Empty args → default roots + full-tree coverage (CI clean run).
  // Explicit path args (fixtures or scoped roots like lib/features/ai) are
  // targeted scans; coverage only when --assert-coverage is requested.
  return args.isEmpty;
}

List<String> _scanDirectory(Directory dir) {
  final violations = <String>[];

  for (final entity in dir.listSync(recursive: true, followLinks: false)) {
    if (entity is! File || !_isScannableFile(entity)) {
      continue;
    }

    violations.addAll(_scanFile(entity));
  }

  return violations;
}

List<String> _scanFile(File entity) {
  final violations = <String>[];
  final content = entity.readAsStringSync();
  final normalized = _normalizeWhitespace(content);

  void matchCategory(
    List<RegExp> patterns,
    String category,
    String haystack, {
    required bool normalize,
  }) {
    for (final pattern in patterns) {
      final effective = normalize
          ? RegExp(
              _whitespaceTolerantPattern(pattern.pattern),
              caseSensitive: pattern.isCaseSensitive,
            )
          : pattern;
      final match = effective.firstMatch(haystack);
      if (match == null) {
        continue;
      }
      final lineNumber = _lineNumberForOffset(
        content,
        normalize
            ? _approxOffsetInOriginal(content, match.start, haystack)
            : match.start,
      );
      violations.add(
        '${entity.path}:$lineNumber: $category (${pattern.pattern})',
      );
    }
  }

  // Prompts: whitespace-tolerant over the full file (closes multi-line ''' splits).
  matchCategory(_promptPatterns, 'prompt-like string', normalized, normalize: true);
  // Providers / models: full-file match so a split across lines is still caught.
  matchCategory(_providerPatterns, 'provider name', content, normalize: false);
  matchCategory(_modelPatterns, 'model identifier', content, normalize: false);

  return violations;
}

String _normalizeWhitespace(String input) {
  return input.replaceAll(RegExp(r'\s+'), ' ');
}

String _whitespaceTolerantPattern(String pattern) {
  return pattern.replaceAllMapped(
    RegExp(r'\s+'),
    (_) => r'\s+',
  );
}

int _approxOffsetInOriginal(
  String original,
  int normalizedOffset,
  String normalized,
) {
  // Map a position in the whitespace-collapsed haystack back to the original
  // by walking both strings; falls back to 0 if mapping fails.
  if (normalizedOffset <= 0) {
    return 0;
  }
  if (normalizedOffset >= normalized.length) {
    return original.length;
  }

  var oi = 0;
  var ni = 0;
  while (oi < original.length && ni < normalizedOffset) {
    final oc = original[oi];
    if (RegExp(r'\s').hasMatch(oc)) {
      oi++;
      continue;
    }
    oi++;
    ni++;
  }
  return oi;
}

int _lineNumberForOffset(String content, int offset) {
  if (offset <= 0) {
    return 1;
  }
  var line = 1;
  final end = offset < content.length ? offset : content.length;
  for (var i = 0; i < end; i++) {
    if (content[i] == '\n') {
      line++;
    }
  }
  return line;
}

bool _isScannableFile(File file) {
  final normalized = _normalizePath(file.path);
  final basename = normalized.split('/').last;
  if (ignorableBasenames.contains(basename)) {
    return false;
  }
  if (scannedBasenames.contains(basename)) {
    return true;
  }
  final dot = basename.lastIndexOf('.');
  if (dot < 0) {
    return false;
  }
  final ext = basename.substring(dot).toLowerCase();
  return scannedExtensions.contains(ext);
}

bool _isIgnorableFile(File file) {
  final normalized = _normalizePath(file.path);
  final basename = normalized.split('/').last;
  if (ignorableBasenames.contains(basename)) {
    return true;
  }
  final dot = basename.lastIndexOf('.');
  if (dot < 0) {
    return false;
  }
  final ext = basename.substring(dot).toLowerCase();
  return ignorableExtensions.contains(ext);
}

List<String> _assertFullCoverage(
  List<String> scanRoots,
  Directory frontendRoot,
) {
  final normalizedScanRoots = scanRoots
      .map((root) => _normalizePath(Directory(root).absolute.path))
      .toSet();
  final frontendPrefix = _normalizePath(frontendRoot.absolute.path);
  final uncovered = <String>[];

  for (final entity in frontendRoot.listSync(recursive: true, followLinks: false)) {
    if (entity is! File) {
      continue;
    }

    final normalizedFile = _normalizePath(entity.absolute.path);
    if (!normalizedFile.startsWith('$frontendPrefix/')) {
      continue;
    }

    final relative = normalizedFile.substring(frontendPrefix.length + 1);

    if (_isCoverageExcluded(relative)) {
      continue;
    }
    if (_isIgnorableFile(entity)) {
      continue;
    }
    // Only require coverage for files the scanner would actually read.
    if (!_isScannableFile(entity)) {
      // Non-scannable, non-ignorable text must be explicitly excluded.
      uncovered.add('$normalizedFile (not scannable and not excluded)');
      continue;
    }

    final covered = normalizedScanRoots.any(
      (root) =>
          normalizedFile.startsWith('$root/') || normalizedFile == root,
    );

    if (!covered) {
      uncovered.add(normalizedFile);
    }
  }

  return uncovered;
}

bool _isCoverageExcluded(String relativePath) {
  final normalized = relativePath.replaceAll('\\', '/');
  if (coverageExcludedExact.contains(normalized)) {
    return true;
  }
  for (final prefix in coverageExcludedPrefixes) {
    if (normalized == prefix.replaceAll(RegExp(r'/$'), '') ||
        normalized.startsWith(prefix)) {
      return true;
    }
  }
  return false;
}

String _normalizePath(String path) {
  return Directory(path).absolute.path.replaceAll('\\', '/');
}
