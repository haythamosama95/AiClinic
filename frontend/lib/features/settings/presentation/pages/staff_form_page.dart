import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/auth/domain/branch_summary.dart';
import 'package:ai_clinic/features/auth/domain/provisioning_rules.dart';
import 'package:ai_clinic/features/auth/presentation/providers/provisioning_notifier.dart';
import 'package:ai_clinic/features/settings/presentation/providers/staff_form_notifier.dart';
import 'package:ai_clinic/features/settings/presentation/providers/staff_management_branches_provider.dart';
import 'package:ai_clinic/features/settings/presentation/widgets/staff_form_fields.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';

/// Create or edit a staff member from settings (US3).
class StaffFormPage extends ConsumerStatefulWidget {
  const StaffFormPage({this.staffId, super.key});

  final String? staffId;

  @override
  ConsumerState<StaffFormPage> createState() => _StaffFormPageState();
}

class _StaffFormPageState extends ConsumerState<StaffFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _fullNameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _phoneController = TextEditingController();

  StaffRole? _selectedRole;
  final Set<String> _selectedBranchIds = {};
  String? _primaryBranchId;
  bool _controllersInitialized = false;

  bool get _isEdit => widget.staffId != null;

  @override
  void initState() {
    super.initState();
    ref.listenManual(staffManagementBranchesProvider, (previous, next) {
      next.whenData((branches) {
        if (!mounted) {
          return;
        }
        setState(() => _syncBranchSelection(branches.map((b) => b.id).toList()));
      });
    });
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _fullNameController.dispose();
    _passwordController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  void _syncFromExisting(StaffFormUiState ui) {
    final existing = ui.existing;
    if (existing == null || _controllersInitialized) {
      return;
    }
    _fullNameController.text = existing.fullName;
    _phoneController.text = existing.phone ?? '';
    _selectedRole = existing.role;
    _selectedBranchIds
      ..clear()
      ..addAll(existing.branchIds);
    _primaryBranchId = existing.primaryBranchId ?? (existing.branchIds.length == 1 ? existing.branchIds.first : null);
    _controllersInitialized = true;
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

  void _onBranchChecked(String branchId, bool checked) {
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
  }

  Future<void> _submitCreate(StaffFormUiState ui) async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    final role = _selectedRole;
    if (role == null) {
      return;
    }

    if (_selectedBranchIds.isEmpty) {
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
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Staff account created'),
          content: SelectableText(
            'Share these credentials with the staff member:\n\n'
            'Username: ${result.username}\n'
            'Password: ${result.assignedPassword}',
          ),
          actions: [
            FilledButton(
              onPressed: () {
                ref.read(provisioningNotifierProvider.notifier).clearLastCreated();
                Navigator.of(context).pop();
                context.go(AppRoutes.settingsStaff);
              },
              child: const Text('Back to staff list'),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _submitEdit(StaffFormUiState ui) async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    final role = _selectedRole;
    if (role == null) {
      return;
    }

    if (_selectedBranchIds.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Select at least one branch assignment.')));
      return;
    }

    final savedId = await ref
        .read(staffFormProvider(widget.staffId).notifier)
        .saveEdit(
          fullName: _fullNameController.text,
          role: role,
          branchIds: _selectedBranchIds.toList(),
          phone: _phoneController.text,
          primaryBranchId: _primaryBranchId,
        );

    if (savedId != null && mounted) {
      final router = GoRouter.maybeOf(context);
      if (router != null) {
        context.go(AppRoutes.settingsStaff);
      }
    }
  }

  static String _branchAssignmentLabel({
    required List<String> branchIds,
    required Map<String, BranchSummary> branchById,
    required String? primaryBranchId,
  }) {
    if (branchIds.isEmpty) {
      return '';
    }
    final names = <String>[];
    for (final id in branchIds) {
      final branch = branchById[id];
      final name = branch?.name ?? 'Branch $id';
      if (id == primaryBranchId) {
        names.add('$name (primary)');
      } else {
        names.add(name);
      }
    }
    return names.join(', ');
  }

  @override
  Widget build(BuildContext context) {
    final formAsync = ref.watch(staffFormProvider(widget.staffId));
    final branchesAsync = ref.watch(staffManagementBranchesProvider);
    final provisioning = ref.watch(provisioningNotifierProvider);
    final auth = ref.watch(authSessionProvider).context?.staffProfile;
    final isBusy = formAsync.value?.isSaving == true || (!_isEdit && provisioning.isSubmitting);
    final canResetPassword = _isEdit && auth != null && ProvisioningRules.canResetStaffPassword(auth);

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Edit staff member' : 'New staff member'),
        leading: IconButton(tooltip: 'Go back', icon: const Icon(Icons.arrow_back), onPressed: () => context.go(AppRoutes.settingsStaff)),
      ),
      body: formAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Failed to load staff form: $error')),
        data: (ui) {
          if (ui.errorMessage != null && ui.existing == null && _isEdit) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(ui.errorMessage!, textAlign: TextAlign.center),
              ),
            );
          }

          if (ui.permissionDenied) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('You do not have permission to manage staff.', textAlign: TextAlign.center),
              ),
            );
          }

          _syncFromExisting(ui);

          final selectableRoles = ref.read(staffFormProvider(widget.staffId).notifier).selectableRoles();
          if (_selectedRole != null && !selectableRoles.contains(_selectedRole)) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                setState(() => _selectedRole = null);
              }
            });
          }

          return branchesAsync.when(
            data: (branches) {
              final branchIds = branches.map((b) => b.id).toList();
              final branchById = {for (final branch in branches) branch.id: branch};
              final existing = ui.existing;

              return SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (ui.errorMessage != null) ...[
                        Text(ui.errorMessage!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                        const SizedBox(height: 16),
                      ],
                      if (!_isEdit && provisioning.errorMessage != null) ...[
                        Text(provisioning.errorMessage!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                        const SizedBox(height: 16),
                      ],
                      StaffFormFields(
                        mode: _isEdit ? StaffFormFieldsMode.edit : StaffFormFieldsMode.create,
                        usernameController: _usernameController,
                        fullNameController: _fullNameController,
                        phoneController: _phoneController,
                        passwordController: _passwordController,
                        existing: existing == null
                            ? null
                            : StaffFormExistingData(
                                fullName: existing.fullName,
                                phone: existing.phone,
                                role: existing.role,
                                branchAssignmentLabel: _branchAssignmentLabel(
                                  branchIds: existing.branchIds,
                                  branchById: branchById,
                                  primaryBranchId: existing.primaryBranchId,
                                ),
                              ),
                        enabled: !isBusy,
                        selectableRoles: selectableRoles,
                        selectedRole: _selectedRole,
                        onRoleChanged: (role) => setState(() => _selectedRole = role),
                        branchIds: branchIds,
                        branchById: branchById,
                        selectedBranchIds: _selectedBranchIds,
                        primaryBranchId: _primaryBranchId,
                        onBranchChecked: _onBranchChecked,
                        onPrimaryBranchChanged: (id) => setState(() => _primaryBranchId = id),
                      ),
                      if (canResetPassword) ...[
                        const SizedBox(height: 24),
                        Text('Security', style: Theme.of(context).textTheme.titleSmall),
                        const SizedBox(height: 8),
                        OutlinedButton(
                          onPressed: isBusy
                              ? null
                              : () => context.go(AppRoutes.settingsStaffResetPassword(widget.staffId!)),
                          child: const Text('Reset password'),
                        ),
                      ],
                      const SizedBox(height: 24),
                      FilledButton(
                        onPressed: isBusy || branchIds.isEmpty
                            ? null
                            : () => _isEdit ? _submitEdit(ui) : _submitCreate(ui),
                        child: isBusy
                            ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                            : Text(_isEdit ? 'Save changes' : 'Create staff account'),
                      ),
                    ],
                  ),
                ),
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, _) => const Center(child: Text('Unable to load branches for assignment.')),
          );
        },
      ),
    );
  }
}
