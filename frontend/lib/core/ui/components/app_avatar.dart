import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';

/// Application-owned avatar (`04-components` D5).
class AppAvatar extends StatelessWidget {
  const AppAvatar({required this.name, this.size = 32, super.key});

  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final initials = _initials(name);

    return CircleAvatar(
      radius: size / 2,
      backgroundColor: colors.surfaceSunken,
      child: Text(
        initials,
        style: AppTypography.bodySm(context).copyWith(fontWeight: FontWeight.w600, color: colors.textPrimary),
      ),
    );
  }

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) {
      return '?';
    }
    if (parts.length == 1) {
      return parts.first[0].toUpperCase();
    }
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }
}
