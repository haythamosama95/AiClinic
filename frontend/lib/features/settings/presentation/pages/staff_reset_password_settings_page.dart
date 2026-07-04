import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/navigation/app_navigator.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/auth/auth_route_guard.dart';
import 'package:ai_clinic/core/ui/ui.dart';
import 'package:ai_clinic/features/setup/domain/provisioning_rules.dart';
import 'package:ai_clinic/features/setup/presentation/providers/provisioning_notifier.dart';

/// Administrator-initiated staff password reset on `/settings/staff/:staffId/reset-password`.
class StaffResetPasswordSettingsPage extends ConsumerStatefulWidget {
  const StaffResetPasswordSettingsPage({required this.staffId, super.key});

  final String staffId;

  @override
  ConsumerState<StaffResetPasswordSettingsPage> createState() => _StaffResetPasswordSettingsPageState();
}

class _StaffResetPasswordSettingsPageState extends ConsumerState<StaffResetPasswordSettingsPage> {
  final _passwordController = TextEditingController();
  String? _passwordError;

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
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

  Future<void> _submit() async {
    final passwordError = _validatePassword(_passwordController.text);
    setState(() => _passwordError = passwordError);
    if (passwordError != null) {
      return;
    }

    final result = await ref.read(provisioningNotifierProvider.notifier).resetStaffPassword(
          staffMemberId: widget.staffId,
          newPassword: _passwordController.text,
        );

    if (result != null && mounted) {
      await _showAssignedPasswordDialog(result.revealAssignedPassword() ?? '');
    }
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
            label: 'Back to staff member',
            onPressed: () async {
              ref.read(provisioningNotifierProvider.notifier).clearLastPasswordReset();
              await close();
              if (!mounted) {
                return;
              }
              context.nav.goSettingsStaffDetail(widget.staffId);
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
    final canAccess = AuthRouteGuard.canAccessStaffManagement(ref.watch(authSessionProvider));
    final canReset = caller != null && ProvisioningRules.canResetStaffPassword(caller);
    final provisioning = ref.watch(provisioningNotifierProvider);

    if (!canAccess || !canReset) {
      return ColoredBox(
        color: context.colors.surfaceCanvas,
        child: const Center(
          child: AppEmptyState(
            variant: AppEmptyStateVariant.noAccess,
            title: 'Reset staff password',
            description: 'Only clinic administrators can reset staff passwords.',
          ),
        ),
      );
    }

    return ColoredBox(
      color: context.colors.surfaceCanvas,
      child: EditorFormPattern(
        title: 'Reset staff password',
        description: 'Set a new password for this staff member. They must sign in with the password you assign.',
        breadcrumb: AppBreadcrumb(
          items: [
            AppBreadcrumbItem(label: 'Settings', onTap: () => context.nav.goSettings()),
            AppBreadcrumbItem(label: 'Staff', onTap: () => context.nav.goSettingsStaff()),
            AppBreadcrumbItem(
              label: 'Staff member',
              onTap: () => context.nav.goSettingsStaffDetail(widget.staffId),
            ),
            const AppBreadcrumbItem(label: 'Reset password'),
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
              label: 'Cancel',
              variant: AppButtonVariant.secondary,
              disabled: provisioning.isSubmitting,
              onPressed: () => context.nav.goSettingsStaffDetail(widget.staffId),
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
