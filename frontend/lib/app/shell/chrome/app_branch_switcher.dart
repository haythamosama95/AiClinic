import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/providers/branch_selection_notifier.dart';
import 'package:ai_clinic/core/ui/foundation.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/settings/presentation/providers/clinic_setup_providers.dart';
import 'package:ai_clinic/features/setup/domain/branch_summary.dart';
import 'package:ai_clinic/features/setup/presentation/providers/staff_assignable_branches_provider.dart';

/// Dropdown branch switcher bound to [branchSelectionProvider].
class AppBranchSwitcher extends ConsumerStatefulWidget {
  const AppBranchSwitcher({super.key});

  @override
  ConsumerState<AppBranchSwitcher> createState() => _AppBranchSwitcherState();
}

class _AppBranchSwitcherState extends ConsumerState<AppBranchSwitcher> {
  String _query = '';
  String? _feedback;
  Timer? _feedbackTimer;

  @override
  void dispose() {
    _feedbackTimer?.cancel();
    super.dispose();
  }

  void _showFeedback(String message) {
    _feedbackTimer?.cancel();
    setState(() => _feedback = message);
    _feedbackTimer = Timer(const Duration(milliseconds: 2500), () {
      if (mounted) {
        setState(() => _feedback = null);
      }
    });
  }

  void _selectBranch(BranchSummary branch, String? currentBranchId) {
    if (branch.id == currentBranchId) {
      return;
    }
    ref.read(branchSelectionProvider.notifier).selectBranch(branch.id);
    _showFeedback('Switched to ${branch.name}');
    setState(() => _query = '');
  }

  List<BranchSummary> _filterBranches(List<BranchSummary> branches, String? orgName) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) {
      return branches;
    }
    return branches
        .where(
          (branch) =>
              branch.name.toLowerCase().contains(q) ||
              (orgName?.toLowerCase().contains(q) ?? false),
        )
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;
    final density = ref.watch(appDensityProvider);
    final branchesAsync = ref.watch(staffAssignableBranchesProvider);
    final orgAsync = ref.watch(clinicSetupOrganizationProvider);
    final currentBranchId = ref.watch(branchSelectionProvider);

    return branchesAsync.when(
      loading: () => const SizedBox(
        width: AppSpacing.s12 * 3,
        child: Center(child: AppSpinner(size: AppSpinnerSize.sm)),
      ),
      error: (_, _) => const SizedBox.shrink(),
      data: (branches) {
        if (branches.isEmpty) {
          return const SizedBox.shrink();
        }

        final current = branches.firstWhere(
          (branch) => branch.id == currentBranchId,
          orElse: () => branches.first,
        );
        final orgName = orgAsync.maybeWhen(data: (org) => org?.name, orElse: () => null);
        final filtered = _filterBranches(branches, orgName);
        final verticalPadding = switch (density) {
          AppDensity.compact => AppSpacing.s1,
          AppDensity.standard => AppSpacing.s1 + AppSpacing.s0_5,
          AppDensity.comfortable => AppSpacing.s2,
        };

        return Stack(
          clipBehavior: Clip.none,
          children: [
            AppDropdownMenu(
              align: AppDropdownMenuAlign.end,
              minWidth: AppSpacing.s12 * 4 + AppSpacing.s8,
              trigger: (context, show, hide, toggle) {
                return AppPressable(
                  onTap: show,
                  semanticLabel: 'Current branch: ${current.name}',
                  borderRadius: AppRadii.mdAll,
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: AppSpacing.s12 * 3),
                    padding: EdgeInsetsDirectional.symmetric(
                      horizontal: AppSpacing.s3,
                      vertical: verticalPadding,
                    ),
                    decoration: BoxDecoration(
                      color: colors.surfaceDefault,
                      border: Border.all(color: colors.borderDefault),
                      borderRadius: AppRadii.mdAll,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AppIcon(
                          icon: LucideIcons.building2,
                          dimension: AppSpacing.s4,
                          color: colors.iconDefault,
                        ),
                        const SizedBox(width: AppSpacing.s2),
                        Flexible(
                          child: Text(
                            current.name,
                            style: typography.bodySm.copyWith(
                              fontWeight: FontWeight.w500,
                              color: colors.textPrimary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.s2),
                        AppIcon(
                          icon: LucideIcons.chevronDown,
                          dimension: AppSpacing.s4,
                          color: colors.iconMuted,
                        ),
                      ],
                    ),
                  ),
                );
              },
              children: [
                if (orgName != null)
                  Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(
                      AppSpacing.s2,
                      AppSpacing.s2,
                      AppSpacing.s2,
                      AppSpacing.s1,
                    ),
                    child: AppDropdownMenuLabel(label: orgName),
                  ),
                if (branches.length > 4)
                  Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(
                      AppSpacing.s2,
                      0,
                      AppSpacing.s2,
                      AppSpacing.s2,
                    ),
                    child: AppSearchField(
                      hintText: 'Search branches…',
                      showShortcutHint: false,
                      size: AppFieldSize.sm,
                      onValueChange: (value) => setState(() => _query = value),
                    ),
                  ),
                if (orgName != null || branches.length > 4) const AppDropdownMenuSeparator(),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: AppSpacing.s12 * 5),
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final branch in filtered)
                          AppDropdownMenuItem(
                            key: ValueKey<String>(branch.id),
                            label: branch.name,
                            checked: branch.id == currentBranchId,
                            onSelected: () => _selectBranch(branch, currentBranchId),
                          ),
                        if (filtered.isEmpty)
                          Padding(
                            padding: const EdgeInsetsDirectional.all(AppSpacing.s3),
                            child: Text(
                              'No branches found',
                              textAlign: TextAlign.center,
                              style: typography.bodySm.copyWith(color: colors.textTertiary),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            if (_feedback != null)
              PositionedDirectional(
                top: density.topbarHeight,
                end: 0,
                child: Semantics(
                  liveRegion: true,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: colors.surfaceRaised,
                      border: Border.all(color: colors.borderDefault),
                      borderRadius: AppRadii.mdAll,
                      boxShadow: AppShadows.forContext(context, 2),
                    ),
                    child: Padding(
                      padding: const EdgeInsetsDirectional.symmetric(
                        horizontal: AppSpacing.s3,
                        vertical: AppSpacing.s1 + AppSpacing.s0_5,
                      ),
                      child: Text(
                        _feedback!,
                        style: typography.bodySm.copyWith(color: colors.textPrimary),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
