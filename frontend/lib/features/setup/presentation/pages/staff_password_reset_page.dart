import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/ui/ui.dart';
import 'package:ai_clinic/features/setup/domain/provisioning_rules.dart';
import 'package:ai_clinic/features/setup/domain/staff_member_summary.dart';
import 'package:ai_clinic/features/setup/presentation/providers/provisioning_notifier.dart';

/// Administrator-initiated staff password reset on `/staff/reset-password` (US7).
class StaffPasswordResetPage extends ConsumerStatefulWidget {
  const StaffPasswordResetPage({super.key});

  @override
  ConsumerState<StaffPasswordResetPage> createState() => _StaffPasswordResetPageState();
}

class _StaffPasswordResetPageState extends ConsumerState<StaffPasswordResetPage> {
  final _passwordController = TextEditingController();

  String? _selectedStaffId;
  String? _passwordError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.invalidate(staffResetCandidatesProvider);
    });
  }

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final passwordError = _validatePassword(_passwordController.text);
    final staffError = _selectedStaffId == null ? 'Select a staff member to reset.' : null;
    setState(() {
      _passwordError = passwordError;
    });

    if (passwordError != null || staffError != null) {
      if (staffError != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(staffError)));
      }
      return;
    }

    final result = await ref.read(provisioningNotifierProvider.notifier).resetStaffPassword(
          staffMemberId: _selectedStaffId!,
          newPassword: _passwordController.text,
        );

    if (result != null && mounted) {
      await _showAssignedPasswordDialog(result.revealAssignedPassword() ?? '');
    }
  }

  String? _validatePassword(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return 'Enter a new password for the staff member.';
    }
    if (trimmed.length < 6) {
      return 'Password must be at least 6 characters.';
    }
    return null;
  }

  Future<void> _showAssignedPasswordDialog(String password) async {
    await showAppDialog<void>(
      context,
      builder: (dialogContext, close) {
        return AppDialog(
          title: 'Password reset',
          body: SelectableText(
            'Share this new password with the staff member:\n\nPassword: $password',
            style: dialogContext.typography.body.copyWith(color: dialogContext.colors.textPrimary),
          ),
          footer: AppButton(
            label: 'Done',
            onPressed: () async {
              ref.read(provisioningNotifierProvider.notifier).clearLastPasswordReset();
              await close();
            },
          ),
        );
      },
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
        body: AppAsyncStateView(
          state: AppContentState.noAccess,
          config: const AppContentStateConfig(
            noAccessTitle: 'Reset staff password',
            noAccessDescription: 'Only clinic administrators can reset staff passwords.',
          ),
          child: const SizedBox.shrink(),
        ),
      );
    }

    return Scaffold(
      backgroundColor: context.colors.surfaceCanvas,
      body: EditorFormPattern(
        title: 'Reset staff password',
        description: 'Set a new password for a staff member. They must sign in with the password you assign.',
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
            title: 'Staff member',
            fields: [
              AppAsyncStateView(
                state: candidatesAsync.isLoading
                    ? AppContentState.loading
                    : candidatesAsync.hasError
                    ? AppContentState.error
                    : candidatesAsync.requireValue.isEmpty
                    ? AppContentState.emptyNoResults
                    : AppContentState.ready,
                config: const AppContentStateConfig(
                  errorTitle: 'Unable to load staff',
                  errorMessage: 'Unable to load staff list. Try again later.',
                  emptyNoResultsTitle: 'No staff available',
                  emptyNoResultsDescription: 'No staff members are available to reset. Create staff accounts first.',
                ),
                child: AppFormField(
                  label: 'Staff member',
                  requiredMark: true,
                  child: AppSelect<String>(
                    options: [
                      for (final member in candidatesAsync.requireValue)
                        AppSelectOption<String>(
                          value: member.id,
                          label: '${member.fullName} (${member.roleLabel})',
                        ),
                    ],
                    value: _selectedStaffId,
                    placeholder: 'Select a staff member',
                    disabled: provisioning.isSubmitting,
                    onChanged: provisioning.isSubmitting
                        ? null
                        : (value) => setState(() => _selectedStaffId = value),
                  ),
                ),
              ),
            ],
          ),
          EditorFormSection(
            title: 'New password',
            fields: [
              AppFormField(
                label: 'New password',
                requiredMark: true,
                error: _passwordError,
                child: AppPasswordField(
                  controller: _passwordController,
                  disabled: provisioning.isSubmitting,
                  invalid: _passwordError != null,
                  onChanged: (_) {
                    if (_passwordError != null) {
                      setState(() => _passwordError = _validatePassword(_passwordController.text));
                    }
                  },
                ),
              ),
            ],
          ),
        ],
        footer: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppButton(
              label: 'Back to home',
              variant: AppButtonVariant.secondary,
              disabled: provisioning.isSubmitting,
              onPressed: () => context.go(AppRoutes.home),
            ),
            const SizedBox(width: AppSpacing.s3),
            AppButton(
              label: 'Reset password',
              loading: provisioning.isSubmitting,
              onPressed: _submit,
            ),
          ],
        ),
      ),
    );
  }
}
