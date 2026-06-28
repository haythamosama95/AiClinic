import 'package:ai_clinic/core/ui/theme/theme.dart';
import 'package:ai_clinic/features/appointments/domain/simplified_booking_slot.dart';
import 'package:flutter/material.dart';

/// Visual style for simplified booking slot chips and legend swatches (011).
class SimplifiedSlotChipStyle {
  const SimplifiedSlotChipStyle({
    required this.background,
    required this.foreground,
    required this.border,
    this.leadingIcon,
  });

  final Color background;
  final Color foreground;
  final Color border;
  final IconData? leadingIcon;

  static const _availableGreen = Color(0xFF16A34A);
  static const _availableForeground = Color(0xFF166534);
  static const _semiAvailableYellow = Color(0xFFEAB308);
  static const _semiAvailableForeground = Color(0xFF92400E);

  static SimplifiedSlotChipStyle forState(
    SemanticColors colors,
    SlotAvailabilityState state, {
    bool isSelected = false,
  }) {
    if (isSelected) {
      return SimplifiedSlotChipStyle(
        background: colors.primary,
        foreground: colors.primaryForeground,
        border: colors.primary,
      );
    }

    return switch (state) {
      SlotAvailabilityState.available => SimplifiedSlotChipStyle(
        background: _availableGreen.withValues(alpha: 0.12),
        foreground: _availableForeground,
        border: _availableGreen.withValues(alpha: 0.32),
        leadingIcon: Icons.check_circle_outline,
      ),
      SlotAvailabilityState.alternateDoctorsAvailable => SimplifiedSlotChipStyle(
        background: _semiAvailableYellow.withValues(alpha: 0.14),
        foreground: _semiAvailableForeground,
        border: _semiAvailableYellow.withValues(alpha: 0.38),
        leadingIcon: Icons.help_outline,
      ),
      SlotAvailabilityState.fullyUnavailable => SimplifiedSlotChipStyle(
        background: colors.destructive.withValues(alpha: 0.1),
        foreground: colors.destructive.withValues(alpha: 0.9),
        border: colors.destructive.withValues(alpha: 0.28),
        leadingIcon: Icons.lock_outline,
      ),
      SlotAvailabilityState.past => SimplifiedSlotChipStyle(
        background: colors.destructive.withValues(alpha: 0.07),
        foreground: colors.destructive.withValues(alpha: 0.7),
        border: colors.destructive.withValues(alpha: 0.2),
        leadingIcon: Icons.lock_outline,
      ),
    };
  }
}
