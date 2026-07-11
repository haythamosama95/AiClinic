import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/navigation/app_navigator.dart';
import 'package:ai_clinic/core/ui/components/app_icon_button.dart';
import 'package:ai_clinic/core/ui/components/app_menu.dart';
import 'package:ai_clinic/core/ui/components/app_toast.dart';
import 'package:ai_clinic/core/ui/theme/app_color_primitives.dart';
import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';
import 'package:ai_clinic/core/ui/theme/theme_transition_controller.dart';
import 'package:ai_clinic/features/patients/domain/usecases/patient_use_case_providers.dart';
import 'package:ai_clinic/features/patients/presentation/models/patient_list_filters.dart';
import 'package:ai_clinic/features/patients/presentation/providers/patient_list_notifier.dart';

/// Row actions menu for a patient table row (web `rowContextMenu`).
class PatientRowContextMenu extends ConsumerWidget {
  const PatientRowContextMenu({required this.row, super.key});

  final PatientTableRow row;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final patient = row.item;
    final patientId = patient.id;
    final fullName = patient.fullName;
    final colors = context.appColors;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final entries = <AppMenuEntry>[
      AppMenuItem(
        id: 'open',
        label: 'Open patient details',
        icon: const Icon(Icons.open_in_new, size: 16),
        onSelect: () => context.nav.pushPatientDetail(patientId, preview: patient),
      ),
      AppMenuItem(
        id: 'book',
        label: 'Book appointment',
        icon: const Icon(Icons.calendar_today, size: 16),
        onSelect: () => context.nav.goAppointments(),
      ),
      AppMenuItem(
        id: 'edit',
        label: 'Edit patient',
        icon: const Icon(Icons.edit, size: 16),
        onSelect: () => context.nav.pushPatientEdit(patientId),
      ),
      const AppMenuSeparator(),
      AppMenuItem(
        id: 'deactivate',
        label: 'Deactivate',
        icon: const Icon(Icons.person_off, size: 16),
        destructive: true,
        onSelect: () => _deactivatePatient(ref, patientId, fullName),
      ),
    ];

    return MenuAnchor(
      alignmentOffset: const Offset(0, AppSpacing.space1),
      style: MenuStyle(
        elevation: const WidgetStatePropertyAll(0),
        backgroundColor: WidgetStatePropertyAll(colors.surfaceRaised),
        surfaceTintColor: WidgetStatePropertyAll(colors.surfaceRaised),
        padding: const WidgetStatePropertyAll(EdgeInsets.all(AppSpacing.space1)),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            side: BorderSide(color: colors.borderDefault),
          ),
        ),
        shadowColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      menuChildren: _buildMenuChildren(context, colors, isDark, entries),
      builder: (context, controller, child) {
        return Material(
          color: Colors.transparent,
          child: AppIconButton(
            variant: AppIconButtonVariant.ghost,
            size: AppIconButtonSize.sm,
            icon: const Icon(Icons.more_vert, size: 16),
            label: 'Patient actions',
            onPressed: () {
              if (controller.isOpen) {
                controller.close();
              } else {
                controller.open();
              }
            },
          ),
        );
      },
    );
  }

  List<Widget> _buildMenuChildren(
    BuildContext context,
    AppSemanticColors colors,
    bool isDark,
    List<AppMenuEntry> entries,
  ) {
    final items = <Widget>[];

    for (final entry in entries) {
      switch (entry) {
        case AppMenuSeparator():
          items.add(
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.space1),
              child: Divider(height: 1, thickness: 1, color: colors.borderSubtle),
            ),
          );
        case AppMenuSection(:final label, items: final sectionItems):
          if (label != null) {
            items.add(
              Padding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.space2, AppSpacing.space1, AppSpacing.space2, 0),
                child: Text(label, style: AppTypography.caption(context).copyWith(color: colors.textTertiary)),
              ),
            );
          }
          for (final item in sectionItems) {
            items.add(_buildMenuItemButton(context, colors, isDark, item));
          }
        case AppMenuItem item:
          items.add(_buildMenuItemButton(context, colors, isDark, item));
      }
    }

    return items;
  }

  Widget _buildMenuItemButton(
    BuildContext context,
    AppSemanticColors colors,
    bool isDark,
    AppMenuItem item,
  ) {
    final dangerSurface = isDark ? AppColorPrimitives.statusDangerSurfaceDark : AppColorPrimitives.red50;

    return MenuItemButton(
      onPressed: item.disabled
          ? null
          : () {
              item.onSelect?.call();
              final controller = MenuController.maybeOf(context);
              controller?.close();
            },
      style: ButtonStyle(
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          if (item.disabled) {
            return colors.textDisabled;
          }
          if (item.destructive) {
            return colors.statusDangerFg;
          }
          return colors.textPrimary;
        }),
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (item.disabled) {
            return Colors.transparent;
          }
          if (states.contains(WidgetState.hovered) || states.contains(WidgetState.focused)) {
            return item.destructive ? dangerSurface : colors.surfaceHover;
          }
          return Colors.transparent;
        }),
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: AppSpacing.space2, vertical: 6),
        ),
        shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md))),
        textStyle: WidgetStatePropertyAll(AppTypography.body(context)),
      ),
      leadingIcon: item.icon == null
          ? null
          : IconTheme(
              data: IconThemeData(
                size: 16,
                color: item.disabled
                    ? colors.textDisabled
                    : (item.destructive ? colors.statusDangerFg : colors.iconDefault),
              ),
              child: item.icon!,
            ),
      child: Text(item.label),
    );
  }

  Future<void> _deactivatePatient(WidgetRef ref, String patientId, String fullName) async {
    await ref.read(archivePatientUseCaseProvider).call(patientId);
    await ref.read(patientListProvider.notifier).reload();

    final toastContext = ref.read(rootNavigatorKeyProvider).currentContext;
    if (toastContext != null && toastContext.mounted) {
      appToast(
        toastContext,
        AppToastInput(
          message: '$fullName deactivated.',
          variant: AppToastVariant.success,
        ),
      );
    }
  }
}
