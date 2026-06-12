import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/settings/presentation/widgets/settings_cards_grid.dart';

/// Grid of cards that fade in and out when filter visibility changes.
class AnimatedFilterCardsGrid<T> extends StatefulWidget {
  const AnimatedFilterCardsGrid({
    required this.items,
    required this.isVisible,
    required this.itemKey,
    required this.itemBuilder,
    this.columns = 2,
    this.enforceColumns = false,
    this.emptyPlaceholder,
    super.key,
  });

  final List<T> items;
  final bool Function(T item) isVisible;
  final Object Function(T item) itemKey;
  final Widget Function(T item) itemBuilder;
  final int columns;
  final bool enforceColumns;
  final Widget? emptyPlaceholder;

  @override
  State<AnimatedFilterCardsGrid<T>> createState() => _AnimatedFilterCardsGridState<T>();
}

class _AnimatedFilterCardsGridState<T> extends State<AnimatedFilterCardsGrid<T>> {
  final _displayedKeys = <Object>[];
  final _keysPendingFadeIn = <Object>{};

  @override
  void initState() {
    super.initState();
    _syncDisplayedKeys();
  }

  @override
  void didUpdateWidget(covariant AnimatedFilterCardsGrid<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncDisplayedKeys();
  }

  void _syncDisplayedKeys() {
    final previouslyDisplayed = _displayedKeys.toSet();
    final nextKeys = <Object>[];

    for (final item in widget.items) {
      final key = widget.itemKey(item);
      if (widget.isVisible(item)) {
        if (!previouslyDisplayed.contains(key)) {
          _keysPendingFadeIn.add(key);
        }
        nextKeys.add(key);
      } else if (previouslyDisplayed.contains(key)) {
        // Keep fading-out cards in the grid until [AppFadeInOutPanel.onHidden].
        nextKeys.add(key);
      }
    }

    _displayedKeys
      ..clear()
      ..addAll(nextKeys);
  }

  void _removeKey(Object key) {
    if (!mounted || !_displayedKeys.contains(key)) {
      return;
    }
    setState(() => _displayedKeys.remove(key));
  }

  @override
  Widget build(BuildContext context) {
    final itemByKey = {for (final item in widget.items) widget.itemKey(item): item};
    final children = <Widget>[
      for (final key in _displayedKeys)
        if (itemByKey.containsKey(key))
          AppFadeInOutPanel(
            key: ValueKey(key),
            visible: widget.isVisible(itemByKey[key] as T),
            animateOnMount: _keysPendingFadeIn.remove(key),
            onHidden: () => _removeKey(key),
            child: widget.itemBuilder(itemByKey[key] as T),
          ),
    ];

    final showEmpty = !widget.items.any(widget.isVisible) && _displayedKeys.isEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (children.isNotEmpty)
          SettingsCardsGrid(columns: widget.columns, enforceColumns: widget.enforceColumns, children: children),
        if (widget.emptyPlaceholder != null) AppFadeInOutPanel(visible: showEmpty, child: widget.emptyPlaceholder!),
      ],
    );
  }
}
