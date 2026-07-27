import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:syncfusion_flutter_calendar/calendar.dart';

import 'package:ai_clinic/core/ui/components/app_menu.dart';
import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';
import 'package:ai_clinic/features/appointments/presentation/theme/appointment_calendar_status_theme.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_calendar_period.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_list_item.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/appointment_calendar_status_swatch.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/appointment_status_chip.dart';

/// Appointment card rendered inside Syncfusion [SfCalendar.appointmentBuilder].
///
/// Day, month agenda, and schedule views use a horizontal encounter strip with
/// time, patient, doctor, and status. Week and doctor timeline views keep the
/// compact vertical tile.
class AppointmentCalendarTile extends StatelessWidget {
  const AppointmentCalendarTile({
    required this.details,
    required this.item,
    required this.mode,
    required this.isDimmed,
    required this.onTap,
    this.contextMenuEntries,
    super.key,
  });

  final CalendarAppointmentDetails details;
  final AppointmentListItem? item;
  final AppointmentCalendarMode mode;
  final bool isDimmed;
  final VoidCallback onTap;
  final List<AppMenuEntry>? contextMenuEntries;

  static const _compactHeightThreshold = 28.0;
  static const _minContentHeight = 14.0;
  static const _horizontalMinHeight = 36.0;
  static const _horizontalFullWidth = 220.0;
  static const _horizontalMediumWidth = 120.0;
  static const _horizontalMediumWithStatusWidth = 196.0;
  static final _timeFormat = DateFormat('HH:mm');

  bool get _usesHorizontalLayout => switch (mode) {
    AppointmentCalendarMode.day => true,
    AppointmentCalendarMode.month => true,
    AppointmentCalendarMode.schedule => true,
    _ => false,
  };

  @override
  Widget build(BuildContext context) {
    final appointment = details.appointments.first;
    final bounds = details.bounds;
    final brightness = Theme.of(context).brightness;
    final status = item?.status ?? AppointmentStatus.unknown;
    final style = isDimmed
        ? AppointmentCalendarStatusTheme.filteredOutStyle(brightness)
        : AppointmentCalendarStatusTheme.statusStyle(status, brightness);
    final textColor = style.text;
    final mutedTextColor = style.textMuted;
    final isCompact = bounds.height < _compactHeightThreshold;
    final hasRoomForContent = bounds.height >= _minContentHeight;

    final tile = GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: bounds.width,
        height: bounds.height,
        child: Opacity(
          opacity: isDimmed ? AppointmentCalendarStatusTheme.filteredOutOpacity : 1,
          child: DecoratedBox(
            decoration: AppointmentCalendarStatusSwatch.decoration(style),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.md - 1),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 0,
                    height: 1,
                    child: ColoredBox(color: AppointmentCalendarStatusSwatch.highlightSheen(brightness)),
                  ),
                  if (hasRoomForContent)
                    if (_usesHorizontalLayout)
                      _HorizontalEncounterStrip(
                        appointment: appointment,
                        item: item,
                        bounds: bounds,
                        accentColor: style.accent,
                        textColor: textColor,
                        mutedTextColor: mutedTextColor,
                      )
                    else
                      Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: isCompact ? AppSpacing.space1 : AppSpacing.space2,
                          vertical: isCompact ? 1 : AppSpacing.space1,
                        ),
                        child: SelectionContainer.disabled(
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              appointment.subject,
                              maxLines: isCompact ? 1 : 2,
                              overflow: TextOverflow.ellipsis,
                              style: AppTypography.caption(context).copyWith(
                                color: textColor,
                                fontWeight: FontWeight.w600,
                                height: 1.0,
                                decoration: TextDecoration.none,
                              ),
                            ),
                          ),
                        ),
                      ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    final entries = contextMenuEntries;
    if (entries == null || entries.isEmpty) {
      return tile;
    }

    return AppContextMenu(entries: entries, child: tile);
  }
}

class _HorizontalEncounterStrip extends StatelessWidget {
  const _HorizontalEncounterStrip({
    required this.appointment,
    required this.item,
    required this.bounds,
    required this.accentColor,
    required this.textColor,
    required this.mutedTextColor,
  });

  final Appointment appointment;
  final AppointmentListItem? item;
  final Rect bounds;
  final Color accentColor;
  final Color textColor;
  final Color mutedTextColor;

  bool get _isTightHeight => bounds.height < AppointmentCalendarTile._horizontalMinHeight;

  /// Width available to the encounter strip after the accent bar and padding.
  double get _contentWidth {
    final accentWidth = _isTightHeight ? 2.0 : 3.0;
    final horizontalPadding = _isTightHeight ? AppSpacing.space1 * 2 : AppSpacing.space2 * 2;
    return (bounds.width - accentWidth - horizontalPadding).clamp(0.0, double.infinity);
  }

  bool get _showFullStrip => _contentWidth >= AppointmentCalendarTile._horizontalFullWidth;
  bool get _showMediumStrip =>
      _contentWidth >= AppointmentCalendarTile._horizontalMediumWidth &&
      bounds.height >= AppointmentCalendarTile._horizontalMinHeight;
  bool get _showStatusInMediumStrip =>
      _contentWidth >= AppointmentCalendarTile._horizontalMediumWithStatusWidth;

  String get _patientName => item?.patientName ?? appointment.subject;
  String get _doctorName => item?.doctorDisplayName ?? appointment.notes ?? 'Unassigned';
  AppointmentStatus get _status => item?.status ?? AppointmentStatus.unknown;

  String get _timeRangeLabel {
    final start = appointment.startTime.toLocal();
    final end = appointment.endTime.toLocal();
    return '${AppointmentCalendarTile._timeFormat.format(start)}–${AppointmentCalendarTile._timeFormat.format(end)}';
  }

  @override
  Widget build(BuildContext context) {
    return SelectionContainer.disabled(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: _isTightHeight ? 2 : 3,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [accentColor.withValues(alpha: 0.85), accentColor],
                ),
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: _isTightHeight ? AppSpacing.space1 : AppSpacing.space2,
                vertical: _isTightHeight ? 2 : AppSpacing.space1,
              ),
              child: _showFullStrip
                  ? _buildFullStrip(context)
                  : _showMediumStrip
                  ? _buildMediumStrip(context)
                  : _buildCompactStrip(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFullStrip(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _TimeBlock(label: _timeRangeLabel, textColor: textColor),
        _StripDivider(color: mutedTextColor),
        Expanded(
          flex: 3,
          child: _LabeledStripSection(icon: Icons.person_outline, label: _patientName, textColor: textColor),
        ),
        _StripDivider(color: mutedTextColor),
        Expanded(
          flex: 2,
          child: _LabeledStripSection(
            icon: Icons.medical_services_outlined,
            label: _doctorName,
            textColor: mutedTextColor,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(width: AppSpacing.space2),
        AppointmentStatusChip(status: _status, textColor: textColor),
      ],
    );
  }

  Widget _buildMediumStrip(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Flexible(
          flex: 2,
          child: _TimeBlock(label: _timeRangeLabel, textColor: textColor, compact: true),
        ),
        const SizedBox(width: AppSpacing.space2),
        Expanded(
          flex: 3,
          child: _LabeledStripSection(
            icon: Icons.person_outline,
            label: _patientName,
            textColor: textColor,
            compact: true,
          ),
        ),
        if (_showStatusInMediumStrip) ...[
          const SizedBox(width: AppSpacing.space2),
          AppointmentStatusChip(status: _status, textColor: textColor, compact: true),
        ],
      ],
    );
  }

  Widget _buildCompactStrip(BuildContext context) {
    return _LabeledStripSection(icon: Icons.person_outline, label: _patientName, textColor: textColor, compact: true);
  }
}

class _TimeBlock extends StatelessWidget {
  const _TimeBlock({required this.label, required this.textColor, this.compact = false});

  final String label;
  final Color textColor;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final iconSize = compact ? 12.0 : 14.0;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.schedule_outlined, size: iconSize, color: textColor.withValues(alpha: 0.88)),
        const SizedBox(width: AppSpacing.space1),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.mono(context).copyWith(
            color: textColor,
            fontWeight: FontWeight.w600,
            fontSize: compact ? 12 : 13,
            fontFeatures: const [FontFeature.tabularFigures()],
            height: 1.15,
            decoration: TextDecoration.none,
          ),
        ),
        ),
      ],
    );
  }
}

class _LabeledStripSection extends StatelessWidget {
  const _LabeledStripSection({
    required this.icon,
    required this.label,
    required this.textColor,
    this.fontWeight = FontWeight.w600,
    this.compact = false,
  });

  final IconData icon;
  final String label;
  final Color textColor;
  final FontWeight fontWeight;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final iconSize = compact ? 12.0 : 14.0;

    return Row(
      children: [
        Icon(icon, size: iconSize, color: textColor.withValues(alpha: 0.88)),
        const SizedBox(width: AppSpacing.space1),
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.caption(
              context,
            ).copyWith(color: textColor, fontWeight: fontWeight, height: 1.15, decoration: TextDecoration.none),
          ),
        ),
      ],
    );
  }
}

class _StripDivider extends StatelessWidget {
  const _StripDivider({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space2),
      child: SizedBox(width: 1, child: ColoredBox(color: color.withValues(alpha: 0.35))),
    );
  }
}
