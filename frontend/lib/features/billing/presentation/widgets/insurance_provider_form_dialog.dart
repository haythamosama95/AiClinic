import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/core/ui/ui.dart';
import 'package:ai_clinic/features/billing/application/billing_rpc_messages.dart';
import 'package:ai_clinic/features/billing/domain/insurance_provider.dart';
import 'package:ai_clinic/features/billing/presentation/providers/insurance_providers_notifier.dart';

/// Create or edit an insurance provider catalog entry.
Future<bool> showInsuranceProviderFormDialog({
  required BuildContext context,
  required WidgetRef ref,
  InsuranceProvider? provider,
}) {
  return showAppDialog<bool>(
    context,
    size: AppDialogSize.sm,
    barrierDismissible: false,
    semanticLabel: provider == null ? 'New insurance provider' : 'Edit insurance provider',
    builder: (dialogContext, close) {
      return _InsuranceProviderFormDialogContent(
        provider: provider,
        onClose: () => close(false),
        onSaved: () => close(true),
      );
    },
  ).then((value) => value ?? false);
}

class _InsuranceProviderFormDialogContent extends ConsumerStatefulWidget {
  const _InsuranceProviderFormDialogContent({
    required this.provider,
    required this.onClose,
    required this.onSaved,
  });

  final InsuranceProvider? provider;
  final VoidCallback onClose;
  final VoidCallback onSaved;

  @override
  ConsumerState<_InsuranceProviderFormDialogContent> createState() =>
      _InsuranceProviderFormDialogContentState();
}

class _InsuranceProviderFormDialogContentState extends ConsumerState<_InsuranceProviderFormDialogContent> {
  late final TextEditingController _nameController;
  late final TextEditingController _contactController;
  var _isSaving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.provider?.name ?? '');
    _contactController = TextEditingController(text: widget.provider?.contactInfo ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _contactController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _errorMessage = 'Name is required.');
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      await ref.read(insuranceProvidersProvider.notifier).upsert(
        id: widget.provider?.id,
        name: name,
        contactInfo: _contactController.text.trim().isEmpty ? null : _contactController.text.trim(),
        isActive: widget.provider?.isActive ?? true,
      );
      if (!mounted) {
        return;
      }
      widget.onSaved();
    } on RpcFailure catch (failure) {
      setState(() {
        _isSaving = false;
        _errorMessage = billingMessageForRpc(failure);
      });
    } catch (error) {
      setState(() {
        _isSaving = false;
        _errorMessage = error.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      title: widget.provider == null ? 'New insurance provider' : 'Edit insurance provider',
      onClose: _isSaving ? null : widget.onClose,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppFormField(
            label: 'Name',
            child: AppTextField(
              key: const Key('insurance_provider_name_field'),
              controller: _nameController,
              hintText: 'Provider name',
              disabled: _isSaving,
            ),
          ),
          const SizedBox(height: AppSpacing.s3),
          AppFormField(
            label: 'Contact info (optional)',
            child: AppTextField(
              key: const Key('insurance_provider_contact_field'),
              controller: _contactController,
              hintText: 'Phone, email, or notes',
              disabled: _isSaving,
            ),
          ),
          if (_errorMessage != null) ...[
            const SizedBox(height: AppSpacing.s3),
            AppAlert(variant: AppAlertVariant.danger, title: _errorMessage!),
          ],
        ],
      ),
      footer: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          AppButton(
            label: 'Cancel',
            variant: AppButtonVariant.secondary,
            disabled: _isSaving,
            onPressed: widget.onClose,
          ),
          const SizedBox(width: AppSpacing.s2),
          AppButton(
            key: const Key('insurance_provider_save_button'),
            label: 'Save',
            loading: _isSaving,
            onPressed: _isSaving ? null : _save,
          ),
        ],
      ),
    );
  }
}
