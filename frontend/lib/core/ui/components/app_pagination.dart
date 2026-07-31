import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

import 'package:ai_clinic/core/ui/components/app_icon_button.dart';
import 'package:ai_clinic/core/ui/components/app_input_styles.dart';
import 'package:ai_clinic/core/ui/components/app_select.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';

/// Application-owned pagination controls (web `Pagination`).
class AppPagination extends StatelessWidget {
  const AppPagination({
    required this.page,
    required this.pageSize,
    required this.total,
    required this.onPageChange,
    this.onPageSizeChange,
    this.pageSizeOptions = const [25, 50, 100],
    this.rowsLabel = 'Rows',
    this.ofLabel = 'of',
    this.previousPageLabel = 'Previous page',
    this.nextPageLabel = 'Next page',
    super.key,
  });

  final int page;
  final int pageSize;
  final int total;
  final ValueChanged<int> onPageChange;
  final ValueChanged<int>? onPageSizeChange;
  final List<int> pageSizeOptions;
  final String rowsLabel;
  final String ofLabel;
  final String previousPageLabel;
  final String nextPageLabel;

  static const _tabularFigures = [FontFeature.tabularFigures()];

  int get _totalPages => (total / pageSize).ceil().clamp(1, 1 << 31);

  int get _start => total == 0 ? 0 : (page - 1) * pageSize + 1;

  int get _end => (page * pageSize).clamp(0, total);

  String _formatNumber(BuildContext context, int value) {
    final locale = Localizations.localeOf(context).toString();
    return Intl.withLocale(locale, () => NumberFormat.decimalPattern().format(value));
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final isRtl = Directionality.of(context) == TextDirection.rtl;
    final prevIcon = isRtl ? Icons.chevron_right : Icons.chevron_left;
    final nextIcon = isRtl ? Icons.chevron_left : Icons.chevron_right;
    final totalPages = _totalPages;
    final canGoPrev = page > 1;
    final canGoNext = page < totalPages;

    final rangeStyle = AppTypography.bodySm(
      context,
    ).copyWith(color: colors.textSecondary, fontFeatures: _tabularFigures);
    final rangeHighlightStyle = rangeStyle.copyWith(fontWeight: FontWeight.w500, color: colors.textPrimary);
    final pageIndicatorStyle = AppTypography.bodySm(
      context,
    ).copyWith(color: colors.textPrimary, fontFeatures: _tabularFigures);
    final rowsLabelStyle = AppTypography.bodySm(context).copyWith(color: colors.textSecondary);

    final rangeSummary = Text.rich(
      TextSpan(
        style: rangeStyle,
        children: [
          TextSpan(
            text: '${_formatNumber(context, _start)}–${_formatNumber(context, _end)}',
            style: rangeHighlightStyle,
          ),
          TextSpan(text: ' $ofLabel ${_formatNumber(context, total)}'),
        ],
      ),
    );

    final controls = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (onPageSizeChange != null) ...[
          Text(rowsLabel, style: rowsLabelStyle),
          const SizedBox(width: AppSpacing.space2),
          SizedBox(
            width: 80,
            child: AppSelect(
              size: AppInputSize.sm,
              value: pageSize.toString(),
              options: [
                for (final option in pageSizeOptions)
                  AppSelectOption(value: option.toString(), label: option.toString()),
              ],
              onChanged: (value) => onPageSizeChange!(int.parse(value)),
            ),
          ),
          const SizedBox(width: AppSpacing.space3),
        ],
        AppIconButton(
          size: AppIconButtonSize.sm,
          variant: AppIconButtonVariant.ghost,
          label: previousPageLabel,
          onPressed: canGoPrev ? () => onPageChange(page - 1) : null,
          icon: Icon(prevIcon),
        ),
        ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 64),
          child: Text('$page / $totalPages', textAlign: TextAlign.center, style: pageIndicatorStyle),
        ),
        AppIconButton(
          size: AppIconButtonSize.sm,
          variant: AppIconButtonVariant.ghost,
          label: nextPageLabel,
          onPressed: canGoNext ? () => onPageChange(page + 1) : null,
          icon: Icon(nextIcon),
        ),
      ],
    );

    return Semantics(
      container: true,
      label: 'Pagination',
      child: Row(
        children: [
          Expanded(
            child: Semantics(label: 'Showing $_start to $_end $ofLabel $total', child: rangeSummary),
          ),
          controls,
        ],
      ),
    );
  }
}
