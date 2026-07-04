import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/ui.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_queue_start_doctor.dart';

/// Prompts staff to choose which doctor will take the appointment when it starts.
Future<String?> showQueueShiftDoctorPickerDialog(
  BuildContext context, {
  required List<QueueStartDoctorOption> options,
}) {
  final available = options.where((option) => !option.isBusy).toList(growable: false);
  if (available.isEmpty) {
    return Future.value();
  }

  final preferredOption = _preferredOption(options);
  final preferredBusy = preferredOption != null && preferredOption.isBusy;
  final message = _messageFor(
    options: options,
    preferredOption: preferredOption,
    preferredBusy: preferredBusy,
  );

  return showAppDialog<String>(
    context,
    size: AppDialogSize.sm,
    barrierDismissible: false,
    semanticLabel: 'Confirm doctor',
    builder: (dialogContext, close) {
      return _QueueShiftDoctorPickerDialogContent(
        options: options,
        message: message,
        onClose: () => close(),
        onConfirm: (doctorId) => close(doctorId),
      );
    },
  );
}

QueueStartDoctorOption? _preferredOption(List<QueueStartDoctorOption> options) {
  for (final option in options) {
    if (option.isPreferred) {
      return option;
    }
  }
  return null;
}

String _messageFor({
  required List<QueueStartDoctorOption> options,
  required QueueStartDoctorOption? preferredOption,
  required bool preferredBusy,
}) {
  if (preferredOption == null) {
    if (options.length == 1) {
      return 'Confirm which doctor will see this patient.';
    }
    return 'Multiple doctors are on shift. Select who will see this patient.';
  }

  final preferredName = preferredOption.name;
  if (preferredBusy) {
    final availableCount = options.where((option) => !option.isBusy).length;
    if (availableCount == 1) {
      return '$preferredName is the preferred doctor but is currently busy. '
          'Another doctor is available — select who will see this patient.';
    }
    return '$preferredName is the preferred doctor but is currently busy. '
        'Other doctors are available — select who will see this patient.';
  }

  if (options.where((option) => !option.isBusy).length == 1) {
    return '$preferredName is the preferred doctor for this appointment. Confirm or choose another doctor.';
  }
  return '$preferredName is the preferred doctor for this appointment. '
      'Confirm or choose another doctor to start the visit.';
}

class _QueueShiftDoctorPickerDialogContent extends StatefulWidget {
  const _QueueShiftDoctorPickerDialogContent({
    required this.options,
    required this.message,
    required this.onClose,
    required this.onConfirm,
  });

  final List<QueueStartDoctorOption> options;
  final String message;
  final VoidCallback onClose;
  final ValueChanged<String> onConfirm;

  @override
  State<_QueueShiftDoctorPickerDialogContent> createState() => _QueueShiftDoctorPickerDialogContentState();
}

class _QueueShiftDoctorPickerDialogContentState extends State<_QueueShiftDoctorPickerDialogContent> {
  String? _selectedDoctorId;

  List<QueueStartDoctorOption> get _availableOptions =>
      widget.options.where((option) => !option.isBusy).toList(growable: false);

  @override
  void initState() {
    super.initState();
    final available = _availableOptions;
    final preferredAvailable = available.where((option) => option.isPreferred).toList(growable: false);
    if (preferredAvailable.length == 1) {
      _selectedDoctorId = preferredAvailable.first.id;
      return;
    }
    if (available.length == 1) {
      _selectedDoctorId = available.first.id;
    }
  }

  @override
  Widget build(BuildContext context) {
    final typography = context.typography;

    return AppDialog(
      title: 'Confirm doctor',
      onClose: widget.onClose,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.message, style: typography.body),
          const SizedBox(height: AppSpacing.s4),
          AppRadioGroup<String>(
            value: _selectedDoctorId,
            semanticLabel: 'Doctor on shift',
            onChanged: (doctorId) => setState(() => _selectedDoctorId = doctorId),
            options: [
              for (final option in widget.options)
                AppRadioOption(
                  value: option.id,
                  label: option.isBusy
                      ? '${option.name} (busy)'
                      : option.isPreferred
                      ? '${option.name} (preferred)'
                      : option.name,
                  disabled: option.isBusy,
                ),
            ],
          ),
        ],
      ),
      footer: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          AppButton(
            label: 'Cancel',
            variant: AppButtonVariant.secondary,
            onPressed: widget.onClose,
          ),
          const SizedBox(width: AppSpacing.s2),
          AppButton(
            label: 'Start visit',
            onPressed: _selectedDoctorId == null ? null : () => widget.onConfirm(_selectedDoctorId!),
          ),
        ],
      ),
    );
  }
}
