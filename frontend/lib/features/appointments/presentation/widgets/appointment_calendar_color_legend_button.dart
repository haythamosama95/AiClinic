import 'dart:async';

import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_calendar_status_filter.dart';
import 'package:ai_clinic/features/appointments/presentation/theme/appointment_calendar_status_theme.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/appointment_calendar_status_swatch.dart';

/// Hover-triggered color legend for appointment statuses in the calendar toolbar.
class AppointmentCalendarColorLegendButton extends StatefulWidget {
  const AppointmentCalendarColorLegendButton({super.key});

  @override
  State<AppointmentCalendarColorLegendButton> createState() => _AppointmentCalendarColorLegendButtonState();
}

class _AppointmentCalendarColorLegendButtonState extends State<AppointmentCalendarColorLegendButton> {
  var _open = false;
  Timer? _hideTimer;
  var _isTriggerHovered = false;
  var _isPanelHovered = false;

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  void _showLegend() {
    _hideTimer?.cancel();
    if (!_open) {
      setState(() => _open = true);
    }
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(milliseconds: 120), () {
      if (!_isTriggerHovered && !_isPanelHovered && mounted) {
        setState(() => _open = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AppPopover(
      open: _open,
      onOpenChange: (open) => setState(() => _open = open),
      align: AppPopoverAlign.end,
      matchTriggerWidth: false,
      minWidth: 220,
      width: 240,
      estimatedContentHeight: 320,
      triggerBuilder: (context, isOpen, onToggle) {
        return MouseRegion(
          onEnter: (_) {
            setState(() => _isTriggerHovered = true);
            _showLegend();
          },
          onExit: (_) {
            setState(() => _isTriggerHovered = false);
            _scheduleHide();
          },
          cursor: SystemMouseCursors.help,
          child: AppIconButton(
            icon: const Icon(Icons.legend_toggle_outlined),
            label: 'Appointment colors',
            tooltip: 'Appointment colors',
            variant: isOpen || _isTriggerHovered ? AppIconButtonVariant.secondary : AppIconButtonVariant.ghost,
            onPressed: onToggle,
          ),
        );
      },
      child: MouseRegion(
        onEnter: (_) {
          setState(() => _isPanelHovered = true);
          _showLegend();
        },
        onExit: (_) {
          setState(() => _isPanelHovered = false);
          _scheduleHide();
        },
        child: const _AppointmentCalendarColorLegendPanel(),
      ),
    );
  }
}

class _AppointmentCalendarColorLegendPanel extends StatelessWidget {
  const _AppointmentCalendarColorLegendPanel();

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.space3),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.space2,
              AppSpacing.space1,
              AppSpacing.space2,
              AppSpacing.space2,
            ),
            child: Text('Appointment colors', style: AppTypography.bodyStrong(context)),
          ),
          for (final status in AppointmentCalendarStatusFilter.calendarStatusLegend) ...[
            _LegendRow(status: status),
            if (status != AppointmentCalendarStatusFilter.calendarStatusLegend.last)
              const SizedBox(height: AppSpacing.space1),
          ],
          const SizedBox(height: AppSpacing.space2),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space2),
            child: Text(
              'Colors reflect appointment status.',
              style: AppTypography.caption(context).copyWith(color: colors.textTertiary),
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
    final brightness = Theme.of(context).brightness;
    final style = AppointmentCalendarStatusTheme.statusStyle(status, brightness);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space2),
      child: Row(
        children: [
          Container(
            width: 14,
            height: 14,
            decoration: AppointmentCalendarStatusSwatch.decoration(style, radius: AppRadius.sm),
          ),
          const SizedBox(width: AppSpacing.space2),
          Expanded(child: Text(status.label, style: AppTypography.bodySm(context))),
        ],
      ),
    );
  }
}
