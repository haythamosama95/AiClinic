import 'package:ai_clinic/core/ui/theme/theme.dart';
import 'package:ai_clinic/features/appointments/domain/simplified_booking_slot.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Duration-sized time block grid for simplified booking (011).
class SimplifiedTimeBlockGrid extends StatefulWidget {
  const SimplifiedTimeBlockGrid({
    required this.slots,
    required this.onSlotTap,
    this.selectedStart,
    this.onAlternateSlotTap,
    this.collapsedSlotCount = 8,
    super.key,
  });

  final List<SimplifiedBookingSlot> slots;
  final DateTime? selectedStart;
  final ValueChanged<SimplifiedBookingSlot> onSlotTap;
  final ValueChanged<SimplifiedBookingSlot>? onAlternateSlotTap;
  final int collapsedSlotCount;

  @override
  State<SimplifiedTimeBlockGrid> createState() => _SimplifiedTimeBlockGridState();
}

class _SimplifiedTimeBlockGridState extends State<SimplifiedTimeBlockGrid> {
  bool _expanded = false;

  @override
  void didUpdateWidget(covariant SimplifiedTimeBlockGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.slots != widget.slots) {
      _expanded = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final slots = widget.slots;
    if (slots.isEmpty) {
      return Text('No slots available for this day.', style: Theme.of(context).textTheme.bodyMedium);
    }

    final visibleSlots = _expanded ? slots : slots.take(widget.collapsedSlotCount).toList();
    final hiddenCount = slots.length - visibleSlots.length;
    final availableCount = slots.where((slot) => slot.state == SlotAvailabilityState.available).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: SpacingTokens.sm,
          runSpacing: SpacingTokens.sm,
          children: [
            for (final slot in visibleSlots)
              _TimeBlockChip(slot: slot, isSelected: _isSelected(slot), onTap: () => _handleTap(slot)),
          ],
        ),
        if (!_expanded && hiddenCount > 0) ...[
          const SizedBox(height: SpacingTokens.md),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              key: const Key('simplified_time_block_show_more'),
              onPressed: () => setState(() => _expanded = true),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Show more slots'),
                  Text(
                    '$availableCount available',
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: context.semanticColors.mutedForeground),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  void _handleTap(SimplifiedBookingSlot slot) {
    switch (slot.state) {
      case SlotAvailabilityState.available:
        widget.onSlotTap(slot);
      case SlotAvailabilityState.alternateDoctorsAvailable:
        widget.onAlternateSlotTap?.call(slot);
      case SlotAvailabilityState.fullyUnavailable:
      case SlotAvailabilityState.past:
        break;
    }
  }

  bool _isSelected(SimplifiedBookingSlot slot) {
    final selected = widget.selectedStart;
    if (selected == null) {
      return false;
    }
    return slot.startTime.toLocal().isAtSameMomentAs(selected.toLocal());
  }
}

class _TimeBlockChip extends StatelessWidget {
  const _TimeBlockChip({required this.slot, required this.isSelected, required this.onTap});

  final SimplifiedBookingSlot slot;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.semanticColors;
    final theme = Theme.of(context);
    final timeLabel = DateFormat.Hm().format(slot.startTime.toLocal());
    final semanticsLabel = _semanticsLabel(timeLabel, slot.state, isSelected);
    final style = _chipStyle(colors, slot.state, isSelected);

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
            padding: const EdgeInsets.symmetric(horizontal: SpacingTokens.md, vertical: SpacingTokens.sm),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(context.shapeTokens.md),
              border: Border.all(color: style.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (style.showLock) ...[
                  Icon(Icons.lock_outline, size: 14, color: style.foreground),
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
    );
  }

  static String _semanticsLabel(String timeLabel, SlotAvailabilityState state, bool isSelected) {
    final stateLabel = switch (state) {
      SlotAvailabilityState.available => 'available',
      SlotAvailabilityState.alternateDoctorsAvailable => 'locked, other doctors available',
      SlotAvailabilityState.fullyUnavailable => 'unavailable',
      SlotAvailabilityState.past => 'past',
    };
    if (isSelected) {
      return '$timeLabel, selected, $stateLabel';
    }
    return '$timeLabel, $stateLabel';
  }
}

class _ChipStyle {
  const _ChipStyle({required this.background, required this.foreground, required this.border, required this.showLock});

  final Color background;
  final Color foreground;
  final Color border;
  final bool showLock;
}

_ChipStyle _chipStyle(SemanticColors colors, SlotAvailabilityState state, bool isSelected) {
  if (isSelected) {
    return _ChipStyle(
      background: colors.primary,
      foreground: colors.primaryForeground,
      border: colors.primary,
      showLock: false,
    );
  }

  return switch (state) {
    SlotAvailabilityState.available => _ChipStyle(
      background: colors.card,
      foreground: colors.foreground,
      border: colors.border,
      showLock: false,
    ),
    SlotAvailabilityState.alternateDoctorsAvailable => _ChipStyle(
      background: colors.accent.withValues(alpha: 0.35),
      foreground: colors.foreground,
      border: colors.accent.withValues(alpha: 0.5),
      showLock: true,
    ),
    SlotAvailabilityState.fullyUnavailable => _ChipStyle(
      background: colors.muted,
      foreground: colors.mutedForeground,
      border: colors.border,
      showLock: true,
    ),
    SlotAvailabilityState.past => _ChipStyle(
      background: colors.muted.withValues(alpha: 0.65),
      foreground: colors.mutedForeground,
      border: colors.border,
      showLock: true,
    ),
  };
}
