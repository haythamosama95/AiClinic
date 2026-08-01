import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/widgets/widgets.dart';

/// Animated list of visit entry cards keyed by entry id.
///
/// Mirrors web `AnimatePresence mode="popLayout"`: per-item `fade-scale` exit,
/// reflow via [AnimatedSize], and reduced-motion fallbacks.
class VisitEntryList<T> extends StatefulWidget {
  const VisitEntryList({
    required this.items,
    required this.itemId,
    required this.itemBuilder,
    this.wrap = false,
    this.maxCrossAxisCount,
    this.spacing = AppSpacing.space3,
    this.runSpacing = AppSpacing.space3,
    super.key,
  });

  final List<T> items;
  final String Function(T item) itemId;
  final Widget Function(BuildContext context, T item) itemBuilder;
  final bool wrap;

  /// When set with [wrap], lays out items in a responsive grid capped at this many columns.
  final int? maxCrossAxisCount;
  final double spacing;
  final double runSpacing;

  @override
  State<VisitEntryList<T>> createState() => _VisitEntryListState<T>();
}

class _VisitEntryListState<T> extends State<VisitEntryList<T>> {
  final Map<String, T> _exitingItems = {};

  @override
  void didUpdateWidget(covariant VisitEntryList<T> oldWidget) {
    super.didUpdateWidget(oldWidget);

    final currentIds = widget.items.map(widget.itemId).toSet();
    final previousIds = oldWidget.items.map(widget.itemId).toSet();

    for (final id in currentIds) {
      _exitingItems.remove(id);
    }

    for (final id in previousIds.difference(currentIds)) {
      final item = oldWidget.items.firstWhere((entry) => widget.itemId(entry) == id);
      _exitingItems[id] = item;
    }
  }

  void _handleExitComplete(String id) {
    if (!_exitingItems.containsKey(id)) {
      return;
    }
    setState(() => _exitingItems.remove(id));
  }

  @override
  Widget build(BuildContext context) {
    final reducedMotion = AppMotion.prefersReducedMotion(context);
    final reflowDuration = reducedMotion ? Duration.zero : AppMotion.base;
    final reflowCurve = reducedMotion ? AppMotionEasing.standard : AppMotionEasing.out;

    final activeIds = widget.items.map(widget.itemId).toList();
    final exitingIds = _exitingItems.keys.where((id) => !activeIds.contains(id)).toList();
    final renderIds = [...activeIds, ...exitingIds];

    final children = [
      for (final id in renderIds)
        _VisitEntryListTile(
          key: ValueKey<String>(id),
          exiting: _exitingItems.containsKey(id),
          onExitComplete: () => _handleExitComplete(id),
          child: widget.itemBuilder(
            context,
            _exitingItems[id] ?? widget.items.firstWhere((item) => widget.itemId(item) == id),
          ),
        ),
    ];

    return ClipRect(
      child: AnimatedSize(
        duration: reflowDuration,
        curve: reflowCurve,
        alignment: Alignment.topCenter,
        clipBehavior: Clip.hardEdge,
        child: widget.wrap
            ? _buildWrappedLayout(children)
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var index = 0; index < children.length; index++) ...[
                    if (index > 0) SizedBox(height: widget.spacing),
                    children[index],
                  ],
                ],
              ),
      ),
    );
  }

  Widget _buildWrappedLayout(List<Widget> children) {
    if (widget.maxCrossAxisCount == null) {
      return Wrap(
        spacing: widget.spacing,
        runSpacing: widget.runSpacing,
        children: children,
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxColumns = widget.maxCrossAxisCount!;
        final crossAxisCount = switch (constraints.maxWidth) {
          < 640 => 1,
          < 1024 => 2,
          _ => maxColumns,
        };
        final itemWidth = (constraints.maxWidth - widget.spacing * (crossAxisCount - 1)) / crossAxisCount;

        return Wrap(
          spacing: widget.spacing,
          runSpacing: widget.runSpacing,
          children: [
            for (final child in children)
              SizedBox(
                width: itemWidth,
                child: child,
              ),
          ],
        );
      },
    );
  }
}

class _VisitEntryListTile extends StatefulWidget {
  const _VisitEntryListTile({
    required this.child,
    required this.exiting,
    this.onExitComplete,
    super.key,
  });

  final Widget child;
  final bool exiting;
  final VoidCallback? onExitComplete;

  @override
  State<_VisitEntryListTile> createState() => _VisitEntryListTileState();
}

class _VisitEntryListTileState extends State<_VisitEntryListTile> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  CurvedAnimation? _animation;
  var _configured = false;
  var _exitStarted = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, value: 1);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_configured) {
      return;
    }
    _configured = true;
    _configureAnimation();
    if (widget.exiting) {
      _startExit();
    }
  }

  @override
  void didUpdateWidget(covariant _VisitEntryListTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.exiting && widget.exiting) {
      _startExit();
    }
  }

  void _configureAnimation() {
    final reducedMotion = AppMotion.prefersReducedMotion(context);
    _controller.duration = reducedMotion
        ? Duration.zero
        : AppMotion.resolveDuration(AppMotionPreset.fadeScale);
    _animation?.dispose();
    _animation = CurvedAnimation(
      parent: _controller,
      curve: reducedMotion ? AppMotionEasing.standard : AppMotion.resolveCurve(AppMotionPreset.fadeScale),
    );
  }

  void _startExit() {
    if (_exitStarted) {
      return;
    }
    _exitStarted = true;

    final reducedMotion = AppMotion.prefersReducedMotion(context);
    if (reducedMotion) {
      widget.onExitComplete?.call();
      return;
    }

    _controller.reverse().then((_) {
      if (mounted) {
        widget.onExitComplete?.call();
      }
    });
  }

  @override
  void dispose() {
    _animation?.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.exiting) {
      return widget.child;
    }

    return AppMotion.animatedPreset(
      context: context,
      preset: AppMotionPreset.fadeScale,
      animation: _animation ?? _controller,
      child: widget.child,
    );
  }
}
