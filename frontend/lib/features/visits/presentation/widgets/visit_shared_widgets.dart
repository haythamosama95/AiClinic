import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/theme/semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/spacing_tokens.dart';
import 'package:ai_clinic/features/visits/domain/visit_status.dart';
import 'package:ai_clinic/features/visits/domain/visit_vital_sign.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_page_tokens.dart';

/// Status accent + label helpers for visit pages.
abstract final class VisitStatusDisplay {
  static Color statusColor(BuildContext context, VisitStatus status) {
    final colors = context.semanticColors;
    final theme = context.visitTheme;
    return switch (status) {
      VisitStatus.inProgress => colors.chart4,
      VisitStatus.completed => theme.pulse,
    };
  }
}

/// Page shell: workspace background with a minimal top bar and scrollable body.
class VisitPageShell extends StatelessWidget {
  const VisitPageShell({required this.onBack, required this.body, this.headerActions = const [], super.key});

  final VoidCallback onBack;
  final List<Widget> headerActions;
  final Widget body;

  @override
  Widget build(BuildContext context) {
    final theme = context.visitTheme;

    return ColoredBox(
      color: theme.canvas,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(SpacingTokens.lg, SpacingTokens.md, SpacingTokens.lg, SpacingTokens.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _VisitTopBar(onBack: onBack, headerActions: headerActions),
              const SizedBox(height: SpacingTokens.md),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.only(bottom: SpacingTokens.xl),
                  child: body,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VisitTopBar extends StatelessWidget {
  const _VisitTopBar({required this.onBack, required this.headerActions});

  final VoidCallback onBack;
  final List<Widget> headerActions;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _BackControl(onPressed: onBack),
        const Spacer(),
        ...headerActions.map(
          (action) => Padding(
            padding: const EdgeInsets.only(left: SpacingTokens.sm),
            child: action,
          ),
        ),
      ],
    );
  }
}

class _BackControl extends StatelessWidget {
  const _BackControl({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = context.visitTheme;

    return Material(
      color: theme.surface,
      shape: StadiumBorder(side: BorderSide(color: theme.hairline)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: SpacingTokens.md, vertical: SpacingTokens.sm),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.arrow_back_rounded, size: 17, color: theme.ink),
              const SizedBox(width: SpacingTokens.xs),
              Text('Back', style: theme.bodyStrong(size: 13.5)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Signature header band with vital readouts and a pulse accent line.
class VisitHeroCard extends StatelessWidget {
  const VisitHeroCard({
    required this.dateLabel,
    required this.doctorName,
    required this.status,
    this.vitalSigns = const [],
    super.key,
  });

  final String dateLabel;
  final String doctorName;
  final VisitStatus status;
  final List<VisitVitalSign> vitalSigns;

  @override
  Widget build(BuildContext context) {
    final theme = context.visitTheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [theme.heroGradientStart, theme.heroGradientEnd],
        ),
        borderRadius: BorderRadius.circular(theme.panelRadius + SpacingTokens.xs),
        boxShadow: theme.headerShadow,
        border: Border.all(color: theme.pulse.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(SpacingTokens.xl, SpacingTokens.xl, SpacingTokens.xl, SpacingTokens.md),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final stacked = constraints.maxWidth < 640;
                final identity = _Identity(dateLabel: dateLabel, doctorName: doctorName, status: status);
                final readout = _VitalReadout(vitalSigns: vitalSigns);

                if (stacked) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      identity,
                      const SizedBox(height: SpacingTokens.lg),
                      readout,
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(child: identity),
                    const SizedBox(width: SpacingTokens.lg),
                    Flexible(
                      child: Align(alignment: Alignment.centerRight, child: readout),
                    ),
                  ],
                );
              },
            ),
          ),
          SizedBox(
            height: 34,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: SpacingTokens.lg),
              child: ClipRect(
                child: CustomPaint(
                  painter: _PulseLinePainter(accentColor: theme.pulse),
                  size: Size.infinite,
                ),
              ),
            ),
          ),
          const SizedBox(height: SpacingTokens.md),
        ],
      ),
    );
  }
}

class _Identity extends StatelessWidget {
  const _Identity({required this.dateLabel, required this.doctorName, required this.status});

  final String dateLabel;
  final String doctorName;
  final VisitStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = context.visitTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _GlowDot(color: theme.pulse),
            const SizedBox(width: SpacingTokens.sm),
            Text('ENCOUNTER RECORD', style: theme.eyebrow(color: theme.onInkMuted)),
          ],
        ),
        const SizedBox(height: SpacingTokens.md),
        Text(dateLabel, style: theme.heroDate()),
        const SizedBox(height: SpacingTokens.md),
        Row(
          children: [
            Icon(Icons.person_outline_rounded, size: 16, color: theme.onInkMuted),
            const SizedBox(width: SpacingTokens.xs),
            Flexible(
              child: Text(
                doctorName,
                overflow: TextOverflow.ellipsis,
                style: theme.bodyStrong(color: theme.onInk, size: 14),
              ),
            ),
            const SizedBox(width: SpacingTokens.md),
            _StatusPill(status: status),
          ],
        ),
      ],
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});

  final VisitStatus status;

  @override
  Widget build(BuildContext context) {
    final color = VisitStatusDisplay.statusColor(context, status);
    final theme = context.visitTheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: SpacingTokens.sm + 2, vertical: 5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _GlowDot(color: color, size: 7),
            const SizedBox(width: SpacingTokens.xs + 1),
            Text(status.label.toUpperCase(), style: theme.eyebrow(color: color, size: 10).copyWith(letterSpacing: 1.2)),
          ],
        ),
      ),
    );
  }
}

class _GlowDot extends StatelessWidget {
  const _GlowDot({required this.color, this.size = 8});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [BoxShadow(color: color.withValues(alpha: 0.7), blurRadius: 8, spreadRadius: 1)],
      ),
    );
  }
}

/// Monitor-style surfacing of recorded vitals as readouts.
class _VitalReadout extends StatelessWidget {
  const _VitalReadout({required this.vitalSigns});

  final List<VisitVitalSign> vitalSigns;

  @override
  Widget build(BuildContext context) {
    final theme = context.visitTheme;
    final visible = vitalSigns.take(4).toList();

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.onInk.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(theme.tileRadius + SpacingTokens.xs),
        border: Border.all(color: theme.onInk.withValues(alpha: 0.12)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: SpacingTokens.lg, vertical: SpacingTokens.md),
        child: visible.isEmpty
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.monitor_heart_outlined, size: 16, color: theme.onInkMuted),
                  const SizedBox(width: SpacingTokens.sm),
                  Text('AWAITING VITALS', style: theme.eyebrow(color: theme.onInkMuted, size: 10)),
                ],
              )
            : Wrap(
                spacing: SpacingTokens.lg,
                runSpacing: SpacingTokens.md,
                children: [for (final sign in visible) _ReadoutStat(sign: sign)],
              ),
      ),
    );
  }
}

class _ReadoutStat extends StatelessWidget {
  const _ReadoutStat({required this.sign});

  final VisitVitalSign sign;

  @override
  Widget build(BuildContext context) {
    final theme = context.visitTheme;
    final hasUnit = sign.unit != null && sign.unit!.trim().isNotEmpty;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          sign.name.toUpperCase(),
          style: theme.eyebrow(color: theme.onInkMuted, size: 9.5).copyWith(letterSpacing: 1.2),
        ),
        const SizedBox(height: 5),
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(sign.value, style: theme.readout(color: theme.pulse, size: 18)),
            if (hasUnit) ...[
              const SizedBox(width: 3),
              Text(sign.unit!, style: theme.readout(color: theme.onInkMuted, size: 11)),
            ],
          ],
        ),
      ],
    );
  }
}

/// ECG-style pulse line accent for the hero header.
class _PulseLinePainter extends CustomPainter {
  const _PulseLinePainter({required this.accentColor});

  final Color accentColor;

  @override
  void paint(Canvas canvas, Size size) {
    final midY = size.height / 2;
    final h = size.height;
    final path = Path()..moveTo(0, midY);

    const segment = 92.0;
    var x = 0.0;
    while (x < size.width + segment) {
      path.lineTo(x + segment * 0.50, midY);
      path.lineTo(x + segment * 0.55, midY - h * 0.12);
      path.lineTo(x + segment * 0.60, midY);
      path.lineTo(x + segment * 0.65, midY + h * 0.16);
      path.lineTo(x + segment * 0.71, midY - h * 0.46);
      path.lineTo(x + segment * 0.77, midY + h * 0.30);
      path.lineTo(x + segment * 0.84, midY);
      x += segment;
    }

    final glow = Paint()
      ..color = accentColor.withValues(alpha: 0.45)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.2
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);
    final line = Paint()
      ..color = accentColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;

    canvas.drawPath(path, glow);
    canvas.drawPath(path, line);
  }

  @override
  bool shouldRepaint(covariant _PulseLinePainter oldDelegate) => oldDelegate.accentColor != accentColor;
}

/// Section panel with a quiet header.
class VisitSectionCard extends StatelessWidget {
  const VisitSectionCard({
    required this.title,
    required this.child,
    this.description,
    this.headerActions,
    this.kind,
    super.key,
  });

  final String title;
  final String? description;
  final Widget child;
  final List<Widget>? headerActions;
  final VisitPanelKind? kind;

  @override
  Widget build(BuildContext context) {
    final theme = context.visitTheme;
    final icon = kind?.icon ?? Icons.folder_open_outlined;
    final tag = kind?.tag;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.surface,
        borderRadius: BorderRadius.circular(theme.panelRadius),
        border: Border.all(color: theme.hairline),
        boxShadow: theme.panelShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(SpacingTokens.lg, SpacingTokens.lg, SpacingTokens.md, SpacingTokens.md),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(icon, size: 19, color: theme.pulseDeep),
                const SizedBox(width: SpacingTokens.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (tag != null) Text(tag, style: theme.eyebrow(color: theme.pulseDeep, size: 10)),
                      if (tag != null) const SizedBox(height: 3),
                      Text(title, style: theme.title()),
                      if (description != null) ...[
                        const SizedBox(height: 3),
                        Text(description!, style: theme.caption()),
                      ],
                    ],
                  ),
                ),
                if (headerActions != null) ...?headerActions,
              ],
            ),
          ),
          Divider(height: 1, color: theme.hairlineSoft),
          Padding(padding: const EdgeInsets.all(SpacingTokens.lg), child: child),
        ],
      ),
    );
  }
}

/// Read-only label/value pair for visit detail sections.
class VisitDetailField extends StatelessWidget {
  const VisitDetailField({required this.label, required this.value, this.abbr, super.key});

  final String label;
  final String value;
  final String? abbr;

  @override
  Widget build(BuildContext context) {
    final theme = context.visitTheme;
    final display = value.trim().isEmpty ? '—' : value.trim();
    final isEmpty = value.trim().isEmpty;

    return Padding(
      padding: const EdgeInsets.only(bottom: SpacingTokens.lg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (abbr != null) ...[VisitMarginAbbr(letter: abbr!), const SizedBox(width: SpacingTokens.md)],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label.toUpperCase(), style: theme.eyebrow(size: 10).copyWith(letterSpacing: 1.2)),
                const SizedBox(height: SpacingTokens.xs + 1),
                Text(display, style: theme.body(color: isEmpty ? theme.mutedInk : theme.ink)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Clinical chart margin abbreviation.
class VisitMarginAbbr extends StatelessWidget {
  const VisitMarginAbbr({required this.letter, super.key});

  final String letter;

  @override
  Widget build(BuildContext context) {
    final theme = context.visitTheme;

    return Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        color: theme.pulse.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(theme.tileRadius - 2),
        border: Border.all(color: theme.pulse.withValues(alpha: 0.28)),
      ),
      alignment: Alignment.center,
      child: Text(letter, style: theme.readout(color: theme.pulseDeep, size: 13)),
    );
  }
}

/// Empty state hint for visit sections.
class VisitEmptyHint extends StatelessWidget {
  const VisitEmptyHint({required this.message, this.icon = Icons.inbox_outlined, super.key});

  final String message;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = context.visitTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: SpacingTokens.lg),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: theme.tile, shape: BoxShape.circle),
              child: Icon(icon, size: 20, color: theme.mutedInk.withValues(alpha: 0.7)),
            ),
            const SizedBox(height: SpacingTokens.sm),
            Text(message, textAlign: TextAlign.center, style: theme.caption()),
          ],
        ),
      ),
    );
  }
}

/// Responsive two-column grid for visit ancillary sections.
class VisitSectionGrid extends StatelessWidget {
  const VisitSectionGrid({required this.children, super.key});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final useTwoColumns = constraints.maxWidth >= 720;

        if (!useTwoColumns) {
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: _withGaps(children));
        }

        final rows = <Widget>[];
        for (var i = 0; i < children.length; i += 2) {
          final left = children[i];
          final right = i + 1 < children.length ? children[i + 1] : const SizedBox.shrink();
          rows.add(
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: left),
                const SizedBox(width: VisitPageTokens.sectionGap),
                Expanded(child: right),
              ],
            ),
          );
          if (i + 2 < children.length) {
            rows.add(const SizedBox(height: VisitPageTokens.sectionGap));
          }
        }

        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows);
      },
    );
  }

  List<Widget> _withGaps(List<Widget> items) {
    final result = <Widget>[];
    for (var i = 0; i < items.length; i++) {
      result.add(items[i]);
      if (i < items.length - 1) {
        result.add(const SizedBox(height: VisitPageTokens.sectionGap));
      }
    }
    return result;
  }
}

/// Constrains visit page content width.
class VisitContentFrame extends StatelessWidget {
  const VisitContentFrame({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: VisitPageTokens.contentMaxWidth),
        child: child,
      ),
    );
  }
}
