import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/foundation.dart';
import 'package:ai_clinic/core/ui/widgets/actions/app_icon_button.dart';

/// Page navigation with numbered pages, ellipsis truncation, and prev/next controls.
class AppPagination extends StatelessWidget {
  const AppPagination({
    required this.page,
    required this.pageCount,
    required this.onPageChanged,
    this.pageSizeSelect,
    this.semanticLabel = 'Pagination',
    super.key,
  }) : assert(page >= 1),
       assert(pageCount >= 1);

  final int page;
  final int pageCount;
  final ValueChanged<int> onPageChanged;

  /// Optional trailing control (for example an [AppSelect] for page size).
  final Widget? pageSizeSelect;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final isRtl = Directionality.of(context) == TextDirection.rtl;
    final prevIcon =
        isRtl ? LucideIcons.chevronRight : LucideIcons.chevronLeft;
    final nextIcon =
        isRtl ? LucideIcons.chevronLeft : LucideIcons.chevronRight;

    return Semantics(
      label: semanticLabel,
      container: true,
      child: Wrap(
        spacing: AppSpacing.s4,
        runSpacing: AppSpacing.s3,
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          const SizedBox(width: 1, height: 1),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (pageSizeSelect != null) ...[
                pageSizeSelect!,
                const SizedBox(width: AppSpacing.s3),
              ],
              AppIconButton(
                icon: prevIcon,
                semanticLabel: 'Previous page',
                size: AppIconButtonSize.sm,
                variant: AppIconButtonVariant.ghost,
                disabled: page <= 1,
                onPressed: page <= 1 ? null : () => onPageChanged(page - 1),
              ),
              const SizedBox(width: AppSpacing.s1),
              ..._buildPageButtons(context),
              const SizedBox(width: AppSpacing.s1),
              AppIconButton(
                icon: nextIcon,
                semanticLabel: 'Next page',
                size: AppIconButtonSize.sm,
                variant: AppIconButtonVariant.ghost,
                disabled: page >= pageCount,
                onPressed:
                    page >= pageCount ? null : () => onPageChanged(page + 1),
              ),
            ],
          ),
        ],
      ),
    );
  }

  List<Widget> _buildPageButtons(BuildContext context) {
    final entries = _pageEntries(page, pageCount);
    return [
      for (final entry in entries)
        if (entry.isEllipsis)
          _Ellipsis(key: ValueKey<String>('ellipsis-${entry.key}'))
        else
          _PageButton(
            key: ValueKey<int>(entry.page!),
            pageNumber: entry.page!,
            selected: entry.page == page,
            onTap: () => onPageChanged(entry.page!),
          ),
    ];
  }
}

class _PageEntry {
  const _PageEntry.page(this.page) : isEllipsis = false, key = null;

  const _PageEntry.ellipsis(this.key) : isEllipsis = true, page = null;

  final int? page;
  final bool isEllipsis;
  final String? key;
}

List<_PageEntry> _pageEntries(int current, int total) {
  if (total <= 7) {
    return [for (var i = 1; i <= total; i++) _PageEntry.page(i)];
  }

  final entries = <_PageEntry>[_PageEntry.page(1)];

  var left = current - 1;
  var right = current + 1;

  if (current <= 3) {
    left = 2;
    right = 4;
  } else if (current >= total - 2) {
    left = total - 3;
    right = total - 1;
  }

  if (left > 2) {
    entries.add(const _PageEntry.ellipsis('start'));
  }

  for (var i = left; i <= right; i++) {
    entries.add(_PageEntry.page(i));
  }

  if (right < total - 1) {
    entries.add(const _PageEntry.ellipsis('end'));
  }

  entries.add(_PageEntry.page(total));
  return entries;
}

class _PageButton extends StatelessWidget {
  const _PageButton({
    required this.pageNumber,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final int pageNumber;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;
    final label = _formatWesternInt(pageNumber);

    return AppPressable.builder(
      onTap: onTap,
      semanticLabel: 'Page $label',
      borderRadius: AppRadii.mdAll,
      builder: (context, states, _) {
        final hovered = states.contains(WidgetState.hovered);
        final background = selected
            ? colors.surfaceSelected
            : hovered
            ? colors.surfaceHover
            : Colors.transparent;

        return AnimatedContainer(
          duration: AppDurations.instant,
          curve: AppEasings.standard,
          constraints: const BoxConstraints(
            minWidth: AppSpacing.s8 - AppSpacing.s1,
            minHeight: AppSpacing.s8 - AppSpacing.s1,
          ),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s2),
          decoration: BoxDecoration(
            color: background,
            borderRadius: AppRadii.mdAll,
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: typography.bodySm.copyWith(
              fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
              color: selected ? colors.textPrimary : colors.textSecondary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        );
      },
    );
  }
}

class _Ellipsis extends StatelessWidget {
  const _Ellipsis({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s1),
      child: Text(
        '…',
        style: typography.bodySm.copyWith(color: colors.textTertiary),
      ),
    );
  }
}

String _formatWesternInt(int value) {
  const eastern = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];
  const persian = ['۰', '۱', '۲', '۳', '۴', '۵', '۶', '۷', '۸', '۹'];
  var text = value.toString();
  for (var i = 0; i < 10; i++) {
    text = text.replaceAll(eastern[i], '$i').replaceAll(persian[i], '$i');
  }
  return text;
}
