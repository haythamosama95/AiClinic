import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:ai_clinic/core/ui/motion/app_motion.dart';
import 'package:ai_clinic/core/ui/theme/app_elevation.dart';
import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';
import 'package:ai_clinic/features/billing/presentation/widgets/visit_billing/visit_invoice_summary_panel.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_submitted_confirmation_data.dart';

/// Post-finalize confirmation combining celebration seal and filing receipt.
class VisitSubmittedCombinedConfirmation extends StatefulWidget {
  const VisitSubmittedCombinedConfirmation({required this.data, super.key});

  final VisitSubmittedConfirmationData data;

  @override
  State<VisitSubmittedCombinedConfirmation> createState() => _VisitSubmittedCombinedConfirmationState();
}

class _VisitSubmittedCombinedConfirmationState extends State<VisitSubmittedCombinedConfirmation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _sealScale;
  late final Animation<double> _contentOpacity;
  late final Animation<double> _bodySlide;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: AppMotionDuration.deliberate);
    _sealScale = Tween<double>(
      begin: 0.6,
      end: 1,
    ).animate(CurvedAnimation(parent: _controller, curve: AppMotion.outCurve));
    _contentOpacity = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.2, 1, curve: AppMotion.outCurve),
      ),
    );
    _bodySlide = Tween<double>(begin: 12, end: 0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.25, 1, curve: AppMotion.outCurve),
      ),
    );
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final elevation = context.appElevation;
    final reducedMotion = AppMotion.prefersReducedMotion(context);
    final kind = widget.data.kind;
    final actionLabel = kind == VisitConfirmationKind.edited ? 'Updated' : 'Filed';
    final filedAt = DateFormat('EEEE, MMM d, yyyy · h:mm a').format(widget.data.displayTimestamp.toLocal());
    final visitDateLabel = DateFormat('MMM d, yyyy').format(widget.data.visitDate.toLocal());
    final slotLabel = _formatSlot(widget.data.appointmentStart, widget.data.appointmentEnd);

    Widget card = Semantics(
      liveRegion: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surfaceRaised,
          borderRadius: BorderRadius.circular(AppRadius.x2l),
          border: Border.all(color: colors.borderSubtle),
          boxShadow: elevation.shadows1,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.x2l),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.space5,
                  AppSpacing.space6,
                  AppSpacing.space5,
                  AppSpacing.space5,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    _ConfirmationSeal(
                      colors: colors,
                      kind: kind,
                      reducedMotion: reducedMotion,
                      sealScale: _sealScale,
                      contentOpacity: _contentOpacity,
                    ),
                    const SizedBox(height: AppSpacing.space5),
                    Text(kind.title, style: AppTypography.h2(context), textAlign: TextAlign.center),
                    const SizedBox(height: AppSpacing.space2),
                    Text.rich(
                      TextSpan(
                        style: AppTypography.body(context).copyWith(color: colors.textSecondary),
                        children: _bodySpans(kind, widget.data.patientName),
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppSpacing.space2),
                    Text(
                      '$actionLabel $filedAt',
                      style: AppTypography.caption(context).copyWith(color: colors.textTertiary),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppSpacing.space5),
                    const _PerforationDivider(),
                    const SizedBox(height: AppSpacing.space5),
                    _FilingStub(
                      kind: kind,
                      filingReference: widget.data.filingReference,
                      branchName: widget.data.branchName,
                      doctorName: widget.data.doctorName,
                      visitDateLabel: visitDateLabel,
                      slotLabel: slotLabel,
                    ),
                    if (widget.data.invoicePreview != null) ...[
                      const SizedBox(height: AppSpacing.space5),
                      VisitInvoiceSummaryPanel(
                        preview: widget.data.invoicePreview,
                        invoice: widget.data.persistedInvoice,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (reducedMotion) {
      return card;
    }

    return AnimatedBuilder(
      animation: _bodySlide,
      builder: (context, child) {
        return Opacity(
          opacity: _contentOpacity.value.clamp(0.0, 1.0),
          child: Transform.translate(offset: Offset(0, _bodySlide.value), child: child),
        );
      },
      child: card,
    );
  }

  static String _formatSlot(DateTime start, DateTime end) {
    final localStart = start.toLocal();
    final localEnd = end.toLocal();
    return '${DateFormat.jm().format(localStart)} – ${DateFormat.jm().format(localEnd)}';
  }

  static List<InlineSpan> _bodySpans(VisitConfirmationKind kind, String patientName) {
    return switch (kind) {
      VisitConfirmationKind.completed => [
        const TextSpan(text: 'The visit for '),
        TextSpan(
          text: patientName,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        const TextSpan(text: ' is on file.'),
      ],
      VisitConfirmationKind.edited => [
        const TextSpan(text: 'Documentation for '),
        TextSpan(
          text: patientName,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        const TextSpan(text: ' has been saved to the patient chart.'),
      ],
    };
  }
}

class _ConfirmationSeal extends StatelessWidget {
  const _ConfirmationSeal({
    required this.colors,
    required this.kind,
    required this.reducedMotion,
    required this.sealScale,
    required this.contentOpacity,
  });

  final AppSemanticColors colors;
  final VisitConfirmationKind kind;
  final bool reducedMotion;
  final Animation<double> sealScale;
  final Animation<double> contentOpacity;

  Color get _accentFg => kind == VisitConfirmationKind.edited ? colors.statusInfoFg : colors.statusSuccessFg;

  Color get _accentSurface =>
      kind == VisitConfirmationKind.edited ? colors.statusInfoSurface : colors.statusSuccessSurface;

  Color get _accentBorder =>
      kind == VisitConfirmationKind.edited ? colors.statusInfoBorder : colors.statusSuccessBorder;

  IconData get _icon => kind == VisitConfirmationKind.edited ? Icons.edit_note_rounded : Icons.check_rounded;

  @override
  Widget build(BuildContext context) {
    Widget seal = Stack(
      alignment: Alignment.center,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [BoxShadow(color: _accentFg.withValues(alpha: 0.18), blurRadius: 24, spreadRadius: 4)],
          ),
          child: const SizedBox(width: 88, height: 88),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _accentSurface,
            border: Border.all(color: _accentBorder, width: 2),
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.space5),
            child: Icon(_icon, size: 36, color: _accentFg),
          ),
        ),
      ],
    );

    if (reducedMotion) {
      return seal;
    }

    return AnimatedBuilder(
      animation: Listenable.merge([sealScale, contentOpacity]),
      builder: (context, child) {
        return Opacity(
          opacity: contentOpacity.value.clamp(0.0, 1.0),
          child: Transform.scale(scale: sealScale.value, child: child),
        );
      },
      child: seal,
    );
  }
}

class _PerforationDivider extends StatelessWidget {
  const _PerforationDivider();

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return LayoutBuilder(
      builder: (context, constraints) {
        const dashWidth = 6.0;
        const gap = 4.0;
        final count = (constraints.maxWidth / (dashWidth + gap)).floor();

        return Row(
          children: [
            for (var i = 0; i < count; i++) ...[
              if (i > 0) const SizedBox(width: gap),
              DecoratedBox(
                decoration: BoxDecoration(color: colors.borderSubtle, borderRadius: BorderRadius.circular(1)),
                child: const SizedBox(width: dashWidth, height: 1),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// Filing stub below the tear line — reference banner plus visit details grid.
class _FilingStub extends StatelessWidget {
  const _FilingStub({
    required this.kind,
    required this.filingReference,
    required this.branchName,
    required this.doctorName,
    required this.visitDateLabel,
    required this.slotLabel,
  });

  final VisitConfirmationKind kind;
  final String filingReference;
  final String branchName;
  final String doctorName;
  final String visitDateLabel;
  final String slotLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final accentFg = kind == VisitConfirmationKind.edited ? colors.statusInfoFg : colors.statusSuccessFg;
    final accentSurface = kind == VisitConfirmationKind.edited ? colors.statusInfoSurface : colors.statusSuccessSurface;
    final accentBorder = kind == VisitConfirmationKind.edited ? colors.statusInfoBorder : colors.statusSuccessBorder;
    final badgeIcon = kind == VisitConfirmationKind.edited ? Icons.edit_rounded : Icons.check_rounded;
    final referenceIcon = kind == VisitConfirmationKind.edited
        ? Icons.history_edu_outlined
        : Icons.folder_copy_outlined;
    final referenceLabel = kind == VisitConfirmationKind.edited ? 'Visit reference' : 'Filing reference';
    final footerIcon = kind == VisitConfirmationKind.edited ? Icons.sync_rounded : Icons.lock_outline_rounded;

    final cells = [
      _VisitDetailCell(label: 'Doctor', value: doctorName, icon: Icons.person_outline),
      _VisitDetailCell(label: 'Branch', value: branchName, icon: Icons.location_on_outlined),
      _VisitDetailCell(label: 'Appointment', value: slotLabel, icon: Icons.schedule_outlined),
      _VisitDetailCell(label: 'Visit date', value: visitDateLabel, icon: Icons.calendar_today_outlined),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: accentSurface,
                borderRadius: BorderRadius.circular(AppRadius.sm),
                border: Border.all(color: accentBorder),
              ),
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.space2),
                child: Icon(referenceIcon, size: 16, color: accentFg),
              ),
            ),
            const SizedBox(width: AppSpacing.space3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    referenceLabel,
                    style: AppTypography.caption(
                      context,
                    ).copyWith(color: colors.textTertiary, fontWeight: FontWeight.w600, letterSpacing: 0.3),
                  ),
                  const SizedBox(height: AppSpacing.space05),
                  Text(
                    filingReference,
                    style: AppTypography.bodySm(
                      context,
                    ).copyWith(fontFamily: 'JetBrains Mono', fontWeight: FontWeight.w700, letterSpacing: 0.5),
                  ),
                ],
              ),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                color: accentSurface,
                borderRadius: BorderRadius.circular(AppRadius.full),
                border: Border.all(color: accentBorder),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space2, vertical: AppSpacing.space1),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(badgeIcon, size: 12, color: accentFg),
                    const SizedBox(width: AppSpacing.space1),
                    Text(
                      kind.filingBadgeLabel,
                      style: AppTypography.caption(
                        context,
                      ).copyWith(color: accentFg, fontWeight: FontWeight.w700, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.space5),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'Visit details',
            style: AppTypography.caption(
              context,
            ).copyWith(color: colors.textTertiary, fontWeight: FontWeight.w600, letterSpacing: 0.4),
          ),
        ),
        const SizedBox(height: AppSpacing.space3),
        _VisitDetailsGrid(cells: cells, colors: colors),
        const SizedBox(height: AppSpacing.space4),
        Row(
          children: [
            Icon(footerIcon, size: 14, color: accentFg),
            const SizedBox(width: AppSpacing.space2),
            Expanded(
              child: Text(
                kind.footerNote,
                style: AppTypography.caption(
                  context,
                ).copyWith(color: colors.textSecondary, fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _VisitDetailCell {
  const _VisitDetailCell({required this.label, required this.value, required this.icon});

  final String label;
  final String value;
  final IconData icon;
}

class _VisitDetailsGrid extends StatelessWidget {
  const _VisitDetailsGrid({required this.cells, required this.colors});

  final List<_VisitDetailCell> cells;
  final AppSemanticColors colors;

  @override
  Widget build(BuildContext context) {
    assert(cells.length == 4, 'Visit details grid expects exactly four cells.');

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: colors.borderSubtle),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: Column(
          children: [
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: _VisitDetailTile(cell: cells[0], colors: colors),
                  ),
                  _GridDivider.vertical(color: colors.borderSubtle),
                  Expanded(
                    child: _VisitDetailTile(cell: cells[1], colors: colors),
                  ),
                ],
              ),
            ),
            _GridDivider.horizontal(color: colors.borderSubtle),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: _VisitDetailTile(cell: cells[2], colors: colors),
                  ),
                  _GridDivider.vertical(color: colors.borderSubtle),
                  Expanded(
                    child: _VisitDetailTile(cell: cells[3], colors: colors),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VisitDetailTile extends StatelessWidget {
  const _VisitDetailTile({required this.cell, required this.colors});

  final _VisitDetailCell cell;
  final AppSemanticColors colors;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.space4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(cell.icon, size: 14, color: colors.iconMuted),
              const SizedBox(width: AppSpacing.space2),
              Expanded(
                child: Text(
                  cell.label,
                  style: AppTypography.caption(
                    context,
                  ).copyWith(color: colors.textTertiary, fontWeight: FontWeight.w600, letterSpacing: 0.3),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.space2),
          Text(
            cell.value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.bodySm(
              context,
            ).copyWith(color: colors.textPrimary, fontWeight: FontWeight.w500, height: 1.35),
          ),
        ],
      ),
    );
  }
}

class _GridDivider extends StatelessWidget {
  const _GridDivider._({this.width, this.height, required this.color});

  const _GridDivider.vertical({required Color color}) : this._(width: 1, color: color);
  const _GridDivider.horizontal({required Color color}) : this._(height: 1, color: color);

  final double? width;
  final double? height;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: color,
      child: SizedBox(width: width, height: height),
    );
  }
}
