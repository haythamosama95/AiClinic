import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import 'package:ai_clinic/core/ui/theme/semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/spacing_tokens.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/appointment_doctor_select_items.dart';
import 'package:ai_clinic/features/settings/domain/branch_list_item.dart';
import 'package:ai_clinic/features/settings/domain/staff_list_item.dart';

final _filterPopoverMotion = FPopoverStyleDelta.delta(
  motion: FPopoverMotionDelta.delta(
    entranceDuration: Duration(milliseconds: 200),
    exitDuration: Duration(milliseconds: 150),
    scaleTween: Tween<double>(begin: 0.96, end: 1),
    fadeTween: Tween<double>(begin: 0, end: 1),
  ),
);

/// Applied branch and doctor filters for the appointment calendar.
typedef AppointmentCalendarFilters = ({String? branchId, String? doctorId});

/// Filter popover for the appointment calendar header.
class AppointmentCalendarFilterButton extends ConsumerStatefulWidget {
  const AppointmentCalendarFilterButton({
    required this.branchesAsync,
    required this.doctorsAsync,
    required this.appliedBranchId,
    required this.appliedDoctorId,
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
  final bool showDoctorFilter;
  final bool hasActiveFilters;
  final ValueChanged<AppointmentCalendarFilters> onApplyFilters;
  final VoidCallback onClearFilters;

  @override
  ConsumerState<AppointmentCalendarFilterButton> createState() => _AppointmentCalendarFilterButtonState();
}

class _AppointmentCalendarFilterButtonState extends ConsumerState<AppointmentCalendarFilterButton>
    with SingleTickerProviderStateMixin {
  late final FPopoverController _controller = FPopoverController(vsync: this);
  final _filterPopoverGroup = Object();
  var _isHovered = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.semanticColors;
    final isFilterActive = widget.hasActiveFilters;

    return FPopover(
      control: FPopoverControl.managed(controller: _controller),
      style: _filterPopoverMotion,
      groupId: _filterPopoverGroup,
      constraints: const FPortalConstraints(minWidth: 280, maxWidth: 320),
      popoverAnchor: Alignment.topCenter,
      childAnchor: Alignment.bottomCenter,
      popoverBuilder: (context, controller) => _AppointmentCalendarFilterPanel(
        controller: controller,
        filterPopoverGroup: _filterPopoverGroup,
        branchesAsync: widget.branchesAsync,
        doctorsAsync: widget.doctorsAsync,
        appliedBranchId: widget.appliedBranchId,
        appliedDoctorId: widget.appliedDoctorId,
        showDoctorFilter: widget.showDoctorFilter,
        onApplyFilters: widget.onApplyFilters,
        onClearFilters: widget.onClearFilters,
      ),
      builder: (context, controller, child) => MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        cursor: SystemMouseCursors.click,
        child: FTappable(
          onPress: controller.toggle,
          child: IgnorePointer(child: child),
        ),
      ),
      child: Tooltip(
        message: isFilterActive ? 'Filters active' : 'Filter appointments',
        child: SizedBox(
          width: 40,
          height: 40,
          child: Badge(
            isLabelVisible: isFilterActive,
            smallSize: 8,
            backgroundColor: colors.primary,
            child: Material(
              color: _isHovered ? colors.muted : colors.background,
              shape: CircleBorder(side: BorderSide(color: isFilterActive ? colors.primary : colors.border)),
              clipBehavior: Clip.antiAlias,
              child: Center(
                child: Icon(
                  Icons.filter_list_outlined,
                  color: isFilterActive ? colors.primary : colors.foreground,
                  size: 20,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AppointmentCalendarFilterPanel extends StatefulWidget {
  const _AppointmentCalendarFilterPanel({
    required this.controller,
    required this.filterPopoverGroup,
    required this.branchesAsync,
    required this.doctorsAsync,
    required this.appliedBranchId,
    required this.appliedDoctorId,
    required this.showDoctorFilter,
    required this.onApplyFilters,
    required this.onClearFilters,
  });

  final FPopoverController controller;
  final Object filterPopoverGroup;
  final AsyncValue<List<BranchListItem>> branchesAsync;
  final AsyncValue<List<StaffListItem>> doctorsAsync;
  final String? appliedBranchId;
  final String? appliedDoctorId;
  final bool showDoctorFilter;
  final ValueChanged<AppointmentCalendarFilters> onApplyFilters;
  final VoidCallback onClearFilters;

  @override
  State<_AppointmentCalendarFilterPanel> createState() => _AppointmentCalendarFilterPanelState();
}

class _AppointmentCalendarFilterPanelState extends State<_AppointmentCalendarFilterPanel> {
  late String? _draftBranchId;
  late String? _draftDoctorId;

  @override
  void initState() {
    super.initState();
    _syncDraftFromApplied();
  }

  @override
  void didUpdateWidget(covariant _AppointmentCalendarFilterPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.appliedBranchId != widget.appliedBranchId || oldWidget.appliedDoctorId != widget.appliedDoctorId) {
      _syncDraftFromApplied();
    }
  }

  void _syncDraftFromApplied() {
    _draftBranchId = widget.appliedBranchId;
    _draftDoctorId = widget.appliedDoctorId;
  }

  void _applyFilters() {
    widget.onApplyFilters((branchId: _draftBranchId, doctorId: _draftDoctorId));
    widget.controller.hide();
  }

  void _clearFilters() {
    widget.onClearFilters();
    widget.controller.hide();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.semanticColors;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(SpacingTokens.sm),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  SpacingTokens.sm,
                  SpacingTokens.sm,
                  SpacingTokens.sm,
                  SpacingTokens.xs,
                ),
                child: Text('Filter by', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
              ),
              _FilterSection(
                title: 'Branch',
                icon: Icons.storefront_outlined,
                child: widget.branchesAsync.when(
                  data: (items) => AppFilterSelect<String?>(
                    items: {for (final branch in items) branch.name: branch.id},
                    value: _draftBranchId,
                    hintText: items.isEmpty ? 'No branches' : 'Select branch',
                    enabled: items.isNotEmpty,
                    contentGroupId: widget.filterPopoverGroup,
                    showPopoverCloseButton: true,
                    onChanged: items.isEmpty ? null : (branchId) => setState(() => _draftBranchId = branchId),
                  ),
                  loading: () => const _FilterPanelPlaceholder(message: 'Loading branches…'),
                  error: (_, _) => const _FilterPanelPlaceholder(message: 'Could not load branches.', error: true),
                ),
              ),
              if (widget.showDoctorFilter) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: SpacingTokens.sm, vertical: SpacingTokens.xs),
                  child: Divider(height: 1, color: colors.border),
                ),
                _FilterSection(
                  title: 'Doctor',
                  icon: Icons.person_outline,
                  child: widget.doctorsAsync.when(
                    data: (doctors) {
                      final branchId = _draftBranchId ?? widget.appliedBranchId;

                      return AppFilterSelect<String>(
                        richChildren: AppointmentDoctorSelectItems.build(
                          context: context,
                          branchId: branchId,
                          doctors: doctors,
                          emptyLabel: 'All doctors',
                        ),
                        format: (doctorId) {
                          if (doctorId.isEmpty) {
                            return 'All doctors';
                          }
                          final doctor = doctors.where((entry) => entry.id == doctorId).firstOrNull;
                          return doctor?.fullName ?? 'All doctors';
                        },
                        value: _draftDoctorId ?? '',
                        hintText: 'All doctors',
                        contentGroupId: widget.filterPopoverGroup,
                        showPopoverCloseButton: true,
                        onChanged: (doctorId) =>
                            setState(() => _draftDoctorId = doctorId == null || doctorId.isEmpty ? null : doctorId),
                      );
                    },
                    loading: () => const _FilterPanelPlaceholder(message: 'Loading doctors…'),
                    error: (_, _) => const _FilterPanelPlaceholder(message: 'Could not load doctors.', error: true),
                  ),
                ),
              ],
            ],
          ),
        ),
        _FilterFooter(onClearFilters: _clearFilters, onApplyFilters: _applyFilters),
      ],
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
    final theme = Theme.of(context);
    final colors = context.semanticColors;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: SpacingTokens.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: colors.mutedForeground),
              const SizedBox(width: SpacingTokens.xs),
              Text(
                title,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: colors.mutedForeground,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
          const SizedBox(height: SpacingTokens.sm),
          child,
        ],
      ),
    );
  }
}

class _FilterFooter extends StatelessWidget {
  const _FilterFooter({required this.onClearFilters, required this.onApplyFilters});

  final VoidCallback onClearFilters;
  final VoidCallback onApplyFilters;

  @override
  Widget build(BuildContext context) {
    final colors = context.semanticColors;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.muted.withValues(alpha: 0.45),
        border: Border(top: BorderSide(color: colors.border)),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(SpacingTokens.md, SpacingTokens.md, SpacingTokens.md, SpacingTokens.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppButton(label: 'Apply Filters', size: AppFieldSize.sm, onPressed: onApplyFilters),
            const SizedBox(height: SpacingTokens.sm),
            AppButton(
              label: 'Clear Filters',
              variant: AppButtonVariant.outline,
              size: AppFieldSize.sm,
              onPressed: onClearFilters,
            ),
          ],
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
    final colors = context.semanticColors;

    return Text(
      message,
      style: Theme.of(
        context,
      ).textTheme.bodySmall?.copyWith(color: error ? colors.destructive : colors.mutedForeground),
    );
  }
}
