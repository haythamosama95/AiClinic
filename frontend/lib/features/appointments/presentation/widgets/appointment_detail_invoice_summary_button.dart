import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/auth/auth_route_guard.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_detail.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';
import 'package:ai_clinic/features/billing/application/billing_rpc_messages.dart';
import 'package:ai_clinic/features/billing/data/invoice_repository.dart';
import 'package:ai_clinic/features/visits/data/visit_repository.dart';
import 'package:ai_clinic/features/billing/presentation/widgets/visit_billing/visit_invoice_summary_dialog.dart';

/// Header action that opens the visit invoice summary for completed appointments.
class AppointmentDetailInvoiceSummaryButton extends ConsumerStatefulWidget {
  const AppointmentDetailInvoiceSummaryButton({
    required this.detail,
    super.key,
  });

  final AppointmentDetail detail;

  @override
  ConsumerState<AppointmentDetailInvoiceSummaryButton> createState() =>
      _AppointmentDetailInvoiceSummaryButtonState();
}

class _AppointmentDetailInvoiceSummaryButtonState
    extends ConsumerState<AppointmentDetailInvoiceSummaryButton> {
  var _isLoading = false;

  AppointmentDetail get detail => widget.detail;

  bool get _canViewInvoices => ref.watch(
    authSessionProvider.select(AuthRouteGuard.canAccessInvoiceList),
  );

  bool get _isCompleted => detail.status == AppointmentStatus.completed;

  Future<void> _handleOpenInvoiceSummary() async {
    if (_isLoading) {
      return;
    }

    setState(() => _isLoading = true);
    try {
      final visitRepo = ref.read(visitRepositoryProvider);
      final invoiceRepo = ref.read(invoiceRepositoryProvider);

      final link = await visitRepo.getVisitByAppointment(
        appointmentId: detail.id,
      );
      final visitId = link.visitId?.trim();
      if (visitId == null || visitId.isEmpty) {
        if (mounted) {
          appToast(
            context,
            const AppToastInput(
              message: 'No visit found for this appointment.',
              variant: AppToastVariant.info,
            ),
          );
        }
        return;
      }

      final listItem = await invoiceRepo.findForVisit(visitId: visitId);
      if (listItem == null) {
        if (mounted) {
          appToast(
            context,
            const AppToastInput(
              message: 'No invoice linked to this visit.',
              variant: AppToastVariant.info,
            ),
          );
        }
        return;
      }

      final invoice = await invoiceRepo.getDetail(invoiceId: listItem.id);
      if (!mounted) {
        return;
      }

      await VisitInvoiceSummaryDialog.show(context, invoice: invoice);
    } on RpcFailure catch (error) {
      if (mounted) {
        appToast(
          context,
          AppToastInput(
            message: billingMessageForRpc(error),
            variant: AppToastVariant.danger,
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        appToast(
          context,
          const AppToastInput(
            message: 'Could not load the invoice summary. Please try again.',
            variant: AppToastVariant.danger,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_canViewInvoices || !_isCompleted) {
      return const SizedBox.shrink();
    }

    return AppButton(
      key: const Key('appointment_detail_invoice_summary'),
      variant: AppButtonVariant.secondary,
      size: AppButtonSize.md,
      loading: _isLoading,
      leadingIcon: const Icon(Icons.receipt_long_outlined),
      onPressed: _handleOpenInvoiceSummary,
      child: const Text('Invoice summary'),
    );
  }
}
