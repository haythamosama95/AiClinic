import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/navigation/app_navigator.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/core/ui/components/app_badge.dart';
import 'package:ai_clinic/core/ui/components/app_breadcrumb.dart';
import 'package:ai_clinic/core/ui/components/app_card.dart';
import 'package:ai_clinic/core/ui/components/app_dialog.dart';
import 'package:ai_clinic/core/ui/components/app_empty_state.dart';
import 'package:ai_clinic/core/ui/components/app_icon_button.dart';
import 'package:ai_clinic/core/ui/components/app_page_header.dart';
import 'package:ai_clinic/core/ui/motion/app_motion.dart';
import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/billing/domain/invoice_detail.dart';
import 'package:ai_clinic/core/money/money.dart';
import 'package:ai_clinic/features/billing/application/billing_rpc_messages.dart';
import 'package:ai_clinic/features/billing/domain/invoice_stale_exception.dart';
import 'package:ai_clinic/features/billing/presentation/providers/invoice_ledger_notifier.dart';
import 'package:ai_clinic/features/billing/presentation/providers/invoice_detail_provider.dart';
import 'package:ai_clinic/features/billing/presentation/utils/billing_formatting.dart';
import 'package:ai_clinic/features/billing/presentation/widgets/invoice_detail/invoice_detail_tooltip.dart';
import 'package:ai_clinic/features/billing/presentation/widgets/invoice_detail/invoice_hero_card.dart';
import 'package:ai_clinic/features/billing/presentation/widgets/invoice_detail/invoice_line_items_card.dart';
import 'package:ai_clinic/features/billing/presentation/widgets/invoice_detail/invoice_link_card.dart';
import 'package:ai_clinic/features/billing/presentation/widgets/invoice_detail/invoice_payments_card.dart';
import 'package:ai_clinic/features/billing/presentation/widgets/invoice_detail/invoice_totals_panel.dart';
import 'package:ai_clinic/features/billing/presentation/widgets/invoice_detail/invoice_voided_notice.dart';
import 'package:ai_clinic/features/billing/presentation/widgets/payment_form.dart';
import 'package:ai_clinic/features/billing/presentation/widgets/refund_form.dart';
import 'package:ai_clinic/features/billing/presentation/widgets/receipt/receipt_print_preview.dart';
import 'package:ai_clinic/features/billing/presentation/widgets/void_invoice_dialog.dart';
import 'package:ai_clinic/features/patients/domain/patient_detail.dart';
import 'package:ai_clinic/features/patients/presentation/providers/patient_detail_provider.dart';

/// Invoice detail surface (`/billing/invoices/:id`).
class InvoiceDetailPage extends ConsumerStatefulWidget {
  const InvoiceDetailPage({required this.invoiceId, super.key});

  final String invoiceId;

  @override
  ConsumerState<InvoiceDetailPage> createState() => _InvoiceDetailPageState();
}

class _InvoiceDetailPageState extends ConsumerState<InvoiceDetailPage> with SingleTickerProviderStateMixin {
  late final AnimationController _enterController;
  CurvedAnimation? _enterAnimation;
  var _enterStarted = false;

  @override
  void initState() {
    super.initState();
    _enterController = AnimationController(vsync: this, duration: const Duration(milliseconds: 220));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_enterStarted) {
      _enterStarted = true;
      final reducedMotion = AppMotion.prefersReducedMotion(context);
      _enterController.duration = reducedMotion ? Duration.zero : const Duration(milliseconds: 220);
      _enterAnimation = CurvedAnimation(
        parent: _enterController,
        curve: AppMotion.resolveCurve(AppMotionPreset.slideUp, reducedMotion: reducedMotion),
      );
      if (reducedMotion) {
        _enterController.value = 1;
      } else {
        _enterController.forward();
      }
    }
  }

  @override
  void dispose() {
    _enterAnimation?.dispose();
    _enterController.dispose();
    super.dispose();
  }

  bool _isInvoiceNotFound(Object error) {
    return error is RpcFailure && error.code == 'NOT_FOUND';
  }

  void _popToInvoicesList() {
    if (context.nav.canPop()) {
      context.nav.pop();
    } else {
      context.nav.goBillingInvoices();
    }
  }

  @override
  Widget build(BuildContext context) {
    final detailAsync = ref.watch(invoiceDetailViewProvider(widget.invoiceId));

    final content = detailAsync.when(
      loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      error: (error, _) {
        if (_isInvoiceNotFound(error)) {
          return _InvoiceNotFoundView(onBack: _popToInvoicesList);
        }

        return Center(
          child: AppEmptyState(
            variant: AppEmptyStateVariant.error,
            title: 'Could not load invoice',
            description: error.toString(),
            action: EmptyStateAction(
              label: 'Retry',
              onPressed: () => ref.invalidate(invoiceDetailViewProvider(widget.invoiceId)),
            ),
          ),
        );
      },
      data: (view) => _InvoiceDetailBody(view: view, onPopToInvoicesList: _popToInvoicesList),
    );

    return FadeTransition(
      opacity: _enterAnimation ?? _enterController,
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: AppSpacing.space8),
        child: content,
      ),
    );
  }
}

class _InvoiceNotFoundView extends StatelessWidget {
  const _InvoiceNotFoundView({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      spacing: AppSpacing.space6,
      children: [
        AppPageHeader(
          title: 'Invoice not found',
          breadcrumb: AppBreadcrumb(
            items: [
              AppBreadcrumbItem(label: 'Invoices', onTap: onBack),
              const AppBreadcrumbItem(label: 'Not found'),
            ],
          ),
        ),
        AppEmptyState(
          variant: AppEmptyStateVariant.error,
          title: 'Invoice not found',
          description: 'The invoice you requested does not exist or has been removed.',
          action: EmptyStateAction(label: 'Back to invoices', onPressed: onBack),
        ),
      ],
    );
  }
}

class _InvoiceDetailBody extends ConsumerStatefulWidget {
  const _InvoiceDetailBody({required this.view, required this.onPopToInvoicesList});

  final InvoiceDetailViewState view;
  final VoidCallback onPopToInvoicesList;

  @override
  ConsumerState<_InvoiceDetailBody> createState() => _InvoiceDetailBodyState();
}

class _InvoiceDetailBodyState extends ConsumerState<_InvoiceDetailBody> {
  InvoiceDetail get invoice => widget.view.invoice;

  String _displayOrDash(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? '—' : trimmed;
  }

  VisitSummary? get _visitSummary => invoice.visitSummary;

  bool get _hasResolvableVisit => _visitSummary != null;

  Future<void> _voidInvoice() async {
    final reason = await VoidInvoiceDialog.show(context, invoice: invoice);
    if (reason == null || !mounted) {
      return;
    }

    try {
      await ref.read(invoiceLedgerProvider(invoice.id)).voidInvoice(reason: reason);
    } on InvoiceStaleException {
      if (!mounted) {
        return;
      }
      appToast(
        context,
        const AppToastInput(
          message: 'This invoice was updated elsewhere. Reloading…',
          variant: AppToastVariant.info,
        ),
      );
      ref.invalidate(invoiceDetailViewProvider(invoice.id));
    } on RpcFailure catch (error) {
      if (!mounted) {
        return;
      }
      appToast(
        context,
        AppToastInput(message: billingMessageForRpc(error), variant: AppToastVariant.danger),
      );
    }
  }

  Future<void> _refreshLedgerSurfaces() {
    return ref.read(invoiceLedgerProvider(invoice.id)).refreshSurfaces();
  }

  Future<void> _showRecordPaymentDialog() async {
    await AppDialog.show<void>(
      context,
      title: 'Record payment',
      size: AppDialogSize.lg,
      child: Builder(
        builder: (dialogContext) => PaymentForm(
          invoice: invoice,
          onRecorded: () async {
            Navigator.of(dialogContext).pop();
            await _refreshLedgerSurfaces();
          },
        ),
      ),
    );
  }

  Future<void> _showRefundDialog() async {
    await AppDialog.show<void>(
      context,
      title: 'Record refund',
      size: AppDialogSize.lg,
      child: Builder(
        builder: (dialogContext) => RefundForm(
          invoice: invoice,
          onRecorded: () async {
            Navigator.of(dialogContext).pop();
            await _refreshLedgerSurfaces();
          },
        ),
      ),
    );
  }

  Widget _buildVisitLinkCard(AppSemanticColors colors) {
    final summary = _visitSummary;
    if (!_hasResolvableVisit || summary == null) {
      return _VisitUnavailableCard(colors: colors);
    }

    return InvoiceLinkCard(
      eyebrow: 'Visit',
      icon: Icons.medical_services_outlined,
      title: BillingFormatting.formatDate(summary.date),
      subtitle: '${summary.doctor} · ${summary.branch}',
      badge: const AppBadge(
        variant: BadgeVariant.soft,
        color: BadgeColor.success,
        size: BadgeSize.sm,
        label: 'Completed',
      ),
      actionLabel: 'View visit in patient record',
      tooltip: 'Open the completed visit linked to this invoice',
      onAction: () => context.nav.pushVisitDocument(invoice.visitId),
    );
  }

  String? _resolvePatientPhone(AsyncValue<PatientDetail> patientAsync) {
    final invoicePhone = invoice.patientPhone?.trim();
    if (invoicePhone != null && invoicePhone.isNotEmpty) {
      return invoicePhone;
    }

    return patientAsync.maybeWhen(
      data: (patient) {
        final phone = patient.phone?.trim();
        return phone == null || phone.isEmpty ? null : phone;
      },
      orElse: () => null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final patientAsync = ref.watch(patientDetailProvider(invoice.patientId));
    final displayNumber = BillingFormatting.invoiceDisplayNumber(invoice.invoiceNumber, invoice.id);
    final patientName = invoice.patientDisplayName?.trim().isNotEmpty == true
        ? invoice.patientDisplayName!.trim()
        : 'Unknown patient';
    final patientMrn = _displayOrDash(invoice.patientMrn);
    final patientPhone = _displayOrDash(_resolvePatientPhone(patientAsync));
    final actions = widget.view.actions;
    final amountDue = invoice.originalDue;
    final netPaid = invoice.netPaid;
    final canEdit = actions.canEdit;
    final canAddPayment = actions.canRecordPayment;
    final canVoid = actions.canVoid;
    final canRefund = actions.canRefund && invoice.payments.isNotEmpty;
    final editDisabledReason = InvoiceDetailActionTooltips.editDisabledReason(
      canCreate: widget.view.canCreate,
      status: invoice.status,
    );
    final addPaymentDisabledReason = InvoiceDetailActionTooltips.addPaymentDisabledReason(
      canRecordPayment: widget.view.canRecordPayment,
      status: invoice.status,
    );
    final voidDisabledReason = InvoiceDetailActionTooltips.voidDisabledReason(
      canVoid: widget.view.canVoid,
      status: invoice.status,
    );
    final refundDisabledReason = InvoiceDetailActionTooltips.refundDisabledReason(
      canRefund: widget.view.canRefund,
      status: invoice.status,
      hasPayments: invoice.payments.isNotEmpty,
    );

    final linkCards = [
      InvoiceLinkCard(
        eyebrow: 'Patient',
        icon: Icons.person_outline,
        title: patientName,
        subtitle: '$patientMrn · $patientPhone',
        actionLabel: 'View patient profile',
        tooltip: 'Open the patient profile for $patientName',
        onAction: () => context.nav.pushPatientDetail(invoice.patientId),
      ),
      _buildVisitLinkCard(colors),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      spacing: AppSpacing.space6,
      children: [
        AppBreadcrumb(
          items: [
            AppBreadcrumbItem(label: 'Invoices', onTap: widget.onPopToInvoicesList),
            AppBreadcrumbItem(label: displayNumber),
          ],
        ),
        InvoiceHeroCard(
          invoice: invoice,
          patientName: patientName,
          mrn: patientMrn,
          branchName: invoice.branchName,
          balance: invoice.balance,
          onPatientTap: () => context.nav.pushPatientDetail(invoice.patientId),
          canVoid: canVoid,
          voidTooltip: InvoiceDetailActionTooltips.voidMessage(disabledReason: voidDisabledReason),
          onVoid: _voidInvoice,
          onPrint: () => ReceiptPrintPreview.show(context, invoice),
        ),
        if (invoice.status.isVoided) InvoiceVoidedNotice(invoice: invoice),
        LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth >= 600) {
              return IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var index = 0; index < linkCards.length; index++) ...[
                      if (index > 0) const SizedBox(width: AppSpacing.space4),
                      Expanded(
                        child: _StaggeredLinkCard(index: index, child: linkCards[index]),
                      ),
                    ],
                  ],
                ),
              );
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var index = 0; index < linkCards.length; index++) ...[
                  if (index > 0) const SizedBox(height: AppSpacing.space4),
                  _StaggeredLinkCard(index: index, child: linkCards[index]),
                ],
              ],
            );
          },
        ),
        InvoiceLineItemsCard(
          items: invoice.items,
          currency: invoice.currency,
          canEdit: canEdit,
          editTooltip: InvoiceDetailActionTooltips.editMessage(disabledReason: editDisabledReason),
          onEdit: () => context.nav.pushBillingInvoiceEdit(invoice.id),
          totals: InvoiceTotalsModel.lineItems(
            subtotal: invoice.subtotal,
            discountAmount: invoice.discountAmount,
            discountKind: invoice.discountKind,
            discountValue: invoice.discountValue,
            insuranceCoveredAmount: invoice.insuranceCoveredAmount,
            insuranceProviderName: invoice.insuranceProviderName,
            amountDue: amountDue,
            currency: invoice.currency,
          ),
        ),
        InvoicePaymentsCard(
          payments: invoice.payments,
          currency: invoice.currency,
          status: invoice.status,
          canAddPayment: canAddPayment,
          addPaymentTooltip: InvoiceDetailActionTooltips.addPaymentMessage(disabledReason: addPaymentDisabledReason),
          onAddPayment: _showRecordPaymentDialog,
          canRefund: canRefund,
          refundTooltip: InvoiceDetailActionTooltips.refundMessage(disabledReason: refundDisabledReason),
          onRefund: _showRefundDialog,
          totals: InvoiceTotalsModel.payments(
            amountDue: amountDue,
            netPaid: netPaid,
            balance: invoice.balance,
            currency: invoice.currency,
            isVoided: invoice.status.isVoided,
            hasPayments: invoice.payments.isNotEmpty,
          ),
        ),
      ],
    );
  }
}

class _StaggeredLinkCard extends StatefulWidget {
  const _StaggeredLinkCard({required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  State<_StaggeredLinkCard> createState() => _StaggeredLinkCardState();
}

class _StaggeredLinkCardState extends State<_StaggeredLinkCard> with SingleTickerProviderStateMixin {
  static const _staggerStepMs = 60;

  late final AnimationController _controller;
  CurvedAnimation? _animation;
  var _configured = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_configured) {
      return;
    }
    _configured = true;

    final reducedMotion = AppMotion.prefersReducedMotion(context);
    _controller.duration = AppMotion.resolveDuration(AppMotionPreset.rowEnter, reducedMotion: reducedMotion);
    _animation = CurvedAnimation(
      parent: _controller,
      curve: AppMotion.resolveCurve(AppMotionPreset.rowEnter, reducedMotion: reducedMotion),
    );

    final delay = reducedMotion ? Duration.zero : Duration(milliseconds: widget.index * _staggerStepMs);

    if (delay == Duration.zero) {
      _controller.forward();
    } else {
      Future<void>.delayed(delay, () {
        if (mounted) {
          _controller.forward();
        }
      });
    }
  }

  @override
  void dispose() {
    _animation?.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppMotion.animatedPreset(
      context: context,
      preset: AppMotionPreset.rowEnter,
      animation: _animation ?? _controller,
      child: widget.child,
    );
  }
}

class _VisitUnavailableCard extends StatelessWidget {
  const _VisitUnavailableCard({required this.colors});

  final AppSemanticColors colors;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      variant: CardVariant.flat,
      padding: CardPadding.lg,
      child: SizedBox(
        width: double.infinity,
        height: double.infinity,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(color: colors.surfaceMuted, borderRadius: BorderRadius.circular(AppRadius.xl)),
              child: SizedBox(
                width: 40,
                height: 40,
                child: Icon(Icons.event_busy_outlined, size: 18, color: colors.iconMuted),
              ),
            ),
            const SizedBox(width: AppSpacing.space3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Visit', style: AppTypography.overline(context).copyWith(color: colors.textTertiary)),
                  const SizedBox(height: AppSpacing.space1),
                  Text(
                    'Visit unavailable',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.bodyStrong(context).copyWith(color: colors.textPrimary),
                  ),
                  Text(
                    'The source visit for this invoice is no longer available.',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.bodySm(context).copyWith(color: colors.textSecondary),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.space3),
            InvoiceDetailTooltip(
              message: 'The source visit for this invoice is no longer available.',
              child: Opacity(
                opacity: 0.4,
                child: AppIconButton(
                  variant: AppIconButtonVariant.secondary,
                  size: AppIconButtonSize.lg,
                  label: 'Visit unavailable',
                  tooltipDisabled: true,
                  onPressed: null,
                  icon: const Icon(Icons.arrow_forward, size: 18),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
