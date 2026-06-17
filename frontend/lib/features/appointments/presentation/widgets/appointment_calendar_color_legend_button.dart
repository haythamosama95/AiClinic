import 'dart:async';

import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import 'package:ai_clinic/core/ui/theme/semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/spacing_tokens.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_calendar_display.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';

final _legendPopoverMotion = FPopoverStyleDelta.delta(
  motion: FPopoverMotionDelta.delta(
    entranceDuration: Duration(milliseconds: 150),
    exitDuration: Duration(milliseconds: 100),
    scaleTween: Tween<double>(begin: 0.96, end: 1),
    fadeTween: Tween<double>(begin: 0, end: 1),
  ),
);

/// Hover-triggered color legend for appointment statuses in the calendar header.
class AppointmentCalendarColorLegendButton extends StatefulWidget {
  const AppointmentCalendarColorLegendButton({super.key});

  @override
  State<AppointmentCalendarColorLegendButton> createState() => _AppointmentCalendarColorLegendButtonState();
}

class _AppointmentCalendarColorLegendButtonState extends State<AppointmentCalendarColorLegendButton>
    with SingleTickerProviderStateMixin {
  late final FPopoverController _controller = FPopoverController(vsync: this);
  Timer? _hideTimer;
  var _isButtonHovered = false;
  var _isPopoverHovered = false;

  @override
  void dispose() {
    _hideTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _showLegend() {
    _hideTimer?.cancel();
    _controller.show();
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(milliseconds: 120), () {
      if (!_isButtonHovered && !_isPopoverHovered) {
        _controller.hide();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.semanticColors;

    return FPopover(
      control: FPopoverControl.managed(controller: _controller),
      style: _legendPopoverMotion,
      hideRegion: FPopoverHideRegion.none,
      constraints: const FPortalConstraints(minWidth: 200, maxWidth: 240),
      popoverAnchor: Alignment.topCenter,
      childAnchor: Alignment.bottomCenter,
      popoverBuilder: (context, controller) => MouseRegion(
        onEnter: (_) {
          setState(() => _isPopoverHovered = true);
          _showLegend();
        },
        onExit: (_) {
          setState(() => _isPopoverHovered = false);
          _scheduleHide();
        },
        child: const _AppointmentCalendarColorLegendPanel(),
      ),
      builder: (context, controller, child) => MouseRegion(
        onEnter: (_) {
          setState(() => _isButtonHovered = true);
          _showLegend();
        },
        onExit: (_) {
          setState(() => _isButtonHovered = false);
          _scheduleHide();
        },
        cursor: SystemMouseCursors.help,
        child: IgnorePointer(child: child),
      ),
      child: Tooltip(
        message: 'Appointment colors',
        child: SizedBox(
          width: 40,
          height: 40,
          child: Material(
            color: _isButtonHovered ? colors.muted : colors.background,
            shape: CircleBorder(side: BorderSide(color: colors.border)),
            clipBehavior: Clip.antiAlias,
            child: Center(child: Icon(Icons.legend_toggle_outlined, color: colors.foreground, size: 20)),
          ),
        ),
      ),
    );
  }
}

class _AppointmentCalendarColorLegendPanel extends StatelessWidget {
  const _AppointmentCalendarColorLegendPanel();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.semanticColors;

    return Padding(
      padding: const EdgeInsets.all(SpacingTokens.sm),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(SpacingTokens.sm, SpacingTokens.sm, SpacingTokens.sm, SpacingTokens.xs),
            child: Text('Appointment colors', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
          ),
          for (final status in AppointmentCalendarDisplay.calendarStatusLegend) ...[
            _LegendRow(status: status),
            if (status != AppointmentCalendarDisplay.calendarStatusLegend.last)
              const SizedBox(height: SpacingTokens.xs),
          ],
          const SizedBox(height: SpacingTokens.xs),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: SpacingTokens.sm),
            child: Text(
              'Colors reflect appointment status.',
              style: theme.textTheme.labelSmall?.copyWith(color: colors.mutedForeground),
            ),
          ),
        ],
      ),
    );
  }
}

class _LegendRow extends StatelessWidget {
  const _LegendRow({required this.status});

  final AppointmentStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = AppointmentCalendarDisplay.statusColor(status);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: SpacingTokens.sm),
      child: Row(
        children: [
          Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: color),
            ),
          ),
          const SizedBox(width: SpacingTokens.sm),
          Expanded(child: Text(status.label, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}
