import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/setup/domain/branch_summary.dart';
import 'package:ai_clinic/features/setup/domain/provisioning_rules.dart';
import 'package:ai_clinic/features/setup/domain/setup_wizard_draft_ids.dart';
import 'package:ai_clinic/features/setup/presentation/providers/provisioning_notifier.dart';
import 'package:ai_clinic/features/setup/presentation/providers/staff_assignable_branches_provider.dart';
import 'package:ai_clinic/features/setup/presentation/widgets/setup_step_layout.dart';
import 'package:ai_clinic/features/setup/presentation/widgets/staff_form_fields.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';

class SetupStaffStep extends ConsumerStatefulWidget {
  const SetupStaffStep({
    required this.formKey,
    required this.usernameController,
    required this.fullNameController,
    required this.phoneController,
    required this.passwordController,
    required this.isBusy,
    required this.onCreate,
    this.wizardBranches = const [],
    super.key,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController usernameController;
  final TextEditingController fullNameController;
  final TextEditingController phoneController;
  final TextEditingController passwordController;
  final bool isBusy;
  final Future<bool> Function({required StaffRole role, required List<String> branchIds, String? primaryBranchId})
  onCreate;
  final List<BranchSummary> wizardBranches;

  @override
  ConsumerState<SetupStaffStep> createState() => _SetupStaffStepState();
}

class _SetupStaffStepState extends ConsumerState<SetupStaffStep> {
  StaffRole? _selectedRole;
  String? _primaryBranchId;
  late final FMultiValueNotifier<String> _branchSelection;
  String? _syncedBranchListKey;
  var _defaultRoleScheduled = false;
  var _selectionRebuildScheduled = false;

  bool get _usesWizardBranches => widget.wizardBranches.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _branchSelection = FMultiValueNotifier<String>();
    _branchSelection.addListener(_onBranchSelectionChanged);

    if (_usesWizardBranches) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _syncBranchAssignment(widget.wizardBranches.map((branch) => branch.id).toList());
      });
      return;
    }

    ref.listenManual(staffAssignableBranchesProvider, (previous, next) {
      next.whenData((branches) {
        if (!mounted) return;
        _syncBranchAssignment(branches.map((branch) => branch.id).toList());
      });
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(staffAssignableBranchesProvider).whenData((branches) {
        _syncBranchAssignment(branches.map((branch) => branch.id).toList());
      });
    });
  }

  @override
  void didUpdateWidget(covariant SetupStaffStep oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.wizardBranches != widget.wizardBranches && _usesWizardBranches) {
      _syncBranchAssignment(widget.wizardBranches.map((branch) => branch.id).toList());
    }
  }

  void _syncBranchAssignment(List<String> branchIds) {
    final assignBranchId = _usesWizardBranches ? SetupWizardDraftIds.branch : null;
    _applyBranchListSync(branchIds, assignBranchId: assignBranchId);
  }

  @override
  void dispose() {
    _branchSelection
      ..removeListener(_onBranchSelectionChanged)
      ..dispose();
    super.dispose();
  }

  void _onBranchSelectionChanged() {
    if (_selectionRebuildScheduled) {
      return;
    }
    _selectionRebuildScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _selectionRebuildScheduled = false;
      if (!mounted) return;

      final selected = _branchSelection.value;
      final nextPrimary = _primaryBranchId != null && selected.contains(_primaryBranchId!)
          ? _primaryBranchId
          : (selected.isEmpty ? null : selected.first);
      if (nextPrimary == _primaryBranchId) {
        return;
      }

      setState(() => _primaryBranchId = nextPrimary);
    });
  }

  void _applyBranchListSync(List<String> branchIds, {String? assignBranchId}) {
    final key = '${assignBranchId ?? ''}|${branchIds.join(',')}';
    if (_syncedBranchListKey == key) {
      return;
    }
    _syncedBranchListKey = key;

    final validIds = branchIds.toSet();
    final next = assignBranchId != null && validIds.contains(assignBranchId)
        ? {assignBranchId}
        : _branchSelection.value.where(validIds.contains).toSet();

    if (!setEquals(_branchSelection.value, next)) {
      _branchSelection.value = next;
      return;
    }

    final nextPrimary = assignBranchId != null && next.contains(assignBranchId)
        ? assignBranchId
        : (_primaryBranchId != null && next.contains(_primaryBranchId!)
              ? _primaryBranchId
              : (next.length == 1 ? next.first : null));

    if (nextPrimary != _primaryBranchId) {
      setState(() => _primaryBranchId = nextPrimary);
    }
  }

  void _onBranchChecked(String branchId, bool checked) {
    if (checked) {
      _branchSelection.update(branchId, add: true);
    } else {
      _branchSelection.update(branchId, add: false);
    }
  }

  void _ensureDefaultRole(List<StaffRole> selectableRoles, StaffProfile? caller) {
    if (_selectedRole != null || selectableRoles.isEmpty) {
      return;
    }

    if (caller != null && caller.isBootstrapAdmin && selectableRoles.contains(StaffRole.administrator)) {
      _selectedRole = StaffRole.administrator;
      return;
    }

    _selectedRole = selectableRoles.first;
  }

  void _scheduleDefaultRole(List<StaffRole> selectableRoles, StaffProfile? caller) {
    if (_selectedRole != null || selectableRoles.isEmpty || _defaultRoleScheduled) {
      return;
    }

    _defaultRoleScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _ensureDefaultRole(selectableRoles, caller));
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authSessionProvider).context;
    final provisioning = ref.watch(provisioningNotifierProvider);
    final isBusy = widget.isBusy || provisioning.isSubmitting;

    final caller = auth?.staffProfile;
    final selectableRoles = caller == null ? const <StaffRole>[] : ProvisioningRules.selectableRoles(caller);

    if (_selectedRole != null && !selectableRoles.contains(_selectedRole)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _selectedRole = null);
      });
    } else {
      _scheduleDefaultRole(selectableRoles, caller);
    }

    if (_usesWizardBranches) {
      return _buildForm(branches: widget.wizardBranches, selectableRoles: selectableRoles, isBusy: isBusy);
    }

    final branchesAsync = ref.watch(staffAssignableBranchesProvider);
    return branchesAsync.when(
      loading: () => const Center(child: AppCircularProgress()),
      error: (_, _) => const Center(child: Text('Unable to load branches for assignment.')),
      data: (branches) => _buildForm(branches: branches, selectableRoles: selectableRoles, isBusy: isBusy),
    );
  }

  Widget _buildForm({
    required List<BranchSummary> branches,
    required List<StaffRole> selectableRoles,
    required bool isBusy,
  }) {
    final branchIds = branches.map((branch) => branch.id).toList();
    final branchById = {for (final branch in branches) branch.id: branch};

    return Form(
      key: widget.formKey,
      child: SetupStepLayout(
        body: StaffFormFields(
          mode: StaffFormFieldsMode.create,
          usernameController: widget.usernameController,
          fullNameController: widget.fullNameController,
          phoneController: widget.phoneController,
          passwordController: widget.passwordController,
          enabled: !isBusy,
          selectableRoles: selectableRoles,
          selectedRole: _selectedRole,
          onRoleChanged: (role) => setState(() => _selectedRole = role),
          branchIds: branchIds,
          branchById: branchById,
          selectedBranchIds: _branchSelection.value,
          primaryBranchId: _primaryBranchId,
          branchSelectionControl: _branchSelection,
          onBranchChecked: _onBranchChecked,
          onPrimaryBranchChanged: (id) => setState(() => _primaryBranchId = id),
          showBranchAssignments: true,
          createAction: AppButton(
            label: 'Create staff account',
            expand: false,
            isLoading: isBusy,
            onPressed: isBusy || branchIds.isEmpty ? null : () => _submit(selectableRoles),
          ),
        ),
      ),
    );
  }

  Future<void> _submit(List<StaffRole> selectableRoles) async {
    if (!(widget.formKey.currentState?.validate() ?? false)) {
      return;
    }

    final role = _selectedRole;
    if (role == null || !selectableRoles.contains(role)) {
      return;
    }

    final selectedBranchIds = _branchSelection.value;
    if (selectedBranchIds.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Select at least one branch assignment.')));
      return;
    }

    final added = await widget.onCreate(
      role: role,
      branchIds: selectedBranchIds.toList(),
      primaryBranchId: _primaryBranchId,
    );
    if (!added || !mounted) {
      return;
    }

    setState(() {
      _selectedRole = null;
      _defaultRoleScheduled = false;
    });
  }
}
