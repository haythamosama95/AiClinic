import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Minutes duration input with optional end-time preview (V1-4 booking forms).
class DurationField extends StatelessWidget {
  const DurationField({
    required this.controller,
    required this.startTime,
    required this.minMinutes,
    required this.maxMinutes,
    this.enabled = true,
    this.onChanged,
    super.key,
  });

  final TextEditingController controller;
  final DateTime? startTime;
  final int minMinutes;
  final int maxMinutes;
  final bool enabled;
  final ValueChanged<int?>? onChanged;

  int? get _parsedMinutes => int.tryParse(controller.text.trim());

  DateTime? get _previewEnd {
    final minutes = _parsedMinutes;
    final start = startTime;
    if (minutes == null || start == null) {
      return null;
    }
    return start.add(Duration(minutes: minutes));
  }

  @override
  Widget build(BuildContext context) {
    final previewEnd = _previewEnd;
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          controller: controller,
          enabled: enabled,
          decoration: InputDecoration(
            labelText: 'Duration (minutes)',
            helperText: 'Between $minMinutes and $maxMinutes minutes',
          ),
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          validator: (value) {
            final minutes = int.tryParse(value?.trim() ?? '');
            if (minutes == null) {
              return 'Enter duration in minutes.';
            }
            if (minutes < minMinutes || minutes > maxMinutes) {
              return 'Duration must be between $minMinutes and $maxMinutes minutes.';
            }
            return null;
          },
          onChanged: (_) => onChanged?.call(_parsedMinutes),
        ),
        if (previewEnd != null) ...[
          const SizedBox(height: 8),
          Text(
            'Ends at ${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(previewEnd.toLocal()))}',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ],
    );
  }
}
