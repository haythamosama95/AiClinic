import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:ai_clinic/core/ui/motion/app_motion.dart';
import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/theme_context_extensions.dart';
import 'package:ai_clinic/core/ui/widgets/display/avatar.dart';
import 'package:ai_clinic/core/ui/widgets/display/kbd.dart';
import 'package:ai_clinic/core/ui/widgets/signal.dart';

/// Command palette item matching web `CommandItem`.
@immutable
class CommandItem {
  const CommandItem({
    required this.id,
    required this.group,
    required this.label,
    this.meta,
    this.icon,
    this.shortcut,
    this.avatarName,
    required this.onSelect,
  });

  final String id;
  final String group;
  final String label;
  final String? meta;
  final Widget? icon;
  final List<String>? shortcut;
  final String? avatarName;
  final VoidCallback onSelect;
}

const _askAiId = '__ask_ai__';

/// Command palette overlay — presentation only; open/close wired by parent.
class AppCommandBar extends StatefulWidget {
  const AppCommandBar({
    super.key,
    required this.open,
    required this.onClose,
    required this.items,
    this.recentItems = const [],
    this.placeholder = 'Search patients, pages, or actions…',
    this.aiMode = false,
    this.onAiModeChange,
  });

  final bool open;
  final VoidCallback onClose;
  final List<CommandItem> items;
  final List<CommandItem> recentItems;
  final String placeholder;
  final bool aiMode;
  final ValueChanged<bool>? onAiModeChange;

  @override
  State<AppCommandBar> createState() => _AppCommandBarState();
}

class _AppCommandBarState extends State<AppCommandBar> {
  final TextEditingController _queryController = TextEditingController();
  final FocusNode _inputFocusNode = FocusNode();
  final FocusNode _dialogFocusNode = FocusNode();
  final ScrollController _listScrollController = ScrollController();
  final Map<int, GlobalKey> _itemKeys = {};

  int _highlightIndex = 0;
  bool _aiEntry = false;
  String? _aiResponse;

  @override
  void initState() {
    super.initState();
    if (widget.open) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _focusInput());
    }
  }

  @override
  void didUpdateWidget(AppCommandBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.open && !oldWidget.open) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _focusInput());
    } else if (!widget.open && oldWidget.open) {
      _reset();
    }
  }

  @override
  void dispose() {
    _queryController.dispose();
    _inputFocusNode.dispose();
    _dialogFocusNode.dispose();
    _listScrollController.dispose();
    super.dispose();
  }

  void _focusInput() {
    if (mounted && widget.open) {
      _dialogFocusNode.requestFocus();
      _inputFocusNode.requestFocus();
    }
  }

  void _reset() {
    _queryController.clear();
    _highlightIndex = 0;
    _aiEntry = false;
    _aiResponse = null;
    widget.onAiModeChange?.call(false);
  }

  void _handleClose() {
    widget.onClose();
    _reset();
  }

  CommandItem _askAiItem(BuildContext context) => CommandItem(
    id: _askAiId,
    group: 'AI',
    label: 'Ask AI…',
    meta: 'Natural language assistant',
    icon: Icon(Icons.auto_awesome, size: 16, color: context.colors.textAi),
    shortcut: const ['↵'],
    onSelect: _enterAiMode,
  );

  void _enterAiMode() {
    setState(() {
      _aiEntry = true;
      widget.onAiModeChange?.call(true);
      final query = _queryController.text.trim();
      if (query.isNotEmpty) {
        _aiResponse =
            'Here\'s a suggested starting point for "$query": review recent patient charts and schedule a follow-up.';
      }
    });
  }

  List<CommandItem> _filtered(BuildContext context) {
    final query = _queryController.text.trim().toLowerCase();
    final base = query.isNotEmpty
        ? widget.items.where((item) {
            return item.label.toLowerCase().contains(query) ||
                (item.meta?.toLowerCase().contains(query) ?? false) ||
                item.group.toLowerCase().contains(query);
          }).toList()
        : widget.recentItems.isNotEmpty
        ? widget.recentItems
        : widget.items;

    if (!_aiEntry && (query.length > 8 || query.contains('?'))) {
      return [...base, _askAiItem(context)];
    }
    return base;
  }

  Map<String, List<CommandItem>> _grouped(BuildContext context) {
    final map = <String, List<CommandItem>>{};
    for (final item in _filtered(context)) {
      map.putIfAbsent(item.group, () => []).add(item);
    }
    return map;
  }

  void _activateItem(CommandItem item) {
    if (item.id == _askAiId) {
      _enterAiMode();
      return;
    }
    item.onSelect();
    _handleClose();
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    if (event.logicalKey == LogicalKeyboardKey.escape) {
      if (_aiEntry) {
        setState(() {
          _aiEntry = false;
          _aiResponse = null;
          widget.onAiModeChange?.call(false);
        });
      } else {
        _handleClose();
      }
      return KeyEventResult.handled;
    }

    if (_aiEntry) return KeyEventResult.ignored;

    final flatList = _filtered(context);
    if (flatList.isEmpty) return KeyEventResult.ignored;

    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      setState(() => _highlightIndex = (_highlightIndex + 1) % flatList.length);
      _scrollToHighlight();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      setState(
        () => _highlightIndex =
            (_highlightIndex - 1 + flatList.length) % flatList.length,
      );
      _scrollToHighlight();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.home) {
      setState(() => _highlightIndex = 0);
      _scrollToHighlight();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.end) {
      setState(() => _highlightIndex = flatList.length - 1);
      _scrollToHighlight();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter) {
      _activateItem(flatList[_highlightIndex]);
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  void _scrollToHighlight() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final key = _itemKeys[_highlightIndex];
      final context = key?.currentContext;
      if (context != null) {
        Scrollable.ensureVisible(
          context,
          duration: AppDurations.fast,
          curve: AppCurves.standard,
          alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
        );
      }
    });
  }

  String _initialsFromName(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty) return '?';
    if (parts.length == 1) {
      return parts.first.characters.take(2).toString().toUpperCase();
    }
    return '${parts.first.characters.first}${parts.last.characters.first}'
        .toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.open) return const SizedBox.shrink();

    final colors = context.colors;
    final typography = context.typography;
    final elevation = context.elevation;
    final reducedMotion = AppMotion.isReducedMotion(context);
    final commandTransition = AppMotion.resolveTransition(
      preset: AppMotionPreset.command,
      reducedMotion: reducedMotion,
    );
    final fadeTransition = AppMotion.resolveTransition(
      preset: AppMotionPreset.fade,
      reducedMotion: reducedMotion,
    );

    final aiActive = _aiEntry || widget.aiMode;
    final flatList = _filtered(context);
    final grouped = _grouped(context);

    return Stack(
      fit: StackFit.expand,
      children: [
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: fadeTransition.duration,
          curve: fadeTransition.curve,
          builder: (context, opacity, child) {
            return Opacity(opacity: opacity, child: child);
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _handleClose,
            child: ClipRect(
              child: BackdropFilter(
                filter: reducedMotion
                    ? ImageFilter.blur()
                    : ImageFilter.blur(sigmaX: 4, sigmaY: 4),
                child: ColoredBox(color: colors.surfaceBackdrop),
              ),
            ),
          ),
        ),
        Align(
          alignment: Alignment.topCenter,
          child: Padding(
            padding: EdgeInsets.only(
              top: MediaQuery.sizeOf(context).height * 0.12,
              left: AppSpacing.s4,
              right: AppSpacing.s4,
            ),
            child: Focus(
              focusNode: _dialogFocusNode,
              autofocus: true,
              onKeyEvent: _handleKeyEvent,
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: commandTransition.duration,
                curve: commandTransition.curve,
                builder: (context, t, child) {
                  final hidden = AppMotion.hiddenValues(
                    AppMotionPreset.command,
                    direction: Directionality.of(context),
                  );
                  final visible = AppMotion.visibleValues;
                  final values = hidden.lerp(visible, t);
                  return Opacity(
                    opacity: values.opacity,
                    child: Transform.translate(
                      offset: Offset(0, values.dy),
                      child: Transform.scale(
                        scale: values.scale,
                        child: child,
                      ),
                    ),
                  );
                },
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 576),
                  child: Material(
                    color: Colors.transparent,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: colors.surfaceRaised,
                        borderRadius: AppRadius.xlAll,
                        border: Border.all(color: colors.borderDefault),
                        boxShadow: elevation.level3,
                      ),
                      child: ClipRRect(
                        borderRadius: AppRadius.xlAll,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Semantics(
                              label: 'Command bar',
                              header: true,
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  AppSpacing.s4,
                                  AppSpacing.s4,
                                  AppSpacing.s4,
                                  AppSpacing.s3,
                                ),
                                child: _CommandInput(
                                  controller: _queryController,
                                  focusNode: _inputFocusNode,
                                  aiActive: aiActive,
                                  aiEntry: _aiEntry,
                                  aiThinking: _aiEntry && _aiResponse == null,
                                  placeholder: widget.placeholder,
                                  onChanged: (_) {
                                    setState(() => _highlightIndex = 0);
                                  },
                                ),
                              ),
                            ),
                            if (_aiEntry)
                              _AiPanel(response: _aiResponse)
                            else
                              _ResultsList(
                                query: _queryController.text,
                                flatList: flatList,
                                grouped: grouped,
                                highlightIndex: _highlightIndex,
                                scrollController: _listScrollController,
                                itemKeys: _itemKeys,
                                onHighlight: (index) =>
                                    setState(() => _highlightIndex = index),
                                onActivate: _activateItem,
                                initialsFromName: _initialsFromName,
                              ),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.s4,
                                vertical: AppSpacing.s2,
                              ),
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  border: Border(
                                    top: BorderSide(color: colors.borderSubtle),
                                  ),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.only(
                                    top: AppSpacing.s2,
                                  ),
                                  child: Wrap(
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    spacing: AppSpacing.s1,
                                    children: [
                                      AppKbd(keys: const ['↑', '↓']),
                                      Text(
                                        ' navigate · ',
                                        style: typography.caption.copyWith(
                                          color: colors.textTertiary,
                                        ),
                                      ),
                                      AppKbd(keys: const ['↵']),
                                      Text(
                                        ' select · ',
                                        style: typography.caption.copyWith(
                                          color: colors.textTertiary,
                                        ),
                                      ),
                                      AppKbd(keys: const ['Esc']),
                                      Text(
                                        ' close',
                                        style: typography.caption.copyWith(
                                          color: colors.textTertiary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _CommandInput extends StatelessWidget {
  const _CommandInput({
    required this.controller,
    required this.focusNode,
    required this.aiActive,
    required this.aiEntry,
    required this.aiThinking,
    required this.placeholder,
    required this.onChanged,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool aiActive;
  final bool aiEntry;
  final bool aiThinking;
  final String placeholder;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: colors.surfaceDefault,
            borderRadius: AppRadius.mdAll,
            border: Border.all(
              color: aiActive ? colors.borderAi : colors.borderDefault,
              width: aiActive ? 1.5 : 1,
            ),
            boxShadow: aiActive
                ? [
                    BoxShadow(
                      color: colors.focusRingAi.withValues(alpha: 0.35),
                      blurRadius: 0,
                      spreadRadius: 2,
                    ),
                  ]
                : null,
          ),
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            autofocus: true,
            style: typography.body.copyWith(color: colors.textPrimary),
            cursorColor: aiActive ? colors.borderAi : colors.borderFocus,
            decoration: InputDecoration(
              border: InputBorder.none,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.s3,
                vertical: 10,
              ),
              hintText: aiEntry
                  ? 'Ask AI anything about your clinic…'
                  : placeholder,
              hintStyle: typography.body.copyWith(
                color: colors.textPlaceholder,
              ),
            ),
            autocorrect: false,
            enableSuggestions: false,
            onChanged: onChanged,
          ),
        ),
        Positioned(
          left: AppSpacing.s3,
          right: AppSpacing.s3,
          bottom: -1,
          child: Signal(
            variant: aiActive ? SignalVariant.ai : SignalVariant.standard,
            orientation: SignalOrientation.horizontal,
            size: SignalSize.hero,
            thinking: aiThinking,
          ),
        ),
      ],
    );
  }
}

class _AiPanel extends StatelessWidget {
  const _AiPanel({required this.response});

  final String? response;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceAi,
        border: Border(bottom: BorderSide(color: colors.borderSubtle)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              response ?? 'Thinking…',
              style: typography.body.copyWith(
                color: response == null ? colors.textAi : colors.textPrimary,
              ),
            ),
            const SizedBox(height: AppSpacing.s2),
            Text(
              'AI suggestions are human-gated. Review before acting.',
              style: typography.caption.copyWith(color: colors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResultsList extends StatelessWidget {
  const _ResultsList({
    required this.query,
    required this.flatList,
    required this.grouped,
    required this.highlightIndex,
    required this.scrollController,
    required this.itemKeys,
    required this.onHighlight,
    required this.onActivate,
    required this.initialsFromName,
  });

  final String query;
  final List<CommandItem> flatList;
  final Map<String, List<CommandItem>> grouped;
  final int highlightIndex;
  final ScrollController scrollController;
  final Map<int, GlobalKey> itemKeys;
  final ValueChanged<int> onHighlight;
  final ValueChanged<CommandItem> onActivate;
  final String Function(String name) initialsFromName;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;

    if (flatList.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s3,
          vertical: AppSpacing.s6,
        ),
        child: Text(
          'No results for "$query"',
          textAlign: TextAlign.center,
          style: typography.bodySm.copyWith(color: colors.textTertiary),
        ),
      );
    }

    var offset = 0;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 320),
      child: ListView(
        controller: scrollController,
        padding: const EdgeInsets.all(AppSpacing.s2),
        shrinkWrap: true,
        children: [
          for (final entry in grouped.entries) ...[
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.s2,
                vertical: AppSpacing.s1,
              ),
              child: Text(
                entry.key,
                style: typography.overline.copyWith(
                  color: colors.textTertiary,
                ),
              ),
            ),
            for (final item in entry.value)
              Builder(
                builder: (context) {
                  final index = offset;
                  offset += 1;
                  itemKeys[index] ??= GlobalKey();
                  final highlighted = index == highlightIndex;

                  return _CommandRow(
                    key: itemKeys[index],
                    item: item,
                    highlighted: highlighted,
                    initialsFromName: initialsFromName,
                    onHover: () => onHighlight(index),
                    onTap: () => onActivate(item),
                  );
                },
              ),
          ],
        ],
      ),
    );
  }
}

class _CommandRow extends StatefulWidget {
  const _CommandRow({
    super.key,
    required this.item,
    required this.highlighted,
    required this.initialsFromName,
    required this.onHover,
    required this.onTap,
  });

  final CommandItem item;
  final bool highlighted;
  final String Function(String name) initialsFromName;
  final VoidCallback onHover;
  final VoidCallback onTap;

  @override
  State<_CommandRow> createState() => _CommandRowState();
}

class _CommandRowState extends State<_CommandRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;
    final item = widget.item;
    final highlighted = widget.highlighted || _hovered;

    return MouseRegion(
      onEnter: (_) {
        setState(() => _hovered = true);
        widget.onHover();
      },
      onExit: (_) => setState(() => _hovered = false),
      child: Material(
        color: highlighted ? colors.surfaceSelected : Colors.transparent,
        borderRadius: AppRadius.mdAll,
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: AppRadius.mdAll,
          hoverColor: colors.surfaceHover,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.s3,
              vertical: AppSpacing.s2,
            ),
            child: Row(
              children: [
                if (item.avatarName != null)
                  AppAvatar(
                    size: AppAvatarSize.sm,
                    initials: widget.initialsFromName(item.avatarName!),
                    semanticLabel: item.avatarName,
                  )
                else if (item.icon != null)
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: colors.surfaceMuted,
                      borderRadius: AppRadius.mdAll,
                    ),
                    child: SizedBox(
                      width: 32,
                      height: 32,
                      child: Center(child: item.icon),
                    ),
                  ),
                if (item.avatarName != null || item.icon != null)
                  const SizedBox(width: AppSpacing.s3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: typography.body.copyWith(
                          color: colors.textPrimary,
                        ),
                      ),
                      if (item.meta != null)
                        Text(
                          item.meta!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: typography.caption.copyWith(
                            color: colors.textSecondary,
                          ),
                        ),
                    ],
                  ),
                ),
                if (item.shortcut != null) AppKbd(keys: item.shortcut),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
