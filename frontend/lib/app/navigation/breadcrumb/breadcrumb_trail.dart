import 'package:flutter/foundation.dart';

import 'package:ai_clinic/app/navigation/breadcrumb/breadcrumb_entry.dart';
import 'package:ai_clinic/app/navigation/breadcrumb/breadcrumb_label.dart';

/// Ordered breadcrumb segments for the current route.
@immutable
class BreadcrumbTrail {
  const BreadcrumbTrail(this.entries);

  final List<BreadcrumbEntry> entries;

  static const empty = BreadcrumbTrail([]);

  BreadcrumbTrail append(BreadcrumbEntry entry) => BreadcrumbTrail([...entries, entry]);

  BreadcrumbTrail updateLabel(String entryId, BreadcrumbLabel label) => BreadcrumbTrail([
    for (final entry in entries)
      if (entry.id == entryId) entry.copyWith(label: label) else entry,
  ]);

  /// Keeps resolved labels from [current] when [incoming] still uses the `…` placeholder.
  BreadcrumbTrail mergePreservedLabelsFrom(BreadcrumbTrail current) {
    if (entries.isEmpty) {
      return this;
    }

    final currentById = {for (final entry in current.entries) entry.id: entry};
    return BreadcrumbTrail([for (final entry in entries) entry.mergePreservedLabelFrom(currentById[entry.id])]);
  }

  BreadcrumbEntry? get parent => entries.length > 1 ? entries[entries.length - 2] : null;

  BreadcrumbEntry? get current => entries.isNotEmpty ? entries.last : null;

  /// Weak deep-link default for visit documentation: Calendar → Visit documentation.
  bool get isWeakVisitDocumentDefault {
    if (entries.length != 2) {
      return false;
    }
    return entries[0].id == 'hub:calendar' && entries[1].id.startsWith('visit-doc:');
  }
}
