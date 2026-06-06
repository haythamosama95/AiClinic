import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/billing/data/invoice_repository.dart';
import 'package:ai_clinic/features/billing/presentation/billing_rpc_messages.dart';
import 'package:ai_clinic/features/billing/presentation/providers/invoice_detail_provider.dart';

/// Confirms voiding an issued or partially paid invoice with a mandatory reason (V1-6 US6).
Future<bool> showVoidInvoiceDialog({
  required BuildContext context,
  required WidgetRef ref,
  required String invoiceId,
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => VoidInvoiceDialog(invoiceId: invoiceId),
  );
  return result == true;
}

class VoidInvoiceDialog extends ConsumerStatefulWidget {
  const VoidInvoiceDialog({super.key, required this.invoiceId});

  final String invoiceId;

  @override
  ConsumerState<VoidInvoiceDialog> createState() => _VoidInvoiceDialogState();
}

class _VoidInvoiceDialogState extends ConsumerState<VoidInvoiceDialog> {
  final _formKey = GlobalKey<FormState>();
  final _reasonController = TextEditingController();
  bool _isSaving = false;
  String? _errorMessage;

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!ref.read(permissionServiceProvider).canVoidInvoice()) {
      setState(() => _errorMessage = 'You do not have permission to void invoices.');
      return;
    }

    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      await ref
          .read(invoiceRepositoryProvider)
          .voidInvoice(invoiceId: widget.invoiceId, reason: _reasonController.text.trim());
      ref.invalidate(invoiceDetailProvider(widget.invoiceId));
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(true);
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
    return AlertDialog(
      key: const Key('void_invoice_dialog'),
      title: const Text('Void invoice'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Voiding locks this invoice from further changes. A reason is required for the audit trail.'),
            const SizedBox(height: 16),
            TextFormField(
              key: const Key('void_reason_field'),
              controller: _reasonController,
              enabled: !_isSaving,
              decoration: const InputDecoration(labelText: 'Reason', border: OutlineInputBorder()),
              maxLines: 3,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Enter a reason before voiding.';
                }
                return null;
              },
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 12),
              Text(
                _errorMessage!,
                key: const Key('void_invoice_error'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const Key('void_invoice_cancel_button'),
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('void_invoice_confirm_button'),
          onPressed: _isSaving ? null : _submit,
          child: _isSaving
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Void invoice'),
        ),
      ],
    );
  }
}
