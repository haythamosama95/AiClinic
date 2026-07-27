import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/navigation/app_navigator.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/features/billing/application/visit_finalize_outcome.dart';
import 'package:ai_clinic/features/billing/domain/invoice_detail.dart';
import 'package:ai_clinic/features/billing/domain/visit_billing_models.dart';
import 'package:ai_clinic/features/billing/presentation/pages/visit_billing_page.dart';
import 'package:ai_clinic/features/billing/presentation/widgets/visit_billing/visit_invoice_summary_panel.dart';
import 'package:ai_clinic/features/patients/presentation/providers/patient_detail_provider.dart';
import 'package:ai_clinic/features/setup/presentation/providers/staff_assignable_branches_provider.dart';
import 'package:ai_clinic/features/visits/application/visit_finalization_service.dart';
import 'package:ai_clinic/features/visits/domain/visit_detail.dart';
import 'package:ai_clinic/features/visits/domain/visit_submission_confirmation.dart';
import 'package:ai_clinic/features/visits/presentation/providers/visit_documentation_notifier.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_submitted_dialog.dart';

/// Visits-owned host for the billing workflow; wires finalization and confirmation.
class VisitBillingHostPage extends ConsumerWidget {
  const VisitBillingHostPage({required this.visitId, super.key});

  final String visitId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final docAsync = ref.watch(visitDocumentationProvider(visitId));

    return docAsync.when(
      loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      error: (error, _) => Center(child: Text(error.toString())),
      data: (docState) {
        final visit = docState.visit;
        final patientAsync = ref.watch(patientDetailProvider(visit.patientId));
        final branchesAsync = ref.watch(staffAssignableBranchesProvider);
        final patientName = patientAsync.maybeWhen(
          data: (patient) => patient.fullName,
          orElse: () => 'Patient',
        );
        final branchName = branchesAsync.maybeWhen(
          data: (branches) =>
              branches.where((branch) => branch.id == visit.branchId).map((branch) => branch.name).firstOrNull ??
              visit.branchId,
          orElse: () => visit.branchId,
        );

        return VisitBillingPage(
          visitId: visitId,
          patientId: visit.patientId,
          patientName: patientName,
          branchId: visit.branchId,
          branchName: branchName,
          onBackToReview: () => context.nav.goVisitDocument(visitId),
          onFinalizeRequested: (request) {
            final permissions = ref.read(permissionServiceProvider);
            return ref.read(visitFinalizationServiceProvider).finalize(
              visitId: visitId,
              request: request,
              canCreateInvoices: permissions.canCreateInvoices(),
              canApplyDiscount: permissions.canApplyDiscount(),
            );
          },
          onFinalizeOutcome: (outcome, {invoicePreview}) => _showFinalizeOutcome(
            context,
            outcome: outcome,
            patientName: patientName,
            branchName: branchName,
            invoicePreview: invoicePreview,
          ),
        );
      },
    );
  }

  static Future<void> _showFinalizeOutcome(
    BuildContext context, {
    required VisitFinalizeOutcome outcome,
    required String patientName,
    required String branchName,
    VisitBillingInvoicePreview? invoicePreview,
  }) {
    return switch (outcome) {
      VisitFinalizeSucceeded(:final visit, :final invoice) => _showConfirmation(
        context,
        visit: visit,
        patientName: patientName,
        branchName: branchName,
        invoicePreview: invoicePreview,
        persistedInvoice: invoice,
      ),
      VisitFinalizeInvoiceFailed(:final visit) => _showConfirmation(
        context,
        visit: visit,
        patientName: patientName,
        branchName: branchName,
        invoicePreview: invoicePreview,
      ),
      VisitFinalizeVisitFailed() => Future<void>.value(),
    };
  }

  static Future<void> _showConfirmation(
    BuildContext context, {
    required VisitDetail visit,
    required String patientName,
    required String branchName,
    VisitBillingInvoicePreview? invoicePreview,
    InvoiceDetail? persistedInvoice,
  }) {
    final confirmation = VisitSubmissionConfirmation.fromVisit(
      visit: visit,
      patientName: patientName,
      branchName: branchName,
      appointmentStart: visit.visitDate,
      appointmentEnd: visit.visitDate.add(const Duration(minutes: 30)),
      actionAt: DateTime.now().toUtc(),
    );

    Widget? invoiceSummary;
    if (persistedInvoice != null) {
      invoiceSummary = VisitInvoiceSummaryPanel(invoice: persistedInvoice, expanded: true);
    } else if (invoicePreview != null) {
      invoiceSummary = VisitInvoiceSummaryPanel(preview: invoicePreview, expanded: true);
    }

    return VisitSubmittedDialog.show(
      context,
      confirmation: confirmation,
      invoiceSummary: invoiceSummary,
    );
  }
}
