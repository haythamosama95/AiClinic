import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';

/// Locale-aware day / month / year column for patient record cards.
class PatientDateStamp extends StatelessWidget {
  const PatientDateStamp({
    required this.date,
    this.showWeekday = false,
    this.compact = false,
    super.key,
  });

  final DateTime date;
  final bool showWeekday;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final locale = Localizations.localeOf(context).toString();
    final day = DateFormat('d', locale).format(date);
    final month = DateFormat.MMM(locale).format(date).toUpperCase();
    final year = DateFormat('y', locale).format(date);
    final weekday = DateFormat.EEEE(locale).format(date);

    if (compact) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            day,
            style: AppTypography.bodyStrong(
              context,
            ).copyWith(color: colors.textPrimary),
          ),
          const SizedBox(height: AppSpacing.space05),
          Text(
            month,
            style: AppTypography.caption(context).copyWith(
              color: colors.textSecondary,
              letterSpacing: 1.2,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          day,
          style: AppTypography.display(context).copyWith(
            color: colors.textPrimary,
            height: 1,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: AppSpacing.space05),
        Text(
          month,
          style: AppTypography.overline(
            context,
          ).copyWith(color: colors.textSecondary, letterSpacing: 0.14 * 11),
        ),
        Text(
          year,
          style: AppTypography.caption(context).copyWith(
            color: colors.textTertiary,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        if (showWeekday) ...[
          const SizedBox(height: AppSpacing.space05),
          Text(
            weekday,
            style: AppTypography.overline(
              context,
            ).copyWith(color: colors.textTertiary),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }
}
