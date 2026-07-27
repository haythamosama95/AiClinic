import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/billing/application/billing_rpc_messages.dart';
import 'package:ai_clinic/features/billing/application/visit_finalize_outcome.dart';
import 'package:ai_clinic/features/billing/application/visit_invoice_finalization_service.dart';
import 'package:ai_clinic/features/billing/data/invoice_repository.dart';
import 'package:ai_clinic/features/billing/domain/invoice_detail.dart';
import 'package:ai_clinic/features/billing/domain/visit_billing_models.dart';
import 'package:ai_clinic/features/visits/application/visit_rpc_messages.dart';
import 'package:ai_clinic/features/visits/presentation/providers/visit_documentation_notifier.dart';

/// Orchestrates post-review visit finalization: invoice first, then visit completion.
class VisitFinalizationService {
  const VisitFinalizationService(this._ref);

  final Ref _ref;

  Future<VisitFinalizeOutcome> finalize({
    required String visitId,
    required VisitFinalizationRequest request,
    required bool canCreateInvoices,
    required bool canApplyDiscount,
  }) async {
    final docState = _ref.read(visitDocumentationProvider(visitId)).value;
    if (docState == null) {
      return const VisitFinalizeVisitFailed('visit_finalize_failed');
    }

    final expectedUpdatedAt = docState.expectedUpdatedAt;

    if (canCreateInvoices && request.lines.isNotEmpty) {
      try {
        final invoice = await _ref
            .read(visitInvoiceFinalizationServiceProvider)
            .createIssuedInvoiceForVisit(
              visitId: visitId,
              existingDraftId: request.draftInvoiceId,
              lines: request.lines,
              discountType: request.discountType,
              discountValue: request.discountValue,
              canApplyDiscount: canApplyDiscount,
            );

        return _completeVisit(visitId: visitId, expectedUpdatedAt: expectedUpdatedAt, invoice: invoice);
      } on RpcFailure catch (error) {
        final draftId = request.draftInvoiceId ?? await _tryResolveDraftInvoiceId(visitId);
        final visit = _ref.read(visitDocumentationProvider(visitId)).value?.visit;
        if (visit == null) {
          return const VisitFinalizeVisitFailed('visit_finalize_failed');
        }
        return VisitFinalizeInvoiceFailed(
          visit: visit,
          message: billingMessageForRpc(error),
          draftInvoiceId: draftId,
        );
      }
    }

    return _completeVisit(visitId: visitId, expectedUpdatedAt: expectedUpdatedAt);
  }

  Future<VisitFinalizeOutcome> _completeVisit({
    required String visitId,
    required DateTime? expectedUpdatedAt,
    InvoiceDetail? invoice,
  }) async {
    final docNotifier = _ref.read(visitDocumentationProvider(visitId).notifier);

    try {
      await docNotifier.completeVisit(expectedUpdatedAt: expectedUpdatedAt);
      final visit = _ref.read(visitDocumentationProvider(visitId)).value?.visit;
      if (visit == null) {
        return const VisitFinalizeVisitFailed('visit_finalize_failed');
      }
      return VisitFinalizeSucceeded(visit: visit, invoice: invoice);
    } on RpcFailure catch (error) {
      return VisitFinalizeVisitFailed(visitMessageForRpc(error));
    } catch (_) {
      return const VisitFinalizeVisitFailed('visit_finalize_failed');
    }
  }

  Future<String?> _tryResolveDraftInvoiceId(String visitId) async {
    try {
      final existing = await _ref.read(invoiceRepositoryProvider).findForVisit(visitId: visitId);
      if (existing?.status.isDraft == true) {
        return existing!.id;
      }
    } catch (_) {
      return null;
    }
    return null;
  }
}

final visitFinalizationServiceProvider = Provider<VisitFinalizationService>((ref) {
  return VisitFinalizationService(ref);
});
