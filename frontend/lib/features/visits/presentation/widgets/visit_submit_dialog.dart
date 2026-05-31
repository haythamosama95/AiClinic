import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/core/utils/user_error_mapper.dart';
import 'package:ai_clinic/features/visits/data/visit_repository.dart';
import 'package:ai_clinic/features/visits/presentation/visit_rpc_messages.dart';

/// Confirms visit submission and completes the linked appointment (V1-5 US6).
class VisitSubmitDialog extends ConsumerStatefulWidget {
  const VisitSubmitDialog({required this.visitId, this.expectedUpdatedAt, super.key});

  final String visitId;
  final DateTime? expectedUpdatedAt;

  static Future<CompleteVisitResult?> show(
    BuildContext context, {
    required String visitId,
    DateTime? expectedUpdatedAt,
  }) {
    return showDialog<CompleteVisitResult>(
      context: context,
      barrierDismissible: false,
      builder: (context) => VisitSubmitDialog(visitId: visitId, expectedUpdatedAt: expectedUpdatedAt),
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
          .read(visitRepositoryProvider)
          .completeVisit(visitId: widget.visitId, expectedUpdatedAt: widget.expectedUpdatedAt);

      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(result);
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
    return AlertDialog(
      key: const Key('visit_submit_dialog'),
      title: const Text('Submit visit'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Submitting completes this visit and marks the linked appointment as completed. '
              'At least one SOAP section must contain text.',
            ),
            if (_formError != null) ...[
              const SizedBox(height: 12),
              Text(
                _formError!,
                key: const Key('visit_submit_error_label'),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.error),
              ),
            ],
            if (_isSubmitting) ...[
              const SizedBox(height: 16),
              const Center(key: Key('visit_submit_submitting'), child: CircularProgressIndicator()),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const Key('visit_submit_cancel_button'),
          onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('visit_submit_confirm_button'),
          onPressed: _isSubmitting ? null : _submit,
          child: const Text('Submit visit'),
        ),
      ],
    );
  }
}
