import 'package:flutter/material.dart';

/// Confirmation dialog before soft-cancelling a shift (V1-7 US4).
Future<bool> showCancelShiftDialog({
  required BuildContext context,
  required DateTime shiftDate,
  required String startTime,
  required String endTime,
}) {
  final dateLabel = MaterialLocalizations.of(context).formatFullDate(shiftDate);

  return showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      key: const Key('cancel_shift_dialog'),
      title: const Text('Cancel shift?'),
      content: Text(
        'Cancel the shift on $dateLabel ($startTime–$endTime)? '
        'It will be removed from the calendar but kept in audit history.',
      ),
      actions: [
        TextButton(
          key: const Key('cancel_shift_dialog_dismiss'),
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Keep shift'),
        ),
        FilledButton(
          key: const Key('cancel_shift_dialog_confirm'),
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Cancel shift'),
        ),
      ],
    ),
  ).then((value) => value ?? false);
}
