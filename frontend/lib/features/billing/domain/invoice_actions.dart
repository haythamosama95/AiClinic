import 'package:flutter/foundation.dart';

import 'package:ai_clinic/features/billing/domain/invoice_status.dart';

/// Status and permission matrix for invoice ledger actions (V1-6).
@immutable
class InvoiceActionPolicy {
  const InvoiceActionPolicy({
    required this.status,
    required this.canCreate,
    required this.canApplyDiscount,
    required this.canVoidPermission,
    required this.canRecordPaymentPermission,
    required this.canRefundPermission,
  });

  final InvoiceStatus status;
  final bool canCreate;
  final bool canApplyDiscount;
  final bool canVoidPermission;
  final bool canRecordPaymentPermission;
  final bool canRefundPermission;

  bool get canEdit => status.isDraft && canCreate;

  bool get canIssue => status.isDraft && canCreate;

  bool get canVoid => canVoidPermission && status.isVoidable;

  bool get canRecordPayment => canRecordPaymentPermission && !status.isDraft && !status.isTerminal;

  bool get canRefund => canRefundPermission && !status.isDraft && !status.isVoided;
}
