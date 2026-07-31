import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:ai_clinic/core/ui/components/app_input_styles.dart';
import 'package:ai_clinic/core/ui/components/app_segmented_control.dart';
import 'package:ai_clinic/core/ui/components/app_signal.dart';
import 'package:ai_clinic/core/ui/motion/app_motion.dart';
import 'package:ai_clinic/core/ui/theme/app_color_primitives.dart';
import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';

/// Variant for [AppTabs] (web `underline` | `segmented` | `vertical`).
enum AppTabsVariant { underline, segmented, vertical }

/// A single tab entry in [AppTabs].
class AppTabItem {
  const AppTabItem({required this.id, required this.label, this.icon, this.disabled = false});

  final String id;
  final String label;
  final IconData? icon;
  final bool disabled;
}

/// Application-owned tabs (`04-components` navigation).
///
/// Underline variant animates an [AppSignal] indicator; segmented delegates to
/// [AppSegmentedControl]; vertical stacks tab buttons with roving focus.
class AppTabs extends StatelessWidget {
  const AppTabs({
    required this.items,
    required this.value,
    required this.onChanged,
    this.variant = AppTabsVariant.underline,
    this.ariaLabel = 'Tabs',
    super.key,
  });

  final List<AppTabItem> items;
  final String value;
  final ValueChanged<String> onChanged;
  final AppTabsVariant variant;
  final String ariaLabel;

  @override
  Widget build(BuildContext context) {
    return switch (variant) {
      AppTabsVariant.segmented => AppSegmentedControl<String>(
        options: [
          for (final item in items)
            SegmentedOption<String>(value: item.id, label: Text(item.label), disabled: item.disabled),
        ],
        value: value,
        onChanged: onChanged,
        ariaLabel: ariaLabel,
      ),
      AppTabsVariant.vertical => _AppTabList(
        items: items,
        value: value,
        onChanged: onChanged,
        ariaLabel: ariaLabel,
        isVertical: true,
      ),
      AppTabsVariant.underline => _AppTabList(
        items: items,
        value: value,
        onChanged: onChanged,
        ariaLabel: ariaLabel,
        isVertical: false,
      ),
    };
  }
}

class _AppTabList extends StatefulWidget {
  const _AppTabList({
    required this.items,
    required this.value,
    required this.onChanged,
    required this.ariaLabel,
    required this.isVertical,
  });

  final List<AppTabItem> items;
  final String value;
  final ValueChanged<String> onChanged;
  final String ariaLabel;
  final bool isVertical;

  @override
  State<_AppTabList> createState() => _AppTabListState();
}

class _AppTabListState extends State<_AppTabList> {
  final _tabListKey = GlobalKey();
  late List<GlobalKey> _tabKeys = _createTabKeys();
  late List<FocusNode> _focusNodes = _createFocusNodes();

  double? _signalLeft;
  double? _signalWidth;

  List<GlobalKey> _createTabKeys() => List.generate(widget.items.length, (_) => GlobalKey());

  List<FocusNode> _createFocusNodes() {
    final nodes = List.generate(widget.items.length, (_) => FocusNode());
    for (final node in nodes) {
      node.onKeyEvent = _handleKeyEvent;
    }
    return nodes;
  }

  void _disposeFocusNodes() {
    for (final node in _focusNodes) {
      node.onKeyEvent = null;
      node.dispose();
    }
  }

  List<int> get _enabledIndices {
    return [
      for (var i = 0; i < widget.items.length; i++)
        if (!widget.items[i].disabled) i,
    ];
  }

  @override
  void initState() {
    super.initState();
    if (!widget.isVertical) {
      WidgetsBinding.instance.addPostFrameCallback(_measureSelectedTab);
    }
  }

  @override
  void didUpdateWidget(covariant _AppTabList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.items.length != widget.items.length) {
      _disposeFocusNodes();
      _tabKeys = _createTabKeys();
      _focusNodes = _createFocusNodes();
    }
    if (!widget.isVertical &&
        (oldWidget.value != widget.value ||
            oldWidget.items.length != widget.items.length ||
            oldWidget.isVertical != widget.isVertical)) {
      WidgetsBinding.instance.addPostFrameCallback(_measureSelectedTab);
    }
  }

  @override
  void dispose() {
    _disposeFocusNodes();
    super.dispose();
  }

  void _measureSelectedTab(_) {
    if (!mounted || widget.isVertical) return;

    final selectedIndex = widget.items.indexWhere((item) => item.id == widget.value);
    if (selectedIndex < 0) return;

    final tabBox = _tabKeys[selectedIndex].currentContext?.findRenderObject() as RenderBox?;
    final listBox = _tabListKey.currentContext?.findRenderObject() as RenderBox?;
    if (tabBox == null || !tabBox.hasSize || listBox == null || !listBox.hasSize) return;

    final offset = tabBox.localToGlobal(Offset.zero, ancestor: listBox);
    final inset = AppSpacing.space2;
    final newLeft = offset.dx + inset;
    final newWidth = tabBox.size.width - inset * 2;

    if (_signalLeft != newLeft || _signalWidth != newWidth) {
      setState(() {
        _signalLeft = newLeft;
        _signalWidth = newWidth;
      });
    }
  }

  void _focusItem(int index) {
    _focusNodes[index].requestFocus();
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    final currentIndex = widget.items.indexWhere((item) => item.id == widget.value);
    final enabledIndices = _enabledIndices;
    final currentEnabledPos = enabledIndices.indexOf(currentIndex);
    if (currentEnabledPos < 0) return KeyEventResult.ignored;

    final int nextEnabledPos;

    if (widget.isVertical) {
      if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
        nextEnabledPos = (currentEnabledPos + 1) % enabledIndices.length;
      } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
        nextEnabledPos = (currentEnabledPos - 1 + enabledIndices.length) % enabledIndices.length;
      } else if (event.logicalKey == LogicalKeyboardKey.home) {
        nextEnabledPos = 0;
      } else if (event.logicalKey == LogicalKeyboardKey.end) {
        nextEnabledPos = enabledIndices.length - 1;
      } else {
        return KeyEventResult.ignored;
      }
    } else {
      if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
        nextEnabledPos = (currentEnabledPos + 1) % enabledIndices.length;
      } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
        nextEnabledPos = (currentEnabledPos - 1 + enabledIndices.length) % enabledIndices.length;
      } else if (event.logicalKey == LogicalKeyboardKey.home) {
        nextEnabledPos = 0;
      } else if (event.logicalKey == LogicalKeyboardKey.end) {
        nextEnabledPos = enabledIndices.length - 1;
      } else {
        return KeyEventResult.ignored;
      }
    }

    final nextIndex = enabledIndices[nextEnabledPos];
    widget.onChanged(widget.items[nextIndex].id);
    _focusItem(nextIndex);
    return KeyEventResult.handled;
  }

  Duration _tabMotionDuration(BuildContext context) {
    return AppMotion.resolveDurationFromTokens(
      context: context,
      duration: AppMotionDurationToken.quick,
      ease: AppMotionEasingToken.inOut,
    );
  }

  Curve _tabMotionCurve(BuildContext context) {
    return AppMotion.resolveCurveFromTokens(context: context, ease: AppMotionEasingToken.inOut);
  }

  @override
  Widget build(BuildContext context) {
    final tabButtons = [
      for (var index = 0; index < widget.items.length; index++)
        _AppTabButton(
          key: _tabKeys[index],
          item: widget.items[index],
          selected: widget.items[index].id == widget.value,
          isVertical: widget.isVertical,
          focusNode: _focusNodes[index],
          onSelected: () => widget.onChanged(widget.items[index].id),
        ),
    ];

    if (widget.isVertical) {
      return Semantics(
        container: true,
        label: widget.ariaLabel,
        child: Column(
          key: _tabListKey,
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var index = 0; index < tabButtons.length; index++) ...[
              if (index > 0) const SizedBox(height: AppSpacing.space1),
              tabButtons[index],
            ],
          ],
        ),
      );
    }

    final duration = _tabMotionDuration(context);
    final curve = _tabMotionCurve(context);

    return Semantics(
      container: true,
      label: widget.ariaLabel,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: context.appColors.borderSubtle)),
        ),
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.bottomLeft,
          children: [
            Row(
              key: _tabListKey,
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var index = 0; index < tabButtons.length; index++) ...[
                  if (index > 0) const SizedBox(width: AppSpacing.space1),
                  tabButtons[index],
                ],
              ],
            ),
            if (_signalLeft != null && _signalWidth != null)
              AnimatedPositioned(
                duration: duration,
                curve: curve,
                left: _signalLeft,
                bottom: 0,
                width: _signalWidth,
                child: const AppSignal(orientation: Axis.horizontal),
              ),
          ],
        ),
      ),
    );
  }
}

class _AppTabButton extends StatefulWidget {
  const _AppTabButton({
    required this.item,
    required this.selected,
    required this.isVertical,
    required this.focusNode,
    required this.onSelected,
    super.key,
  });

  final AppTabItem item;
  final bool selected;
  final bool isVertical;
  final FocusNode focusNode;
  final VoidCallback onSelected;

  @override
  State<_AppTabButton> createState() => _AppTabButtonState();
}

class _AppTabButtonState extends State<_AppTabButton> {
  var _hovered = false;

  Color _textColor(AppSemanticColors colors) {
    if (widget.item.disabled) {
      return Theme.of(context).brightness == Brightness.dark
          ? AppColorPrimitives.textDisabledDark
          : AppColorPrimitives.neutral400;
    }
    if (widget.selected || _hovered) {
      return colors.textPrimary;
    }
    return colors.textSecondary;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final textStyle = widget.selected ? AppTypography.bodyStrong(context) : AppTypography.body(context);
    final padding = widget.isVertical
        ? const EdgeInsets.symmetric(horizontal: AppSpacing.space3, vertical: AppSpacing.space2)
        : const EdgeInsetsDirectional.fromSTEB(
            AppSpacing.space4,
            AppSpacing.space2,
            AppSpacing.space4,
            AppSpacing.space3,
          );

    return Semantics(
      button: true,
      enabled: !widget.item.disabled,
      selected: widget.selected,
      child: Focus(
        focusNode: widget.focusNode,
        skipTraversal: !widget.selected,
        canRequestFocus: !widget.item.disabled,
        child: Builder(
          builder: (context) {
            final focused = Focus.of(context).hasFocus;
            final focusRing = focused
                ? [BoxShadow(color: appInputFocusRingColor(context), blurRadius: 0, spreadRadius: 2)]
                : null;
            final label = Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.item.icon != null) ...[
                  Icon(widget.item.icon, size: 16, color: _textColor(colors)),
                  const SizedBox(width: AppSpacing.space2),
                ],
                Text(
                  widget.item.label,
                  style: textStyle.copyWith(color: _textColor(colors)),
                  textAlign: widget.isVertical ? TextAlign.start : TextAlign.center,
                ),
              ],
            );

            if (widget.isVertical) {
              return MouseRegion(
                onEnter: widget.item.disabled ? null : (_) => setState(() => _hovered = true),
                onExit: (_) => setState(() => _hovered = false),
                cursor: widget.item.disabled ? SystemMouseCursors.basic : SystemMouseCursors.click,
                child: Material(
                  color: widget.selected ? colors.surfaceSelected : Colors.transparent,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  child: InkWell(
                    onTap: widget.item.disabled ? null : widget.onSelected,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    hoverColor: widget.selected || widget.item.disabled ? Colors.transparent : colors.surfaceHover,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        boxShadow: focusRing,
                      ),
                      child: Padding(padding: padding, child: label),
                    ),
                  ),
                ),
              );
            }

            return MouseRegion(
              onEnter: widget.item.disabled ? null : (_) => setState(() => _hovered = true),
              onExit: (_) => setState(() => _hovered = false),
              cursor: widget.item.disabled ? SystemMouseCursors.basic : SystemMouseCursors.click,
              child: GestureDetector(
                onTap: widget.item.disabled ? null : widget.onSelected,
                behavior: HitTestBehavior.opaque,
                child: DecoratedBox(
                  decoration: BoxDecoration(boxShadow: focusRing),
                  child: Padding(padding: padding, child: label),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
