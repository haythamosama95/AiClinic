import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/core/widgets/app_form_field.dart';
import 'package:ai_clinic/features/auth/domain/provisioning_rules.dart';
import 'package:ai_clinic/features/auth/domain/staff_member_summary.dart';
import 'package:ai_clinic/features/auth/presentation/providers/provisioning_notifier.dart';
import 'package:ai_clinic/shared/providers/auth_session_provider.dart';

/// Administrator-initiated staff password reset (US7).
class StaffPasswordResetPage extends ConsumerStatefulWidget {
  const StaffPasswordResetPage({super.key});

  @override
  ConsumerState<StaffPasswordResetPage> createState() => _StaffPasswordResetPageState();
}

class _StaffPasswordResetPageState extends ConsumerState<StaffPasswordResetPage> {
  final _formKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();

  String? _selectedStaffId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      ref.invalidate(staffResetCandidatesProvider);
    });
  }

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    final staffId = _selectedStaffId;
    if (staffId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Select a staff member to reset.')));
      return;
    }

    final result = await ref
        .read(provisioningNotifierProvider.notifier)
        .resetStaffPassword(staffMemberId: staffId, newPassword: _passwordController.text);

    if (result != null && mounted) {
      await _showAssignedPasswordDialog(result.assignedPassword);
    }
  }

  Future<void> _showAssignedPasswordDialog(String password) async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Password reset'),
        content: SelectableText(
          'Share this new password with the staff member:\n\n'
          'Password: $password',
        ),
        actions: [
          TextButton(
            onPressed: () {
              ref.read(provisioningNotifierProvider.notifier).clearLastPasswordReset();
              Navigator.of(context).pop();
            },
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(authSessionProvider).context;
    final caller = session?.staffProfile;
    final canReset = caller != null && ProvisioningRules.canResetStaffPassword(caller);
    final provisioning = ref.watch(provisioningNotifierProvider);
    final candidatesAsync = ref.watch(staffResetCandidatesProvider);

    ref.listen<AsyncValue<List<StaffMemberSummary>>>(staffResetCandidatesProvider, (previous, next) {
      next.whenData((staff) {
        final selectedId = _selectedStaffId;
        if (selectedId != null && !staff.any((member) => member.id == selectedId)) {
          setState(() => _selectedStaffId = null);
        }
      });
    });

    if (!canReset) {
      return Scaffold(
        appBar: AppBar(title: const Text('Reset staff password')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Only clinic owners and administrators can reset staff passwords.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Reset staff password')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Set a new password for a staff member. They must sign in with the password you assign.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 24),
                  candidatesAsync.when(
                    data: (staff) => _StaffPicker(
                      staff: staff,
                      selectedStaffId: _selectedStaffId,
                      enabled: !provisioning.isSubmitting,
                      onChanged: (value) => setState(() => _selectedStaffId = value),
                    ),
                    loading: () => const Center(child: CircularProgressIndicator()),
                    error: (_, _) => const Text('Unable to load staff list. Try again later.'),
                  ),
                  const SizedBox(height: 16),
                  AppFormField(
                    controller: _passwordController,
                    label: 'New password',
                    obscureText: true,
                    enabled: !provisioning.isSubmitting,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Enter a new password';
                      }
                      if (value.trim().length < 6) {
                        return 'Password must be at least 6 characters';
                      }
                      return null;
                    },
                  ),
                  if (provisioning.errorMessage != null) ...[
                    const SizedBox(height: 12),
                    Text(provisioning.errorMessage!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  ],
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: provisioning.isSubmitting ? null : _submit,
                    child: provisioning.isSubmitting
                        ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Reset password'),
                  ),
                  const SizedBox(height: 12),
                  TextButton(onPressed: () => context.go(AppRoutes.home), child: const Text('Back to home')),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StaffPicker extends StatelessWidget {
  const _StaffPicker({
    required this.staff,
    required this.selectedStaffId,
    required this.enabled,
    required this.onChanged,
  });

  final List<StaffMemberSummary> staff;
  final String? selectedStaffId;
  final bool enabled;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    if (staff.isEmpty) {
      return const Text('No staff members are available to reset. Create staff accounts first.');
    }

    return DropdownButtonFormField<String>(
      isExpanded: true,
      value: selectedStaffId,
      decoration: const InputDecoration(labelText: 'Staff member', border: OutlineInputBorder()),
      items: [
        for (final member in staff)
          DropdownMenuItem(value: member.id, child: Text('${member.fullName} (${member.roleLabel})')),
      ],
      onChanged: enabled ? onChanged : null,
      validator: (value) => value == null || value.isEmpty ? 'Select a staff member' : null,
    );
  }
}
