import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/app/shell/models/shell_nav_models.dart';
import 'package:ai_clinic/app/shell/widgets/shell_nav_group.dart';
import 'package:ai_clinic/core/ui/theme/spacing_tokens.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/app/shell/dev/shell_dev_fill_dummy_clinic.dart';
import 'package:ai_clinic/features/setup/presentation/providers/setup_notifier.dart';

/// Debug-only shell nav footer: Dev Options group (Theme Showcase, Reset Database).
///
/// Delete this file and its call site in [ShellNav] to remove dev tooling from the shell.
abstract final class ShellDevNav {
  const ShellDevNav._();

  static const groupId = 'dev-options';
  static const themeShowcaseId = 'theme-showcase';
  static const resetDatabaseId = 'reset-database';

  static ShellNavGroup get footerGroup => ShellNavGroup(
    id: groupId,
    label: 'Dev Options',
    icon: Icons.developer_mode_outlined,
    children: [
      const ShellNavSingle(id: themeShowcaseId, label: 'Theme Showcase', icon: Icons.palette_outlined),
      if (ShellDevFillDummyClinic.isEnabled)
        ShellNavSingle(
          id: ShellDevFillDummyClinic.itemId,
          label: ShellDevFillDummyClinic.label,
          icon: ShellDevFillDummyClinic.icon,
        ),
      const ShellNavSingle(id: resetDatabaseId, label: 'Reset Database', icon: Icons.storage_outlined),
    ],
  );

  static const Map<String, String> _routesByItemId = {themeShowcaseId: AppRoutes.foundationDemo};

  static bool get isEnabled => kDebugMode;

  static String? routeFor(String itemId) => _routesByItemId[itemId];

  static String? itemIdForLocation(String location) {
    for (final entry in _routesByItemId.entries) {
      if (entry.value == location) {
        return entry.key;
      }
    }
    return null;
  }

  static String? labelFor(String itemId) {
    for (final child in footerGroup.children) {
      if (child.id == itemId) {
        return child.label;
      }
    }
    return null;
  }

  static String? groupIdFor(String itemId) {
    if (footerGroup.children.any((child) => child.id == itemId)) {
      return groupId;
    }
    return null;
  }
}

/// Footer slot for [ShellNav]: expandable Dev Options group (debug builds only).
class ShellDevNavFooter extends ConsumerWidget {
  const ShellDevNavFooter({
    required this.selectedItemId,
    required this.expandedGroupIds,
    required this.onItemSelected,
    required this.onGroupToggled,
    super.key,
  });

  final String selectedItemId;
  final Set<String> expandedGroupIds;
  final ValueChanged<String> onItemSelected;
  final ValueChanged<String> onGroupToggled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ShellDevNav.isEnabled) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(SpacingTokens.md, SpacingTokens.sm, SpacingTokens.md, SpacingTokens.xs),
      child: ShellNavGroupWidget(
        group: ShellDevNav.footerGroup,
        isExpanded: expandedGroupIds.contains(ShellDevNav.groupId),
        selectedItemId: selectedItemId,
        onToggle: onGroupToggled,
        onSelected: (itemId) {
          if (itemId == ShellDevFillDummyClinic.itemId) {
            unawaited(ShellDevFillDummyClinic.handleNavSelection(context, ref));
            return;
          }
          if (itemId == ShellDevNav.resetDatabaseId) {
            unawaited(_confirmAndResetDatabase(context, ref));
            return;
          }
          onItemSelected(itemId);
        },
      ),
    );
  }

  Future<void> _confirmAndResetDatabase(BuildContext context, WidgetRef ref) async {
    await AppDialog.showConfirmation(
      context: context,
      title: 'Reset database?',
      message: 'This clears all clinic data for this installation. You will need to run setup again.',
      confirmLabel: 'Reset database',
      cancelLabel: 'Cancel',
      destructive: true,
      onConfirm: () => unawaited(_resetDatabase(context, ref)),
    );
  }

  Future<void> _resetDatabase(BuildContext context, WidgetRef ref) async {
    final ok = await ref.read(setupNotifierProvider.notifier).resetInstallationForDevelopment();
    if (!context.mounted) {
      return;
    }

    if (ok) {
      context.go(AppRoutes.bootstrap);
      return;
    }

    final errorMessage = ref.read(setupNotifierProvider).errorMessage;
    AppToast.error(context, message: errorMessage ?? 'Unable to reset clinic data.');
  }
}
