import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import 'package:ai_clinic/core/ui/theme/semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/spacing_tokens.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/settings/domain/branch_list_item.dart';
import 'package:ai_clinic/features/settings/domain/staff_list_query.dart';
import 'package:ai_clinic/features/settings/presentation/providers/clinic_setup_providers.dart';

final _filterPopoverMotion = FPopoverStyleDelta.delta(
  motion: FPopoverMotionDelta.delta(
    entranceDuration: Duration(milliseconds: 180),
    exitDuration: Duration(milliseconds: 140),
    scaleTween: Tween<double>(begin: 0.98, end: 1),
    fadeTween: Tween<double>(begin: 0, end: 1),
  ),
);

/// Filter popover for the staff list with branch and role multi-select.
class StaffListFilterButton extends ConsumerStatefulWidget {
  const StaffListFilterButton({required this.query, required this.onQueryChanged, super.key});

  final StaffListQuery query;
  final ValueChanged<StaffListQuery> onQueryChanged;

  @override
  ConsumerState<StaffListFilterButton> createState() => _StaffListFilterButtonState();
}

class _StaffListFilterButtonState extends ConsumerState<StaffListFilterButton> with SingleTickerProviderStateMixin {
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
    final filterCount = widget.query.activeFilterCount;
    final branchesAsync = ref.watch(clinicSetupBranchesProvider);

    return FPopover(
      control: FPopoverControl.managed(controller: _controller),
      style: _filterPopoverMotion,
      groupId: _filterPopoverGroup,
      constraints: const FPortalConstraints(minWidth: 320, maxWidth: 380),
      popoverAnchor: Alignment.topCenter,
      childAnchor: Alignment.bottomCenter,
      popoverBuilder: (context, controller) => branchesAsync.when(
        loading: () => const SizedBox(width: 320, height: 120, child: Center(child: AppCircularProgress())),
        error: (error, _) => _StaffListFilterPanel(
          controller: controller,
          query: widget.query,
          branches: const [],
          filterPopoverGroup: _filterPopoverGroup,
          loadError: 'Failed to load branches: $error',
          onQueryChanged: widget.onQueryChanged,
        ),
        data: (branches) => _StaffListFilterPanel(
          controller: controller,
          query: widget.query,
          branches: branches,
          filterPopoverGroup: _filterPopoverGroup,
          onQueryChanged: widget.onQueryChanged,
        ),
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
        message: filterCount > 0 ? 'Filters active' : 'Filter by role or branch',
        child: SizedBox(
          width: 40,
          height: 40,
          child: Badge(
            isLabelVisible: filterCount > 0,
            label: Text('$filterCount'),
            backgroundColor: colors.primaryForeground,
            textColor: colors.primary,
            child: Material(
              color: _isHovered
                  ? Color.alphaBlend(colors.primaryForeground.withValues(alpha: 0.15), colors.primary)
                  : colors.primary,
              shape: const CircleBorder(),
              clipBehavior: Clip.antiAlias,
              child: Center(child: Icon(Icons.filter_list_outlined, color: colors.primaryForeground, size: 20)),
            ),
          ),
        ),
      ),
    );
  }
}

class _StaffListFilterPanel extends StatefulWidget {
  const _StaffListFilterPanel({
    required this.controller,
    required this.query,
    required this.branches,
    required this.filterPopoverGroup,
    required this.onQueryChanged,
    this.loadError,
  });

  final FPopoverController controller;
  final StaffListQuery query;
  final List<BranchListItem> branches;
  final Object filterPopoverGroup;
  final ValueChanged<StaffListQuery> onQueryChanged;
  final String? loadError;

  @override
  State<_StaffListFilterPanel> createState() => _StaffListFilterPanelState();
}

class _StaffListFilterPanelState extends State<_StaffListFilterPanel> {
  late Set<StaffRole> _roles;
  late Set<String> _branchIds;

  static const _roleItems = {
    'Administrator': StaffRole.administrator,
    'Doctor': StaffRole.doctor,
    'Receptionist': StaffRole.receptionist,
    'Lab staff': StaffRole.labStaff,
  };

  @override
  void initState() {
    super.initState();
    _roles = Set<StaffRole>.of(widget.query.roles);
    _branchIds = Set<String>.of(widget.query.branchIds);
  }

  Map<String, String> get _branchItems => {for (final branch in widget.branches) _branchLabel(branch): branch.id};

  String _branchLabel(BranchListItem branch) {
    final code = branch.code?.trim();
    if (code == null || code.isEmpty) {
      return branch.name;
    }
    return '${branch.name} ($code)';
  }

  void _clearAll() {
    widget.onQueryChanged(widget.query.copyWith(roles: {}, branchIds: {}));
    widget.controller.hide();
  }

  void _applyFilters() {
    widget.onQueryChanged(widget.query.copyWith(roles: _roles, branchIds: _branchIds));
    widget.controller.hide();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.semanticColors;
    final loadError = widget.loadError;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(SpacingTokens.lg, SpacingTokens.lg, SpacingTokens.lg, SpacingTokens.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Filters', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: SpacingTokens.md),
              if (loadError != null) ...[
                Text(loadError, style: theme.textTheme.bodySmall?.copyWith(color: colors.destructive)),
                const SizedBox(height: SpacingTokens.md),
              ],
              AppMultiSelect<String>(
                label: 'Branches',
                items: _branchItems,
                values: _branchIds,
                hintText: 'All branches',
                size: AppFieldSize.sm,
                enabled: loadError == null && _branchItems.isNotEmpty,
                contentGroupId: widget.filterPopoverGroup,
                showPopoverCloseButton: true,
                onChanged: (values) => setState(() => _branchIds = values),
              ),
              const SizedBox(height: SpacingTokens.md),
              Divider(height: 1, color: colors.border),
              const SizedBox(height: SpacingTokens.md),
              AppMultiSelect<StaffRole>(
                label: 'Roles',
                items: _roleItems,
                values: _roles,
                hintText: 'All roles',
                size: AppFieldSize.sm,
                contentGroupId: widget.filterPopoverGroup,
                showPopoverCloseButton: true,
                onChanged: (values) => setState(() => _roles = values),
              ),
            ],
          ),
        ),
        _FilterFooter(onClearAll: _clearAll, onApplyFilters: _applyFilters),
      ],
    );
  }
}

class _FilterFooter extends StatelessWidget {
  const _FilterFooter({required this.onClearAll, required this.onApplyFilters});

  final VoidCallback onClearAll;
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
              label: 'Clear All',
              variant: AppButtonVariant.outline,
              size: AppFieldSize.sm,
              onPressed: onClearAll,
            ),
          ],
        ),
      ),
    );
  }
}
