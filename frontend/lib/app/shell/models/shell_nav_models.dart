import 'package:flutter/material.dart';

/// Badge color tone for nav notification counters.
enum ShellNavBadgeTone { neutral, warning, success }

sealed class ShellNavEntry {
  const ShellNavEntry();
}

final class ShellNavSingle extends ShellNavEntry {
  const ShellNavSingle({required this.id, required this.label, required this.icon, this.badgeCount, this.badgeTone});

  final String id;
  final String label;
  final IconData icon;
  final int? badgeCount;
  final ShellNavBadgeTone? badgeTone;
}

final class ShellNavGroup extends ShellNavEntry {
  const ShellNavGroup({required this.id, required this.label, required this.icon, required this.children});

  final String id;
  final String label;
  final IconData icon;
  final List<ShellNavSingle> children;
}
