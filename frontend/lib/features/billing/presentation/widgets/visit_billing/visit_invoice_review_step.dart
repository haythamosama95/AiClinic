import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/money/organization_currency_provider.dart';
import 'package:ai_clinic/core/ui/motion/app_motion.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/features/billing/presentation/providers/visit_billing_flow_notifier.dart';
import 'package:ai_clinic/features/billing/presentation/widgets/visit_billing/visit_invoice_discount_sidebar.dart';
import 'package:ai_clinic/features/billing/presentation/widgets/visit_billing/visit_invoice_document_card.dart';
import 'package:ai_clinic/features/billing/presentation/widgets/visit_billing/visit_invoice_review_footer.dart';

/// Step 2 — invoice review with optional discount (web `InvoiceReviewStep`).
class VisitInvoiceReviewStep extends ConsumerStatefulWidget {
  const VisitInvoiceReviewStep({
    required this.visitId,
    required this.patientName,
    required this.onBack,
    required this.onFinalize,
    this.patientPhone,
    this.isSubmitting = false,
    super.key,
  });

  final String visitId;
  final String patientName;
  final String? patientPhone;
  final VoidCallback onBack;
  final VoidCallback? onFinalize;
  final bool isSubmitting;

  @override
  ConsumerState<VisitInvoiceReviewStep> createState() =>
      _VisitInvoiceReviewStepState();
}

class _VisitInvoiceReviewStepState extends ConsumerState<VisitInvoiceReviewStep>
    with TickerProviderStateMixin {
  late final AnimationController _mainController;
  late final AnimationController _sidebarController;
  late final Animation<double> _mainAnimation;
  late final Animation<double> _sidebarAnimation;

  @override
  void initState() {
    super.initState();
    final reducedMotion = WidgetsBinding
        .instance
        .platformDispatcher
        .accessibilityFeatures
        .disableAnimations;
    _mainController = AnimationController(
      vsync: this,
      duration: reducedMotion ? Duration.zero : AppMotionDuration.base,
    );
    _sidebarController = AnimationController(
      vsync: this,
      duration: reducedMotion ? Duration.zero : AppMotionDuration.base,
    );
    _mainAnimation = CurvedAnimation(
      parent: _mainController,
      curve: AppMotion.outCurve,
    );
    _sidebarAnimation = CurvedAnimation(
      parent: _sidebarController,
      curve: AppMotion.outCurve,
    );

    _mainController.forward();
    if (reducedMotion) {
      _sidebarController.forward();
    } else {
      Future<void>.delayed(const Duration(milliseconds: 50), () {
        if (mounted) {
          _sidebarController.forward();
        }
      });
    }
  }

  @override
  void dispose() {
    _mainController.dispose();
    _sidebarController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final billing = ref.watch(visitBillingFlowProvider(widget.visitId));
    final billingNotifier = ref.read(
      visitBillingFlowProvider(widget.visitId).notifier,
    );
    final permissions = ref.watch(permissionServiceProvider);
    final canApplyDiscount = permissions.canApplyDiscount();
    final totals = billing.totals;
    final previewNumber = billing.invoicePreviewNumber ?? '—';
    final reducedMotion = AppMotion.prefersReducedMotion(context);
    final discountValue = billing.discountValue;

    final currency = ref.watch(organizationCurrencyProvider);

    final invoiceCard = VisitInvoiceDocumentCard(
      previewNumber: previewNumber,
      lines: billing.selectedLines,
      totals: VisitInvoiceDocumentTotals.fromPreview(totals),
      discountType: billing.discountType,
      discountValue: discountValue,
      currency: currency,
      patientName: widget.patientName,
      patientPhone: widget.patientPhone,
    );

    final discountSidebar = canApplyDiscount
        ? VisitInvoiceDiscountSidebar(
            discountType: billing.discountType,
            discountValue: discountValue,
            subtotal: totals.subtotal,
            currency: currency,
            onDiscountTypeChanged: billingNotifier.setDiscountType,
            onDiscountValueChanged: billingNotifier.setDiscountValue,
          )
        : const VisitInvoiceDiscountInfoCard();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 1024;

            if (isWide) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _wrapMotion(
                      invoiceCard,
                      _mainAnimation,
                      reducedMotion,
                      AppMotionPreset.slideUp,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.space6),
                  SizedBox(
                    width: 320,
                    child: _wrapMotion(
                      discountSidebar,
                      _sidebarAnimation,
                      reducedMotion,
                      AppMotionPreset.slideInline,
                    ),
                  ),
                ],
              );
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _wrapMotion(
                  invoiceCard,
                  _mainAnimation,
                  reducedMotion,
                  AppMotionPreset.slideUp,
                ),
                const SizedBox(height: AppSpacing.space6),
                _wrapMotion(
                  discountSidebar,
                  _sidebarAnimation,
                  reducedMotion,
                  AppMotionPreset.slideInline,
                ),
              ],
            );
          },
        ),
        const SizedBox(height: AppSpacing.space6),
        VisitInvoiceReviewFooter(
          onBack: widget.onBack,
          onFinalize: widget.onFinalize,
          isSubmitting: widget.isSubmitting,
        ),
      ],
    );
  }

  Widget _wrapMotion(
    Widget child,
    Animation<double> animation,
    bool reducedMotion,
    AppMotionPreset preset,
  ) {
    if (reducedMotion) {
      return child;
    }
    return AppMotion.animatedPreset(
      context: context,
      preset: preset,
      animation: animation,
      child: child,
    );
  }
}
