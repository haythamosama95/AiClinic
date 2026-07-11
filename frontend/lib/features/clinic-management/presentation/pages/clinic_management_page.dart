import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:skeletonizer/skeletonizer.dart';

import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/clinic-management/domain/organization_profile.dart';
import 'package:ai_clinic/features/clinic-management/presentation/components/branches_tab.dart';
import 'package:ai_clinic/features/clinic-management/presentation/components/organization_tab.dart';
import 'package:ai_clinic/features/clinic-management/presentation/components/roles_tab.dart';
import 'package:ai_clinic/features/clinic-management/presentation/components/staff_tab.dart';
import 'package:ai_clinic/features/clinic-management/presentation/models/branch_form_values.dart';
import 'package:ai_clinic/features/clinic-management/presentation/models/clinic_management_tab.dart';
import 'package:ai_clinic/features/clinic-management/presentation/models/staff_form_values.dart';
import 'package:ai_clinic/features/clinic-management/presentation/providers/clinic_management_notifier.dart';

/// Clinic management hub: organization, branches, staff, and roles (web `ClinicManagementPage`).
class ClinicManagementPage extends ConsumerStatefulWidget {
  const ClinicManagementPage({super.key});

  @override
  ConsumerState<ClinicManagementPage> createState() => _ClinicManagementPageState();
}

class _ClinicManagementPageState extends ConsumerState<ClinicManagementPage> {
  static const _minimumSkeletonDuration = Duration(seconds: 2);

  String? _activeTabId;
  bool _minSkeletonElapsed = false;
  bool _initialRevealComplete = false;
  Timer? _skeletonTimer;

  @override
  void initState() {
    super.initState();
    _skeletonTimer = Timer(_minimumSkeletonDuration, () {
      if (!mounted) {
        return;
      }
      setState(() {
        _minSkeletonElapsed = true;
        if (ref.read(clinicManagementProvider).hasValue) {
          _initialRevealComplete = true;
        }
      });
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final current = ref.read(clinicManagementProvider);
      if (current.hasValue) {
        ref.read(clinicManagementProvider.notifier).reload();
      }
    });
  }

  @override
  void dispose() {
    _skeletonTimer?.cancel();
    super.dispose();
  }

  bool _shouldShowInitialSkeleton(AsyncValue<ClinicManagementState> clinicState) {
    if (_initialRevealComplete || clinicState.hasError) {
      return false;
    }
    return clinicState.isLoading || !_minSkeletonElapsed;
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authSessionProvider);
    final visibleTabs = clinicManagementTabsFor(auth);

    if (visibleTabs.isEmpty) {
      return const _ClinicManagementShell(
        tabs: null,
        activeTabId: null,
        body: AppEmptyState(variant: AppEmptyStateVariant.noAccess),
      );
    }

    final activeTabId = _resolveActiveTab(visibleTabs);
    final clinicState = ref.watch(clinicManagementProvider);
    final notifier = ref.read(clinicManagementProvider.notifier);

    ref.listen<AsyncValue<ClinicManagementState>>(clinicManagementProvider, (previous, next) {
      if (!_initialRevealComplete && _minSkeletonElapsed && next.hasValue) {
        setState(() => _initialRevealComplete = true);
      }
    });

    final showInitialSkeleton = _shouldShowInitialSkeleton(clinicState);

    final Widget body;
    if (showInitialSkeleton) {
      body = _TabSkeletonBody(key: ValueKey('skeleton-$activeTabId'), tabId: activeTabId);
    } else {
      body = clinicState.when(
        data: (state) => _ActiveTabBody(
          key: ValueKey(activeTabId),
          tabId: activeTabId,
          state: state,
          onUpdateOrganization: notifier.updateOrganization,
          onAddBranch: (values) => notifier.addBranch(createBranchInputFromFormValues(values)),
          onUpdateBranch: (branchId, values) =>
              notifier.updateBranch(updateBranchInputFromFormValues(branchId: branchId, values: values)),
          onRemoveBranch: notifier.removeBranch,
          onToggleBranchActive: ({required branchId, required isActive}) =>
              notifier.toggleBranchActive(branchId: branchId, isActive: isActive),
          onAddStaff: (values) => notifier.addStaff(toCreateStaffAccountInput(values)),
          onUpdateStaff: (id, values) {
            final original = state.staff.where((member) => member.id == id).firstOrNull;
            return notifier.updateStaffFromForm(
              staffMemberId: id,
              values: values,
              originalUsername: original?.username,
            );
          },
          onRemoveStaff: notifier.removeStaff,
        ),
        loading: () {
          final previous = clinicState.value;
          if (previous != null) {
            return _ActiveTabBody(
              key: ValueKey(activeTabId),
              tabId: activeTabId,
              state: previous,
              onUpdateOrganization: notifier.updateOrganization,
              onAddBranch: (values) => notifier.addBranch(createBranchInputFromFormValues(values)),
              onUpdateBranch: (branchId, values) =>
                  notifier.updateBranch(updateBranchInputFromFormValues(branchId: branchId, values: values)),
              onRemoveBranch: notifier.removeBranch,
              onToggleBranchActive: ({required branchId, required isActive}) =>
                  notifier.toggleBranchActive(branchId: branchId, isActive: isActive),
              onAddStaff: (values) => notifier.addStaff(toCreateStaffAccountInput(values)),
              onUpdateStaff: (id, values) {
                final original = previous.staff.where((member) => member.id == id).firstOrNull;
                return notifier.updateStaffFromForm(
                  staffMemberId: id,
                  values: values,
                  originalUsername: original?.username,
                );
              },
              onRemoveStaff: notifier.removeStaff,
            );
          }
          return _TabSkeletonBody(key: ValueKey('skeleton-$activeTabId'), tabId: activeTabId);
        },
        error: (_, _) => const AppEmptyState(variant: AppEmptyStateVariant.error),
      );
    }

    return _ClinicManagementShell(
      tabs: visibleTabs,
      activeTabId: activeTabId,
      onTabChanged: (id) => setState(() => _activeTabId = id),
      body: body,
    );
  }

  String _resolveActiveTab(List<ClinicManagementTab> visibleTabs) {
    final current = _activeTabId;
    if (current != null && visibleTabs.any((tab) => tab.id == current)) {
      return current;
    }
    return visibleTabs.first.id;
  }
}

class _ClinicManagementShell extends StatelessWidget {
  const _ClinicManagementShell({required this.body, this.tabs, this.activeTabId, this.onTabChanged});

  final Widget body;
  final List<ClinicManagementTab>? tabs;
  final String? activeTabId;
  final ValueChanged<String>? onTabChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        AppPageHeader(
          title: 'Clinic Management',
          description: 'Organization identity, locations, team accounts, and access roles.',
          tabs: tabs == null || activeTabId == null || onTabChanged == null
              ? null
              : SizedBox(
                  width: double.infinity,
                  child: AppTabs(
                    items: [for (final tab in tabs!) AppTabItem(id: tab.id, label: tab.label, icon: tab.icon)],
                    value: activeTabId!,
                    onChanged: onTabChanged!,
                    ariaLabel: 'Clinic management sections',
                  ),
                ),
        ),
        const SizedBox(height: AppSpacing.space8),
        SizedBox(width: double.infinity, child: body),
      ],
    );
  }
}

class _ActiveTabBody extends StatelessWidget {
  const _ActiveTabBody({
    required this.tabId,
    required this.state,
    required this.onUpdateOrganization,
    required this.onAddBranch,
    required this.onUpdateBranch,
    required this.onRemoveBranch,
    required this.onToggleBranchActive,
    required this.onAddStaff,
    required this.onUpdateStaff,
    required this.onRemoveStaff,
    super.key,
  });

  final String tabId;
  final ClinicManagementState state;
  final Future<void> Function(OrganizationProfile) onUpdateOrganization;
  final Future<void> Function(BranchFormValues values) onAddBranch;
  final Future<void> Function(String branchId, BranchFormValues values) onUpdateBranch;
  final Future<void> Function(String branchId) onRemoveBranch;
  final Future<void> Function({required String branchId, required bool isActive}) onToggleBranchActive;
  final StaffAddCallback onAddStaff;
  final StaffUpdateCallback onUpdateStaff;
  final StaffRemoveCallback onRemoveStaff;

  @override
  Widget build(BuildContext context) {
    final transition = AppMotion.transitionFor(context: context, preset: AppMotionPreset.slideUp);

    return AnimatedSwitcher(
      duration: transition.duration,
      switchInCurve: transition.curve,
      switchOutCurve: transition.curve,
      transitionBuilder: (child, animation) {
        return AppMotion.animatedPreset(
          context: context,
          preset: AppMotionPreset.slideUp,
          animation: animation,
          child: child,
        );
      },
      layoutBuilder: (currentChild, previousChildren) => currentChild ?? const SizedBox.shrink(),
      child: SizedBox(
        key: ValueKey(tabId),
        width: double.infinity,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            switch (tabId) {
              'organization' => _buildOrganizationTab(),
              'branches' => BranchesTab(
                branches: state.branches,
                onAddBranch: onAddBranch,
                onUpdateBranch: onUpdateBranch,
                onRemoveBranch: onRemoveBranch,
                onToggleBranchActive: onToggleBranchActive,
              ),
              'staff' => StaffTab(
                staff: state.staff,
                branches: state.branches,
                onAdd: onAddStaff,
                onUpdate: onUpdateStaff,
                onRemove: onRemoveStaff,
              ),
              'roles' => const RolesTab(),
              _ => const SizedBox.shrink(),
            },
          ],
        ),
      ),
    );
  }

  Widget _buildOrganizationTab() {
    final organization = state.organization;
    if (organization == null) {
      return const AppEmptyState(
        variant: AppEmptyStateVariant.firstRun,
        title: 'No organization profile',
        description: 'Organization details are not available for this session.',
      );
    }

    return OrganizationTab(
      organization: organization,
      onSave: (next) => onUpdateOrganization(next),
      branchCount: state.branches.length,
      staffCount: state.staff.length,
      activeBranchCount: state.branches.where((branch) => branch.isActive).length,
    );
  }
}

class _TabSkeletonBody extends StatelessWidget {
  const _TabSkeletonBody({required this.tabId, super.key});

  final String tabId;

  @override
  Widget build(BuildContext context) {
    final transition = AppMotion.transitionFor(context: context, preset: AppMotionPreset.slideUp);

    return AnimatedSwitcher(
      duration: transition.duration,
      switchInCurve: transition.curve,
      switchOutCurve: transition.curve,
      transitionBuilder: (child, animation) {
        return AppMotion.animatedPreset(
          context: context,
          preset: AppMotionPreset.slideUp,
          animation: animation,
          child: child,
        );
      },
      layoutBuilder: (currentChild, previousChildren) => currentChild ?? const SizedBox.shrink(),
      child: SizedBox(
        key: ValueKey(tabId),
        width: double.infinity,
        child: AppSkeletonizerZone(
          child: switch (tabId) {
            'organization' => const _OrganizationTabSkeleton(),
            'branches' => const _BranchesTabSkeleton(),
            'staff' => const _StaffTabSkeleton(),
            'roles' => const _RolesTabSkeleton(),
            _ => const _OrganizationTabSkeleton(),
          },
        ),
      ),
    );
  }
}

class _OrganizationTabSkeleton extends StatelessWidget {
  const _OrganizationTabSkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Bone(height: 152, borderRadius: BorderRadius.circular(AppRadius.x2l)),
        const SizedBox(height: AppSpacing.space6),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.start,
          spacing: AppSpacing.space4,
          runSpacing: AppSpacing.space4,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Bone(height: 24, width: 220),
                const SizedBox(height: AppSpacing.space1),
                Bone(height: 16, width: 420),
              ],
            ),
            Bone(height: 32, width: 140, borderRadius: BorderRadius.circular(AppRadius.md)),
          ],
        ),
        const SizedBox(height: AppSpacing.space6),
        Bone(height: 280, borderRadius: BorderRadius.circular(AppRadius.x2l)),
      ],
    );
  }
}

class _ListTabSkeleton extends StatelessWidget {
  const _ListTabSkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.start,
          spacing: AppSpacing.space4,
          runSpacing: AppSpacing.space4,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Bone(height: 24, width: 120),
                const SizedBox(height: AppSpacing.space1),
                Bone(height: 16, width: 360),
              ],
            ),
            Bone(height: 36, width: 132, borderRadius: BorderRadius.circular(AppRadius.md)),
          ],
        ),
        const SizedBox(height: AppSpacing.space6),
        Bone(height: 44, borderRadius: BorderRadius.circular(AppRadius.md)),
        const SizedBox(height: AppSpacing.space6),
        LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 720;
            if (isWide) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < 2; i++) ...[
                    if (i > 0) const SizedBox(width: AppSpacing.space4),
                    Expanded(child: Bone(height: 168, borderRadius: BorderRadius.circular(AppRadius.xl))),
                  ],
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < 2; i++) ...[
                  if (i > 0) const SizedBox(height: AppSpacing.space4),
                  Bone(height: 168, borderRadius: BorderRadius.circular(AppRadius.xl)),
                ],
              ],
            );
          },
        ),
      ],
    );
  }
}

class _BranchesTabSkeleton extends StatelessWidget {
  const _BranchesTabSkeleton();

  @override
  Widget build(BuildContext context) => const _ListTabSkeleton();
}

class _StaffTabSkeleton extends StatelessWidget {
  const _StaffTabSkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const _ListTabSkeleton(),
        const SizedBox(height: AppSpacing.space4),
        Bone(height: 72, borderRadius: BorderRadius.circular(AppRadius.xl)),
      ],
    );
  }
}

class _RolesTabSkeleton extends StatelessWidget {
  const _RolesTabSkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.start,
          spacing: AppSpacing.space4,
          runSpacing: AppSpacing.space4,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Bone(height: 24, width: 200),
                const SizedBox(height: AppSpacing.space1),
                Bone(height: 16, width: 480),
              ],
            ),
            Bone(height: 32, width: 112, borderRadius: BorderRadius.circular(AppRadius.md)),
          ],
        ),
        const SizedBox(height: AppSpacing.space6),
        Bone(height: 320, borderRadius: BorderRadius.circular(AppRadius.xl)),
      ],
    );
  }
}
