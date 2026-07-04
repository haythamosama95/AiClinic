import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:ai_clinic/core/ui/motion/app_motion.dart';
import 'package:ai_clinic/core/ui/providers/density_provider.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/theme_context_extensions.dart';
import 'package:ai_clinic/core/ui/widgets/actions/segmented_control.dart';
import 'package:ai_clinic/core/ui/widgets/signal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Single tab in [AppTabs].
@immutable
class TabItem {
  const TabItem({
    required this.id,
    required this.label,
    this.disabled = false,
  });

  final String id;
  final Widget label;
  final bool disabled;
}

enum AppTabsVariant { underline, segmented, vertical }

/// Tab list with underline, segmented, or vertical variants.
class AppTabs extends ConsumerStatefulWidget {
  const AppTabs({
    super.key,
    required this.items,
    required this.value,
    required this.onChange,
    this.variant = AppTabsVariant.underline,
    this.ariaLabel = 'Tabs',
  });

  final List<TabItem> items;
  final String value;
  final ValueChanged<String> onChange;
  final AppTabsVariant variant;
  final String ariaLabel;

  @override
  ConsumerState<AppTabs> createState() => _AppTabsState();
}

class _AppTabsState extends ConsumerState<AppTabs> {
  final GlobalKey _tabListKey = GlobalKey();
  final List<GlobalKey> _tabKeys = [];
  final List<FocusNode> _focusNodes = [];

  double _underlineStart = 0;
  double _underlineExtent = 0;
  bool _underlineReady = false;

  @override
  void initState() {
    super.initState();
    _syncKeys();
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateUnderline());
  }

  @override
  void didUpdateWidget(AppTabs oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.items.length != widget.items.length ||
        oldWidget.value != widget.value) {
      if (oldWidget.items.length != widget.items.length) {
        _syncKeys();
      }
      WidgetsBinding.instance.addPostFrameCallback((_) => _updateUnderline());
    }
  }

  @override
  void dispose() {
    for (final node in _focusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  void _syncKeys() {
    for (final node in _focusNodes) {
      node.dispose();
    }
    _tabKeys
      ..clear()
      ..addAll(List.generate(widget.items.length, (_) => GlobalKey()));
    _focusNodes
      ..clear()
      ..addAll(List.generate(widget.items.length, (_) => FocusNode()));
  }

  List<int> get _enabledIndices => [
    for (var i = 0; i < widget.items.length; i++)
      if (!widget.items[i].disabled) i,
  ];

  int get _selectedIndex =>
      widget.items.indexWhere((item) => item.id == widget.value);

  void _updateUnderline() {
    if (!mounted || widget.variant != AppTabsVariant.underline) return;

    final selectedIndex = _selectedIndex;
    if (selectedIndex < 0 || selectedIndex >= _tabKeys.length) return;

    final tabBox =
        _tabKeys[selectedIndex].currentContext?.findRenderObject() as RenderBox?;
    final listBox =
        _tabListKey.currentContext?.findRenderObject() as RenderBox?;
    if (tabBox == null ||
        listBox == null ||
        !tabBox.hasSize ||
        !listBox.hasSize) {
      return;
    }

    final offset = tabBox.localToGlobal(Offset.zero, ancestor: listBox);
    final isRtl = Directionality.of(context) == TextDirection.rtl;
    final nextStart = isRtl
        ? listBox.size.width - offset.dx - tabBox.size.width
        : offset.dx;

    setState(() {
      _underlineStart = nextStart;
      _underlineExtent = tabBox.size.width;
      _underlineReady = true;
    });
  }

  void _focusTab(int index) {
    if (index >= 0 && index < _focusNodes.length) {
      _focusNodes[index].requestFocus();
    }
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    final enabled = _enabledIndices;
    if (enabled.isEmpty) return KeyEventResult.ignored;

    final currentIndex = _selectedIndex;
    final currentEnabledPos = enabled.indexOf(currentIndex);
    if (currentEnabledPos < 0) return KeyEventResult.ignored;

    final isVertical = widget.variant == AppTabsVariant.vertical;
    int? nextEnabledPos;

    if ((isVertical && event.logicalKey == LogicalKeyboardKey.arrowDown) ||
        (!isVertical && event.logicalKey == LogicalKeyboardKey.arrowRight)) {
      nextEnabledPos = (currentEnabledPos + 1) % enabled.length;
    } else if ((isVertical && event.logicalKey == LogicalKeyboardKey.arrowUp) ||
        (!isVertical && event.logicalKey == LogicalKeyboardKey.arrowLeft)) {
      nextEnabledPos =
          (currentEnabledPos - 1 + enabled.length) % enabled.length;
    } else if (event.logicalKey == LogicalKeyboardKey.home) {
      nextEnabledPos = 0;
    } else if (event.logicalKey == LogicalKeyboardKey.end) {
      nextEnabledPos = enabled.length - 1;
    } else {
      return KeyEventResult.ignored;
    }

    final nextIndex = enabled[nextEnabledPos];
    final nextId = widget.items[nextIndex].id;
    widget.onChange(nextId);
    _focusTab(nextIndex);
    return KeyEventResult.handled;
  }

  EdgeInsets _tabPadding(AppDensity density) {
    if (widget.variant == AppTabsVariant.vertical) {
      return switch (density) {
        AppDensity.compact => const EdgeInsets.symmetric(
          horizontal: AppSpacing.s3,
          vertical: AppSpacing.s1 + AppSpacing.s0_5,
        ),
        AppDensity.default_ => const EdgeInsets.symmetric(
          horizontal: AppSpacing.s3,
          vertical: AppSpacing.s2,
        ),
        AppDensity.comfortable => const EdgeInsets.symmetric(
          horizontal: AppSpacing.s3,
          vertical: AppSpacing.s2 + AppSpacing.s0_5,
        ),
      };
    }

    return switch (density) {
      AppDensity.compact => const EdgeInsets.fromLTRB(
        AppSpacing.s3,
        AppSpacing.s2,
        AppSpacing.s3,
        AppSpacing.s2,
      ),
      AppDensity.default_ => const EdgeInsets.fromLTRB(
        AppSpacing.s4,
        AppSpacing.s2,
        AppSpacing.s4,
        AppSpacing.s3,
      ),
      AppDensity.comfortable => const EdgeInsets.fromLTRB(
        AppSpacing.s4,
        AppSpacing.s2,
        AppSpacing.s4,
        AppSpacing.s3,
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    if (widget.variant == AppTabsVariant.segmented) {
      return AppSegmentedControl<String>(
        semanticLabel: widget.ariaLabel,
        selected: widget.value,
        onChanged: widget.onChange,
        options: [
          for (final item in widget.items)
            AppSegmentedOption<String>(
              value: item.id,
              label: item.label,
              disabled: item.disabled,
            ),
        ],
      );
    }

    final density = ref.watch(appDensityProvider);
    final colors = context.colors;
    final reducedMotion = AppMotion.isReducedMotion(context);
    final underlineDuration = reducedMotion
        ? Duration.zero
        : AppMotion.resolveTransition(
            preset: AppMotionPreset.tab,
            reducedMotion: false,
          ).duration;

    final isVertical = widget.variant == AppTabsVariant.vertical;

    return Semantics(
      container: true,
      label: widget.ariaLabel,
      child: Focus(
        onKeyEvent: _handleKeyEvent,
        child: DecoratedBox(
          key: _tabListKey,
          decoration: isVertical
              ? const BoxDecoration()
              : BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: colors.borderSubtle),
                  ),
                ),
          child: isVertical
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: _buildTabs(density),
                )
              : Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: _buildTabs(density),
                    ),
                    if (_underlineReady)
                      AnimatedPositioned(
                        duration: underlineDuration,
                        curve: AppCurves.inOut,
                        left: Directionality.of(context) == TextDirection.rtl
                            ? null
                            : _underlineStart,
                        right: Directionality.of(context) == TextDirection.rtl
                            ? _underlineStart
                            : null,
                        bottom: 0,
                        width: _underlineExtent,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.s1,
                          ),
                          child: const Signal(
                            orientation: SignalOrientation.horizontal,
                          ),
                        ),
                      ),
                  ],
                ),
        ),
      ),
    );
  }

  List<Widget> _buildTabs(AppDensity density) {
    return [
      for (var index = 0; index < widget.items.length; index++)
        _TabButton(
          key: _tabKeys[index],
          item: widget.items[index],
          selected: widget.items[index].id == widget.value,
          focusNode: _focusNodes[index],
          padding: _tabPadding(density),
          vertical: widget.variant == AppTabsVariant.vertical,
          onSelected: () {
            widget.onChange(widget.items[index].id);
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _updateUnderline();
            });
          },
          onFocus: () => WidgetsBinding.instance.addPostFrameCallback((_) {
            _updateUnderline();
          }),
        ),
    ];
  }
}

class _TabButton extends StatefulWidget {
  const _TabButton({
    super.key,
    required this.item,
    required this.selected,
    required this.focusNode,
    required this.padding,
    required this.vertical,
    required this.onSelected,
    required this.onFocus,
  });

  final TabItem item;
  final bool selected;
  final FocusNode focusNode;
  final EdgeInsets padding;
  final bool vertical;
  final VoidCallback onSelected;
  final VoidCallback onFocus;

  @override
  State<_TabButton> createState() => _TabButtonState();
}

class _TabButtonState extends State<_TabButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final disabled = widget.item.disabled;
    final selected = widget.selected;

    Color foreground;
    if (disabled) {
      foreground = colors.textDisabled;
    } else if (selected) {
      foreground = colors.textPrimary;
    } else if (_hovered) {
      foreground = colors.textPrimary;
    } else {
      foreground = colors.textSecondary;
    }

    final background = widget.vertical && selected
        ? colors.surfaceSelected
        : (!widget.vertical && _hovered && !disabled)
        ? Colors.transparent
        : widget.vertical && _hovered && !disabled
        ? colors.surfaceHover
        : Colors.transparent;

    return Focus(
      focusNode: widget.focusNode,
      onFocusChange: (focused) {
        if (focused) widget.onFocus();
      },
      child: MouseRegion(
        onEnter: disabled ? null : (_) => setState(() => _hovered = true),
        onExit: disabled ? null : (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: disabled ? null : widget.onSelected,
          child: Semantics(
            selected: selected,
            button: true,
            enabled: !disabled,
            child: AnimatedContainer(
              duration: AppDurations.instant,
              padding: widget.padding,
              decoration: BoxDecoration(
                color: background,
                borderRadius: widget.vertical ? BorderRadius.circular(6) : null,
              ),
              child: DefaultTextStyle(
                style: context.typography.body.copyWith(
                  color: foreground,
                  fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
                ),
                textAlign: widget.vertical ? TextAlign.start : TextAlign.center,
                child: widget.item.label,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
