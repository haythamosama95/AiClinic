import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_calendar_display.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/appointment_doctor_select_items.dart';
import 'package:ai_clinic/features/clinic-management/domain/branch_list_item.dart';
import 'package:ai_clinic/features/clinic-management/domain/staff_list_item.dart';

/// Applied branch, doctor, and status filters for the appointment calendar.
typedef AppointmentCalendarFilters = ({String? branchId, String? doctorId, Set<AppointmentStatus> statuses});

/// Filter popover for the appointment calendar toolbar.
class AppointmentCalendarFilterButton extends ConsumerStatefulWidget {
  const AppointmentCalendarFilterButton({
    required this.branchesAsync,
    required this.doctorsAsync,
    required this.appliedBranchId,
    required this.appliedDoctorId,
    required this.appliedStatuses,
    required this.showDoctorFilter,
    required this.hasActiveFilters,
    required this.onApplyFilters,
    required this.onClearFilters,
    super.key,
  });

  final AsyncValue<List<BranchListItem>> branchesAsync;
  final AsyncValue<List<StaffListItem>> doctorsAsync;
  final String? appliedBranchId;
  final String? appliedDoctorId;
  final Set<AppointmentStatus> appliedStatuses;
  final bool showDoctorFilter;
  final bool hasActiveFilters;
  final ValueChanged<AppointmentCalendarFilters> onApplyFilters;
  final VoidCallback onClearFilters;

  @override
  ConsumerState<AppointmentCalendarFilterButton> createState() => _AppointmentCalendarFilterButtonState();
}

class _AppointmentCalendarFilterButtonState extends ConsumerState<AppointmentCalendarFilterButton> {
  var _open = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return AppPopover(
      open: _open,
      onOpenChange: (open) => setState(() => _open = open),
      minWidth: 320,
      matchTriggerWidth: false,
      triggerBuilder: (context, isOpen, onToggle) {
        return AppIconButton(
          icon: Icon(
            Icons.filter_list_outlined,
            color: widget.hasActiveFilters ? colors.actionPrimary : colors.iconDefault,
          ),
          label: widget.hasActiveFilters ? 'Filters active' : 'Filter appointments',
          tooltip: widget.hasActiveFilters ? 'Filters active' : 'Filter appointments',
          variant: widget.hasActiveFilters ? AppIconButtonVariant.secondary : AppIconButtonVariant.ghost,
          onPressed: onToggle,
        );
      },
      child: _AppointmentCalendarFilterPanel(
        branchesAsync: widget.branchesAsync,
        doctorsAsync: widget.doctorsAsync,
        appliedBranchId: widget.appliedBranchId,
        appliedDoctorId: widget.appliedDoctorId,
        appliedStatuses: widget.appliedStatuses,
        showDoctorFilter: widget.showDoctorFilter,
        onApplyFilters: (filters) {
          widget.onApplyFilters(filters);
          setState(() => _open = false);
        },
        onClearFilters: () {
          widget.onClearFilters();
          setState(() => _open = false);
        },
      ),
    );
  }
}

class _AppointmentCalendarFilterPanel extends StatefulWidget {
  const _AppointmentCalendarFilterPanel({
    required this.branchesAsync,
    required this.doctorsAsync,
    required this.appliedBranchId,
    required this.appliedDoctorId,
    required this.appliedStatuses,
    required this.showDoctorFilter,
    required this.onApplyFilters,
    required this.onClearFilters,
  });

  final AsyncValue<List<BranchListItem>> branchesAsync;
  final AsyncValue<List<StaffListItem>> doctorsAsync;
  final String? appliedBranchId;
  final String? appliedDoctorId;
  final Set<AppointmentStatus> appliedStatuses;
  final bool showDoctorFilter;
  final ValueChanged<AppointmentCalendarFilters> onApplyFilters;
  final VoidCallback onClearFilters;

  @override
  State<_AppointmentCalendarFilterPanel> createState() => _AppointmentCalendarFilterPanelState();
}

class _AppointmentCalendarFilterPanelState extends State<_AppointmentCalendarFilterPanel> {
  late String? _draftBranchId;
  late String? _draftDoctorId;
  late Set<AppointmentStatus> _draftStatuses;
  late List<AppComboboxItem> _draftStatusItems;

  static List<AppComboboxItem> get _statusOptions => [
    for (final status in AppointmentCalendarDisplay.calendarStatusLegend)
      AppComboboxItem(id: status.name, label: status.label),
  ];

  @override
  void initState() {
    super.initState();
    _syncDraftFromApplied();
  }

  @override
  void didUpdateWidget(covariant _AppointmentCalendarFilterPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.appliedBranchId != widget.appliedBranchId ||
        oldWidget.appliedDoctorId != widget.appliedDoctorId ||
        !setEquals(oldWidget.appliedStatuses, widget.appliedStatuses)) {
      _syncDraftFromApplied();
    }
  }

  void _syncDraftFromApplied() {
    _draftBranchId = widget.appliedBranchId;
    _draftDoctorId = widget.appliedDoctorId;
    _draftStatuses = Set<AppointmentStatus>.from(widget.appliedStatuses);
    _draftStatusItems = _statusOptions
        .where((option) => _draftStatuses.any((status) => status.name == option.id))
        .toList(growable: false);
  }

  Set<AppointmentStatus> _statusesFromItems(List<AppComboboxItem> items) {
    return items
        .map((item) => AppointmentStatus.values.where((status) => status.name == item.id).firstOrNull)
        .whereType<AppointmentStatus>()
        .toSet();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.space4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Filter by', style: AppTypography.bodyStrong(context)),
          const SizedBox(height: AppSpacing.space4),
          _FilterSection(
            title: 'Branch',
            icon: Icons.storefront_outlined,
            child: widget.branchesAsync.when(
              data: (items) => AppSelect(
                options: [for (final branch in items) AppSelectOption(value: branch.id, label: branch.name)],
                value: _draftBranchId ?? '',
                disabled: items.isEmpty,
                placeholder: items.isEmpty ? 'No branches' : 'Select branch',
                onChanged: items.isEmpty ? null : (branchId) => setState(() => _draftBranchId = branchId),
              ),
              loading: () => const _FilterPanelPlaceholder(message: 'Loading branches…'),
              error: (_, _) => const _FilterPanelPlaceholder(message: 'Could not load branches.', error: true),
            ),
          ),
          if (widget.showDoctorFilter) ...[
            const SizedBox(height: AppSpacing.space4),
            Divider(height: 1, color: colors.borderSubtle),
            const SizedBox(height: AppSpacing.space4),
            _FilterSection(
              title: 'Doctor',
              icon: Icons.person_outline,
              child: widget.doctorsAsync.when(
                data: (doctors) {
                  final branchId = _draftBranchId ?? widget.appliedBranchId;
                  return AppSelect(
                    options: AppointmentDoctorSelectItems.buildOptions(
                      branchId: branchId,
                      doctors: doctors,
                      emptyLabel: 'All doctors',
                    ),
                    value: _draftDoctorId ?? '',
                    placeholder: 'All doctors',
                    onChanged: (doctorId) =>
                        setState(() => _draftDoctorId = doctorId.isEmpty ? null : doctorId),
                  );
                },
                loading: () => const _FilterPanelPlaceholder(message: 'Loading doctors…'),
                error: (_, _) => const _FilterPanelPlaceholder(message: 'Could not load doctors.', error: true),
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.space4),
          Divider(height: 1, color: colors.borderSubtle),
          const SizedBox(height: AppSpacing.space4),
          _FilterSection(
            title: 'Appointment status',
            icon: Icons.event_available_outlined,
            child: AppMultiSelect(
              placeholder: 'All statuses',
              options: _statusOptions,
              value: _draftStatusItems,
              onValueChange: (items) => setState(() {
                _draftStatusItems = items;
                _draftStatuses = _statusesFromItems(items);
              }),
            ),
          ),
          const SizedBox(height: AppSpacing.space6),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              AppButton(
                variant: AppButtonVariant.secondary,
                onPressed: widget.onClearFilters,
                child: const Text('Clear'),
              ),
              const SizedBox(width: AppSpacing.space2),
              AppButton(
                onPressed: () => widget.onApplyFilters((
                  branchId: _draftBranchId,
                  doctorId: _draftDoctorId,
                  statuses: _draftStatuses,
                )),
                child: const Text('Apply'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FilterSection extends StatelessWidget {
  const _FilterSection({required this.title, required this.icon, required this.child});

  final String title;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: colors.iconMuted),
            const SizedBox(width: AppSpacing.space1),
            Text(title, style: AppTypography.caption(context).copyWith(color: colors.textSecondary)),
          ],
        ),
        const SizedBox(height: AppSpacing.space2),
        child,
      ],
    );
  }
}

class _FilterPanelPlaceholder extends StatelessWidget {
  const _FilterPanelPlaceholder({required this.message, this.error = false});

  final String message;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Text(
      message,
      style: AppTypography.bodySm(context).copyWith(color: error ? colors.statusDangerFg : colors.textSecondary),
    );
  }
}
