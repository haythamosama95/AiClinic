import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/motion/app_motion.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/billing/domain/invoice_detail.dart';
import 'package:ai_clinic/features/billing/domain/visit_billing_mapping.dart';
import 'package:ai_clinic/features/billing/presentation/utils/billing_formatting.dart';
import 'package:ai_clinic/features/billing/presentation/widgets/visit_billing/visit_invoice_discount_sidebar.dart';
import 'package:ai_clinic/features/billing/presentation/widgets/visit_billing/visit_invoice_document_card.dart';

/// Read-only invoice document view matching step 2/2 layout (issued invoices).
class VisitInvoiceReadOnlyReview extends ConsumerStatefulWidget {
  const VisitInvoiceReadOnlyReview({
    required this.invoice,
    required this.onBack,
    super.key,
  });

  final InvoiceDetail invoice;
  final VoidCallback onBack;

  @override
  ConsumerState<VisitInvoiceReadOnlyReview> createState() =>
      _VisitInvoiceReadOnlyReviewState();
}

class _VisitInvoiceReadOnlyReviewState
    extends ConsumerState<VisitInvoiceReadOnlyReview>
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
    final invoice = widget.invoice;
    final currency = invoice.currency;
    final lines = VisitBillingMapping.linesFromInvoice(invoice.items);
    final discount = VisitBillingMapping.discountFromInvoice(invoice);
    final totals = VisitInvoiceDocumentTotals(
      subtotal: invoice.subtotal,
      discountAmount: invoice.discountAmount,
      insuranceCoveredAmount: invoice.insuranceCoveredAmount,
      amountDue: invoice.originalDue,
      balance: invoice.balance,
    );
    final reducedMotion = AppMotion.prefersReducedMotion(context);
    final displayNumber = BillingFormatting.invoiceDisplayNumber(
      invoice.invoiceNumber,
      invoice.id,
    );

    final badgeStyle = statusBadgeStyle(invoice.status);

    final invoiceCard = VisitInvoiceDocumentCard(
      previewNumber: displayNumber,
      lines: lines,
      totals: totals,
      discountType: discount.type,
      discountValue: discount.value,
      currency: currency,
      patientName: invoice.patientDisplayName?.trim().isNotEmpty == true
          ? invoice.patientDisplayName!.trim()
          : 'Patient',
      issuedAt: invoice.issuedAt ?? invoice.updatedAt,
      headerTitle: 'Invoice',
      showStepLabel: false,
      statusBadge: AppBadge(
        size: BadgeSize.md,
        variant: BadgeVariant.soft,
        color: _badgeColor(badgeStyle.variant),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(badgeStyle.icon, size: 14),
            const SizedBox(width: AppSpacing.space1),
            Text(invoice.status.label),
          ],
        ),
      ),
    );

    final discountSidebar = VisitInvoiceReadOnlyDiscountSidebar(
      discountType: discount.type,
      discountValue: discount.value,
      discountAmount: invoice.discountAmount,
      currency: currency,
    );

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
        Align(
          alignment: Alignment.centerLeft,
          child: AppButton(
            variant: AppButtonVariant.secondary,
            leadingIcon: const Icon(Icons.arrow_back_rounded, size: 16),
            onPressed: widget.onBack,
            child: const Text('Back'),
          ),
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

BadgeColor _badgeColor(InvoiceStatusBadgeVariant variant) {
  return switch (variant) {
    InvoiceStatusBadgeVariant.muted => BadgeColor.neutral,
    InvoiceStatusBadgeVariant.primary => BadgeColor.teal,
    InvoiceStatusBadgeVariant.accent => BadgeColor.warning,
    InvoiceStatusBadgeVariant.success => BadgeColor.success,
    InvoiceStatusBadgeVariant.destructive => BadgeColor.danger,
  };
}
