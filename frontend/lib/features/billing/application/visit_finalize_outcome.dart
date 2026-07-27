import 'package:ai_clinic/features/billing/domain/invoice_detail.dart';
import 'package:ai_clinic/features/visits/domain/visit_detail.dart';

/// Result of finalizing a visit with optional invoice issuance.
sealed class VisitFinalizeOutcome {
  const VisitFinalizeOutcome();
}

/// Visit completed; invoice issued when permitted and successful.
final class VisitFinalizeSucceeded extends VisitFinalizeOutcome {
  const VisitFinalizeSucceeded({required this.visit, this.invoice});

  final VisitDetail visit;

  /// Null when the user lacks `invoices.create` or invoice creation was skipped.
  final InvoiceDetail? invoice;
}

/// Visit completed but invoice issuance failed; retry may resume the draft.
final class VisitFinalizeInvoiceFailed extends VisitFinalizeOutcome {
  const VisitFinalizeInvoiceFailed({
    required this.visit,
    required this.message,
    this.draftInvoiceId,
  });

  final VisitDetail visit;
  final String message;

  /// Existing draft to resume on retry, when one was created.
  final String? draftInvoiceId;
}

/// Visit completion failed; no invoice side-effects occurred.
final class VisitFinalizeVisitFailed extends VisitFinalizeOutcome {
  const VisitFinalizeVisitFailed(this.message);

  final String message;
}
