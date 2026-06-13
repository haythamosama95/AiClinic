import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/theme/spacing_tokens.dart';

/// Responsive multi-column layout for settings cards.
class SettingsCardsGrid extends StatelessWidget {
  const SettingsCardsGrid({
    required this.children,
    this.columns = 2,
    this.enforceColumns = false,
    this.compactBreakpoint = compactBreakpointDefault,
    super.key,
  });

  static const compactBreakpointDefault = 640.0;

  final List<Widget> children;
  final int columns;
  final bool enforceColumns;
  final double compactBreakpoint;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < compactBreakpoint;
        final maxColumns = enforceColumns ? columns : (children.isEmpty ? 1 : children.length);
        final columnCount = isCompact ? 1 : columns.clamp(1, maxColumns);

        if (columnCount == 1) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) const SizedBox(height: SpacingTokens.lg),
                children[i],
              ],
            ],
          );
        }

        final rows = <Widget>[];
        for (var i = 0; i < children.length; i += columnCount) {
          if (i > 0) {
            rows.add(const SizedBox(height: SpacingTokens.lg));
          }
          final rowChildren = <Widget>[];
          for (var col = 0; col < columnCount; col++) {
            final index = i + col;
            rowChildren.add(index < children.length ? children[index] : const SizedBox.shrink());
          }
          rows.add(_EqualHeightGridRow(children: rowChildren));
        }

        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows);
      },
    );
  }
}

/// Keeps grid row children at a shared height equal to the tallest card.
///
/// [IntrinsicHeight] cannot be used here because settings cards may contain
/// [LayoutBuilder] descendants (for example [SettingsFieldsRow]).
class _EqualHeightGridRow extends StatefulWidget {
  const _EqualHeightGridRow({required this.children});

  final List<Widget> children;

  @override
  State<_EqualHeightGridRow> createState() => _EqualHeightGridRowState();
}

class _EqualHeightGridRowState extends State<_EqualHeightGridRow> {
  final _cardKeys = <GlobalKey>[];
  double? _sharedHeight;

  @override
  void initState() {
    super.initState();
    _resetKeys();
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncSharedHeight());
  }

  @override
  void didUpdateWidget(covariant _EqualHeightGridRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.children.length != widget.children.length) {
      _resetKeys();
      _sharedHeight = null;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncSharedHeight());
  }

  void _resetKeys() {
    _cardKeys
      ..clear()
      ..addAll(List.generate(widget.children.length, (_) => GlobalKey()));
  }

  void _syncSharedHeight() {
    if (!mounted) {
      return;
    }

    final measuredHeights = <double>[
      for (final key in _cardKeys)
        if (key.currentContext?.size case final size?) size.height,
    ];
    if (measuredHeights.isEmpty) {
      return;
    }

    final tallest = measuredHeights.reduce(math.max);
    if (tallest <= 0 || _sharedHeight == tallest) {
      return;
    }

    setState(() => _sharedHeight = tallest);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < widget.children.length; i++) ...[
          if (i > 0) const SizedBox(width: SpacingTokens.lg),
          Expanded(
            child: SizedBox(
              height: _sharedHeight,
              child: KeyedSubtree(key: _cardKeys[i], child: widget.children[i]),
            ),
          ),
        ],
      ],
    );
  }
}
