import 'package:ai_clinic/core/rpc/rpc_result.dart';

/// User-facing billing RPC error messages (V1-6).
String billingMessageForRpc(RpcFailure failure) {
  return switch (failure.code) {
    'STALE_INVOICE' => 'This invoice was updated elsewhere. Reload and try again.',
    'ACTIVE_INVOICE_EXISTS' => 'This visit already has an active invoice.',
    'VISIT_NOT_COMPLETED' => 'Invoices can only be created from completed visits.',
    'BRANCH_CODE_MISSING' => 'Assign a branch code in Settings before issuing invoices.',
    'NO_ITEMS' => 'Add at least one line item before issuing.',
    'INVOICE_NOT_IN_DRAFT' => 'This invoice can no longer be edited.',
    'FORBIDDEN' => 'You do not have permission to perform this billing action.',
    _ => failure.message.isNotEmpty ? failure.message : 'Billing action failed.',
  };
}
