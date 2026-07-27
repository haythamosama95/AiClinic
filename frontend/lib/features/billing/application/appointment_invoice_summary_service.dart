import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/logging/app_log.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/billing/application/billing_rpc_messages.dart';
import 'package:ai_clinic/features/billing/data/invoice_repository.dart';
import 'package:ai_clinic/features/billing/domain/invoice_detail.dart';
import 'package:ai_clinic/features/visits/data/visit_repository.dart';

/// Why [AppointmentInvoiceSummaryService.loadForAppointment] returned no invoice.
enum AppointmentInvoiceSummaryMissingReason {
  noVisit,
  noInvoice,
}

/// Result of loading an invoice summary for an appointment.
sealed class AppointmentInvoiceSummaryLoadResult {
  const AppointmentInvoiceSummaryLoadResult();
}

/// Invoice detail loaded successfully.
final class AppointmentInvoiceSummaryFound extends AppointmentInvoiceSummaryLoadResult {
  const AppointmentInvoiceSummaryFound(this.invoice);

  final InvoiceDetail invoice;
}

/// No invoice could be loaded; [reason] explains why.
final class AppointmentInvoiceSummaryMissing extends AppointmentInvoiceSummaryLoadResult {
  const AppointmentInvoiceSummaryMissing(this.reason);

  final AppointmentInvoiceSummaryMissingReason reason;
}

/// Load failure with a user-facing message.
final class AppointmentInvoiceSummaryFailed extends AppointmentInvoiceSummaryLoadResult {
  const AppointmentInvoiceSummaryFailed(this.userMessage);

  final String userMessage;
}

/// Resolves visit and invoice data for an appointment's invoice summary.
class AppointmentInvoiceSummaryService {
  const AppointmentInvoiceSummaryService(this._visitRepository, this._invoiceRepository);

  final VisitRepository _visitRepository;
  final InvoiceRepository _invoiceRepository;

  Future<AppointmentInvoiceSummaryLoadResult> loadForAppointment({required String appointmentId}) async {
    try {
      final link = await _visitRepository.getVisitByAppointment(appointmentId: appointmentId);
      final visitId = link.visitId?.trim();
      if (visitId == null || visitId.isEmpty) {
        return const AppointmentInvoiceSummaryMissing(AppointmentInvoiceSummaryMissingReason.noVisit);
      }

      final listItem = await _invoiceRepository.findForVisit(visitId: visitId);
      if (listItem == null) {
        return const AppointmentInvoiceSummaryMissing(AppointmentInvoiceSummaryMissingReason.noInvoice);
      }

      final invoice = await _invoiceRepository.getDetail(invoiceId: listItem.id);
      return AppointmentInvoiceSummaryFound(invoice);
    } on RpcFailure catch (error) {
      return AppointmentInvoiceSummaryFailed(billingMessageForRpc(error));
    } catch (error, stack) {
      AppLog.warning('appointments.detail_invoice_summary.load_failed reason=${error.runtimeType}');
      AppLog.fine('appointments.detail_invoice_summary.load_failed.stack $stack');
      return const AppointmentInvoiceSummaryFailed('Could not load the invoice summary. Please try again.');
    }
  }
}

final appointmentInvoiceSummaryServiceProvider = Provider<AppointmentInvoiceSummaryService>((ref) {
  return AppointmentInvoiceSummaryService(
    ref.watch(visitRepositoryProvider),
    ref.watch(invoiceRepositoryProvider),
  );
});
