import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import 'package:ai_clinic/core/ui/theme/semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/spacing_tokens.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
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

/// Filter popover for the appointment calendar header.
class AppointmentCalendarFilterButton extends ConsumerStatefulWidget {
  const AppointmentCalendarFilterButton({
    required this.branchesAsync,
    required this.doctorsAsync,
    required this.selectedBranchId,
    required this.selectedDoctorId,
    required this.showDoctorFilter,
    required this.onBranchChanged,
    required this.onDoctorChanged,
    super.key,
  });

  final AsyncValue<List<BranchListItem>> branchesAsync;
  final AsyncValue<List<StaffListItem>> doctorsAsync;
  final String? selectedBranchId;
  final String? selectedDoctorId;
  final bool showDoctorFilter;
  final ValueChanged<String?> onBranchChanged;
  final ValueChanged<String?> onDoctorChanged;

  @override
  ConsumerState<AppointmentCalendarFilterButton> createState() => _AppointmentCalendarFilterButtonState();
}

class _AppointmentCalendarFilterButtonState extends ConsumerState<AppointmentCalendarFilterButton>
    with SingleTickerProviderStateMixin {
  late final FPopoverController _controller = FPopoverController(vsync: this);
  var _isHovered = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool _isFilterActive() {
    return widget.showDoctorFilter && widget.selectedDoctorId != null;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.semanticColors;
    final isFilterActive = _isFilterActive();

    return FPopover(
      control: FPopoverControl.managed(controller: _controller),
      style: _filterPopoverMotion,
      constraints: const FPortalConstraints(minWidth: 280, maxWidth: 320),
      popoverAnchor: Alignment.topCenter,
      childAnchor: Alignment.bottomCenter,
      popoverBuilder: (context, controller) => _AppointmentCalendarFilterPanel(
        branchesAsync: widget.branchesAsync,
        doctorsAsync: widget.doctorsAsync,
        selectedBranchId: widget.selectedBranchId,
        selectedDoctorId: widget.selectedDoctorId,
        showDoctorFilter: widget.showDoctorFilter,
        onBranchChanged: widget.onBranchChanged,
        onDoctorChanged: widget.onDoctorChanged,
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
        message: 'Filter appointments',
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

class _AppointmentCalendarFilterPanel extends StatelessWidget {
  const _AppointmentCalendarFilterPanel({
    required this.branchesAsync,
    required this.doctorsAsync,
    required this.selectedBranchId,
    required this.selectedDoctorId,
    required this.showDoctorFilter,
    required this.onBranchChanged,
    required this.onDoctorChanged,
  });

  final AsyncValue<List<BranchListItem>> branchesAsync;
  final AsyncValue<List<StaffListItem>> doctorsAsync;
  final String? selectedBranchId;
  final String? selectedDoctorId;
  final bool showDoctorFilter;
  final ValueChanged<String?> onBranchChanged;
  final ValueChanged<String?> onDoctorChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.semanticColors;

    return Padding(
      padding: const EdgeInsets.all(SpacingTokens.sm),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(SpacingTokens.sm, SpacingTokens.sm, SpacingTokens.sm, SpacingTokens.xs),
            child: Text('Filter by', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
          ),
          _FilterSection(
            title: 'Branch',
            icon: Icons.storefront_outlined,
            child: branchesAsync.when(
              data: (items) => AppFilterSelect<String?>(
                items: {for (final branch in items) branch.name: branch.id},
                value: selectedBranchId,
                hintText: items.isEmpty ? 'No branches' : 'Select branch',
                enabled: items.isNotEmpty,
                onChanged: items.isEmpty ? null : onBranchChanged,
              ),
              loading: () => const _FilterPanelPlaceholder(message: 'Loading branches…'),
              error: (_, _) => const _FilterPanelPlaceholder(message: 'Could not load branches.', error: true),
            ),
          ),
          if (showDoctorFilter) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: SpacingTokens.sm, vertical: SpacingTokens.xs),
              child: Divider(height: 1, color: colors.border),
            ),
            _FilterSection(
              title: 'Doctor',
              icon: Icons.person_outline,
              child: doctorsAsync.when(
                data: (doctors) => AppFilterSelect<String>(
                  items: {'All doctors': '', for (final doctor in doctors) doctor.fullName: doctor.id},
                  value: selectedDoctorId ?? '',
                  hintText: 'All doctors',
                  onChanged: (doctorId) => onDoctorChanged(doctorId == null || doctorId.isEmpty ? null : doctorId),
                ),
                loading: () => const _FilterPanelPlaceholder(message: 'Loading doctors…'),
                error: (_, _) => const _FilterPanelPlaceholder(message: 'Could not load doctors.', error: true),
              ),
            ),
          ],
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
