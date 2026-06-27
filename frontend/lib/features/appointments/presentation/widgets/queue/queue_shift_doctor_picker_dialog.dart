import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import 'package:ai_clinic/core/ui/theme/semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/spacing_tokens.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_queue_start_doctor.dart';

/// Prompts staff to choose which doctor will take the appointment when it starts.
class QueueShiftDoctorPickerDialog extends StatefulWidget {
  static Future<String?> show(BuildContext context, {required List<QueueStartDoctorOption> options}) {
    final available = options.where((option) => !option.isBusy).toList(growable: false);
    if (available.isEmpty) {
      return Future.value();
    }

    final preferredOption = _preferredOption(options);
    final preferredBusy = preferredOption != null && preferredOption.isBusy;
    const title = 'Confirm doctor';
    final message = _messageFor(options: options, preferredOption: preferredOption, preferredBusy: preferredBusy);

    return AppDialog.show<String>(
      context: context,
      title: title,
      barrierDismissible: false,
      body: QueueShiftDoctorPickerDialog(options: options, message: message),
      actions: const [],
    );
  }

  static QueueStartDoctorOption? _preferredOption(List<QueueStartDoctorOption> options) {
    for (final option in options) {
      if (option.isPreferred) {
        return option;
      }
    }
    return null;
  }

  static String _messageFor({
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
        return '$preferredName is the preferred doctor but is currently busy. Another doctor is available — select who will see this patient.';
      }
      return '$preferredName is the preferred doctor but is currently busy. Other doctors are available — select who will see this patient.';
    }

    if (options.where((option) => !option.isBusy).length == 1) {
      return '$preferredName is the preferred doctor for this appointment. Confirm or choose another doctor.';
    }
    return '$preferredName is the preferred doctor for this appointment. Confirm or choose another doctor to start the visit.';
  }

  final List<QueueStartDoctorOption> options;
  final String? message;

  const QueueShiftDoctorPickerDialog({required this.options, this.message, super.key});

  @override
  State<QueueShiftDoctorPickerDialog> createState() => _QueueShiftDoctorPickerDialogState();
}

class _QueueShiftDoctorPickerDialogState extends State<QueueShiftDoctorPickerDialog> {
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
    final theme = Theme.of(context);
    final colors = context.semanticColors;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(widget.message ?? 'Select who will see this patient.', style: theme.textTheme.bodyMedium),
        const SizedBox(height: SpacingTokens.md),
        ...[
          for (final option in widget.options) ...[
            _DoctorOptionTile(
              option: option,
              groupValue: _selectedDoctorId,
              onChanged: option.isBusy ? null : (doctorId) => setState(() => _selectedDoctorId = doctorId),
            ),
            if (option != widget.options.last) Divider(height: 1, color: colors.border),
          ],
        ],
        const SizedBox(height: SpacingTokens.md),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            AppButton(
              label: 'Cancel',
              variant: AppButtonVariant.secondary,
              expand: false,
              onPressed: () => Navigator.of(context).pop(),
            ),
            const SizedBox(width: SpacingTokens.sm),
            AppButton(
              label: 'Start visit',
              expand: false,
              onPressed: _selectedDoctorId == null ? null : () => Navigator.of(context).pop(_selectedDoctorId),
            ),
          ],
        ),
      ],
    );
  }
}

class _DoctorOptionTile extends StatelessWidget {
  const _DoctorOptionTile({required this.option, required this.groupValue, required this.onChanged});

  final QueueStartDoctorOption option;
  final String? groupValue;
  final ValueChanged<String?>? onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.semanticColors;
    final theme = Theme.of(context).textTheme;
    final availabilityLabel = option.isBusy ? 'Busy — patient in progress' : 'Available';
    final subtitle = option.isPreferred ? 'Preferred · $availabilityLabel' : availabilityLabel;
    final selected = groupValue == option.id;
    final enabled = !option.isBusy;

    return FTile(
      prefix: Icon(
        selected ? Icons.radio_button_checked : Icons.radio_button_off,
        color: enabled
            ? (selected ? colors.primary : colors.mutedForeground)
            : colors.mutedForeground.withValues(alpha: 0.5),
      ),
      title: Text(
        option.name,
        style: theme.bodyMedium?.copyWith(fontWeight: FontWeight.w600, color: enabled ? null : colors.mutedForeground),
      ),
      subtitle: Text(
        subtitle,
        style: theme.bodySmall?.copyWith(
          color: option.isBusy ? colors.destructive : const Color(0xFF059669),
          fontWeight: FontWeight.w600,
        ),
      ),
      selected: selected,
      enabled: enabled,
      onPress: enabled && onChanged != null ? () => onChanged!(option.id) : null,
    );
  }
}
