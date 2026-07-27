import 'package:ai_clinic/features/billing/domain/invoice_detail.dart';
import 'package:ai_clinic/features/billing/domain/visit_billing_models.dart';
import 'package:ai_clinic/features/visits/domain/visit_detail.dart';
import 'package:ai_clinic/features/visits/domain/visit_submission_confirmation.dart';

/// Confirmation payload for the post-finalize visit dialog.
class VisitSubmittedConfirmationData {
  const VisitSubmittedConfirmationData({
    required this.confirmation,
    required this.invoicePreview,
    required this.persistedInvoice,
  });

  final VisitSubmissionConfirmation confirmation;
  final VisitBillingInvoicePreview? invoicePreview;
  final InvoiceDetail? persistedInvoice;

  static VisitSubmittedConfirmationData fromVisit({
    required VisitDetail visit,
    required String patientName,
    required String branchName,
    required DateTime appointmentStart,
    required DateTime appointmentEnd,
    VisitConfirmationKind kind = VisitConfirmationKind.completed,
    DateTime? actionAt,
    required VisitBillingInvoicePreview? invoicePreview,
    required InvoiceDetail? persistedInvoice,
  }) {
    return VisitSubmittedConfirmationData(
      confirmation: VisitSubmissionConfirmation.fromVisit(
        visit: visit,
        patientName: patientName,
        branchName: branchName,
        appointmentStart: appointmentStart,
        appointmentEnd: appointmentEnd,
        kind: kind,
        actionAt: actionAt,
      ),
      invoicePreview: invoicePreview,
      persistedInvoice: persistedInvoice,
    );
  }
}
