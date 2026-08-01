import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/clinic-management/presentation/forms/service_form_fields.dart';
import 'package:ai_clinic/features/clinic-management/presentation/models/service_form_values.dart';

enum ServiceFormDialogMode { create, edit }

/// Create/edit service dialog (web `ServicesTab` dialog).
class ServiceFormDialog extends StatefulWidget {
  const ServiceFormDialog({
    required this.open,
    required this.onOpenChange,
    required this.mode,
    required this.currencyCode,
    required this.initialValues,
    required this.onSubmit,
    this.loading = false,
    this.loadError,
    super.key,
  });

  final bool open;
  final ValueChanged<bool> onOpenChange;
  final ServiceFormDialogMode mode;
  final String currencyCode;
  final ServiceFormValues initialValues;
  final Future<void> Function(ServiceFormValues values) onSubmit;
  final bool loading;
  final String? loadError;

  @override
  State<ServiceFormDialog> createState() => _ServiceFormDialogState();
}

class _ServiceFormDialogState extends State<ServiceFormDialog> {
  late ServiceFormValues _values = widget.initialValues;
  ServiceFormErrors _errors = const {};
  var _submitting = false;
  String? _submitError;

  @override
  void didUpdateWidget(covariant ServiceFormDialog oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.open &&
        (!oldWidget.open ||
            widget.initialValues != oldWidget.initialValues ||
            widget.loadError != oldWidget.loadError)) {
      _values = widget.initialValues;
      _errors = const {};
      _submitting = false;
      _submitError = null;
    }
  }

  Future<void> _handleSubmit() async {
    final nextErrors = validateServiceFormValues(_values);
    if (nextErrors.isNotEmpty) {
      setState(() {
        _errors = nextErrors;
        _submitError = null;
      });
      return;
    }

    setState(() {
      _submitting = true;
      _submitError = null;
    });
    try {
      await widget.onSubmit(_values);
      if (!mounted) {
        return;
      }
      widget.onOpenChange(false);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _submitError = _messageForSubmitError(error));
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  String _messageForSubmitError(Object error) {
    return switch (error) {
      StateError(:final message) when message.isNotEmpty => message,
      _ => 'Unable to save service. Please try again.',
    };
  }

  @override
  Widget build(BuildContext context) {
    final isCreate = widget.mode == ServiceFormDialogMode.create;
    final disabled = widget.loading || _submitting || widget.loadError != null;

    return AppDialog(
      open: widget.open,
      onOpenChange: widget.onOpenChange,
      title: isCreate ? 'Add service' : 'Edit service',
      size: AppDialogSize.md,
      footer: AppButton(
        loading: _submitting,
        disabled: disabled,
        onPressed: disabled ? null : _handleSubmit,
        child: Text(isCreate ? 'Add service' : 'Save changes'),
      ),
      child: widget.loading
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.space8),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: context.appColors.iconMuted)),
            )
          : widget.loadError != null
          ? AppAlert(variant: AppAlertVariant.danger, title: 'Unable to load service', child: Text(widget.loadError!))
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_submitError != null) ...[
                  AppAlert(
                    variant: AppAlertVariant.danger,
                    title: 'Unable to save service',
                    child: Text(_submitError!),
                  ),
                  const SizedBox(height: AppSpacing.space4),
                ],
                ServiceFormFields(
                  idPrefix: isCreate ? 'new-service' : 'edit-service',
                  values: _values,
                  onChange: (values) => setState(() {
                    _values = values;
                    _errors = const {};
                    _submitError = null;
                  }),
                  currency: widget.currencyCode,
                  disabled: disabled,
                  errors: _errors,
                ),
              ],
            ),
    );
  }
}
