import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/core/widgets/app_form_field.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/auth/domain/branch_summary.dart';
import 'package:ai_clinic/features/auth/domain/provisioning_rules.dart';
import 'package:ai_clinic/features/auth/domain/staff_username.dart';
import 'package:ai_clinic/features/auth/presentation/providers/provisioning_notifier.dart';
import 'package:ai_clinic/features/auth/presentation/providers/staff_assignable_branches_provider.dart';
import 'package:ai_clinic/features/auth/presentation/widgets/branch_assignment_label.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';

/// Minimal staff account creation form (US6).
class StaffCreatePage extends ConsumerStatefulWidget {
  const StaffCreatePage({super.key});

  @override
  ConsumerState<StaffCreatePage> createState() => _StaffCreatePageState();
}

class _StaffCreatePageState extends ConsumerState<StaffCreatePage> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _fullNameController = TextEditingController();
  final _passwordController = TextEditingController();

  StaffRole? _selectedRole;
  final Set<String> _selectedBranchIds = {};
  String? _primaryBranchId;

  @override
  void initState() {
    super.initState();
    ref.listenManual(
      authSessionProvider.select((s) => s.context?.branchIds ?? const <String>[]),
      (previous, next) => _onAssignableBranchIdsChanged(next),
      fireImmediately: true,
    );
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _fullNameController.dispose();
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

  void _onAssignableBranchIdsChanged(List<String> branchIds) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _syncBranchSelection(branchIds));
    });
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    final role = _selectedRole;
    if (role == null) {
      return;
    }

    if (_selectedBranchIds.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Select at least one branch assignment.')));
      return;
    }

    final result = await ref
        .read(provisioningNotifierProvider.notifier)
        .createStaffAccount(
          username: _usernameController.text.trim(),
          fullName: _fullNameController.text.trim(),
          role: role,
          branchIds: _selectedBranchIds.toList(),
          password: _passwordController.text.trim(),
          primaryBranchId: _primaryBranchId,
        );

    if (result != null && mounted) {
      await _showCredentialsDialog(result.username, result.assignedPassword);
    }
  }

  Future<void> _showCredentialsDialog(String username, String password) async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Staff account created'),
        content: SelectableText(
          'Share these credentials with the staff member:\n\n'
          'Username: $username\n'
          'Password: $password',
        ),
        actions: [
          TextButton(
            onPressed: () {
              ref.read(provisioningNotifierProvider.notifier).clearLastCreated();
              Navigator.of(context).pop();
              _usernameController.clear();
              _fullNameController.clear();
              _passwordController.clear();
              setState(() {
                _selectedRole = null;
                _selectedBranchIds.clear();
                _primaryBranchId = null;
                final branches = _availableBranchIds;
                if (branches.length == 1) {
                  _selectedBranchIds.add(branches.first);
                  _primaryBranchId = branches.first;
                }
              });
            },
            child: const Text('Create another'),
          ),
          FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Done')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authSessionProvider).context;
    final provisioning = ref.watch(provisioningNotifierProvider);
    final branchesAsync = ref.watch(staffAssignableBranchesProvider);
    final isBusy = provisioning.isSubmitting;
    final branchIds = auth?.branchIds ?? const [];

    final branchById = branchesAsync.maybeWhen(
      data: (branches) => {for (final branch in branches) branch.id: branch},
      orElse: () => const <String, BranchSummary>{},
    );

    if (auth == null) {
      return const Scaffold(body: Center(child: Text('Loading session…')));
    }

    final caller = auth.staffProfile;
    if (!ProvisioningRules.canProvisionStaff(caller)) {
      return Scaffold(
        appBar: AppBar(title: const Text('Create staff')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Only clinic owners and administrators can create staff accounts.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    final selectableRoles = ProvisioningRules.selectableRoles(
      caller,
      ownerAlreadyExists: provisioning.ownerAlreadyExists,
    );

    if (_selectedRole != null && !selectableRoles.contains(_selectedRole)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() => _selectedRole = null);
        }
      });
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Create staff account'),
        actions: [TextButton(onPressed: isBusy ? null : () => context.go(AppRoutes.home), child: const Text('Home'))],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Add a staff member', style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 8),
                  Text(
                    'Signed in as ${caller.fullName}. '
                    'The new account can sign in immediately with the password you assign.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  if (provisioning.errorMessage != null) ...[
                    const SizedBox(height: 16),
                    MaterialBanner(
                      content: Text(provisioning.errorMessage!),
                      leading: const Icon(Icons.error_outline),
                      backgroundColor: Theme.of(context).colorScheme.errorContainer,
                      actions: [
                        TextButton(
                          onPressed: isBusy ? null : () => ref.read(provisioningNotifierProvider.notifier).clearError(),
                          child: const Text('Dismiss'),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 24),
                  AppFormField(
                    label: 'Username',
                    infoTooltip: 'Work username used for clinic sign-in.',
                    controller: _usernameController,
                    enabled: !isBusy,
                    keyboardType: TextInputType.text,
                    validator: (value) => validateStaffUsername(value ?? ''),
                  ),
                  const SizedBox(height: 16),
                  AppFormField(
                    label: 'Full name',
                    controller: _fullNameController,
                    enabled: !isBusy,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Full name is required';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<StaffRole>(
                    key: ValueKey(_selectedRole),
                    initialValue: _selectedRole,
                    decoration: const InputDecoration(labelText: 'Role'),
                    items: [
                      for (final role in selectableRoles) DropdownMenuItem(value: role, child: Text(_roleLabel(role))),
                    ],
                    onChanged: isBusy ? null : (role) => setState(() => _selectedRole = role),
                    validator: (value) => value == null ? 'Select a role' : null,
                  ),
                  const SizedBox(height: 16),
                  Text('Branch assignments', style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 8),
                  if (branchIds.isEmpty)
                    Text(
                      'No branches are assigned to your account. Finish clinic setup first.',
                      style: Theme.of(context).textTheme.bodySmall,
                    )
                  else if (branchesAsync.isLoading)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Center(
                        child: SizedBox(height: 24, width: 24, child: CircularProgressIndicator(strokeWidth: 2)),
                      ),
                    )
                  else ...[
                    if (branchesAsync.hasError)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          'Could not load branch details. Showing branch IDs only.',
                          style: Theme.of(
                            context,
                          ).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.error),
                        ),
                      ),
                    ...branchIds.map((branchId) {
                      final selected = _selectedBranchIds.contains(branchId);
                      final branch = branchById[branchId];
                      return CheckboxListTile(
                        value: selected,
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
                                      _primaryBranchId = _selectedBranchIds.isEmpty ? null : _selectedBranchIds.first;
                                    }
                                  }
                                });
                              },
                        title: BranchAssignmentLabel(branch: branch, fallbackLabel: 'Branch $branchId'),
                        subtitle: const Text('Staff can work at this location'),
                        controlAffinity: ListTileControlAffinity.leading,
                      );
                    }),
                  ],
                  if (_selectedBranchIds.length > 1) ...[
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      key: ValueKey(_primaryBranchId),
                      initialValue: _primaryBranchId,
                      decoration: const InputDecoration(labelText: 'Primary branch'),
                      items: [
                        for (final id in _selectedBranchIds)
                          DropdownMenuItem(
                            value: id,
                            child: BranchAssignmentLabel(branch: branchById[id], fallbackLabel: 'Branch $id'),
                          ),
                      ],
                      onChanged: isBusy ? null : (id) => setState(() => _primaryBranchId = id),
                    ),
                  ],
                  const SizedBox(height: 16),
                  AppFormField(
                    label: 'Initial password',
                    infoTooltip: 'Shown once after creation so you can share it with the staff member.',
                    controller: _passwordController,
                    enabled: !isBusy,
                    obscureText: true,
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
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: isBusy || branchIds.isEmpty ? null : _submit,
                    child: isBusy
                        ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Create staff account'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static String _roleLabel(StaffRole role) => switch (role) {
    StaffRole.owner => 'Owner',
    StaffRole.administrator => 'Administrator',
    StaffRole.doctor => 'Doctor',
    StaffRole.receptionist => 'Receptionist',
    StaffRole.labStaff => 'Lab staff',
  };
}
