import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/core/ui/ui.dart';
import 'package:ai_clinic/features/visits/application/visit_rpc_messages.dart';
import 'package:ai_clinic/features/visits/data/visit_repository.dart' show CompleteVisitResult;
import 'package:ai_clinic/features/visits/presentation/providers/visit_documentation_notifier.dart';

/// Confirms visit submission and completes the linked appointment (V1-5 US6).
class VisitSubmitDialog extends ConsumerStatefulWidget {
  const VisitSubmitDialog({
    required this.visitId,
    required this.onClose,
    this.expectedUpdatedAt,
    super.key,
  });

  final String visitId;
  final AppDialogCloseCallback<CompleteVisitResult> onClose;
  final DateTime? expectedUpdatedAt;

  static Future<CompleteVisitResult?> show(
    BuildContext context, {
    required String visitId,
    DateTime? expectedUpdatedAt,
  }) {
    return showAppDialog<CompleteVisitResult>(
      context,
      size: AppDialogSize.sm,
      barrierDismissible: false,
      semanticLabel: 'Submit visit',
      builder: (dialogContext, close) {
        return AppDialog(
          title: 'Submit visit',
          onClose: () => close(),
          body: VisitSubmitDialog(
            visitId: visitId,
            expectedUpdatedAt: expectedUpdatedAt,
            onClose: close,
          ),
        );
      },
    );
  }

  @override
  ConsumerState<VisitSubmitDialog> createState() => _VisitSubmitDialogState();
}

class _VisitSubmitDialogState extends ConsumerState<VisitSubmitDialog> {
  var _isSubmitting = false;
  String? _formError;

  Future<void> _submit() async {
    setState(() {
      _isSubmitting = true;
      _formError = null;
    });

    try {
      final result = await ref
          .read(visitDocumentationProvider(widget.visitId).notifier)
          .completeVisit(expectedUpdatedAt: widget.expectedUpdatedAt);

      if (!mounted) return;
      await widget.onClose(result);
    } on RpcFailure catch (error) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _formError = visitMessageForRpc(error);
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _formError = error.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final typography = context.typography;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Submitting completes this visit and marks the linked appointment as completed. '
          'After submission, documentation remains editable for users with edit permission.',
          style: typography.body.copyWith(color: context.colors.textSecondary),
        ),
        if (_formError != null) ...[
          const SizedBox(height: AppSpacing.s3),
          AppAlert(variant: AppAlertVariant.danger, title: _formError!),
        ],
        if (_isSubmitting) ...[
          const SizedBox(height: AppSpacing.s4),
          const Center(child: AppSpinner()),
        ],
        const SizedBox(height: AppSpacing.s4),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            AppButton(
              label: 'Cancel',
              variant: AppButtonVariant.secondary,
              size: AppButtonSize.sm,
              disabled: _isSubmitting,
              onPressed: () => widget.onClose(),
            ),
            const SizedBox(width: AppSpacing.s2),
            AppButton(
              label: 'Submit visit',
              size: AppButtonSize.sm,
              loading: _isSubmitting,
              onPressed: _isSubmitting ? null : _submit,
            ),
          ],
        ),
      ],
    );
  }
}
