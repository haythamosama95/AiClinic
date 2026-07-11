import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
  String? _activeTabId;

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

    return _ClinicManagementShell(
      tabs: visibleTabs,
      activeTabId: activeTabId,
      onTabChanged: (id) => setState(() => _activeTabId = id),
      body: clinicState.when(
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
        loading: () => const _ClinicManagementLoadingBody(),
        error: (_, _) => const AppEmptyState(variant: AppEmptyStateVariant.error),
      ),
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
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppPageHeader(
          title: 'Clinic Management',
          description: 'Organization identity, locations, team accounts, and access roles.',
          tabs: tabs == null || activeTabId == null || onTabChanged == null
              ? null
              : AppTabs(
                  items: [for (final tab in tabs!) AppTabItem(id: tab.id, label: tab.label, icon: tab.icon)],
                  value: activeTabId!,
                  onChanged: onTabChanged!,
                  ariaLabel: 'Clinic management sections',
                ),
        ),
        const SizedBox(height: AppSpacing.space8),
        body,
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
    final transition = AppMotion.transitionFor(context: context, preset: AppMotionPreset.rowEnter);

    return AnimatedSwitcher(
      duration: transition.duration,
      switchInCurve: transition.curve,
      switchOutCurve: transition.curve,
      transitionBuilder: (child, animation) {
        return AppMotion.animatedPreset(
          context: context,
          preset: AppMotionPreset.rowEnter,
          animation: animation,
          child: child,
        );
      },
      layoutBuilder: (currentChild, previousChildren) => currentChild ?? const SizedBox.shrink(),
      child: KeyedSubtree(
        key: ValueKey(tabId),
        child: switch (tabId) {
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

class _ClinicManagementLoadingBody extends StatelessWidget {
  const _ClinicManagementLoadingBody();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const AppSkeleton(height: 160),
        const SizedBox(height: AppSpacing.space6),
        const AppSkeleton(height: 24, width: 240),
        const SizedBox(height: AppSpacing.space2),
        const AppSkeleton(height: 16, width: 420),
        const SizedBox(height: AppSpacing.space6),
        const AppSkeleton(height: 200),
      ],
    );
  }
}
