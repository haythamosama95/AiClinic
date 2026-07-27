import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/navigation/app_navigator.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/appointments/presentation/providers/appointment_window_facade.dart';
import 'package:ai_clinic/features/billing/domain/invoice_detail.dart';
import 'package:ai_clinic/features/billing/domain/visit_billing_models.dart';
import 'package:ai_clinic/features/billing/presentation/widgets/visit_billing/visit_invoice_summary_panel.dart';
import 'package:ai_clinic/features/patients/presentation/providers/patient_summary_facade.dart';
import 'package:ai_clinic/features/setup/presentation/providers/branch_name_facade.dart';
import 'package:ai_clinic/features/visits/domain/visit_detail.dart';
import 'package:ai_clinic/features/visits/domain/visit_submission_confirmation.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_submitted_combined_confirmation.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_submitted_confirmation_data.dart';

/// Presents the post-finalize confirmation card in a modal dialog.
class VisitSubmittedDialog {
  VisitSubmittedDialog._();

  /// Legacy entry point for callers that already resolved confirmation data.
  static Future<void> show(
    BuildContext context, {
    required VisitSubmissionConfirmation confirmation,
    Widget? invoiceSummary,
  }) {
    return AppDialog.show<void>(
      context,
      title: confirmation.kind.title,
      showHeader: false,
      maxWidth: 560,
      size: AppDialogSize.lg,
      barrierDismissible: true,
      footer: _VisitSubmittedDialogFooter(appointmentId: confirmation.appointmentId),
      child: VisitSubmittedCombinedConfirmation(
        confirmation: confirmation,
        invoiceSummary: invoiceSummary,
      ),
    );
  }

  /// Resolves patient, branch, and appointment context via feature facades.
  static Future<void> showForVisit(
    BuildContext context,
    WidgetRef ref, {
    required VisitDetail visit,
    VisitConfirmationKind kind = VisitConfirmationKind.completed,
    DateTime? actionAt,
    required VisitBillingInvoicePreview? invoicePreview,
    required InvoiceDetail? persistedInvoice,
  }) {
    return AppDialog.show<void>(
      context,
      title: kind.title,
      showHeader: false,
      maxWidth: 560,
      size: AppDialogSize.lg,
      barrierDismissible: true,
      footer: _VisitSubmittedDialogFooter(appointmentId: visit.appointmentId),
      child: _VisitSubmittedDialogBody(
        visit: visit,
        kind: kind,
        actionAt: actionAt,
        invoicePreview: invoicePreview,
        persistedInvoice: persistedInvoice,
      ),
    );
  }
}

class _VisitSubmittedDialogBody extends ConsumerWidget {
  const _VisitSubmittedDialogBody({
    required this.visit,
    required this.kind,
    required this.actionAt,
    required this.invoicePreview,
    required this.persistedInvoice,
  });

  final VisitDetail visit;
  final VisitConfirmationKind kind;
  final DateTime? actionAt;
  final VisitBillingInvoicePreview? invoicePreview;
  final InvoiceDetail? persistedInvoice;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final patientAsync = ref.watch(patientSummaryForVisitProvider(visit.patientId));
    final appointmentAsync = ref.watch(appointmentWindowProvider(visit.appointmentId));
    final branchAsync = ref.watch(branchNameProvider(visit.branchId));

    if (patientAsync.isLoading || appointmentAsync.isLoading || branchAsync.isLoading) {
      return const AppSkeleton(variant: SkeletonVariant.rectangular, height: 340);
    }

    final patientName = patientAsync.requireValue.fullName;
    final branchName = branchAsync.requireValue;
    final appointmentWindow = appointmentAsync.asData?.value;
    final start = appointmentWindow?.startTime ?? visit.visitDate;
    final end = appointmentWindow?.endTime ?? visit.visitDate.add(const Duration(minutes: 30));

    final data = VisitSubmittedConfirmationData.fromVisit(
      visit: visit,
      patientName: patientName,
      branchName: branchName,
      appointmentStart: start,
      appointmentEnd: end,
      kind: kind,
      actionAt: actionAt,
      invoicePreview: invoicePreview,
      persistedInvoice: persistedInvoice,
    );

    return VisitSubmittedCombinedConfirmation(
      confirmation: data.confirmation,
      invoiceSummary: _invoiceSummaryFromData(data),
    );
  }

  static Widget? _invoiceSummaryFromData(VisitSubmittedConfirmationData data) {
    if (data.persistedInvoice != null) {
      return VisitInvoiceSummaryPanel(invoice: data.persistedInvoice, expanded: true);
    }
    if (data.invoicePreview != null) {
      return VisitInvoiceSummaryPanel(preview: data.invoicePreview, expanded: true);
    }
    return null;
  }
}

class _VisitSubmittedDialogFooter extends StatelessWidget {
  const _VisitSubmittedDialogFooter({required this.appointmentId});

  final String appointmentId;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 420;
        final viewAppointment = AppButton(
          variant: AppButtonVariant.secondary,
          leadingIcon: const Icon(Icons.event_note_outlined, size: 16),
          onPressed: () {
            Navigator.of(context).pop();
            context.nav.pushAppointmentDetail(appointmentId);
          },
          child: const Text('View appointment'),
        );
        final backToCalendar = AppButton(
          trailingIcon: const Icon(Icons.calendar_month_outlined, size: 16),
          onPressed: () {
            Navigator.of(context).pop();
            context.nav.goAppointmentsCalendar();
          },
          child: const Text('Back to calendar'),
        );

        if (isWide) {
          return Row(children: [viewAppointment, const Spacer(), backToCalendar]);
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            backToCalendar,
            const SizedBox(height: AppSpacing.space3),
            viewAppointment,
          ],
        );
      },
    );
  }
}
