import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_calendar/calendar.dart';

import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_calendar_display.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_list_item.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/appointment_calendar_status_swatch.dart';

/// Appointment card rendered inside Syncfusion [SfCalendar.appointmentBuilder].
///
/// Status fill matches [AppointmentCalendarColorLegendButton] swatches. Patient name
/// is centered vertically within the slot.
class AppointmentCalendarTile extends StatelessWidget {
  const AppointmentCalendarTile({
    required this.details,
    required this.item,
    required this.isDimmed,
    required this.onTap,
    super.key,
  });

  final CalendarAppointmentDetails details;
  final AppointmentListItem? item;
  final bool isDimmed;
  final VoidCallback onTap;

  static const _compactHeightThreshold = 28.0;

  @override
  Widget build(BuildContext context) {
    final appointment = details.appointments.first;
    final bounds = details.bounds;
    final statusColor = appointment.color;
    final textColor = AppointmentCalendarStatusSwatch.textOn(statusColor);
    final isCompact = bounds.height < _compactHeightThreshold;

    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: bounds.width,
        height: bounds.height,
        child: Opacity(
          opacity: isDimmed ? AppointmentCalendarDisplay.filteredOutOpacity : 1,
          child: DecoratedBox(
            decoration: AppointmentCalendarStatusSwatch.decoration(statusColor),
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
                    child: ColoredBox(color: Colors.white.withValues(alpha: 0.22)),
                  ),
                  Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: isCompact ? AppSpacing.space1 : AppSpacing.space2,
                      vertical: isCompact ? 2 : AppSpacing.space1,
                    ),
                    child: SelectionContainer.disabled(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            appointment.subject,
                            maxLines: isCompact ? 1 : 2,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.caption(context).copyWith(
                              color: textColor,
                              fontWeight: FontWeight.w600,
                              height: 1.15,
                              decoration: TextDecoration.none,
                            ),
                          ),
                        ],
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
  }
}
