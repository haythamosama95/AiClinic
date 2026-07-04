import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/theme_context_extensions.dart';
import 'package:ai_clinic/core/ui/widgets/actions/icon_button.dart';
import 'package:ai_clinic/core/ui/widgets/inputs/input_styles.dart';
import 'package:ai_clinic/core/ui/widgets/inputs/select.dart';

/// Table pagination with optional page-size selector.
class AppPagination extends StatelessWidget {
  const AppPagination({
    super.key,
    required this.page,
    required this.pageSize,
    required this.total,
    this.pageSizeOptions = const [25, 50, 100],
    required this.onPageChange,
    this.onPageSizeChange,
  });

  final int page;
  final int pageSize;
  final int total;
  final List<int> pageSizeOptions;
  final ValueChanged<int> onPageChange;
  final ValueChanged<int>? onPageSizeChange;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;
    final totalPages = math.max(1, (total / pageSize).ceil());
    final start = total == 0 ? 0 : (page - 1) * pageSize + 1;
    final end = total == 0 ? 0 : math.min(page * pageSize, total);
    final numberFormat = NumberFormat.decimalPattern();

    return Semantics(
      container: true,
      label: 'Pagination',
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: AppSpacing.s4,
        runSpacing: AppSpacing.s2,
        alignment: WrapAlignment.spaceBetween,
        children: [
          Text.rich(
            TextSpan(
              style: typography.bodySm.copyWith(color: colors.textSecondary),
              children: [
                TextSpan(
                  text: '${numberFormat.format(start)}–${numberFormat.format(end)}',
                  style: typography.bodySm.copyWith(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w500,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                TextSpan(text: ' of ${numberFormat.format(total)}'),
              ],
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (onPageSizeChange != null) ...[
                Text(
                  'Rows',
                  style: typography.bodySm.copyWith(color: colors.textSecondary),
                ),
                const SizedBox(width: AppSpacing.s2),
                SizedBox(
                  width: 80,
                  child: AppSelect(
                    size: AppInputSize.sm,
                    value: '$pageSize',
                    options: [
                      for (final option in pageSizeOptions)
                        AppSelectOption(
                          value: '$option',
                          label: '$option',
                        ),
                    ],
                    onValueChange: (value) => onPageSizeChange!(int.parse(value)),
                  ),
                ),
                const SizedBox(width: AppSpacing.s3),
              ],
              AppIconButton(
                semanticLabel: 'Previous page',
                icon: Icons.chevron_left,
                size: AppIconButtonSize.sm,
                disabled: page <= 1,
                onPressed: page <= 1 ? null : () => onPageChange(page - 1),
              ),
              SizedBox(
                width: 64,
                child: Text(
                  '$page / $totalPages',
                  textAlign: TextAlign.center,
                  style: typography.bodySm.copyWith(
                    color: colors.textPrimary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              AppIconButton(
                semanticLabel: 'Next page',
                icon: Icons.chevron_right,
                size: AppIconButtonSize.sm,
                disabled: page >= totalPages,
                onPressed: page >= totalPages ? null : () => onPageChange(page + 1),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
