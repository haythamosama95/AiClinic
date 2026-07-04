import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/navigation/app_navigator.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/auth/auth_route_guard.dart';
import 'package:ai_clinic/core/ui/ui.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/auth/domain/staff_username.dart';
import 'package:ai_clinic/features/setup/domain/branch_field_validation.dart';
import 'package:ai_clinic/features/setup/domain/branch_summary.dart';
import 'package:ai_clinic/features/setup/domain/create_staff_account_result.dart';
import 'package:ai_clinic/features/setup/domain/provisioning_rules.dart';
import 'package:ai_clinic/features/setup/domain/staff_password_validation.dart';
import 'package:ai_clinic/features/setup/presentation/providers/provisioning_notifier.dart';
import 'package:ai_clinic/features/setup/presentation/providers/staff_assignable_branches_provider.dart';

/// Staff account creation on `/settings/staff/new` (reuses setup provisioning).
class SettingsStaffCreatePage extends ConsumerStatefulWidget {
  const SettingsStaffCreatePage({super.key});

  @override
  ConsumerState<SettingsStaffCreatePage> createState() => _SettingsStaffCreatePageState();
}

class _SettingsStaffCreatePageState extends ConsumerState<SettingsStaffCreatePage> {
  final _usernameController = TextEditingController();
  final _fullNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();

  StaffRole? _selectedRole;
  final Set<String> _selectedBranchIds = {};
  String? _primaryBranchId;
  final Map<String, String?> _fieldErrors = {};

  @override
  void initState() {
    super.initState();
    ref.listenManual(
      authSessionProvider.select((session) => session.context?.branchIds ?? const <String>[]),
      (previous, next) => _syncBranchSelection(next),
      fireImmediately: true,
    );
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _fullNameController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  List<String> get _availableBranchIds {
    return ref.read(authSessionProvider).context?.branchIds ?? const [];
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

  Map<String, String?> _validateForm(StaffProfile caller) {
    return {
      'username': validateStaffUsername(_usernameController.text),
      'fullName': _fullNameController.text.trim().isEmpty ? 'Enter the staff member full name.' : null,
      'phone': BranchFieldValidation.validatePhone(_phoneController.text),
      'password': StaffPasswordValidation.validateInitialPassword(_passwordController.text),
      'role': _selectedRole == null
          ? 'Select a role'
          : ProvisioningRules.validateRoleChoice(caller, _selectedRole!),
      'branches': _selectedBranchIds.isEmpty ? 'Select at least one branch assignment.' : null,
    };
  }

  Future<void> _submit() async {
    final auth = ref.read(authSessionProvider).context;
    if (auth == null) {
      return;
    }

    final errors = _validateForm(auth.staffProfile);
    setState(() => _fieldErrors.addAll(errors));
    if (errors.values.any((error) => error != null)) {
      return;
    }

    final role = _selectedRole;
    if (role == null) {
      return;
    }

    final result = await ref.read(provisioningNotifierProvider.notifier).createStaffAccount(
          username: _usernameController.text.trim(),
          fullName: _fullNameController.text.trim(),
          role: role,
          branchIds: _selectedBranchIds.toList(),
          password: _passwordController.text,
          primaryBranchId: _primaryBranchId,
          phone: _phoneController.text.trim().isEmpty ? null : _phoneController.text.trim(),
        );

    if (result != null && mounted) {
      await _showCredentialsDialog(result);
    }
  }

  Future<void> _showCredentialsDialog(CreateStaffAccountResult result) async {
    final password = result.revealAssignedPassword();
    if (password == null) {
      return;
    }

    await showAppDialog<void>(
      context,
      builder: (dialogContext, close) {
        return AppDialog(
          title: 'Staff account created',
          body: SelectableText(
            'Share these credentials with the staff member:\n\n'
            'Username: ${result.username}\n'
            'Password: $password',
            style: dialogContext.typography.body.copyWith(color: dialogContext.colors.textPrimary),
          ),
          footer: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              AppButton(
                label: 'Create another',
                variant: AppButtonVariant.secondary,
                onPressed: () async {
                  ref.read(provisioningNotifierProvider.notifier).clearLastCreated();
                  await close();
                  _resetForm();
                },
              ),
              const SizedBox(width: AppSpacing.s3),
              AppButton(
                label: 'View staff list',
                onPressed: () async {
                  await close();
                  if (!mounted) {
                    return;
                  }
                  context.nav.goSettingsStaff();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _resetForm() {
    _usernameController.clear();
    _fullNameController.clear();
    _phoneController.clear();
    _passwordController.clear();
    setState(() {
      _selectedRole = null;
      _selectedBranchIds.clear();
      _primaryBranchId = null;
      _fieldErrors.clear();
      _syncBranchSelection(_availableBranchIds);
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authSessionProvider).context;
    if (auth == null || !AuthRouteGuard.canAccessStaffManagement(ref.watch(authSessionProvider))) {
      return ColoredBox(
        color: context.colors.surfaceCanvas,
        child: const Center(
          child: AppEmptyState(
            variant: AppEmptyStateVariant.noAccess,
            title: 'Create staff',
            description: 'Only clinic administrators can create staff accounts.',
          ),
        ),
      );
    }

    final caller = auth.staffProfile;
    final branchIds = auth.branchIds;
    final provisioning = ref.watch(provisioningNotifierProvider);
    final branchesAsync = ref.watch(staffAssignableBranchesProvider);
    final isBusy = provisioning.isSubmitting;

    final branchById = branchesAsync.maybeWhen(
      data: (branches) => {for (final branch in branches) branch.id: branch},
      orElse: () => const <String, BranchSummary>{},
    );

    final selectableRoles = ProvisioningRules.selectableRoles(caller);
    final roleOptions = [
      for (final role in selectableRoles)
        AppSelectOption<StaffRole>(value: role, label: role.displayLabel),
    ];

    return ColoredBox(
      color: context.colors.surfaceCanvas,
      child: EditorFormPattern(
        title: 'Create staff account',
        description:
            'Signed in as ${caller.fullName}. '
            'The new account can sign in immediately with the password you assign.',
        breadcrumb: AppBreadcrumb(
          items: [
            AppBreadcrumbItem(label: 'Settings', onTap: () => context.nav.goSettings()),
            AppBreadcrumbItem(label: 'Staff', onTap: () => context.nav.goSettingsStaff()),
            const AppBreadcrumbItem(label: 'New staff'),
          ],
        ),
        summaryAlert: provisioning.errorMessage == null
            ? null
            : AppAlert(
                variant: AppAlertVariant.danger,
                title: provisioning.errorMessage!,
                dismissible: true,
                onDismiss: () => ref.read(provisioningNotifierProvider.notifier).clearError(),
              ),
        sections: [
          EditorFormSection(
            title: 'Account details',
            twoColumn: true,
            fields: [
              AppFormField(
                label: 'Full name',
                requiredMark: true,
                error: _fieldErrors['fullName'],
                child: AppTextField(
                  controller: _fullNameController,
                  hintText: 'Enter full name',
                  disabled: isBusy,
                  invalid: _fieldErrors['fullName'] != null,
                ),
              ),
              AppFormField(
                label: 'Phone number',
                requiredMark: true,
                error: _fieldErrors['phone'],
                child: AppTextField(
                  controller: _phoneController,
                  hintText: 'Numbers only',
                  disabled: isBusy,
                  keyboardType: TextInputType.phone,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  invalid: _fieldErrors['phone'] != null,
                ),
              ),
              AppFormField(
                label: 'Username',
                requiredMark: true,
                helperText: staffUsernameRequirements,
                error: _fieldErrors['username'],
                child: AppTextField(
                  controller: _usernameController,
                  hintText: 'Staff username',
                  disabled: isBusy,
                  invalid: _fieldErrors['username'] != null,
                ),
              ),
              AppFormField(
                label: 'Initial password',
                requiredMark: true,
                helperText:
                    '${StaffPasswordValidation.initialPasswordRequirements} '
                    'Shown once after creation so you can share it with the staff member.',
                error: _fieldErrors['password'],
                child: AppPasswordField(
                  controller: _passwordController,
                  disabled: isBusy,
                  invalid: _fieldErrors['password'] != null,
                ),
              ),
              AppFormField(
                label: 'Role',
                requiredMark: true,
                error: _fieldErrors['role'],
                child: AppSelect<StaffRole>(
                  options: roleOptions,
                  value: _selectedRole,
                  placeholder: 'Select a role',
                  disabled: isBusy,
                  invalid: _fieldErrors['role'] != null,
                  onChanged: isBusy ? null : (role) => setState(() => _selectedRole = role),
                ),
              ),
            ],
          ),
          EditorFormSection(
            title: 'Branch assignments',
            description: 'Staff can work at selected locations.',
            fields: [
              if (branchIds.isEmpty)
                Text(
                  'No branches are assigned to your account. Finish clinic setup first.',
                  style: context.typography.bodySm.copyWith(color: context.colors.textSecondary),
                )
              else
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final branchId in branchIds) ...[
                      AppCheckbox(
                        value: _selectedBranchIds.contains(branchId),
                        label: branchById[branchId]?.name ?? 'Branch $branchId',
                        onChanged: isBusy
                            ? null
                            : (checked) {
                                setState(() {
                                  if (checked == true) {
                                    _selectedBranchIds.add(branchId);
                                    _primaryBranchId ??= branchId;
                                  } else {
                                    _selectedBranchIds.remove(branchId);
                                    if (_primaryBranchId == branchId) {
                                      _primaryBranchId = _selectedBranchIds.isEmpty
                                          ? null
                                          : _selectedBranchIds.first;
                                    }
                                  }
                                  _fieldErrors.remove('branches');
                                });
                              },
                      ),
                      if (branchId != branchIds.last) const SizedBox(height: AppSpacing.s2),
                    ],
                    if (_fieldErrors['branches'] != null) ...[
                      const SizedBox(height: AppSpacing.s2),
                      Text(
                        _fieldErrors['branches']!,
                        style: context.typography.caption.copyWith(color: context.colors.statusDangerFg),
                      ),
                    ],
                    if (_selectedBranchIds.length > 1) ...[
                      const SizedBox(height: AppSpacing.s4),
                      AppFormField(
                        label: 'Primary branch',
                        child: AppSelect<String>(
                          options: [
                            for (final id in _selectedBranchIds)
                              AppSelectOption<String>(
                                value: id,
                                label: branchById[id]?.name ?? 'Branch $id',
                              ),
                          ],
                          value: _primaryBranchId,
                          disabled: isBusy,
                          onChanged: isBusy ? null : (id) => setState(() => _primaryBranchId = id),
                        ),
                      ),
                    ],
                  ],
                ),
            ],
          ),
        ],
        footer: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppButton(
              label: 'Cancel',
              variant: AppButtonVariant.secondary,
              disabled: isBusy,
              onPressed: () => context.nav.goSettingsStaff(),
            ),
            const SizedBox(width: AppSpacing.s3),
            AppButton(
              label: 'Create staff account',
              loading: isBusy,
              disabled: isBusy || branchIds.isEmpty,
              onPressed: _submit,
            ),
          ],
        ),
      ),
    );
  }
}
