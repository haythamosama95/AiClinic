import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_calendar_status_filter.dart';
import 'package:ai_clinic/features/appointments/presentation/theme/appointment_calendar_status_theme.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/appointment_calendar_status_swatch.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/appointment_doctor_select_items.dart';
import 'package:ai_clinic/core/domain/clinic/branch_list_item.dart';
import 'package:ai_clinic/core/domain/clinic/staff_list_item.dart';

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

  int get _activeFilterCount {
    var count = 0;
    if (widget.appliedDoctorId != null && widget.appliedDoctorId!.isNotEmpty) {
      count++;
    }
    if (widget.appliedStatuses.isNotEmpty) {
      count++;
    }
    return count;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final activeCount = _activeFilterCount;

    return AppPopover(
      open: _open,
      onOpenChange: (open) => setState(() => _open = open),
      align: AppPopoverAlign.end,
      minWidth: 360,
      width: 380,
      matchTriggerWidth: false,
      estimatedContentHeight: 460,
      triggerBuilder: (context, isOpen, onToggle) {
        return Semantics(
          button: true,
          label: activeCount > 0 ? 'Schedule filters, $activeCount active' : 'Schedule filters',
          child: AppIconButton(
            icon: Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(
                  Icons.filter_list_outlined,
                  color: widget.hasActiveFilters ? colors.actionPrimary : colors.iconDefault,
                ),
                if (activeCount > 0)
                  Positioned(
                    top: -4,
                    right: -4,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: colors.actionPrimary,
                        borderRadius: BorderRadius.circular(AppRadius.full),
                        border: Border.all(color: colors.surfaceRaised, width: 1.5),
                      ),
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: Center(
                          child: Text(
                            '$activeCount',
                            style: AppTypography.caption(context).copyWith(
                              color: colors.actionPrimaryFg,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              height: 1,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            label: activeCount > 0 ? 'Filters active' : 'Schedule filters',
            tooltip: activeCount > 0 ? 'Filters active' : 'Schedule filters',
            variant: widget.hasActiveFilters || isOpen ? AppIconButtonVariant.secondary : AppIconButtonVariant.ghost,
            onPressed: onToggle,
          ),
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
  }

  int get _draftFilterCount {
    var count = 0;
    if (_draftDoctorId != null && _draftDoctorId!.isNotEmpty) {
      count++;
    }
    if (_draftStatuses.isNotEmpty) {
      count++;
    }
    return count;
  }

  void _toggleStatus(AppointmentStatus status) {
    setState(() {
      _draftStatuses = AppointmentCalendarStatusFilter.toggleStatusChip(status, _draftStatuses);
    });
  }

  bool _isDefaultStatusFilter() => AppointmentCalendarStatusFilter.isDefaultStatusFilter(_draftStatuses);

  String _statusSummary() {
    if (_isDefaultStatusFilter()) {
      return 'Hiding cancelled and no-show';
    }

    final hiddenShown = _draftStatuses.where(AppointmentCalendarStatusFilter.isHiddenOnCalendar).toSet();
    final workflowFiltered = _draftStatuses
        .where((status) => !AppointmentCalendarStatusFilter.isHiddenOnCalendar(status))
        .toSet();

    final parts = <String>[];
    if (workflowFiltered.isNotEmpty) {
      if (workflowFiltered.length == 1) {
        parts.add(workflowFiltered.first.label);
      } else {
        parts.add('${workflowFiltered.length} statuses highlighted');
      }
    }
    if (hiddenShown.isNotEmpty) {
      if (hiddenShown.length == 1) {
        parts.add('Including ${hiddenShown.first.label.toLowerCase()}');
      } else {
        parts.add('Including cancelled and no-show');
      }
    }
    return parts.isEmpty ? 'Custom status filter' : parts.join(' · ');
  }

  String _statusHelperText() {
    if (_isDefaultStatusFilter()) {
      return 'Cancelled and no-show stay off the calendar unless you include them below.';
    }

    final hiddenShown = _draftStatuses.where(AppointmentCalendarStatusFilter.isHiddenOnCalendar).toSet();
    final workflowFiltered = _draftStatuses
        .where((status) => !AppointmentCalendarStatusFilter.isHiddenOnCalendar(status))
        .toSet();

    if (workflowFiltered.isNotEmpty) {
      return 'Only selected statuses stay at full color on the calendar.';
    }
    if (hiddenShown.isNotEmpty) {
      return 'Including inactive appointments on the calendar.';
    }
    return 'Adjust which appointments appear on the calendar.';
  }

  String _branchLabel(List<BranchListItem> branches) {
    if (_draftBranchId == null || _draftBranchId!.isEmpty) {
      return 'No branch';
    }
    return branches.where((branch) => branch.id == _draftBranchId).firstOrNull?.name ?? 'Selected branch';
  }

  String _doctorLabel(List<StaffListItem> doctors) {
    if (_draftDoctorId == null || _draftDoctorId!.isEmpty) {
      return 'All doctors';
    }
    return doctors.where((doctor) => doctor.id == _draftDoctorId).firstOrNull?.fullName ?? 'Selected doctor';
  }

  String _buildPreviewSummary({required List<BranchListItem> branches, required List<StaffListItem> doctors}) {
    final parts = <String>[_branchLabel(branches)];
    if (widget.showDoctorFilter) {
      parts.add(_doctorLabel(doctors));
    }
    parts.add(_statusSummary());
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final brightness = Theme.of(context).brightness;
    final branches = widget.branchesAsync.asData?.value ?? const <BranchListItem>[];
    final doctors = widget.doctorsAsync.asData?.value ?? const <StaffListItem>[];

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _FilterPanelHeader(activeCount: _draftFilterCount),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.space4,
            AppSpacing.space4,
            AppSpacing.space4,
            AppSpacing.space3,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _FilterScopeSection(
                label: 'Location',
                child: widget.branchesAsync.when(
                  data: (items) => AppSelect(
                    options: [for (final branch in items) AppSelectOption(value: branch.id, label: branch.name)],
                    value: _draftBranchId ?? '',
                    disabled: items.isEmpty,
                    placeholder: items.isEmpty ? 'No branches' : 'Select branch',
                    onChanged: items.isEmpty
                        ? null
                        : (branchId) => setState(() {
                            _draftBranchId = branchId;
                            if (_draftDoctorId != null &&
                                _draftDoctorId!.isNotEmpty &&
                                items.any((branch) => branch.id == branchId)) {
                              final doctor = doctors.where((entry) => entry.id == _draftDoctorId).firstOrNull;
                              if (doctor != null && branchId.isNotEmpty && !doctor.isAssignedToBranch(branchId)) {
                                _draftDoctorId = null;
                              }
                            }
                          }),
                  ),
                  loading: () => const _FilterPanelPlaceholder(message: 'Loading branches…'),
                  error: (_, _) => const _FilterPanelPlaceholder(message: 'Could not load branches.', error: true),
                ),
              ),
              if (widget.showDoctorFilter) ...[
                const SizedBox(height: AppSpacing.space4),
                _FilterScopeSection(
                  label: 'Provider',
                  child: widget.doctorsAsync.when(
                    data: (doctorItems) {
                      final branchId = _draftBranchId ?? widget.appliedBranchId;
                      return AppSelect(
                        options: AppointmentDoctorSelectItems.buildOptions(
                          branchId: branchId,
                          doctors: doctorItems,
                          emptyLabel: 'All doctors',
                        ),
                        value: _draftDoctorId ?? '',
                        placeholder: 'All doctors',
                        onChanged: (doctorId) => setState(() => _draftDoctorId = doctorId.isEmpty ? null : doctorId),
                      );
                    },
                    loading: () => const _FilterPanelPlaceholder(message: 'Loading doctors…'),
                    error: (_, _) => const _FilterPanelPlaceholder(message: 'Could not load doctors.', error: true),
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.space4),
              _FilterScopeSection(
                label: 'Appointment status',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Wrap(
                      spacing: AppSpacing.space2,
                      runSpacing: AppSpacing.space2,
                      children: [
                        for (final status in AppointmentCalendarStatusFilter.calendarStatusLegend)
                          _StatusFilterChip(
                            status: status,
                            selected: AppointmentCalendarStatusFilter.isStatusChipSelected(status, _draftStatuses),
                            onToggle: () => _toggleStatus(status),
                          ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.space2),
                    Text(
                      _statusHelperText(),
                      style: AppTypography.caption(context).copyWith(color: colors.textTertiary),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: colors.borderSubtle)),
            color: colors.surfaceSunken.withValues(alpha: brightness == Brightness.dark ? 0.45 : 0.55),
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.space4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _buildPreviewSummary(branches: branches, doctors: doctors),
                  style: AppTypography.caption(context).copyWith(color: colors.textSecondary),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: AppSpacing.space3),
                Row(
                  children: [
                    Expanded(
                      child: AppButton(
                        variant: AppButtonVariant.secondary,
                        size: AppButtonSize.sm,
                        onPressed: widget.onClearFilters,
                        child: const Text('Reset filters'),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.space2),
                    Expanded(
                      child: AppButton(
                        size: AppButtonSize.sm,
                        onPressed: () => widget.onApplyFilters((
                          branchId: _draftBranchId,
                          doctorId: _draftDoctorId,
                          statuses: _draftStatuses,
                        )),
                        child: const Text('Apply filters'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _FilterPanelHeader extends StatelessWidget {
  const _FilterPanelHeader({required this.activeCount});

  final int activeCount;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [colors.actionPrimary.withValues(alpha: 0.1), colors.surfaceRaised],
        ),
        border: Border(bottom: BorderSide(color: colors.borderSubtle)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.space4, AppSpacing.space3, AppSpacing.space4, AppSpacing.space3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Schedule filters', style: AppTypography.overline(context).copyWith(color: colors.textTertiary)),
                  const SizedBox(height: AppSpacing.space1),
                  Text('Narrow the schedule', style: AppTypography.bodyStrong(context)),
                ],
              ),
            ),
            if (activeCount > 0)
              AppBadge(
                label: '$activeCount active',
                color: BadgeColor.teal,
                variant: BadgeVariant.soft,
                size: BadgeSize.sm,
              ),
          ],
        ),
      ),
    );
  }
}

class _FilterScopeSection extends StatelessWidget {
  const _FilterScopeSection({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, style: AppTypography.overline(context).copyWith(color: colors.textTertiary)),
        const SizedBox(height: AppSpacing.space2),
        child,
      ],
    );
  }
}

class _StatusFilterChip extends StatefulWidget {
  const _StatusFilterChip({required this.status, required this.selected, required this.onToggle});

  final AppointmentStatus status;
  final bool selected;
  final VoidCallback onToggle;

  @override
  State<_StatusFilterChip> createState() => _StatusFilterChipState();
}

class _StatusFilterChipState extends State<_StatusFilterChip> {
  var _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final brightness = Theme.of(context).brightness;
    final style = AppointmentCalendarStatusTheme.statusStyle(widget.status, brightness);
    final background = widget.selected
        ? Color.alphaBlend(style.gradientStart.withValues(alpha: 0.55), colors.surfaceDefault)
        : (_hovered ? colors.surfaceHover : colors.surfaceDefault);

    return Semantics(
      button: true,
      selected: widget.selected,
      label: widget.status.label,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        cursor: SystemMouseCursors.click,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(
              color: widget.selected ? style.accent : colors.borderSubtle,
              width: widget.selected ? 1.5 : 1,
            ),
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: BorderRadius.circular(AppRadius.md),
              onTap: widget.onToggle,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space2, vertical: AppSpacing.space1),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: AppointmentCalendarStatusSwatch.decoration(style, radius: AppRadius.sm),
                    ),
                    const SizedBox(width: AppSpacing.space1),
                    Text(widget.status.label, style: AppTypography.bodySm(context)),
                    if (widget.selected) ...[
                      const SizedBox(width: AppSpacing.space1),
                      Icon(Icons.check, size: 14, color: style.accent),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
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

    if (error) {
      return Text(message, style: AppTypography.bodySm(context).copyWith(color: colors.statusDangerFg));
    }

    return Row(
      children: [
        SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: colors.actionPrimary)),
        const SizedBox(width: AppSpacing.space2),
        Expanded(
          child: Text(message, style: AppTypography.bodySm(context).copyWith(color: colors.textSecondary)),
        ),
      ],
    );
  }
}
