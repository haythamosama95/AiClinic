import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_queue_start_doctor.dart';

/// Doctor picker shown before starting a checked-in appointment.
class AppointmentStartDoctorDialog extends StatefulWidget {
  const AppointmentStartDoctorDialog({required this.options, super.key});

  final List<QueueStartDoctorOption> options;

  static Future<String?> show(
    BuildContext context, {
    required List<QueueStartDoctorOption> options,
  }) {
    return AppDialog.show<String?>(
      context,
      title: 'Who will see this patient?',
      description: 'Choose the doctor taking this visit before you start.',
      size: AppDialogSize.sm,
      barrierDismissible: false,
      child: AppointmentStartDoctorDialog(options: options),
    );
  }

  @override
  State<AppointmentStartDoctorDialog> createState() =>
      _AppointmentStartDoctorDialogState();
}

class _AppointmentStartDoctorDialogState
    extends State<AppointmentStartDoctorDialog> {
  String? _selectedDoctorId;

  @override
  void initState() {
    super.initState();
    final available = widget.options
        .where((option) => !option.isBusy)
        .toList(growable: false);
    final preferred = available
        .where((option) => option.isPreferred)
        .firstOrNull;
    _selectedDoctorId = preferred?.id ?? available.firstOrNull?.id;
  }

  void _confirm() {
    Navigator.of(context).pop(_selectedDoctorId);
  }

  @override
  Widget build(BuildContext context) {
    final availableOptions = widget.options
        .where((option) => !option.isBusy)
        .toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (availableOptions.isEmpty)
          const AppEmptyState(
            variant: AppEmptyStateVariant.error,
            title: 'No doctors available',
            description:
                'Every doctor on shift already has a patient in progress.',
          )
        else
          AppRadioGroup(
            value: _selectedDoctorId ?? '',
            onChanged: (doctorId) =>
                setState(() => _selectedDoctorId = doctorId),
            options: [
              for (final option in availableOptions)
                AppRadioOption(
                  value: option.id,
                  label: option.isPreferred
                      ? '${option.name} (preferred)'
                      : option.name,
                ),
            ],
          ),
        const SizedBox(height: AppSpacing.space4),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            AppButton(
              variant: AppButtonVariant.secondary,
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            const SizedBox(width: AppSpacing.space2),
            AppButton(
              disabled: _selectedDoctorId == null || availableOptions.isEmpty,
              onPressed: _confirm,
              child: const Text('Start visit'),
            ),
          ],
        ),
      ],
    );
  }
}
