import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/ui.dart';
import 'package:ai_clinic/features/shifts/presentation/utils/shift_presentation_formatting.dart';

/// Confirmation dialog before soft-cancelling a shift (V1-7 US4).
Future<bool> showCancelShiftDialog({
  required BuildContext context,
  required DateTime shiftDate,
  required String startTime,
  required String endTime,
}) {
  final dateLabel = ShiftPresentationFormatting.formatDate(shiftDate);
  final timeLabel = ShiftPresentationFormatting.formatTimeRange(startTime, endTime);

  return showAppConfirmationDialog(
    context,
    title: 'Cancel shift?',
    message:
        'Cancel the shift on $dateLabel ($timeLabel)? '
        'It will be removed from the calendar but kept in audit history.',
    confirmLabel: 'Cancel shift',
    cancelLabel: 'Keep shift',
    destructive: true,
  );
}
