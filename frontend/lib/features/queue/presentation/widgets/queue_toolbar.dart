import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/components/app_button.dart';
import 'package:ai_clinic/core/ui/components/app_popover.dart';
import 'package:ai_clinic/core/ui/components/app_pressable.dart';
import 'package:ai_clinic/core/ui/components/app_search_input.dart';
import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';

/// Backend statuses shown in the toolbar filter, mirroring web `STATUS_LABELS` order
/// with `arrived` omitted and `confirmed` included (7 statuses).
const queueToolbarFilterStatuses = <AppointmentStatus>[
  AppointmentStatus.scheduled,
  AppointmentStatus.confirmed,
  AppointmentStatus.checkedIn,
  AppointmentStatus.inProgress,
  AppointmentStatus.completed,
  AppointmentStatus.cancelled,
  AppointmentStatus.noShow,
];

/// Production English labels aligned with web `STATUS_LABELS` where applicable.
const queueToolbarStatusLabels = <AppointmentStatus, String>{
  AppointmentStatus.scheduled: 'Scheduled',
  AppointmentStatus.confirmed: 'Confirmed',
  AppointmentStatus.checkedIn: 'Checked In',
  AppointmentStatus.inProgress: 'In Progress',
  AppointmentStatus.completed: 'Completed',
  AppointmentStatus.cancelled: 'Cancelled',
  AppointmentStatus.noShow: 'No Show',
};

/// Patient search and multi-select status filter (web `QueueToolbar`).
class QueueToolbar extends StatefulWidget {
  const QueueToolbar({
    required this.search,
    required this.onSearchChange,
    required this.statusFilters,
    required this.onToggleStatus,
    required this.onClearFilters,
    super.key,
  });

  final String search;
  final ValueChanged<String> onSearchChange;
  final Set<AppointmentStatus> statusFilters;
  final ValueChanged<AppointmentStatus> onToggleStatus;
  final VoidCallback onClearFilters;

  @override
  State<QueueToolbar> createState() => _QueueToolbarState();
}

class _QueueToolbarState extends State<QueueToolbar> {
  late final TextEditingController _searchController;
  var _statusPopoverOpen = false;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(text: widget.search);
  }

  @override
  void didUpdateWidget(covariant QueueToolbar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.search != oldWidget.search && widget.search != _searchController.text) {
      _searchController.text = widget.search;
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  int get _activeCount => widget.statusFilters.length;

  @override
  Widget build(BuildContext context) {
    final popoverWidth = math.min(
      256.0,
      MediaQuery.sizeOf(context).width - 32,
    );

    return Row(
      children: [
        Expanded(
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 200),
            child: Semantics(
              label: 'Search patients by name',
              textField: true,
              child: AppSearchInput(
                controller: _searchController,
                placeholder: 'Search patients…',
                showShortcutHint: false,
                onChanged: widget.onSearchChange,
              ),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.space3),
        AppPopover(
          open: _statusPopoverOpen,
          onOpenChange: (open) => setState(() => _statusPopoverOpen = open),
          align: AppPopoverAlign.end,
          matchTriggerWidth: false,
          width: popoverWidth,
          triggerBuilder: (context, isOpen, toggle) {
            return Semantics(
              button: true,
              expanded: isOpen,
              label: _activeCount > 0
                  ? 'Status filter, $_activeCount selected'
                  : 'Filter by status',
              child: AppButton(
                variant: AppButtonVariant.secondary,
                size: AppButtonSize.md,
                leadingIcon: const Icon(Icons.tune, size: 15),
                onPressed: toggle,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Status'),
                    if (_activeCount > 0)
                      Text(
                        ' · $_activeCount',
                        style: AppTypography.bodySm(context).copyWith(
                          color: context.appColors.textSecondary,
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
          child: _QueueStatusFilterMenu(
            statusFilters: widget.statusFilters,
            activeCount: _activeCount,
            onToggleStatus: widget.onToggleStatus,
            onClearFilters: widget.onClearFilters,
          ),
        ),
      ],
    );
  }
}

class _QueueStatusFilterMenu extends StatelessWidget {
  const _QueueStatusFilterMenu({
    required this.statusFilters,
    required this.activeCount,
    required this.onToggleStatus,
    required this.onClearFilters,
  });

  final Set<AppointmentStatus> statusFilters;
  final int activeCount;
  final ValueChanged<AppointmentStatus> onToggleStatus;
  final VoidCallback onClearFilters;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(AppSpacing.space2),
          child: Semantics(
            container: true,
            label: 'Filter by status',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.space2,
                    vertical: 6,
                  ),
                  child: Text(
                    'Status',
                    style: AppTypography.overline(context).copyWith(
                      color: colors.textTertiary,
                    ),
                  ),
                ),
                for (final status in queueToolbarFilterStatuses)
                  _QueueStatusFilterOptionRow(
                    label: queueToolbarStatusLabels[status]!,
                    selected: statusFilters.contains(status),
                    onPressed: () => onToggleStatus(status),
                  ),
              ],
            ),
          ),
        ),
        if (activeCount > 0)
          DecoratedBox(
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: colors.borderSubtle)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.space2),
              child: SizedBox(
                width: double.infinity,
                child: AppButton(
                  variant: AppButtonVariant.secondary,
                  size: AppButtonSize.sm,
                  onPressed: onClearFilters,
                  child: const Text('Clear filters'),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _QueueStatusFilterOptionRow extends StatefulWidget {
  const _QueueStatusFilterOptionRow({
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  State<_QueueStatusFilterOptionRow> createState() =>
      _QueueStatusFilterOptionRowState();
}

class _QueueStatusFilterOptionRowState extends State<_QueueStatusFilterOptionRow> {
  var _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final background = widget.selected
        ? colors.surfaceSelected
        : (_hovered ? colors.surfaceHover : Colors.transparent);
    final foreground = widget.selected
        ? colors.textPrimary
        : colors.textSecondary;
    final labelStyle = widget.selected
        ? AppTypography.bodySm(context).copyWith(
            fontWeight: FontWeight.w500,
            color: foreground,
          )
        : AppTypography.bodySm(context).copyWith(color: foreground);

    return Semantics(
      button: true,
      selected: widget.selected,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        cursor: SystemMouseCursors.click,
        child: Material(
          color: background,
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: AppPressable(
            onPressed: widget.onPressed,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.space2,
                vertical: AppSpacing.space2,
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: widget.selected
                        ? Icon(
                            Icons.check,
                            size: 14,
                            color: colors.actionPrimary,
                          )
                        : null,
                  ),
                  const SizedBox(width: AppSpacing.space2),
                  Expanded(child: Text(widget.label, style: labelStyle)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
