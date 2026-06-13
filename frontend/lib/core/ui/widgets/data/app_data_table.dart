import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/theme/semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/spacing_tokens.dart';
import 'package:ai_clinic/core/ui/widgets/feedback/app_paginated_slide_switcher.dart';

/// Column definition for [AppDataTable].
class AppDataTableColumn {
  const AppDataTableColumn({required this.label, this.flex = 1, this.width, this.alignment = Alignment.centerLeft});

  final String label;
  final int flex;
  final double? width;
  final Alignment alignment;
}

/// Dense, token-aligned data table for dashboard list views.
class AppDataTable extends StatelessWidget {
  const AppDataTable({
    required this.columns,
    required this.rowCount,
    required this.rowBuilder,
    this.footer,
    this.bodyPageKey,
    this.bodySlideDirection = 0,
    this.onBodyTransitionAnimating,
    this.headerHeight = 36,
    this.rowHeight = 44,
    super.key,
  });

  final List<AppDataTableColumn> columns;
  final int rowCount;
  final Widget Function(BuildContext context, int index) rowBuilder;
  final Widget? footer;
  final Object? bodyPageKey;
  final int bodySlideDirection;
  final ValueChanged<bool>? onBodyTransitionAnimating;
  final double headerHeight;
  final double rowHeight;

  @override
  Widget build(BuildContext context) {
    final colors = context.semanticColors;
    final theme = Theme.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.card,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: headerHeight,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: colors.muted.withValues(alpha: 0.45),
                border: Border(bottom: BorderSide(color: colors.border)),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: SpacingTokens.md),
                child: Row(
                  children: [
                    for (var i = 0; i < columns.length; i++) ...[
                      if (i > 0) const SizedBox(width: SpacingTokens.sm),
                      _HeaderCell(column: columns[i], textStyle: theme.textTheme.labelSmall),
                    ],
                  ],
                ),
              ),
            ),
          ),
          Expanded(child: _buildBody()),
          if (footer != null)
            DecoratedBox(
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: colors.border)),
                color: colors.muted.withValues(alpha: 0.25),
              ),
              child: footer,
            ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    final listView = ListView.builder(itemCount: rowCount, itemExtent: rowHeight, itemBuilder: rowBuilder);
    final pageKey = bodyPageKey;
    if (pageKey == null) {
      return listView;
    }

    return AppPaginatedSlideSwitcher(
      pageKey: pageKey,
      direction: bodySlideDirection,
      onAnimatingChanged: onBodyTransitionAnimating,
      child: listView,
    );
  }
}

class _HeaderCell extends StatelessWidget {
  const _HeaderCell({required this.column, required this.textStyle});

  final AppDataTableColumn column;
  final TextStyle? textStyle;

  @override
  Widget build(BuildContext context) {
    final colors = context.semanticColors;
    final child = Text(
      column.label,
      style: textStyle?.copyWith(color: colors.mutedForeground, fontWeight: FontWeight.w600, letterSpacing: 0.2),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );

    if (column.width != null) {
      return SizedBox(
        width: column.width,
        child: Align(alignment: column.alignment, child: child),
      );
    }

    return Expanded(
      flex: column.flex,
      child: Align(alignment: column.alignment, child: child),
    );
  }
}

/// Interactive table row with hover feedback.
class AppDataTableRow extends StatefulWidget {
  const AppDataTableRow({required this.columns, required this.cells, this.onTap, super.key});

  final List<AppDataTableColumn> columns;
  final List<Widget> cells;
  final void Function(BuildContext rowContext)? onTap;

  @override
  State<AppDataTableRow> createState() => _AppDataTableRowState();
}

class _AppDataTableRowState extends State<AppDataTableRow> {
  var _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.semanticColors;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Material(
        color: _hovered ? colors.accent.withValues(alpha: 0.35) : Colors.transparent,
        child: InkWell(
          onTap: widget.onTap == null ? null : () => widget.onTap!(context),
          hoverColor: Colors.transparent,
          splashColor: colors.primary.withValues(alpha: 0.08),
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: colors.border.withValues(alpha: 0.65))),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: SpacingTokens.md),
              child: Row(
                children: [
                  for (var i = 0; i < widget.cells.length; i++) ...[
                    if (i > 0) const SizedBox(width: SpacingTokens.sm),
                    _BodyCell(column: widget.columns[i], child: widget.cells[i]),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BodyCell extends StatelessWidget {
  const _BodyCell({required this.column, required this.child});

  final AppDataTableColumn column;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (column.width != null) {
      return SizedBox(
        width: column.width,
        child: Align(alignment: column.alignment, child: child),
      );
    }

    return Expanded(
      flex: column.flex,
      child: Align(alignment: column.alignment, child: child),
    );
  }
}
