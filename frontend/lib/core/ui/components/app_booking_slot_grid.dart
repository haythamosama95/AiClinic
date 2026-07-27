import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/components/app_input_styles.dart';
import 'package:ai_clinic/core/ui/components/app_pressable.dart';
import 'package:ai_clinic/core/ui/theme/app_color_primitives.dart';
import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';
import 'package:ai_clinic/core/ui/models/booking_slot.dart';

/// Time slot grid with legend for appointment booking step 2.
class AppBookingSlotGrid extends StatelessWidget {
  const AppBookingSlotGrid({
    required this.slots,
    required this.selectedStart,
    required this.hasPreferredDoctor,
    required this.onSlotSelected,
    this.errorText,
    super.key,
  });

  final List<BookingTimeSlot> slots;
  final DateTime? selectedStart;
  final bool hasPreferredDoctor;
  final ValueChanged<BookingTimeSlot> onSlotSelected;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          label: 'Available time slots',
          child: LayoutBuilder(
            builder: (context, constraints) {
              const columns = 6;
              final spacing = AppSpacing.space2;
              final itemWidth = (constraints.maxWidth - spacing * (columns - 1)) / columns;

              return Wrap(
                spacing: spacing,
                runSpacing: spacing,
                children: [
                  for (final slot in slots)
                    SizedBox(
                      width: itemWidth,
                      child: _SlotButton(
                        slot: slot,
                        selected: selectedStart != null && slot.start == selectedStart,
                        hasPreferredDoctor: hasPreferredDoctor,
                        onPressed: slot.status == BookingSlotStatus.locked
                            ? null
                            : () => onSlotSelected(slot),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
        if (errorText != null) ...[
          const SizedBox(height: AppSpacing.space2),
          Text(errorText!, style: AppTypography.caption(context).copyWith(color: colors.statusDangerFg)),
        ],
        const SizedBox(height: AppSpacing.space4),
        _SlotLegend(hasPreferredDoctor: hasPreferredDoctor),
      ],
    );
  }
}

class _SlotButton extends StatelessWidget {
  const _SlotButton({
    required this.slot,
    required this.selected,
    required this.hasPreferredDoctor,
    required this.onPressed,
  });

  final BookingTimeSlot slot;
  final bool selected;
  final bool hasPreferredDoctor;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final locked = slot.status == BookingSlotStatus.locked;
    final palette = _slotPalette(slot.status, colors, Theme.of(context).brightness);

    return AppPressable(
      onPressed: onPressed,
      enabled: !locked,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        constraints: const BoxConstraints(minHeight: 52),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space2, vertical: 10),
        decoration: BoxDecoration(
          color: palette.background,
          borderRadius: BorderRadius.circular(AppRadius.xl),
          border: Border.all(color: palette.border),
          boxShadow: selected && !locked
              ? [BoxShadow(color: appInputFocusRingColor(context), blurRadius: 0, spreadRadius: 2)]
              : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (locked && hasPreferredDoctor) ...[
              Icon(Icons.lock_outline, size: 14, color: colors.textTertiary.withValues(alpha: 0.5)),
              const SizedBox(height: 2),
            ],
            if (locked && !hasPreferredDoctor)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.lock_outline, size: 12, color: colors.textTertiary.withValues(alpha: 0.5)),
                  const SizedBox(width: 4),
                  Text(
                    slot.label,
                    textAlign: TextAlign.center,
                    style: AppTypography.bodySm(context).copyWith(
                      color: palette.foreground,
                      fontWeight: FontWeight.w600,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              )
            else
              Text(
                slot.label,
                textAlign: TextAlign.center,
                style: AppTypography.bodySm(context).copyWith(
                  color: palette.foreground,
                  fontWeight: FontWeight.w600,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            if (!locked && hasPreferredDoctor && slot.status == BookingSlotStatus.alternate) ...[
              const SizedBox(height: 2),
              Text(
                'Other doctor',
                style: AppTypography.caption(
                  context,
                ).copyWith(color: palette.foreground.withValues(alpha: 0.75), fontSize: 10, height: 1.1),
              ),
            ],
            if (!locked && hasPreferredDoctor && slot.status == BookingSlotStatus.preferred) ...[
              const SizedBox(height: 2),
              Text(
                'Preferred',
                style: AppTypography.caption(
                  context,
                ).copyWith(color: palette.foreground.withValues(alpha: 0.75), fontSize: 10, height: 1.1),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SlotPalette {
  const _SlotPalette({required this.background, required this.border, required this.foreground});

  final Color background;
  final Color border;
  final Color foreground;
}

_SlotPalette _slotPalette(BookingSlotStatus status, AppSemanticColors colors, Brightness brightness) {
  return switch (status) {
    BookingSlotStatus.locked => _SlotPalette(
      background: colors.surfaceMuted,
      border: colors.borderSubtle,
      foreground: colors.textTertiary,
    ),
    BookingSlotStatus.available => _SlotPalette(
      background: brightness == Brightness.dark
          ? AppColorPrimitives.teal800.withValues(alpha: 0.35)
          : AppColorPrimitives.teal50,
      border: brightness == Brightness.dark ? AppColorPrimitives.teal600 : AppColorPrimitives.teal300,
      foreground: brightness == Brightness.dark ? AppColorPrimitives.teal300 : AppColorPrimitives.teal800,
    ),
    BookingSlotStatus.preferred => _SlotPalette(
      background: brightness == Brightness.dark
          ? AppColorPrimitives.teal700.withValues(alpha: 0.45)
          : AppColorPrimitives.teal50,
      border: AppColorPrimitives.teal400,
      foreground: brightness == Brightness.dark ? AppColorPrimitives.teal300 : AppColorPrimitives.teal800,
    ),
    BookingSlotStatus.alternate => _SlotPalette(
      background: brightness == Brightness.dark
          ? AppColorPrimitives.violet700.withValues(alpha: 0.35)
          : AppColorPrimitives.violet50,
      border: brightness == Brightness.dark ? AppColorPrimitives.violet500 : AppColorPrimitives.violet100,
      foreground: brightness == Brightness.dark ? AppColorPrimitives.violet300 : AppColorPrimitives.violet700,
    ),
  };
}

class _SlotLegend extends StatelessWidget {
  const _SlotLegend({required this.hasPreferredDoctor});

  final bool hasPreferredDoctor;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final brightness = Theme.of(context).brightness;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceSunken,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: colors.borderSubtle),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space3, vertical: 10),
        child: Wrap(
          spacing: AppSpacing.space4,
          runSpacing: AppSpacing.space2,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              'LEGEND',
              style: AppTypography.caption(context).copyWith(color: colors.textTertiary, letterSpacing: 0.4),
            ),
            if (hasPreferredDoctor) ...[
              _LegendSwatch(
                border: AppColorPrimitives.teal400,
                background: brightness == Brightness.dark
                    ? AppColorPrimitives.teal700.withValues(alpha: 0.45)
                    : AppColorPrimitives.teal50,
                label: 'Preferred doctor free',
              ),
              _LegendSwatch(
                border: brightness == Brightness.dark ? AppColorPrimitives.violet500 : AppColorPrimitives.violet100,
                background: brightness == Brightness.dark
                    ? AppColorPrimitives.violet700.withValues(alpha: 0.35)
                    : AppColorPrimitives.violet50,
                label: 'Other doctors free',
              ),
            ] else
              _LegendSwatch(
                border: brightness == Brightness.dark ? AppColorPrimitives.teal600 : AppColorPrimitives.teal300,
                background: brightness == Brightness.dark
                    ? AppColorPrimitives.teal800.withValues(alpha: 0.35)
                    : AppColorPrimitives.teal50,
                label: 'Open slot',
              ),
            _LegendSwatch(
              border: colors.borderSubtle,
              background: colors.surfaceMuted,
              label: 'Fully booked',
              muted: true,
            ),
          ],
        ),
      ),
    );
  }
}

class _LegendSwatch extends StatelessWidget {
  const _LegendSwatch({required this.border, required this.background, required this.label, this.muted = false});

  final Color border;
  final Color background;
  final String label;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(3),
            border: Border.all(color: border),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: AppTypography.caption(context).copyWith(color: colors.textSecondary, decoration: muted ? null : null),
        ),
      ],
    );
  }
}
