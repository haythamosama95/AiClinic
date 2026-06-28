import 'package:ai_clinic/core/ui/theme/theme.dart';
import 'package:ai_clinic/features/appointments/domain/simplified_booking_slot.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/simplified_slot_chip_style.dart';
import 'package:flutter/material.dart';

/// Explains simplified booking slot chip styles (011).
class SimplifiedSlotLegend extends StatelessWidget {
  const SimplifiedSlotLegend({this.showAlternateDoctors = true, super.key});

  final bool showAlternateDoctors;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.semanticColors;
    final labelStyle = theme.textTheme.bodySmall;

    return Center(
      child: Wrap(
        key: const Key('simplified_slot_legend'),
        alignment: WrapAlignment.center,
        spacing: SpacingTokens.md,
        runSpacing: SpacingTokens.sm,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _LegendSwatch(
            style: SimplifiedSlotChipStyle.forState(colors, SlotAvailabilityState.available),
            label: 'Available',
            labelStyle: labelStyle,
          ),
          if (showAlternateDoctors)
            _LegendSwatch(
              style: SimplifiedSlotChipStyle.forState(colors, SlotAvailabilityState.alternateDoctorsAvailable),
              label: 'Other doctors free',
              labelStyle: labelStyle,
            ),
          _LegendSwatch(
            style: SimplifiedSlotChipStyle.forState(colors, SlotAvailabilityState.fullyUnavailable),
            label: 'Fully booked',
            labelStyle: labelStyle,
          ),
        ],
      ),
    );
  }
}

class _LegendSwatch extends StatelessWidget {
  const _LegendSwatch({required this.style, required this.label, required this.labelStyle});

  final SimplifiedSlotChipStyle style;
  final String label;
  final TextStyle? labelStyle;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 28,
          height: 20,
          decoration: BoxDecoration(
            color: style.background,
            borderRadius: BorderRadius.circular(context.shapeTokens.sm),
            border: Border.all(color: style.border),
          ),
          child: style.leadingIcon == null
              ? null
              : Center(child: Icon(style.leadingIcon, size: 12, color: style.foreground)),
        ),
        const SizedBox(width: SpacingTokens.xs),
        Text(label, style: labelStyle),
      ],
    );
  }
}
