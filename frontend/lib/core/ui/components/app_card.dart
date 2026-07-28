import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/components/app_avatar.dart';
import 'package:ai_clinic/core/ui/components/app_badge.dart';
import 'package:ai_clinic/core/ui/components/app_button.dart';
import 'package:ai_clinic/core/ui/components/app_icon_button.dart';
import 'package:ai_clinic/core/money/money.dart';
import 'package:ai_clinic/core/ui/components/app_money_display.dart';
import 'package:ai_clinic/core/ui/motion/app_motion.dart';
import 'package:ai_clinic/core/ui/theme/app_elevation.dart';
import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';

// ---------------------------------------------------------------------------
// Card
// ---------------------------------------------------------------------------

enum CardVariant { flat, raised, interactive, ai }

enum CardPadding { sm, md, lg }

/// Application-owned card surface (web `Card`).
///
/// Interactive variant uses hover background transition (web `hover:bg-surface-hover`).
class AppCard extends StatelessWidget {
  const AppCard({
    required this.child,
    this.variant = CardVariant.flat,
    this.header,
    this.footer,
    this.padding = CardPadding.md,
    this.onTap,
    super.key,
  });

  final Widget child;
  final CardVariant variant;
  final Widget? header;
  final Widget? footer;
  final CardPadding padding;
  final VoidCallback? onTap;

  static const _padding = <CardPadding, double>{
    CardPadding.sm: AppSpacing.space4,
    CardPadding.md: AppSpacing.space5,
    CardPadding.lg: AppSpacing.space6,
  };

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final elevation = context.appElevation;

    final spec = _variantSpec(colors, elevation);
    final pad = _padding[padding]!;

    Widget body = Padding(padding: EdgeInsets.all(header != null ? AppSpacing.space5 : pad), child: child);

    if (header != null || footer != null) {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (header != null)
            DecoratedBox(
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: colors.borderSubtle)),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space5, vertical: AppSpacing.space4),
                child: header!,
              ),
            ),
          body,
          if (footer != null)
            DecoratedBox(
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: colors.borderSubtle)),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space5, vertical: AppSpacing.space4),
                child: footer!,
              ),
            ),
        ],
      );
    }

    if (variant == CardVariant.interactive) {
      return _InteractiveCard(
        spec: spec,
        hoverColor: colors.surfaceHover,
        focusBorderColor: colors.actionPrimary,
        onTap: onTap,
        child: body,
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: spec.background,
        border: Border.all(color: spec.border),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        boxShadow: spec.shadow,
      ),
      child: ClipRRect(borderRadius: BorderRadius.circular(AppRadius.lg), child: body),
    );
  }

  _CardVariantSpec _variantSpec(AppSemanticColors colors, AppElevation elevation) {
    return switch (variant) {
      CardVariant.flat => _CardVariantSpec(
        background: colors.surfaceDefault,
        border: colors.borderDefault,
        shadow: elevation.shadows0,
      ),
      CardVariant.raised => _CardVariantSpec(
        background: colors.surfaceRaised,
        border: colors.borderSubtle,
        shadow: elevation.shadows1,
      ),
      CardVariant.interactive => _CardVariantSpec(
        background: colors.surfaceDefault,
        border: colors.borderDefault,
        shadow: elevation.shadows0,
      ),
      CardVariant.ai => _CardVariantSpec(
        background: colors.surfaceAi,
        border: colors.borderAi,
        shadow: elevation.shadows0,
      ),
    };
  }
}

class _CardVariantSpec {
  const _CardVariantSpec({required this.background, required this.border, required this.shadow});

  final Color background;
  final Color border;
  final List<BoxShadow> shadow;
}

/// Interactive card variant — hover background via [MouseRegion] (web `hover:bg-surface-hover`).
class _InteractiveCard extends StatefulWidget {
  const _InteractiveCard({
    required this.spec,
    required this.hoverColor,
    required this.focusBorderColor,
    required this.child,
    this.onTap,
  });

  final _CardVariantSpec spec;
  final Color hoverColor;
  final Color focusBorderColor;
  final VoidCallback? onTap;
  final Widget child;

  @override
  State<_InteractiveCard> createState() => _InteractiveCardState();
}

class _InteractiveCardState extends State<_InteractiveCard> {
  var _hovered = false;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AppRadius.lg);

    // InkWell hover is disabled when onTap is null and still fights opaque
    // decorations. Match AppChip: drive background color from hover state.
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: AppMotion.instant,
          curve: AppMotion.standardCurve,
          decoration: BoxDecoration(
            color: _hovered ? widget.hoverColor : widget.spec.background,
            border: Border.all(color: widget.spec.border),
            borderRadius: radius,
            boxShadow: widget.spec.shadow,
          ),
          child: widget.child,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Metric card
// ---------------------------------------------------------------------------

/// Direction and sign metadata for metric deltas.
class MetricDelta {
  const MetricDelta({required this.value, required this.direction, this.positive});

  final String value;
  final MetricDeltaDirection direction;

  /// When null, defaults to `direction == up`.
  final bool? positive;

  bool get isPositive => positive ?? direction == MetricDeltaDirection.up;
}

enum MetricDeltaDirection { up, down }

/// Metric summary card (web `MetricCard`). Built on [AppCard] variant=raised.
class AppMetricCard extends StatelessWidget {
  const AppMetricCard({required this.label, required this.value, this.delta, this.caption, this.sparkline, super.key});

  final String label;
  final String value;
  final MetricDelta? delta;
  final String? caption;
  final Widget? sparkline;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return AppCard(
      variant: CardVariant.raised,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label.toUpperCase(), style: AppTypography.overline(context).copyWith(color: colors.textTertiary)),
          const SizedBox(height: AppSpacing.space3),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Text(
                  value,
                  style: AppTypography.display(context).copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
                ),
              ),
              ?sparkline,
            ],
          ),
          if (delta != null) ...[const SizedBox(height: AppSpacing.space3), _MetricDeltaRow(delta: delta!)],
          if (caption != null) ...[
            const SizedBox(height: AppSpacing.space1),
            Text(caption!, style: AppTypography.caption(context).copyWith(color: colors.textSecondary)),
          ],
        ],
      ),
    );
  }
}

class _MetricDeltaRow extends StatelessWidget {
  const _MetricDeltaRow({required this.delta});

  final MetricDelta delta;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final color = delta.isPositive ? colors.statusSuccessFg : colors.statusDangerFg;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          delta.direction == MetricDeltaDirection.up ? Icons.trending_up : Icons.trending_down,
          size: 14,
          color: color,
        ),
        const SizedBox(width: AppSpacing.space1 + 2),
        Text(
          delta.value,
          style: AppTypography.bodySm(
            context,
          ).copyWith(color: color, fontFeatures: const [FontFeature.tabularFigures()]),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Entity cards
// ---------------------------------------------------------------------------

/// Patient card (web `PatientCard`).
class AppPatientCard extends StatelessWidget {
  const AppPatientCard({required this.name, required this.mrn, required this.phone, this.tags = const [], super.key});

  final String name;
  final String mrn;
  final String phone;
  final List<String> tags;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return AppCard(
      variant: CardVariant.interactive,
      padding: CardPadding.sm,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppAvatar(name: name, size: AvatarSize.lg),
          const SizedBox(width: AppSpacing.space3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(name, style: AppTypography.bodyStrong(context).copyWith(color: colors.textPrimary)),
                          Text(
                            'MRN \u00B7 $mrn',
                            style: AppTypography.caption(
                              context,
                            ).copyWith(color: colors.textSecondary, fontFeatures: const [FontFeature.tabularFigures()]),
                          ),
                        ],
                      ),
                    ),
                    AppIconButton(
                      icon: const Icon(Icons.more_horiz, size: 16),
                      label: 'Patient actions',
                      size: AppIconButtonSize.sm,
                      onPressed: () {},
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.space2),
                Row(
                  children: [
                    Icon(Icons.phone, size: 14, color: colors.iconMuted),
                    const SizedBox(width: AppSpacing.space1 + 2),
                    Text(
                      phone,
                      style: AppTypography.bodySm(
                        context,
                      ).copyWith(color: colors.textSecondary, fontFeatures: const [FontFeature.tabularFigures()]),
                    ),
                  ],
                ),
                if (tags.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.space3),
                  Wrap(
                    spacing: AppSpacing.space1 + 2,
                    runSpacing: AppSpacing.space1 + 2,
                    children: [
                      for (final tag in tags)
                        AppBadge(size: BadgeSize.sm, color: BadgeColor.neutral, variant: BadgeVariant.soft, label: tag),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Appointment card (web `AppointmentCard`).
class AppAppointmentCard extends StatelessWidget {
  const AppAppointmentCard({
    required this.time,
    required this.patient,
    required this.doctor,
    required this.status,
    required this.branch,
    super.key,
  });

  final String time;
  final String patient;
  final String doctor;
  final String status;
  final String branch;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final statusColor = switch (status.toLowerCase()) {
      'confirmed' => BadgeColor.success,
      'pending' => BadgeColor.warning,
      'cancelled' => BadgeColor.danger,
      _ => BadgeColor.neutral,
    };

    final timeParts = time.split(' ');
    final timeValue = timeParts.isNotEmpty ? timeParts.first : time;

    return AppCard(
      variant: CardVariant.flat,
      padding: CardPadding.sm,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.surfaceSelected,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  child: SizedBox(
                    width: 40,
                    height: 40,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.calendar_today, size: 14, color: colors.textLink),
                        Text(
                          timeValue,
                          style: AppTypography.caption(
                            context,
                          ).copyWith(color: colors.textLink, fontFeatures: const [FontFeature.tabularFigures()]),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.space3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(patient, style: AppTypography.bodyStrong(context).copyWith(color: colors.textPrimary)),
                      Text(doctor, style: AppTypography.bodySm(context).copyWith(color: colors.textSecondary)),
                      Text(branch, style: AppTypography.caption(context).copyWith(color: colors.textTertiary)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          AppBadge(color: statusColor, variant: BadgeVariant.soft, label: status),
        ],
      ),
    );
  }
}

/// Invoice card (web `InvoiceCard`).
class AppInvoiceCard extends StatelessWidget {
  const AppInvoiceCard({
    required this.number,
    required this.patient,
    required this.amount,
    required this.status,
    required this.date,
    this.currency = 'EGP',
    super.key,
  });

  final String number;
  final String patient;
  final double amount;
  final String status;
  final String date;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final statusColor = switch (status.toLowerCase()) {
      'paid' => BadgeColor.success,
      'pending' => BadgeColor.warning,
      'overdue' => BadgeColor.danger,
      _ => BadgeColor.neutral,
    };

    return AppCard(
      variant: CardVariant.flat,
      padding: CardPadding.sm,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(number, style: AppTypography.mono(context).copyWith(color: colors.textPrimary)),
                Text(patient, style: AppTypography.bodySm(context).copyWith(color: colors.textSecondary)),
                Text(
                  date,
                  style: AppTypography.caption(
                    context,
                  ).copyWith(color: colors.textTertiary, fontFeatures: const [FontFeature.tabularFigures()]),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              DefaultTextStyle(
                style: AppTypography.bodyStrong(context),
                child: AppMoneyDisplay(amount: Money.parse(amount.toStringAsFixed(2)), currency: currency, emphasis: true),
              ),
              const SizedBox(height: AppSpacing.space1),
              AppBadge(color: statusColor, variant: BadgeVariant.soft, label: status),
            ],
          ),
        ],
      ),
    );
  }
}

/// Service card (web `ServiceCard`).
class AppServiceCard extends StatelessWidget {
  const AppServiceCard({
    required this.name,
    required this.price,
    required this.globalStatus,
    required this.branchSummary,
    this.currency = 'EGP',
    super.key,
  });

  final String name;
  final double price;
  final String globalStatus;
  final String branchSummary;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final statusColor = globalStatus.toLowerCase() == 'active' ? BadgeColor.success : BadgeColor.neutral;

    return AppCard(
      variant: CardVariant.raised,
      padding: CardPadding.sm,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(name, style: AppTypography.bodyStrong(context).copyWith(color: colors.textPrimary)),
                    const SizedBox(height: AppSpacing.space1),
                    DefaultTextStyle(
                      style: AppTypography.bodySm(context),
                      child: AppMoneyDisplay(amount: Money.parse(price.toStringAsFixed(2)), currency: currency),
                    ),
                    const SizedBox(height: AppSpacing.space2),
                    Text(branchSummary, style: AppTypography.caption(context).copyWith(color: colors.textSecondary)),
                  ],
                ),
              ),
              AppBadge(color: statusColor, variant: BadgeVariant.soft, label: globalStatus),
            ],
          ),
          const SizedBox(height: AppSpacing.space4),
          AppButton(
            variant: AppButtonVariant.ghost,
            size: AppButtonSize.sm,
            onPressed: () {},
            child: const Text('View branches'),
          ),
        ],
      ),
    );
  }
}
