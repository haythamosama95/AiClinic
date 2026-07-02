import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/core/ui/theme/spacing_tokens.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/core/utils/user_error_mapper.dart';
import 'package:ai_clinic/features/visits/application/visit_rpc_messages.dart';
import 'package:ai_clinic/features/visits/data/visit_repository.dart' show CompleteVisitResult;
import 'package:ai_clinic/features/visits/presentation/providers/visit_documentation_notifier.dart';

/// Confirms visit submission and completes the linked appointment (V1-5 US6).
class VisitSubmitDialog extends ConsumerStatefulWidget {
  const VisitSubmitDialog({required this.visitId, required this.dialogContext, this.expectedUpdatedAt, super.key});

  final String visitId;
  final BuildContext dialogContext;
  final DateTime? expectedUpdatedAt;

  static Future<CompleteVisitResult?> show(
    BuildContext context, {
    required String visitId,
    DateTime? expectedUpdatedAt,
  }) {
    return AppDialog.show<CompleteVisitResult>(
      context: context,
      title: 'Submit visit',
      barrierDismissible: false,
      bodyBuilder: (dialogContext) => VisitSubmitDialog(
        key: const Key('visit_submit_dialog'),
        visitId: visitId,
        expectedUpdatedAt: expectedUpdatedAt,
        dialogContext: dialogContext,
      ),
    );
  }

  @override
  ConsumerState<VisitSubmitDialog> createState() => _VisitSubmitDialogState();
}

class _VisitSubmitDialogState extends ConsumerState<VisitSubmitDialog> {
  bool _isSubmitting = false;
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

      if (!mounted || !widget.dialogContext.mounted) {
        return;
      }
      Navigator.of(widget.dialogContext).pop(result);
    } on RpcFailure catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isSubmitting = false;
        _formError = visitMessageForRpc(error);
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isSubmitting = false;
        _formError = UserErrorMapper.mapToUserMessage(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Submitting completes this visit and marks the linked appointment as completed. '
          'After submission, documentation remains editable for users with edit permission.',
          style: theme.textTheme.bodyMedium,
        ),
        if (_formError != null) ...[
          const SizedBox(height: SpacingTokens.md),
          AppAlert(
            key: const Key('visit_submit_error_label'),
            title: _formError!,
            variant: AppAlertVariant.destructive,
          ),
        ],
        if (_isSubmitting) ...[
          const SizedBox(height: SpacingTokens.lg),
          const Center(key: Key('visit_submit_submitting'), child: AppCircularProgress()),
        ],
        const SizedBox(height: SpacingTokens.lg),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            AppButton(
              key: const Key('visit_submit_cancel_button'),
              label: 'Cancel',
              variant: AppButtonVariant.secondary,
              expand: false,
              onPressed: _isSubmitting ? null : () => Navigator.of(widget.dialogContext).pop(),
            ),
            const SizedBox(width: SpacingTokens.sm),
            AppButton(
              key: const Key('visit_submit_confirm_button'),
              label: 'Submit visit',
              expand: false,
              isLoading: _isSubmitting,
              onPressed: _isSubmitting ? null : _submit,
            ),
          ],
        ),
      ],
    );
  }
}
