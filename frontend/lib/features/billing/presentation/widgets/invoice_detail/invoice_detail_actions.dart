import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/components/app_icon_button.dart';
import 'package:ai_clinic/core/ui/components/app_menu.dart';
import 'package:ai_clinic/core/ui/theme/app_color_primitives.dart';
import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';
import 'package:ai_clinic/features/billing/domain/invoice_detail.dart';
import 'package:ai_clinic/features/billing/presentation/providers/invoice_detail_provider.dart';

/// Permission-aware overflow actions for the invoice detail hero card.
class InvoiceDetailActions extends StatefulWidget {
  const InvoiceDetailActions({
    required this.invoice,
    required this.view,
    required this.onEdit,
    required this.onVoid,
    required this.onRecordPayment,
    required this.onRecordRefund,
    required this.onViewPatient,
    required this.onViewVisit,
    super.key,
  });

  final InvoiceDetail invoice;
  final InvoiceDetailViewState view;
  final VoidCallback onEdit;
  final VoidCallback onVoid;
  final VoidCallback onRecordPayment;
  final VoidCallback onRecordRefund;
  final VoidCallback onViewPatient;
  final VoidCallback onViewVisit;

  @override
  State<InvoiceDetailActions> createState() => _InvoiceDetailActionsState();
}

class _InvoiceDetailActionsState extends State<InvoiceDetailActions> {
  final FocusNode _triggerFocusNode = FocusNode();

  @override
  void dispose() {
    _triggerFocusNode.dispose();
    super.dispose();
  }

  List<AppMenuEntry> _buildEntries() {
    final invoice = widget.invoice;
    final view = widget.view;

    final canEdit = invoice.status.isDraft && view.canCreate;
    final canVoid = view.canVoid && invoice.status.isVoidable;
    final canPay =
        view.canRecordPayment &&
        !invoice.status.isDraft &&
        !invoice.status.isTerminal;
    final canRefund =
        view.canRefund && invoice.payments.any((payment) => !payment.isRefund);

    final entries = <AppMenuEntry>[];

    if (canEdit) {
      entries.add(
        AppMenuItem(
          id: 'edit',
          label: 'Edit draft',
          icon: const Icon(Icons.edit_outlined, size: 16),
          onSelect: widget.onEdit,
        ),
      );
    }
    if (canVoid) {
      entries.add(
        AppMenuItem(
          id: 'void',
          label: 'Void',
          icon: const Icon(Icons.delete_outline, size: 16),
          destructive: true,
          onSelect: widget.onVoid,
        ),
      );
    }
    if (canPay) {
      entries.add(
        AppMenuItem(
          id: 'record-payment',
          label: 'Record payment',
          icon: const Icon(Icons.payments_outlined, size: 16),
          onSelect: widget.onRecordPayment,
        ),
      );
    }
    if (canRefund) {
      entries.add(
        AppMenuItem(
          id: 'record-refund',
          label: 'Record refund',
          icon: const Icon(Icons.replay, size: 16),
          onSelect: widget.onRecordRefund,
        ),
      );
    }

    if (entries.isNotEmpty) {
      entries.add(const AppMenuSeparator());
    }

    entries.addAll([
      AppMenuItem(
        id: 'view-patient',
        label: 'View patient profile',
        icon: const Icon(Icons.person_outline, size: 16),
        onSelect: widget.onViewPatient,
      ),
      AppMenuItem(
        id: 'view-visit',
        label: 'View visit',
        icon: const Icon(Icons.event_note_outlined, size: 16),
        onSelect: widget.onViewVisit,
      ),
    ]);

    return entries;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final entries = _buildEntries();

    return MenuAnchor(
      childFocusNode: _triggerFocusNode,
      alignmentOffset: const Offset(0, AppSpacing.space1),
      style: MenuStyle(
        elevation: const WidgetStatePropertyAll(0),
        backgroundColor: WidgetStatePropertyAll(colors.surfaceRaised),
        surfaceTintColor: WidgetStatePropertyAll(colors.surfaceRaised),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.all(AppSpacing.space1),
        ),
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
        return Focus(
          focusNode: _triggerFocusNode,
          child: Material(
            color: Colors.transparent,
            child: AppIconButton(
              variant: AppIconButtonVariant.secondary,
              size: AppIconButtonSize.lg,
              icon: const Icon(Icons.more_vert),
              label: 'Invoice actions',
              tooltipDisabled: true,
              onPressed: () {
                if (controller.isOpen) {
                  controller.close();
                } else {
                  controller.open();
                }
              },
            ),
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
              child: Divider(
                height: 1,
                thickness: 1,
                color: colors.borderSubtle,
              ),
            ),
          );
        case AppMenuSection(:final label, items: final sectionItems):
          if (label != null) {
            items.add(
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.space2,
                  AppSpacing.space1,
                  AppSpacing.space2,
                  0,
                ),
                child: Text(
                  label,
                  style: AppTypography.caption(
                    context,
                  ).copyWith(color: colors.textTertiary),
                ),
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
    final dangerSurface = isDark
        ? AppColorPrimitives.statusDangerSurfaceDark
        : AppColorPrimitives.red50;

    return MenuItemButton(
      onPressed: item.disabled
          ? null
          : () {
              item.onSelect?.call();
              MenuController.maybeOf(context)?.close();
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
          if (states.contains(WidgetState.hovered) ||
              states.contains(WidgetState.focused)) {
            return item.destructive ? dangerSurface : colors.surfaceHover;
          }
          return Colors.transparent;
        }),
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: AppSpacing.space2, vertical: 6),
        ),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
        ),
        textStyle: WidgetStatePropertyAll(AppTypography.body(context)),
      ),
      leadingIcon: item.icon == null
          ? null
          : IconTheme(
              data: IconThemeData(
                size: 16,
                color: item.disabled
                    ? colors.textDisabled
                    : (item.destructive
                          ? colors.statusDangerFg
                          : colors.iconDefault),
              ),
              child: item.icon!,
            ),
      child: Text(item.label),
    );
  }
}
