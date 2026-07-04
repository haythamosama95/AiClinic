import 'dart:convert';

import 'package:flutter/services.dart';

/// Bundled Egyptian medication trade names for dev clinic seeding.
///
/// Schema matches [medications.name] (max 200 chars, case-insensitive unique per org).
abstract final class DevEgyptianMedicationsAsset {
  static const assetPath = 'assets/dev/egyptian_medication_names.json';
  static const batchSize = 1000;

  static Future<List<String>> loadNames() async {
    final raw = await rootBundle.loadString(assetPath);
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw StateError('Egyptian medication asset must be a JSON object.');
    }

    final namesRaw = decoded['names'];
    if (namesRaw is! List) {
      throw StateError('Egyptian medication asset is missing a "names" array.');
    }

    return [
      for (final entry in namesRaw)
        if (entry is String && entry.trim().isNotEmpty) entry.trim(),
    ];
  }

  static List<List<String>> batchesFor(
    List<String> names, {
    int batchSize = batchSize,
  }) {
    if (names.isEmpty || batchSize <= 0) {
      return const [];
    }

    final batches = <List<String>>[];
    for (var index = 0; index < names.length; index += batchSize) {
      final end = index + batchSize;
      batches.add(
        names.sublist(index, end > names.length ? names.length : end),
      );
    }
    return batches;
  }
}
