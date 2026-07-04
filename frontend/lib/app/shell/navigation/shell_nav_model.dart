import 'package:flutter/material.dart';

/// Navigation tree models for the authenticated shell.
@immutable
class ShellNavItem {
  const ShellNavItem({required this.id, required this.label, required this.icon, this.count});

  final String id;
  final String label;
  final IconData icon;
  final int? count;
}

@immutable
class ShellNavGroup {
  const ShellNavGroup({required this.id, required this.items, this.label});

  final String id;
  final String? label;
  final List<ShellNavItem> items;
}

@immutable
class ShellBranch {
  const ShellBranch({required this.id, required this.name, this.org});

  final String id;
  final String name;
  final String? org;
}

@immutable
class ShellUser {
  const ShellUser({required this.name, this.role, this.email});

  final String name;
  final String? role;
  final String? email;
}
