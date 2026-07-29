import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/patients/presentation/providers/patient_detail_provider.dart';
import 'package:ai_clinic/features/billing/domain/discount_kind.dart';
import 'package:ai_clinic/features/billing/domain/invoice_detail.dart';
import 'package:ai_clinic/features/billing/domain/invoice_item.dart';
import 'package:ai_clinic/features/billing/domain/visit_billing_models.dart';
import 'package:ai_clinic/features/billing/presentation/providers/organization_currency_provider.dart';
import 'package:ai_clinic/features/billing/presentation/providers/visit_billing_flow_notifier.dart';
import 'package:ai_clinic/features/billing/presentation/utils/billing_formatting.dart';
import 'package:ai_clinic/features/billing/presentation/widgets/invoice_status_badge.dart';
import 'package:ai_clinic/features/visits/presentation/providers/visit_documentation_notifier.dart';

/// Step 2 — invoice review with optional discount (web `InvoiceReviewStep`).
class VisitInvoiceReviewStep extends ConsumerStatefulWidget {
  const VisitInvoiceReviewStep({
    required this.visitId,
    required this.onBack,
    required this.onFinalize,
    this.isSubmitting = false,
    super.key,
  });

  final String visitId;
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

    final currency = ref.watch(organizationCurrencyProvider);
    final docState = ref
        .watch(visitDocumentationProvider(widget.visitId))
        .value;
    final patientAsync = docState == null
        ? null
        : ref.watch(patientDetailProvider(docState.visit.patientId));

    final invoiceCard = _InvoiceDocumentCard(
      previewNumber: previewNumber,
      lines: billing.selectedLines,
      totals: totals,
      discountType: billing.discountType,
      discountValue: billing.discountValue,
      currency: currency,
      patientName:
          patientAsync?.maybeWhen(
            data: (patient) => patient.fullName,
            orElse: () => 'Patient',
          ) ??
          'Patient',
      patientPhone: patientAsync?.maybeWhen(
        data: (patient) => patient.phone,
        orElse: () => null,
      ),
    );

    final discountSidebar = canApplyDiscount
        ? _DiscountSidebar(
            discountType: billing.discountType,
            discountValue: billing.discountValue,
            subtotal: totals.subtotal,
            currency: currency,
            onDiscountTypeChanged: billingNotifier.setDiscountType,
            onDiscountValueChanged: billingNotifier.setDiscountValue,
          )
        : const _DiscountInfoCard();

    Widget content = Column(
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
        _InvoiceReviewFooter(
          onBack: widget.onBack,
          onFinalize: widget.onFinalize,
          isSubmitting: widget.isSubmitting,
        ),
      ],
    );

    return content;
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
    final lines = _linesFromInvoiceItems(invoice.items);
    final discount = _discountFromInvoice(invoice);
    final totals = _totalsFromInvoice(invoice);
    final reducedMotion = AppMotion.prefersReducedMotion(context);
    final displayNumber = BillingFormatting.invoiceDisplayNumber(
      invoice.invoiceNumber,
      invoice.id,
    );

    final invoiceCard = _InvoiceDocumentCard(
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
      statusBadge: InvoiceStatusBadge(
        status: invoice.status,
        size: BadgeSize.md,
      ),
    );

    final discountSidebar = _ReadOnlyDiscountSidebar(
      discountType: discount.type,
      discountValue: discount.value,
      discountAmount: totals.discountAmount,
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

List<VisitSelectedServiceLine> _linesFromInvoiceItems(List<InvoiceItem> items) {
  return items
      .map(
        (item) => VisitSelectedServiceLine(
          id: item.id,
          serviceId: item.id,
          name: item.description,
          unitPrice: item.unitPrice.asDouble,
          quantity: int.tryParse(item.quantity) ?? 1,
        ),
      )
      .toList(growable: false);
}

({VisitBillingDiscountType type, double value}) _discountFromInvoice(
  InvoiceDetail invoice,
) {
  if (invoice.discountAmount.isZero) {
    return (type: VisitBillingDiscountType.none, value: 0);
  }

  final parsedValue = double.tryParse(invoice.discountValue ?? '') ?? 0;
  return switch (invoice.discountKind) {
    DiscountKind.percentage => (
      type: VisitBillingDiscountType.percentage,
      value: parsedValue,
    ),
    DiscountKind.fixed => (
      type: VisitBillingDiscountType.fixed,
      value: parsedValue,
    ),
    null => (
      type: VisitBillingDiscountType.fixed,
      value: invoice.discountAmount.asDouble,
    ),
  };
}

VisitBillingTotals _totalsFromInvoice(InvoiceDetail invoice) {
  final subtotal = invoice.subtotal.asDouble;
  final discountAmount = invoice.discountAmount.asDouble;
  return VisitBillingTotals(
    subtotal: subtotal,
    discountAmount: discountAmount,
    total: subtotal - discountAmount,
  );
}

class _InvoiceDocumentCard extends StatelessWidget {
  const _InvoiceDocumentCard({
    required this.previewNumber,
    required this.lines,
    required this.totals,
    required this.discountType,
    required this.discountValue,
    required this.currency,
    required this.patientName,
    this.patientPhone,
    this.headerTitle = 'Review invoice',
    this.showStepLabel = true,
    this.statusBadge,
    this.issuedAt,
  });

  final String previewNumber;
  final List<VisitSelectedServiceLine> lines;
  final VisitBillingTotals totals;
  final VisitBillingDiscountType discountType;
  final double discountValue;
  final String currency;
  final String patientName;
  final String? patientPhone;
  final String headerTitle;
  final bool showStepLabel;
  final Widget? statusBadge;
  final DateTime? issuedAt;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final elevation = context.appElevation;
    final issuedDate = DateFormat(
      'd MMM yyyy',
    ).format((issuedAt ?? DateTime.now()).toLocal());

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceRaised,
        border: Border.all(color: colors.borderSubtle),
        borderRadius: BorderRadius.circular(AppRadius.x2l),
        boxShadow: elevation.shadows1,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.x2l),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _PerforatedEdge(colors: colors),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.space6,
                AppSpacing.space5,
                AppSpacing.space6,
                AppSpacing.space5,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: headerTitle,
                                style: AppTypography.bodySm(context).copyWith(
                                  color: colors.textPrimary,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              if (showStepLabel)
                                TextSpan(
                                  text: ' · Step 2 of 2',
                                  style: AppTypography.bodySm(
                                    context,
                                  ).copyWith(color: colors.textTertiary),
                                ),
                            ],
                          ),
                        ),
                      ),
                      statusBadge ??
                          const AppBadge(
                            label: 'Draft',
                            color: BadgeColor.warning,
                          ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.space5),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AppAvatar(name: patientName, size: AvatarSize.lg),
                      const SizedBox(width: AppSpacing.space4),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    patientName,
                                    style: AppTypography.h2(
                                      context,
                                    ).copyWith(color: colors.textPrimary),
                                  ),
                                ),
                                Text(
                                  previewNumber,
                                  style: AppTypography.bodySm(context).copyWith(
                                    color: colors.textPrimary,
                                    fontFamily: 'monospace',
                                    letterSpacing: 0.8,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: AppSpacing.space2),
                            Text.rich(
                              TextSpan(
                                children: [
                                  if (patientPhone != null &&
                                      patientPhone!.trim().isNotEmpty)
                                    TextSpan(
                                      text: patientPhone!.trim(),
                                      style: AppTypography.bodySm(
                                        context,
                                      ).copyWith(color: colors.textSecondary),
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(height: AppSpacing.space1),
                            Text(
                              issuedDate,
                              style: AppTypography.bodySm(context).copyWith(
                                color: colors.textSecondary,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.space6,
                0,
                AppSpacing.space6,
                AppSpacing.space5,
              ),
              child: _InvoiceLineTable(lines: lines, currency: currency),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                color: colors.surfaceSunken.withValues(alpha: 0.2),
                border: Border(
                  top: BorderSide(
                    color: colors.borderDefault,
                    style: BorderStyle.solid,
                  ),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.space6,
                  AppSpacing.space5,
                  AppSpacing.space6,
                  AppSpacing.space5,
                ),
                child: Column(
                  children: [
                    _TotalRow(
                      label: 'Subtotal',
                      child: AppMoneyDisplay(
                        amount: totals.subtotal,
                        currency: currency,
                      ),
                    ),
                    if (totals.discountAmount > 0) ...[
                      const SizedBox(height: AppSpacing.space2),
                      _TotalRow(
                        label:
                            discountType == VisitBillingDiscountType.percentage
                            ? 'Discount (${discountValue.round()}%)'
                            : 'Discount',
                        labelColor: colors.statusSuccessFg,
                        child: AppMoneyDisplay(
                          amount: totals.discountAmount,
                          currency: currency,
                          negative: true,
                        ),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.space3),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border(
                          top: BorderSide(color: colors.borderSubtle),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.only(top: AppSpacing.space3),
                        child: _TotalRow(
                          label: 'Total due',
                          labelStyle: AppTypography.bodyStrong(
                            context,
                          ).copyWith(color: colors.textPrimary),
                          child: DefaultTextStyle(
                            style: AppTypography.h2(
                              context,
                            ).copyWith(color: colors.textPrimary),
                            child: AppMoneyDisplay(
                              amount: totals.total,
                              currency: currency,
                              emphasis: true,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PerforatedEdge extends StatelessWidget {
  const _PerforatedEdge({required this.colors});

  final AppSemanticColors colors;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 6,
      child: CustomPaint(
        painter: _PerforatedEdgePainter(
          color: colors.borderDefault.withValues(alpha: 0.4),
        ),
      ),
    );
  }
}

class _PerforatedEdgePainter extends CustomPainter {
  const _PerforatedEdgePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    const dashWidth = 6.0;
    const gap = 6.0;
    var x = 0.0;
    while (x < size.width) {
      canvas.drawRect(Rect.fromLTWH(x, 0, dashWidth, size.height), paint);
      x += dashWidth + gap;
    }
  }

  @override
  bool shouldRepaint(covariant _PerforatedEdgePainter oldDelegate) =>
      oldDelegate.color != color;
}

class _InvoiceLineTable extends StatelessWidget {
  const _InvoiceLineTable({required this.lines, required this.currency});

  final List<VisitSelectedServiceLine> lines;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return LayoutBuilder(
      builder: (context, constraints) {
        final showUnit = constraints.maxWidth >= 640;

        return Table(
          columnWidths: const {
            0: FlexColumnWidth(2),
            1: FlexColumnWidth(1),
            2: FixedColumnWidth(48),
            3: FlexColumnWidth(1),
          },
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          children: [
            TableRow(
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: colors.borderSubtle)),
              ),
              children: [
                _TableHeaderCell('Service'),
                if (showUnit) _TableHeaderCell('Unit', align: TextAlign.end),
                _TableHeaderCell('Qty', align: TextAlign.center),
                _TableHeaderCell('Amount', align: TextAlign.end),
              ],
            ),
            for (final line in lines)
              TableRow(
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: colors.borderSubtle.withValues(alpha: 0.7),
                    ),
                  ),
                ),
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.space3 + 2,
                    ),
                    child: Text(
                      line.name,
                      style: AppTypography.bodySm(
                        context,
                      ).copyWith(color: colors.textPrimary),
                    ),
                  ),
                  if (showUnit)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: AppSpacing.space3 + 2,
                      ),
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: AppMoneyDisplay(
                          amount: line.unitPrice,
                          currency: currency,
                        ),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.space3 + 2,
                    ),
                    child: Text(
                      '${line.quantity}',
                      textAlign: TextAlign.center,
                      style: AppTypography.bodySm(context).copyWith(
                        color: colors.textSecondary,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.space3 + 2,
                    ),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: AppMoneyDisplay(
                        amount: line.lineTotal,
                        currency: currency,
                      ),
                    ),
                  ),
                ],
              ),
          ],
        );
      },
    );
  }
}

class _TableHeaderCell extends StatelessWidget {
  const _TableHeaderCell(this.label, {this.align = TextAlign.start});

  final String label;
  final TextAlign align;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.space2 + 2),
      child: Text(
        label.toUpperCase(),
        textAlign: align,
        style: AppTypography.overline(
          context,
        ).copyWith(color: context.appColors.textTertiary),
      ),
    );
  }
}

class _TotalRow extends StatelessWidget {
  const _TotalRow({
    required this.label,
    required this.child,
    this.labelStyle,
    this.labelColor,
  });

  final String label;
  final Widget child;
  final TextStyle? labelStyle;
  final Color? labelColor;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style:
                labelStyle ??
                AppTypography.bodySm(
                  context,
                ).copyWith(color: labelColor ?? colors.textSecondary),
          ),
        ),
        child,
      ],
    );
  }
}

class _DiscountSidebar extends StatelessWidget {
  const _DiscountSidebar({
    required this.discountType,
    required this.discountValue,
    required this.subtotal,
    required this.currency,
    required this.onDiscountTypeChanged,
    required this.onDiscountValueChanged,
  });

  final VisitBillingDiscountType discountType;
  final double discountValue;
  final double subtotal;
  final String currency;
  final ValueChanged<VisitBillingDiscountType> onDiscountTypeChanged;
  final ValueChanged<double> onDiscountValueChanged;

  bool get _fixedDiscountExceedsSubtotal =>
      discountType == VisitBillingDiscountType.fixed &&
      discountValue > 0 &&
      discountValue > subtotal;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppCard(
          variant: CardVariant.raised,
          padding: CardPadding.lg,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: AppColorPrimitives.amber50,
                      borderRadius: BorderRadius.circular(AppRadius.lg),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.space2 + 2),
                      child: Icon(
                        Icons.percent_rounded,
                        size: 18,
                        color: AppColorPrimitives.amber700,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.space3),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Discount',
                          style: AppTypography.overline(
                            context,
                          ).copyWith(color: colors.textTertiary),
                        ),
                        Text(
                          'Optional adjustment',
                          style: AppTypography.bodySm(
                            context,
                          ).copyWith(color: colors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.space5),
              DecoratedBox(
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: colors.borderSubtle)),
                ),
                child: Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.space5),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      AppFormField(
                        id: 'discount-type',
                        label: 'Discount type',
                        child: AppRadioGroup(
                          value: discountType.name,
                          onChanged: (value) => onDiscountTypeChanged(
                            VisitBillingDiscountType.values.byName(value),
                          ),
                          options: const [
                            AppRadioOption(value: 'none', label: 'No discount'),
                            AppRadioOption(
                              value: 'percentage',
                              label: 'Percentage off',
                            ),
                            AppRadioOption(
                              value: 'fixed',
                              label: 'Fixed amount off',
                            ),
                          ],
                        ),
                      ),
                      if (discountType ==
                          VisitBillingDiscountType.percentage) ...[
                        const SizedBox(height: AppSpacing.space4),
                        AppFormField(
                          id: 'discount-percent',
                          label: 'Percentage',
                          helperText: 'Applied to subtotal before tax',
                          child: AppNumberInput(
                            min: 0,
                            max: 100,
                            step: 1,
                            placeholder: '0',
                            initialValue: discountValue > 0
                                ? discountValue.round()
                                : null,
                            onValueChange: (value) =>
                                onDiscountValueChanged(value?.toDouble() ?? 0),
                          ),
                        ),
                      ],
                      if (discountType == VisitBillingDiscountType.fixed) ...[
                        const SizedBox(height: AppSpacing.space4),
                        AppFormField(
                          id: 'discount-fixed',
                          label: 'Amount off',
                          child: AppMoneyField(
                            currency: currency,
                            placeholder: '0.00',
                            invalid: _fixedDiscountExceedsSubtotal,
                            initialValue: discountValue > 0
                                ? discountValue
                                : null,
                            onValueChange: (value) =>
                                onDiscountValueChanged(value ?? 0),
                          ),
                        ),
                        if (_fixedDiscountExceedsSubtotal) ...[
                          const SizedBox(height: AppSpacing.space3),
                          const AppAlert(
                            variant: AppAlertVariant.warning,
                            title: 'Amount exceeds invoice subtotal',
                            child: Text(
                              'The discount will be capped at the subtotal.',
                            ),
                          ),
                        ],
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.space4),
        const _DiscountInfoCard(),
      ],
    );
  }
}

class _DiscountInfoCard extends StatelessWidget {
  const _DiscountInfoCard({this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return AppCard(
      variant: CardVariant.flat,
      padding: CardPadding.md,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.receipt_long_outlined, size: 16, color: colors.iconMuted),
          const SizedBox(width: AppSpacing.space3),
          Expanded(
            child: Text(
              message ??
                  'Finalizing issues the invoice linked to this visit. Payment can be recorded from the patient billing tab.',
              style: AppTypography.caption(
                context,
              ).copyWith(color: colors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReadOnlyDiscountSidebar extends StatelessWidget {
  const _ReadOnlyDiscountSidebar({
    required this.discountType,
    required this.discountValue,
    required this.discountAmount,
    required this.currency,
  });

  final VisitBillingDiscountType discountType;
  final double discountValue;
  final double discountAmount;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    if (discountAmount <= 0) {
      return const _DiscountInfoCard(
        message: 'No discount was applied to this invoice.',
      );
    }

    final discountLabel = switch (discountType) {
      VisitBillingDiscountType.percentage =>
        'Percentage off (${discountValue.round()}%)',
      VisitBillingDiscountType.fixed => 'Fixed amount off',
      VisitBillingDiscountType.none => 'Discount',
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppCard(
          variant: CardVariant.raised,
          padding: CardPadding.lg,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: AppColorPrimitives.amber50,
                      borderRadius: BorderRadius.circular(AppRadius.lg),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.space2 + 2),
                      child: Icon(
                        Icons.percent_rounded,
                        size: 18,
                        color: AppColorPrimitives.amber700,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.space3),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Discount',
                          style: AppTypography.overline(
                            context,
                          ).copyWith(color: colors.textTertiary),
                        ),
                        Text(
                          'Applied adjustment',
                          style: AppTypography.bodySm(
                            context,
                          ).copyWith(color: colors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.space5),
              DecoratedBox(
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: colors.borderSubtle)),
                ),
                child: Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.space5),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Discount type',
                        style: AppTypography.caption(
                          context,
                        ).copyWith(color: colors.textTertiary),
                      ),
                      const SizedBox(height: AppSpacing.space1),
                      Text(
                        discountLabel,
                        style: AppTypography.bodySm(
                          context,
                        ).copyWith(color: colors.textPrimary),
                      ),
                      const SizedBox(height: AppSpacing.space4),
                      Text(
                        'Amount',
                        style: AppTypography.caption(
                          context,
                        ).copyWith(color: colors.textTertiary),
                      ),
                      const SizedBox(height: AppSpacing.space1),
                      AppMoneyDisplay(
                        amount: discountAmount,
                        currency: currency,
                        negative: true,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.space4),
        const _DiscountInfoCard(
          message:
              'This invoice has been finalized. Payment can be recorded from the patient billing tab.',
        ),
      ],
    );
  }
}

class _InvoiceReviewFooter extends StatelessWidget {
  const _InvoiceReviewFooter({
    required this.onBack,
    required this.onFinalize,
    required this.isSubmitting,
  });

  final VoidCallback onBack;
  final VoidCallback? onFinalize;
  final bool isSubmitting;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 640;
        final backButton = AppButton(
          variant: AppButtonVariant.secondary,
          leadingIcon: const Icon(Icons.arrow_back_rounded, size: 16),
          onPressed: onBack,
          child: const Text('Edit services'),
        );
        final finalizeButton = AppButton(
          loading: isSubmitting,
          trailingIcon: const Icon(
            Icons.check_circle_outline_rounded,
            size: 16,
          ),
          onPressed: onFinalize,
          child: const Text('Finalize visit & invoice'),
        );

        if (isWide) {
          return Row(children: [backButton, const Spacer(), finalizeButton]);
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            finalizeButton,
            const SizedBox(height: AppSpacing.space3),
            backButton,
          ],
        );
      },
    );
  }
}
