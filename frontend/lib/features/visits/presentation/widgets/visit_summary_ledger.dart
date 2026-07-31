import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/widgets/widgets.dart';

/// A single label/value row in [VisitSummaryLedger].
class LedgerRow {
  const LedgerRow({required this.label, required this.value});

  final String label;
  final Widget? value;
}

/// Read-only prose value with empty fallback (web `LedgerText`).
class LedgerText extends StatelessWidget {
  const LedgerText({required this.value, super.key});

  final String value;

  @override
  Widget build(BuildContext context) {
    if (value.trim().isEmpty) {
      return const LedgerEmpty();
    }

    return Text(value, style: const TextStyle(height: 1.5));
  }
}

/// Inline dot-separated list with optional meta (web `LedgerInlineList`).
class LedgerInlineList extends StatelessWidget {
  const LedgerInlineList({
    required this.items,
    this.emptyLabel = '—',
    super.key,
  });

  final List<LedgerInlineItem> items;
  final String emptyLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    if (items.isEmpty) {
      return Text(emptyLabel, style: TextStyle(color: colors.textTertiary));
    }

    return Text.rich(
      TextSpan(
        children: [
          for (var index = 0; index < items.length; index++) ...[
            if (index > 0)
              TextSpan(
                text: ' · ',
                style: TextStyle(color: colors.textTertiary),
              ),
            TextSpan(text: items[index].label),
            if (items[index].meta != null)
              TextSpan(
                text: ' (${items[index].meta})',
                style: TextStyle(color: colors.textSecondary),
              ),
          ],
        ],
      ),
    );
  }
}

/// Item for [LedgerInlineList].
class LedgerInlineItem {
  const LedgerInlineItem({required this.id, required this.label, this.meta});

  final String id;
  final String label;
  final String? meta;
}

/// Tertiary em dash placeholder (web `LedgerEmpty`).
class LedgerEmpty extends StatelessWidget {
  const LedgerEmpty({super.key});

  @override
  Widget build(BuildContext context) {
    return Text('—', style: TextStyle(color: context.appColors.textTertiary));
  }
}

/// One ledger label/value pair rendered via [AppDescriptionList] (web `LedgerEntry`).
class LedgerEntry extends StatelessWidget {
  const LedgerEntry({
    required this.label,
    required this.value,
    this.isLast = false,
    super.key,
  });

  final String label;
  final Widget value;
  final bool isLast;

  DescriptionItem toDescriptionItem() {
    return DescriptionItem(label: label, value: value);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final border = isLast ? null : Border(bottom: BorderSide(color: colors.borderSubtle));

    return DecoratedBox(
      decoration: BoxDecoration(border: border),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.space3),
        child: AppDescriptionList(
          columns: 1,
          items: [toDescriptionItem()],
        ),
      ),
    );
  }
}

/// Ledger section with title, rows, and delayed slide-up enter (web `LedgerSection`).
class VisitSummaryLedger extends StatefulWidget {
  const VisitSummaryLedger({
    required this.title,
    required this.rows,
    required this.vsync,
    this.delay = Duration.zero,
    this.isLast = false,
    super.key,
  });

  final String title;
  final List<LedgerRow> rows;
  final TickerProvider vsync;
  final Duration delay;
  final bool isLast;

  @override
  State<VisitSummaryLedger> createState() => _VisitSummaryLedgerState();
}

class _VisitSummaryLedgerState extends State<VisitSummaryLedger> {
  late final AnimationController _controller;
  late final CurvedAnimation _animation;
  var _configured = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: widget.vsync,
      duration: AppMotion.base,
    );
    _animation = CurvedAnimation(parent: _controller, curve: AppMotionEasing.out);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_configured) {
      return;
    }
    _configured = true;

    final reducedMotion = AppMotion.prefersReducedMotion(context);
    if (reducedMotion) {
      _controller.value = 1;
      return;
    }

    Future<void>.delayed(widget.delay, () {
      if (mounted) {
        _controller.forward(from: 0);
      }
    });
  }

  @override
  void dispose() {
    _animation.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final visibleRows = widget.rows.where((row) => row.value != null).toList(growable: false);

    if (visibleRows.isEmpty) {
      return const SizedBox.shrink();
    }

    final content = _buildContent(context, visibleRows);
    final reducedMotion = AppMotion.prefersReducedMotion(context);

    return Semantics(
      container: true,
      label: widget.title,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: widget.isLast ? null : Border(bottom: BorderSide(color: colors.borderDefault)),
        ),
        child: reducedMotion
            ? content
            : AppMotion.animatedPreset(
                context: context,
                preset: AppMotionPreset.slideUp,
                animation: _animation,
                child: content,
              ),
      ),
    );
  }

  Widget _buildContent(BuildContext context, List<LedgerRow> visibleRows) {
    final colors = context.appColors;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 640;

        if (!isWide) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.space5,
                  AppSpacing.space3,
                  AppSpacing.space5,
                  0,
                ),
                child: Text(widget.title, style: AppTypography.bodyStrong(context)),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space5),
                child: _buildRowList(context, visibleRows),
              ),
            ],
          );
        }

        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: 112,
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.space6,
                  AppSpacing.space3,
                  AppSpacing.space4,
                  AppSpacing.space3,
                ),
                decoration: BoxDecoration(
                  border: BorderDirectional(end: BorderSide(color: colors.borderSubtle)),
                ),
                child: Align(
                  alignment: AlignmentDirectional.topStart,
                  child: Text(widget.title, style: AppTypography.bodyStrong(context)),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(
                    AppSpacing.space5,
                    0,
                    AppSpacing.space6,
                    0,
                  ),
                  child: _buildRowList(context, visibleRows),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildRowList(BuildContext context, List<LedgerRow> visibleRows) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < visibleRows.length; index++)
          LedgerEntry(
            label: visibleRows[index].label,
            value: visibleRows[index].value!,
            isLast: index == visibleRows.length - 1,
          ),
      ],
    );
  }
}
