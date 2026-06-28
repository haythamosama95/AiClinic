import 'package:ai_clinic/core/ui/theme/theme.dart';
import 'package:ai_clinic/features/appointments/domain/simplified_booking_slot.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/simplified_slot_chip_style.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Duration-sized time block grid for simplified booking (011).
class SimplifiedTimeBlockGrid extends StatelessWidget {
  const SimplifiedTimeBlockGrid({
    required this.slots,
    required this.onSlotTap,
    this.selectedStart,
    this.onAlternateSlotTap,
    this.hideFullyBooked = false,
    this.collapsedSlotCount = 8,
    this.crossAxisCount = 4,
    super.key,
  });

  static const _rowExtent = 40.0;
  static const _animationDuration = Duration(milliseconds: 250);

  final List<SimplifiedBookingSlot> slots;
  final DateTime? selectedStart;
  final ValueChanged<SimplifiedBookingSlot> onSlotTap;
  final ValueChanged<SimplifiedBookingSlot>? onAlternateSlotTap;
  final bool hideFullyBooked;
  final int collapsedSlotCount;
  final int crossAxisCount;

  List<SimplifiedBookingSlot> _visibleSlots(List<SimplifiedBookingSlot> slots) {
    if (!hideFullyBooked) {
      return slots;
    }
    return [
      for (final slot in slots)
        if (slot.state != SlotAvailabilityState.fullyUnavailable) slot,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final slots = this.slots;
    if (slots.isEmpty) {
      return Text('No slots available for this day.', style: Theme.of(context).textTheme.bodyMedium);
    }

    final visibleSlots = _visibleSlots(slots);
    if (visibleSlots.isEmpty) {
      return Text('No bookable slots for this day.', style: Theme.of(context).textTheme.bodyMedium);
    }

    final rowCount = (visibleSlots.length / crossAxisCount).ceil();
    final maxRows = (collapsedSlotCount / crossAxisCount).ceil();
    final viewportRows = rowCount > maxRows ? maxRows : rowCount;
    final gridHeight = viewportRows * _rowExtent + (viewportRows - 1) * SpacingTokens.sm;
    final gridKey = ValueKey('grid-${visibleSlots.length}-$hideFullyBooked');

    return AnimatedSize(
      duration: _animationDuration,
      curve: Curves.easeInOut,
      alignment: Alignment.topCenter,
      clipBehavior: Clip.hardEdge,
      child: AnimatedSwitcher(
        duration: _animationDuration,
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeIn,
        transitionBuilder: (child, animation) => FadeTransition(opacity: animation, child: child),
        child: SizedBox(
          key: gridKey,
          height: gridHeight,
          child: GridView.builder(
            key: const Key('simplified_time_block_grid'),
            physics: rowCount > maxRows ? const ClampingScrollPhysics() : const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              crossAxisSpacing: SpacingTokens.sm,
              mainAxisSpacing: SpacingTokens.sm,
              mainAxisExtent: _rowExtent,
            ),
            itemCount: visibleSlots.length,
            itemBuilder: (context, index) {
              final slot = visibleSlots[index];
              return _TimeBlockChip(
                key: ValueKey('slot-${slot.startTime.toIso8601String()}'),
                slot: slot,
                isSelected: _isSelected(slot),
                onTap: () => _handleTap(slot),
              );
            },
          ),
        ),
      ),
    );
  }

  void _handleTap(SimplifiedBookingSlot slot) {
    switch (slot.state) {
      case SlotAvailabilityState.available:
        onSlotTap(slot);
      case SlotAvailabilityState.alternateDoctorsAvailable:
        onAlternateSlotTap?.call(slot);
      case SlotAvailabilityState.fullyUnavailable:
      case SlotAvailabilityState.past:
        break;
    }
  }

  bool _isSelected(SimplifiedBookingSlot slot) {
    final selected = selectedStart;
    if (selected == null) {
      return false;
    }
    return slot.startTime.toLocal().isAtSameMomentAs(selected.toLocal());
  }
}

class _TimeBlockChip extends StatelessWidget {
  const _TimeBlockChip({required this.slot, required this.isSelected, required this.onTap, super.key});

  final SimplifiedBookingSlot slot;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.semanticColors;
    final theme = Theme.of(context);
    final timeLabel = DateFormat.jm().format(slot.startTime.toLocal());
    final semanticsLabel = _semanticsLabel(timeLabel, slot.state, isSelected);
    final style = SimplifiedSlotChipStyle.forState(colors, slot.state, isSelected: isSelected);

    return Semantics(
      button: true,
      selected: isSelected,
      label: semanticsLabel,
      child: Material(
        color: style.background,
        borderRadius: BorderRadius.circular(context.shapeTokens.md),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(context.shapeTokens.md),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: SpacingTokens.sm, vertical: SpacingTokens.sm),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(context.shapeTokens.md),
              border: Border.all(color: style.border),
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (style.leadingIcon != null) ...[
                    Icon(style.leadingIcon, size: 14, color: style.foreground),
                    const SizedBox(width: SpacingTokens.xs),
                  ],
                  Text(
                    timeLabel,
                    style: theme.textTheme.labelLarge?.copyWith(color: style.foreground, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static String _semanticsLabel(String timeLabel, SlotAvailabilityState state, bool isSelected) {
    final stateLabel = switch (state) {
      SlotAvailabilityState.available => 'available',
      SlotAvailabilityState.alternateDoctorsAvailable => 'other doctors available',
      SlotAvailabilityState.fullyUnavailable => 'fully booked',
      SlotAvailabilityState.past => 'past',
    };
    if (isSelected) {
      return '$timeLabel, selected, $stateLabel';
    }
    return '$timeLabel, $stateLabel';
  }
}
