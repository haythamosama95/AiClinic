import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/core/ui/theme/spacing_tokens.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/settings/application/settings_rpc_messages.dart';
import 'package:ai_clinic/features/settings/domain/organization_profile.dart';
import 'package:ai_clinic/features/settings/domain/update_organization_input.dart';
import 'package:ai_clinic/features/settings/domain/usecases/settings_use_case_providers.dart';
import 'package:ai_clinic/features/settings/presentation/providers/clinic_setup_providers.dart';
import 'package:ai_clinic/features/settings/presentation/widgets/create_branch_modal.dart';
import 'package:ai_clinic/features/settings/presentation/widgets/settings_section_card.dart';
import 'package:ai_clinic/features/setup/presentation/widgets/organization_form_fields.dart';

/// Organization profile card for clinic setup settings.
class OrganizationSettingsSection extends ConsumerStatefulWidget {
  const OrganizationSettingsSection({required this.profile, super.key});

  final OrganizationProfile profile;

  @override
  ConsumerState<OrganizationSettingsSection> createState() => _OrganizationSettingsSectionState();
}

class _OrganizationSettingsSectionState extends ConsumerState<OrganizationSettingsSection> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _logoUrlController;
  String? _currency;
  String? _timezone;
  var _isEditing = false;
  var _isSaving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _logoUrlController = TextEditingController();
    _applyProfile(widget.profile);
  }

  @override
  void didUpdateWidget(covariant OrganizationSettingsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.profile != widget.profile && !_isEditing) {
      _applyProfile(widget.profile);
    }
  }

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

  OrganizationFormExistingData get _existingData => OrganizationFormExistingData(
    name: widget.profile.name,
    logoUrl: widget.profile.logoUrl,
    currencyCode: widget.profile.currencyCode,
    timezone: widget.profile.timezone,
  );

  void _startEditing() {
    setState(() {
      _isEditing = true;
      _errorMessage = null;
    });
  }

  void _cancelEditing() {
    _applyProfile(widget.profile);
    setState(() {
      _isEditing = false;
      _errorMessage = null;
    });
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
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
      AppToast.success(context, message: 'Organization updated.');
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

  Future<void> _openCreateBranchModal() async {
    await CreateBranchModal.show(context);
  }

  @override
  Widget build(BuildContext context) {
    return SettingsSectionCard(
      title: 'Organization',
      isEditing: _isEditing,
      isSaving: _isSaving,
      headerLeadingActions: _isEditing
          ? null
          : AppButton(
              label: 'Add branch',
              variant: AppButtonVariant.outline,
              expand: false,
              icon: const Icon(Icons.add_business_outlined, size: 18),
              onPressed: _openCreateBranchModal,
            ),
      onEdit: _startEditing,
      onSave: _save,
      onCancel: _cancelEditing,
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_errorMessage != null) ...[
              AppAlert(variant: AppAlertVariant.destructive, title: _errorMessage!),
              const SizedBox(height: SpacingTokens.lg),
            ],
            OrganizationFormFields(
              mode: OrganizationFormFieldsMode.edit,
              isEditing: _isEditing,
              existing: _existingData,
              nameController: _nameController,
              logoUrlController: _logoUrlController,
              currency: _currency,
              timezone: _timezone,
              onCurrencyChanged: (value) => setState(() => _currency = value),
              onTimezoneChanged: (value) => setState(() => _timezone = value),
              enabled: !_isSaving,
            ),
          ],
        ),
      ),
    );
  }
}
