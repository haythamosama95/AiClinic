import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/core/widgets/app_form_field.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/auth/domain/provisioning_rules.dart';
import 'package:ai_clinic/features/auth/presentation/providers/provisioning_notifier.dart';
import 'package:ai_clinic/features/settings/domain/usecases/settings_use_case_providers.dart';
import 'package:ai_clinic/features/settings/domain/staff_list_filter.dart';
import 'package:ai_clinic/features/settings/domain/staff_list_item.dart';
import 'package:ai_clinic/shared/providers/auth_session_provider.dart';

/// Password reset for a specific staff member from settings (US3).
class StaffSettingsPasswordResetPage extends ConsumerStatefulWidget {
  const StaffSettingsPasswordResetPage({required this.staffId, super.key});

  final String staffId;

  @override
  ConsumerState<StaffSettingsPasswordResetPage> createState() => _StaffSettingsPasswordResetPageState();
}

class _StaffSettingsPasswordResetPageState extends ConsumerState<StaffSettingsPasswordResetPage> {
  final _formKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit(StaffListItem? member) async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    final result = await ref
        .read(provisioningNotifierProvider.notifier)
        .resetStaffPassword(staffMemberId: widget.staffId, newPassword: _passwordController.text);

    if (result != null && mounted) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Password reset'),
          content: SelectableText(
            member == null
                ? 'Share this new password with the staff member:\n\nPassword: ${result.assignedPassword}'
                : 'Share this new password with ${member.fullName}:\n\nPassword: ${result.assignedPassword}',
          ),
          actions: [
            TextButton(
              onPressed: () {
                ref.read(provisioningNotifierProvider.notifier).clearLastPasswordReset();
                Navigator.of(context).pop();
                context.go(AppRoutes.settingsStaffDetail(widget.staffId));
              },
              child: const Text('Done'),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(authSessionProvider).context;
    final caller = session?.staffProfile;
    final canReset = caller != null && ProvisioningRules.canResetStaffPassword(caller);
    final provisioning = ref.watch(provisioningNotifierProvider);
    final staffAsync = ref.watch(_staffMemberProvider(widget.staffId));

    if (!canReset) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Reset password'),
          leading: IconButton(tooltip: 'Go back', icon: const Icon(Icons.arrow_back), onPressed: () => context.go(AppRoutes.settingsStaff)),
        ),
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
      appBar: AppBar(
        title: const Text('Reset password'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go(AppRoutes.settingsStaffDetail(widget.staffId)),
        ),
      ),
      body: staffAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Unable to load staff member.', textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => context.go(AppRoutes.settingsStaff),
                  child: const Text('Back to staff list'),
                ),
              ],
            ),
          ),
        ),
        data: (member) {
          if (member == null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Staff member not found.', textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: () => context.go(AppRoutes.settingsStaff),
                      child: const Text('Back to staff list'),
                    ),
                  ],
                ),
              ),
            );
          }

          return Center(
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
                        'Set a new password for ${member.fullName} (${_roleLabel(member.role)}).',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 24),
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
                        onPressed: provisioning.isSubmitting ? null : () => _submit(member),
                        child: provisioning.isSubmitting
                            ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Text('Reset password'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
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

final _staffMemberProvider = FutureProvider.autoDispose.family<StaffListItem?, String>((ref, staffId) async {
  final staff = await ref.read(listStaffUseCaseProvider)(filter: StaffListFilter.all);
  for (final member in staff) {
    if (member.id == staffId) {
      return member;
    }
  }
  return null;
});
