import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/navigation/app_navigator.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/auth/auth_route_guard.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/core/ui/ui.dart';
import 'package:ai_clinic/features/settings/application/settings_rpc_messages.dart';
import 'package:ai_clinic/features/settings/domain/organization_profile.dart';
import 'package:ai_clinic/features/settings/domain/update_organization_input.dart';
import 'package:ai_clinic/features/settings/domain/usecases/settings_use_case_providers.dart';
import 'package:ai_clinic/features/settings/presentation/providers/clinic_setup_providers.dart';
import 'package:ai_clinic/features/settings/presentation/widgets/settings_organization_fields.dart';
import 'package:ai_clinic/features/settings/presentation/widgets/settings_permission_action.dart';
import 'package:ai_clinic/features/setup/domain/bootstrap_field_options.dart';

/// Organization profile settings for administrator roles.
class OrganizationSettingsPage extends ConsumerStatefulWidget {
  const OrganizationSettingsPage({super.key});

  @override
  ConsumerState<OrganizationSettingsPage> createState() => _OrganizationSettingsPageState();
}

class _OrganizationSettingsPageState extends ConsumerState<OrganizationSettingsPage> {
  final _nameController = TextEditingController();
  final _logoUrlController = TextEditingController();
  String? _currency;
  String? _timezone;
  var _isEditing = false;
  var _isSaving = false;
  String? _errorMessage;
  final Map<String, String?> _fieldErrors = {};

  @override
  void dispose() {
    _nameController.dispose();
    _logoUrlController.dispose();
    super.dispose();
  }

  void _applyProfile(OrganizationProfile profile) {
    _nameController.text = profile.name;
    _logoUrlController.text = profile.logoUrl ?? '';
    _currency = profile.currencyCode;
    _timezone = profile.timezone;
  }

  Map<String, String?> _validate() {
    return {
      'name': _nameController.text.trim().isEmpty ? 'Organization name is required.' : null,
      'currency': !BootstrapCurrencyOptions.isValid(_currency) ? 'Select a currency code from the list.' : null,
      'timezone': !BootstrapTimezoneOptions.isValid(_timezone) ? 'Select a timezone from the list.' : null,
    };
  }

  Future<void> _save(OrganizationProfile profile) async {
    final errors = _validate();
    setState(() => _fieldErrors.addAll(errors));
    if (errors.values.any((error) => error != null)) {
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      await ref.read(updateOrganizationUseCaseProvider)(
        UpdateOrganizationInput(
          name: _nameController.text,
          logoUrl: _logoUrlController.text.trim().isEmpty ? null : _logoUrlController.text.trim(),
          currencyCode: _currency,
          timezone: _timezone,
        ),
      );

      ref.invalidate(clinicSetupOrganizationProvider);

      if (!mounted) {
        return;
      }

      setState(() {
        _isEditing = false;
        _isSaving = false;
      });
      ref.showAppToast(message: 'Organization updated.', variant: AppToastVariant.success);
    } on RpcFailure catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isSaving = false;
        _errorMessage = organizationMessageForRpc(error);
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isSaving = false;
        _errorMessage = 'Unable to save organization settings. Check connectivity and try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authSessionProvider);
    final canManage = AuthRouteGuard.canAccessOrganizationSettings(auth);
    final organizationAsync = ref.watch(clinicSetupOrganizationProvider);

    if (!canManage) {
      return ColoredBox(
        color: context.colors.surfaceCanvas,
        child: const Center(
          child: AppEmptyState(
            variant: AppEmptyStateVariant.noAccess,
            title: 'Organization',
            description: 'Only clinic administrators can view or change organization settings.',
          ),
        ),
      );
    }

    return ColoredBox(
      color: context.colors.surfaceCanvas,
      child: organizationAsync.when(
        loading: () => const Center(child: AppSpinner()),
        error: (error, _) => Center(
          child: AppErrorState(
            message: 'Failed to load organization: $error',
            onRetry: () => ref.invalidate(clinicSetupOrganizationProvider),
          ),
        ),
        data: (profile) {
          if (profile == null) {
            return const Center(
              child: AppEmptyState(
                variant: AppEmptyStateVariant.error,
                title: 'Organization not found',
                description: 'Your clinic organization could not be found.',
              ),
            );
          }

          if (!_isEditing && _nameController.text.isEmpty) {
            _applyProfile(profile);
          }

          return EditorFormPattern(
            title: 'Organization',
            description: 'Clinic profile, currency, and timezone.',
            breadcrumb: AppBreadcrumb(
              items: [
                AppBreadcrumbItem(label: 'Settings', onTap: () => context.nav.goSettings()),
                const AppBreadcrumbItem(label: 'Organization'),
              ],
            ),
            headerActions: _isEditing
                ? null
                : SettingsPermissionAction(
                    disabledReason: canManage ? null : 'Only clinic administrators can edit organization settings.',
                    builder: (enabled) => AppButton(
                      label: 'Edit',
                      variant: AppButtonVariant.secondary,
                      size: AppButtonSize.sm,
                      leadingIcon: LucideIcons.pencil,
                      disabled: !enabled,
                      onPressed: enabled ? () => setState(() => _isEditing = true) : null,
                    ),
                  ),
            summaryAlert: _errorMessage == null
                ? null
                : AppAlert(variant: AppAlertVariant.danger, title: _errorMessage!),
            sections: [
              EditorFormSection(
                title: 'Profile',
                fields: [
                  SettingsOrganizationFields(
                    isEditing: _isEditing,
                    nameController: _nameController,
                    logoUrlController: _logoUrlController,
                    currency: _currency,
                    timezone: _timezone,
                    onCurrencyChanged: (value) => setState(() => _currency = value),
                    onTimezoneChanged: (value) => setState(() => _timezone = value),
                    profile: profile,
                    disabled: _isSaving,
                    fieldErrors: _fieldErrors,
                  ),
                ],
              ),
            ],
            footer: _isEditing
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AppButton(
                        label: 'Cancel',
                        variant: AppButtonVariant.secondary,
                        disabled: _isSaving,
                        onPressed: () {
                          _applyProfile(profile);
                          setState(() {
                            _isEditing = false;
                            _errorMessage = null;
                            _fieldErrors.clear();
                          });
                        },
                      ),
                      const SizedBox(width: AppSpacing.s3),
                      AppButton(
                        label: 'Save',
                        loading: _isSaving,
                        onPressed: _isSaving ? null : () => _save(profile),
                      ),
                    ],
                  )
                : AppButton(
                    label: 'Back to settings',
                    variant: AppButtonVariant.secondary,
                    onPressed: () => context.nav.goSettings(),
                  ),
          );
        },
      ),
    );
  }
}
