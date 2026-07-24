import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/patients/application/patient_rpc_messages.dart';
import 'package:ai_clinic/features/patients/domain/usecases/patient_use_case_providers.dart';
import 'package:ai_clinic/features/patients/presentation/providers/patient_detail_provider.dart';

const _mrnFormatHint = 'MRN-NNNNNN';

/// Restricted administrator flow to reassign a patient's MRN.
abstract final class MrnReassignmentDialog {
  const MrnReassignmentDialog._();

  static Future<bool> show(
    BuildContext context, {
    required String patientId,
    required String currentMrn,
  }) async {
    final result = await AppDialog.show<bool>(
      context,
      title: 'Reassign MRN',
      description: 'Change this patient\'s medical record number. The new value must be unique.',
      maxWidth: 440,
      size: AppDialogSize.md,
      child: _MrnReassignmentDialogContent(patientId: patientId, currentMrn: currentMrn),
    );
    return result ?? false;
  }
}

class _MrnReassignmentDialogContent extends ConsumerStatefulWidget {
  const _MrnReassignmentDialogContent({required this.patientId, required this.currentMrn});

  final String patientId;
  final String currentMrn;

  @override
  ConsumerState<_MrnReassignmentDialogContent> createState() => _MrnReassignmentDialogContentState();
}

class _MrnReassignmentDialogContentState extends ConsumerState<_MrnReassignmentDialogContent> {
  late final TextEditingController _controller;
  var _submitting = false;
  String? _inlineError;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.currentMrn);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _controller.selection = TextSelection(baseOffset: 0, extentOffset: _controller.text.length);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _canSave {
    final trimmed = _controller.text.trim();
    return trimmed.isNotEmpty && trimmed != widget.currentMrn && !_submitting;
  }

  void _handleChanged(String _) {
    if (_inlineError != null) {
      setState(() => _inlineError = null);
    } else {
      setState(() {});
    }
  }

  Future<void> _submit(BuildContext dialogContext) async {
    if (!_canSave) {
      return;
    }

    setState(() {
      _submitting = true;
      _inlineError = null;
    });

    try {
      final newMrn = await ref
          .read(reassignPatientMrnUseCaseProvider)
          .call(patientId: widget.patientId, newMrn: _controller.text.trim());

      ref.invalidate(patientDetailProvider(widget.patientId));

      if (!mounted) {
        return;
      }

      appToast(
        context,
        AppToastInput(message: 'MRN updated to $newMrn', variant: AppToastVariant.success),
      );

      if (dialogContext.mounted) {
        Navigator.of(dialogContext).pop(true);
      }
    } on RpcFailure catch (error) {
      if (!mounted) {
        return;
      }

      switch (error.code) {
        case 'MRN_EXISTS':
          setState(() => _inlineError = patientMessageForRpc(error));
        case 'INVALID_INPUT':
          setState(() => _inlineError = _mrnFormatHint);
        case 'PATIENT_ARCHIVED':
        case 'FORBIDDEN':
          if (dialogContext.mounted) {
            Navigator.of(dialogContext).pop(false);
          }
          appToast(context, AppToastInput(message: patientMessageForRpc(error), variant: AppToastVariant.danger));
        default:
          appToast(context, AppToastInput(message: patientMessageForRpc(error), variant: AppToastVariant.danger));
      }
    } catch (_) {
      if (mounted) {
        appToast(
          context,
          const AppToastInput(
            message: 'Could not reassign the MRN. Please try again.',
            variant: AppToastVariant.danger,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppFormField(
          id: 'reassign-mrn',
          label: 'Medical record number',
          requiredMark: true,
          helperText: _inlineError == null ? _mrnFormatHint : null,
          error: _inlineError,
          child: Focus(
            autofocus: true,
            child: AppTextInput(
              id: 'reassign-mrn',
              controller: _controller,
              onChanged: _handleChanged,
              placeholder: _mrnFormatHint,
              disabled: _submitting,
              invalid: _inlineError != null,
              textInputAction: TextInputAction.done,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.space4),
        Row(
          children: [
            AppButton(
              variant: AppButtonVariant.secondary,
              onPressed: _submitting ? null : () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            const Spacer(),
            AppButton(
              variant: AppButtonVariant.primary,
              loading: _submitting,
              onPressed: _canSave ? () => _submit(context) : null,
              child: const Text('Save'),
            ),
          ],
        ),
      ],
    );
  }
}
