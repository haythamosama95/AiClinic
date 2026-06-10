import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/theme/theme.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/auth/domain/staff_username.dart';
import 'package:ai_clinic/features/setup/domain/branch_summary.dart';
import 'package:ai_clinic/features/setup/domain/provisioning_rules.dart';
import 'package:ai_clinic/features/setup/presentation/providers/provisioning_notifier.dart';
import 'package:ai_clinic/features/setup/presentation/providers/staff_assignable_branches_provider.dart';
import 'package:ai_clinic/features/setup/presentation/widgets/setup_form_grid.dart';
import 'package:ai_clinic/features/setup/presentation/widgets/setup_step_layout.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';

class SetupStaffStep extends ConsumerStatefulWidget {
  const SetupStaffStep({
    required this.formKey,
    required this.usernameController,
    required this.fullNameController,
    required this.passwordController,
    required this.isBusy,
    required this.onCreate,
    required this.onSkip,
    super.key,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController usernameController;
  final TextEditingController fullNameController;
  final TextEditingController passwordController;
  final bool isBusy;
  final Future<void> Function({required StaffRole role, required List<String> branchIds, String? primaryBranchId})
  onCreate;
  final VoidCallback onSkip;

  @override
  ConsumerState<SetupStaffStep> createState() => _SetupStaffStepState();
}

class _SetupStaffStepState extends ConsumerState<SetupStaffStep> {
  StaffRole? _selectedRole;
  final Set<String> _selectedBranchIds = {};
  String? _primaryBranchId;
  var _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    ref.listenManual(
      authSessionProvider.select((s) => s.context?.branchIds ?? const <String>[]),
      (previous, next) => _onAssignableBranchIdsChanged(next),
      fireImmediately: true,
    );
  }

  void _syncBranchSelection(List<String> branchIds) {
    _selectedBranchIds.removeWhere((id) => !branchIds.contains(id));
    if (_selectedBranchIds.isEmpty && branchIds.length == 1) {
      _selectedBranchIds.add(branchIds.first);
      _primaryBranchId = branchIds.first;
    }
    if (_primaryBranchId != null && !_selectedBranchIds.contains(_primaryBranchId)) {
      _primaryBranchId = _selectedBranchIds.isEmpty ? null : _selectedBranchIds.first;
    }
  }

  void _onAssignableBranchIdsChanged(List<String> branchIds) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _syncBranchSelection(branchIds));
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authSessionProvider).context;
    final provisioning = ref.watch(provisioningNotifierProvider);
    final branchesAsync = ref.watch(staffAssignableBranchesProvider);
    final branchIds = auth?.branchIds ?? const [];
    final isBusy = widget.isBusy || provisioning.isSubmitting;

    final branchById = branchesAsync.maybeWhen(
      data: (branches) => {for (final branch in branches) branch.id: branch},
      orElse: () => const <String, BranchSummary>{},
    );

    final caller = auth?.staffProfile;
    final selectableRoles = caller == null
        ? const <StaffRole>[]
        : ProvisioningRules.selectableRoles(caller, ownerAlreadyExists: provisioning.ownerAlreadyExists);

    if (_selectedRole != null && !selectableRoles.contains(_selectedRole)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _selectedRole = null);
      });
    }

    final roleItems = {for (final role in selectableRoles) _roleLabel(role): role};

    return Form(
      key: widget.formKey,
      child: SetupStepLayout(
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SetupFormGrid(
              children: [
                AppTextField(
                  label: 'Username *',
                  controller: widget.usernameController,
                  hintText: 'Staff username',
                  enabled: !isBusy,
                  validator: (value) => validateStaffUsername(value ?? ''),
                ),
                AppTextField(
                  label: 'Full name *',
                  controller: widget.fullNameController,
                  hintText: 'Enter full name',
                  enabled: !isBusy,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Full name is required';
                    }
                    return null;
                  },
                ),
                AppSelect<StaffRole>(
                  label: 'Role *',
                  items: roleItems,
                  value: _selectedRole,
                  hintText: 'Select a role',
                  enabled: !isBusy && roleItems.isNotEmpty,
                  onChanged: isBusy ? null : (role) => setState(() => _selectedRole = role),
                  validator: (value) => value == null ? 'Select a role' : null,
                ),
                AppTextField(
                  label: 'Initial password *',
                  controller: widget.passwordController,
                  hintText: '••••••••',
                  obscureText: _obscurePassword,
                  enabled: !isBusy,
                  suffixIcon: IconButton(
                    onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                    icon: Icon(_obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Password is required';
                    }
                    if (value.length < 6) {
                      return 'Password must be at least 6 characters';
                    }
                    return null;
                  },
                ),
              ],
            ),
            const SizedBox(height: SpacingTokens.lg),
            Text('Branch assignments *', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: SpacingTokens.sm),
            if (branchIds.isEmpty)
              Text(
                'No branches are available yet. Go back and finish the branch step.',
                style: Theme.of(context).textTheme.bodySmall,
              )
            else if (branchesAsync.isLoading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: SpacingTokens.sm),
                child: Center(child: AppCircularProgress()),
              )
            else
              ...branchIds.map((branchId) {
                final branch = branchById[branchId];
                final label = branch == null
                    ? 'Branch $branchId'
                    : '${branch.name}${branch.code == null ? '' : ' (${branch.code})'}';
                return AppCheckbox(
                  value: _selectedBranchIds.contains(branchId),
                  label: label,
                  enabled: !isBusy,
                  onChanged: (checked) {
                    setState(() {
                      if (checked) {
                        _selectedBranchIds.add(branchId);
                        _primaryBranchId ??= branchId;
                      } else {
                        _selectedBranchIds.remove(branchId);
                        if (_primaryBranchId == branchId) {
                          _primaryBranchId = _selectedBranchIds.isEmpty ? null : _selectedBranchIds.first;
                        }
                      }
                    });
                  },
                );
              }),
            if (_selectedBranchIds.length > 1) ...[
              const SizedBox(height: SpacingTokens.md),
              AppSelect<String>(
                label: 'Primary branch',
                items: {for (final id in _selectedBranchIds) branchById[id]?.name ?? 'Branch $id': id},
                value: _primaryBranchId,
                enabled: !isBusy,
                onChanged: (id) => setState(() => _primaryBranchId = id),
              ),
            ],
          ],
        ),
        actions: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AppButton(label: 'Skip for now', variant: AppButtonVariant.ghost, onPressed: isBusy ? null : widget.onSkip),
            const SizedBox(width: SpacingTokens.md),
            AppButton(
              label: 'Create staff account',
              isLoading: isBusy,
              onPressed: isBusy || branchIds.isEmpty ? null : () => _submit(selectableRoles),
            ),
          ],
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

    if (_selectedBranchIds.isEmpty) {
      return;
    }

    await widget.onCreate(role: role, branchIds: _selectedBranchIds.toList(), primaryBranchId: _primaryBranchId);
  }

  static String _roleLabel(StaffRole role) => switch (role) {
    StaffRole.owner => 'Owner',
    StaffRole.administrator => 'Administrator',
    StaffRole.doctor => 'Doctor',
    StaffRole.receptionist => 'Receptionist',
    StaffRole.labStaff => 'Lab staff',
  };
}
