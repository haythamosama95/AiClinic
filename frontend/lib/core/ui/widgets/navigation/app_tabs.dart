import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:ai_clinic/core/ui/foundation.dart';
import 'package:ai_clinic/core/ui/widgets/actions/app_segmented_control.dart';
import 'package:ai_clinic/core/ui/widgets/display/app_badge.dart';

/// Visual layout for [AppTabs].
enum AppTabsVariant {
  /// Horizontal tabs with animated Signal underline (default).
  underline,

  /// Compact mutually exclusive pill control.
  segmented,

  /// Vertical stacked tabs with selected surface fill.
  vertical,
}

/// One tab entry inside [AppTabs].
class AppTabItem {
  const AppTabItem({
    required this.id,
    required this.label,
    this.disabled = false,
    this.count,
  });

  final String id;
  final String label;
  final bool disabled;

  /// Optional count rendered as a trailing [AppBadge].
  final int? count;
}

/// Tab list with Signal underline, segmented, or vertical variants.
class AppTabs extends StatefulWidget {
  const AppTabs({
    required this.items,
    required this.selectedId,
    required this.onChanged,
    this.variant = AppTabsVariant.underline,
    this.semanticLabel = 'Tabs',
    super.key,
  });

  final List<AppTabItem> items;
  final String selectedId;
  final ValueChanged<String> onChanged;
  final AppTabsVariant variant;
  final String semanticLabel;

  @override
  State<AppTabs> createState() => _AppTabsState();
}

class _AppTabsState extends State<AppTabs> {
  final GlobalKey _barKey = GlobalKey();
  final List<GlobalKey> _tabKeys = [];
  late final List<FocusNode> _focusNodes;

  double _indicatorStart = 0;
  double _indicatorWidth = 0;
  bool _indicatorReady = false;

  @override
  void initState() {
    super.initState();
    _syncKeysAndNodes();
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateIndicator());
  }

  @override
  void didUpdateWidget(covariant AppTabs oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.items.length != widget.items.length) {
      for (final node in _focusNodes) {
        node.dispose();
      }
      _syncKeysAndNodes();
    }
    if (oldWidget.selectedId != widget.selectedId ||
        oldWidget.variant != widget.variant) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _updateIndicator());
    }
  }

  void _syncKeysAndNodes() {
    _tabKeys
      ..clear()
      ..addAll(List.generate(widget.items.length, (_) => GlobalKey()));
    _focusNodes = List.generate(widget.items.length, (_) => FocusNode());
  }

  @override
  void dispose() {
    for (final node in _focusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  int get _selectedIndex =>
      widget.items.indexWhere((item) => item.id == widget.selectedId);

  List<int> get _enabledIndices => [
    for (var i = 0; i < widget.items.length; i++)
      if (!widget.items[i].disabled) i,
  ];

  void _updateIndicator() {
    if (widget.variant != AppTabsVariant.underline) return;
    final selectedIndex = _selectedIndex;
    if (selectedIndex < 0 || selectedIndex >= _tabKeys.length) {
      if (_indicatorReady) {
        setState(() => _indicatorReady = false);
      }
      return;
    }

    final tabContext = _tabKeys[selectedIndex].currentContext;
    final barContext = _barKey.currentContext;
    if (tabContext == null || barContext == null) return;

    final tabBox = tabContext.findRenderObject() as RenderBox?;
    final barBox = barContext.findRenderObject() as RenderBox?;
    if (tabBox == null || barBox == null || !tabBox.hasSize) return;

    final offset = tabBox.localToGlobal(Offset.zero, ancestor: barBox);
    final inset = AppSpacing.s2;
    final width = (tabBox.size.width - inset * 2).clamp(0.0, tabBox.size.width);

    setState(() {
      _indicatorStart = offset.dx + inset;
      _indicatorWidth = width;
      _indicatorReady = width > 0;
    });
  }

  void _selectIndex(int index) {
    final item = widget.items[index];
    if (item.disabled) return;
    widget.onChanged(item.id);
    _focusNodes[index].requestFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateIndicator());
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    final enabled = _enabledIndices;
    if (enabled.isEmpty) return KeyEventResult.ignored;

    final currentIndex = _selectedIndex;
    final currentEnabledPos = enabled.indexOf(currentIndex);
    if (currentEnabledPos < 0) return KeyEventResult.ignored;

    final isRtl = Directionality.of(context) == TextDirection.rtl;
    final isVertical = widget.variant == AppTabsVariant.vertical;

    int? nextEnabledPos;
    if ((isVertical && event.logicalKey == LogicalKeyboardKey.arrowDown) ||
        (!isVertical && event.logicalKey == LogicalKeyboardKey.arrowRight)) {
      nextEnabledPos = isRtl
          ? (currentEnabledPos - 1 + enabled.length) % enabled.length
          : (currentEnabledPos + 1) % enabled.length;
    } else if ((isVertical && event.logicalKey == LogicalKeyboardKey.arrowUp) ||
        (!isVertical && event.logicalKey == LogicalKeyboardKey.arrowLeft)) {
      nextEnabledPos = isRtl
          ? (currentEnabledPos + 1) % enabled.length
          : (currentEnabledPos - 1 + enabled.length) % enabled.length;
    } else if (event.logicalKey == LogicalKeyboardKey.home) {
      nextEnabledPos = 0;
    } else if (event.logicalKey == LogicalKeyboardKey.end) {
      nextEnabledPos = enabled.length - 1;
    }

    if (nextEnabledPos == null) return KeyEventResult.ignored;

    _selectIndex(enabled[nextEnabledPos]);
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.variant == AppTabsVariant.segmented) {
      return AppSegmentedControl<String>(
        options: [
          for (final item in widget.items)
            AppSegmentedOption<String>(
              value: item.id,
              label: item.label,
              disabled: item.disabled,
            ),
        ],
        value: widget.selectedId,
        onChanged: widget.onChanged,
        semanticLabel: widget.semanticLabel,
      );
    }

    return Focus(
      onKeyEvent: _handleKeyEvent,
      child: Semantics(
        container: true,
        label: widget.semanticLabel,
        child: widget.variant == AppTabsVariant.vertical
            ? _buildVertical(context)
            : _buildUnderline(context),
      ),
    );
  }

  Widget _buildVertical(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < widget.items.length; i++)
          _TabButton(
            key: _tabKeys[i],
            item: widget.items[i],
            selected: widget.items[i].id == widget.selectedId,
            focusNode: _focusNodes[i],
            variant: AppTabsVariant.vertical,
            onTap: () => _selectIndex(i),
          ),
      ].separated(const SizedBox(height: AppSpacing.s0_5)),
    );
  }

  Widget _buildUnderline(BuildContext context) {
    final colors = context.colors;
    final reduced = AppMotion.reduced(context);
    final motion = AppMotion.resolvePreset(
      AppMotionPreset.tab,
      reduced: reduced,
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: colors.borderSubtle),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Stack(
          key: _barKey,
          clipBehavior: Clip.none,
          children: [
            Row(
              children: [
                for (var i = 0; i < widget.items.length; i++)
                  _TabButton(
                    key: _tabKeys[i],
                    item: widget.items[i],
                    selected: widget.items[i].id == widget.selectedId,
                    focusNode: _focusNodes[i],
                    variant: AppTabsVariant.underline,
                    onTap: () => _selectIndex(i),
                  ),
              ],
            ),
            if (_indicatorReady)
              AnimatedPositioned(
                duration: motion.duration,
                curve: motion.curve,
                left: _indicatorStart,
                width: _indicatorWidth,
                bottom: 0,
                height: AppSignal.thickness,
                child: AppSignalLine(
                  orientation: AppSignalOrientation.horizontal,
                  length: _indicatorWidth,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.item,
    required this.selected,
    required this.focusNode,
    required this.variant,
    required this.onTap,
    super.key,
  });

  final AppTabItem item;
  final bool selected;
  final FocusNode focusNode;
  final AppTabsVariant variant;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;
    final isUnderline = variant == AppTabsVariant.underline;
    final isVertical = variant == AppTabsVariant.vertical;

    final padding = isUnderline
        ? const EdgeInsetsDirectional.fromSTEB(
            AppSpacing.s4,
            AppSpacing.s2,
            AppSpacing.s4,
            AppSpacing.s3,
          )
        : isVertical
        ? const EdgeInsetsDirectional.symmetric(
            horizontal: AppSpacing.s3,
            vertical: AppSpacing.s2,
          )
        : EdgeInsets.zero;

    return AppPressable.builder(
      enabled: !item.disabled,
      onTap: onTap,
      focusNode: focusNode,
      semanticLabel: item.label,
      borderRadius: AppRadii.mdAll,
      builder: (context, states, _) {
        final hovered = states.contains(WidgetState.hovered);
        Color foreground;
        Color? background;

        if (item.disabled) {
          foreground = colors.textDisabled;
        } else if (selected && isVertical) {
          foreground = colors.textPrimary;
          background = colors.surfaceSelected;
        } else if (selected) {
          foreground = colors.textPrimary;
        } else if (hovered) {
          foreground = colors.textPrimary;
          background = isVertical ? colors.surfaceHover : null;
        } else {
          foreground = colors.textSecondary;
          background = null;
        }

        final labelStyle = (isUnderline || isVertical
                ? typography.body
                : typography.bodyStrong)
            .copyWith(
              fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
              color: foreground,
            );

        return AnimatedContainer(
          duration: AppDurations.instant,
          curve: AppEasings.standard,
          padding: padding,
          decoration: BoxDecoration(
            color: background,
            borderRadius: AppRadii.mdAll,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(item.label, style: labelStyle),
              if (item.count != null) ...[
                const SizedBox(width: AppSpacing.s2),
                AppBadge(
                  size: AppBadgeSize.sm,
                  label: _formatWesternInt(item.count!),
                ),
              ],
            ],
          ),
        );
      },
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

extension on List<Widget> {
  List<Widget> separated(Widget separator) {
    if (length <= 1) return this;
    return [
      for (var i = 0; i < length; i++) ...[
        if (i > 0) separator,
        this[i],
      ],
    ];
  }
}
