import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/components/app_avatar.dart';
import 'package:ai_clinic/core/ui/components/app_input_styles.dart';
import 'package:ai_clinic/core/ui/components/app_kbd.dart';
import 'package:ai_clinic/core/ui/components/app_signal.dart';
import 'package:ai_clinic/core/ui/motion/app_motion.dart';
import 'package:ai_clinic/core/ui/theme/app_elevation.dart';
import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';
import 'package:ai_clinic/features/design_system/presentation/providers/command_bar_controller.dart';

const _aiAskId = '__ask_ai__';

/// Single command bar result row (web `CommandItem`).
class AppCommandItem {
  const AppCommandItem({
    required this.id,
    required this.group,
    required this.label,
    required this.onSelect,
    this.meta,
    this.icon,
    this.shortcut,
    this.avatarName,
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

/// Global command palette overlay (web `CommandBar`).
class AppCommandBar extends ConsumerStatefulWidget {
  const AppCommandBar({required this.items, this.recentItems = const [], this.placeholder, super.key});

  final List<AppCommandItem> items;
  final List<AppCommandItem> recentItems;
  final String? placeholder;

  @override
  ConsumerState<AppCommandBar> createState() => _AppCommandBarState();
}

class _AppCommandBarState extends ConsumerState<AppCommandBar> with SingleTickerProviderStateMixin {
  final _focusNode = FocusNode();
  final _scrollController = ScrollController();
  final _queryController = TextEditingController();

  late final AnimationController _motionController;

  var _highlightIndex = 0;
  var _aiEntry = false;
  String? _aiResponse;
  var _wasOpen = false;

  @override
  void initState() {
    super.initState();
    _motionController = AnimationController(vsync: this, duration: AppMotion.resolveDuration(AppMotionPreset.command));
    _focusNode.onKeyEvent = _handleKeyEvent;
  }

  @override
  void dispose() {
    _focusNode
      ..onKeyEvent = null
      ..dispose();
    _queryController.dispose();
    _scrollController.dispose();
    _motionController.dispose();
    super.dispose();
  }

  void _resetLocal() {
    _queryController.clear();
    _highlightIndex = 0;
    _aiEntry = false;
    _aiResponse = null;
  }

  void _clearAiModeAfterBuild() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(commandBarProvider.notifier).setAiMode(false);
    });
  }

  void _handleClose() {
    ref.read(commandBarProvider.notifier).closeCommandBar();
    _resetLocal();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(commandBarProvider.notifier).focusTrigger();
    });
  }

  AppCommandItem _askAiItem(BuildContext context) {
    return AppCommandItem(
      id: _aiAskId,
      group: 'AI',
      label: 'Ask AI…',
      meta: 'Natural language assistant',
      icon: Icon(Icons.auto_awesome_outlined, size: 16, color: context.appColors.textAi),
      shortcut: const ['↵'],
      onSelect: () {
        setState(() {
          _aiEntry = true;
          ref.read(commandBarProvider.notifier).setAiMode(true);
        });
      },
    );
  }

  List<AppCommandItem> _filteredItems(BuildContext context) {
    final query = _queryController.text.trim().toLowerCase();
    final base = query.isNotEmpty
        ? widget.items.where((item) {
            return item.label.toLowerCase().contains(query) ||
                (item.meta?.toLowerCase().contains(query) ?? false) ||
                item.group.toLowerCase().contains(query);
          }).toList()
        : (widget.recentItems.isNotEmpty ? widget.recentItems : widget.items);

    if (!_aiEntry && (query.length > 8 || query.contains('?'))) {
      return [...base, _askAiItem(context)];
    }
    return base;
  }

  Map<String, List<AppCommandItem>> _grouped(List<AppCommandItem> items) {
    final map = <String, List<AppCommandItem>>{};
    for (final item in items) {
      map.putIfAbsent(item.group, () => []).add(item);
    }
    return map;
  }

  void _activateItem(AppCommandItem item) {
    if (item.id == _aiAskId) {
      setState(() {
        _aiEntry = true;
        ref.read(commandBarProvider.notifier).setAiMode(true);
        final query = _queryController.text.trim();
        if (query.isNotEmpty) {
          _aiResponse =
              'Here\'s a suggested starting point for "$query": review recent patient charts and schedule a follow-up.';
        }
      });
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
          ref.read(commandBarProvider.notifier).setAiMode(false);
        });
      } else {
        _handleClose();
      }
      return KeyEventResult.handled;
    }

    if (_aiEntry) return KeyEventResult.ignored;

    final flatList = _filteredItems(context);
    if (flatList.isEmpty) return KeyEventResult.ignored;

    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      setState(() => _highlightIndex = (_highlightIndex + 1) % flatList.length);
      _scrollToHighlight();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      setState(() => _highlightIndex = (_highlightIndex - 1 + flatList.length) % flatList.length);
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
      if (!_scrollController.hasClients) return;
      final offset = (_highlightIndex * 52.0).clamp(0.0, _scrollController.position.maxScrollExtent);
      _scrollController.animateTo(offset, duration: AppMotion.fast, curve: AppMotion.standardCurve);
    });
  }

  @override
  Widget build(BuildContext context) {
    final open = ref.watch(commandBarProvider.select((s) => s.open));
    final aiMode = ref.watch(commandBarProvider.select((s) => s.aiMode));

    if (open && !_wasOpen) {
      _wasOpen = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _motionController.forward(from: 0);
        _focusNode.requestFocus();
      });
    } else if (!open && _wasOpen) {
      _wasOpen = false;
      _resetLocal();
      _motionController.value = 0;
      _clearAiModeAfterBuild();
    }

    if (!open) return const SizedBox.shrink();

    final colors = context.appColors;
    final elevation = context.appElevation;
    final filtered = _filteredItems(context);
    final grouped = _grouped(filtered);
    final placeholder = widget.placeholder ?? 'Search patients, pages, or actions…';
    final aiActive = _aiEntry || aiMode;

    return Positioned.fill(
      child: Material(
        type: MaterialType.transparency,
        child: Stack(
          children: [
            GestureDetector(
              onTap: _handleClose,
              child: AnimatedBuilder(
                animation: _motionController,
                builder: (context, child) {
                  return ColoredBox(
                    color: Colors.black.withValues(alpha: 0.45 * _motionController.value),
                    child: child,
                  );
                },
                child: const SizedBox.expand(),
              ),
            ),
            Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: EdgeInsets.only(top: MediaQuery.sizeOf(context).height * 0.12, left: 16, right: 16),
                child: AppMotion.animatedPreset(
                  context: context,
                  preset: AppMotionPreset.command,
                  animation: _motionController,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 576),
                    child: Material(
                      color: colors.surfaceRaised,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.xl),
                        side: BorderSide(color: colors.borderDefault),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: DecoratedBox(
                        decoration: elevation.decoration(
                          level: 3,
                          color: colors.surfaceRaised,
                          borderRadius: BorderRadius.circular(AppRadius.xl),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Semantics(
                              label: 'Command bar',
                              container: true,
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  AppSpacing.space4,
                                  AppSpacing.space4,
                                  AppSpacing.space4,
                                  AppSpacing.space3,
                                ),
                                child: Stack(
                                  clipBehavior: Clip.none,
                                  children: [
                                    DecoratedBox(
                                      decoration: BoxDecoration(
                                        color: colors.surfaceDefault,
                                        borderRadius: BorderRadius.circular(AppRadius.md),
                                        border: Border.all(color: aiActive ? colors.borderAi : colors.borderDefault),
                                      ),
                                      child: appWrapMaterialInput(
                                        TextField(
                                          controller: _queryController,
                                          focusNode: _focusNode,
                                          onChanged: (_) => setState(() => _highlightIndex = 0),
                                          style: AppTypography.body(context),
                                          decoration: InputDecoration(
                                            hintText: _aiEntry ? 'Ask AI anything about your clinic…' : placeholder,
                                            border: InputBorder.none,
                                            contentPadding: const EdgeInsets.symmetric(
                                              horizontal: AppSpacing.space3,
                                              vertical: 10,
                                            ),
                                            isDense: true,
                                          ),
                                        ),
                                      ),
                                    ),
                                    Positioned(
                                      left: AppSpacing.space3,
                                      right: AppSpacing.space3,
                                      bottom: -1,
                                      child: AppSignal(
                                        variant: aiActive ? AppSignalVariant.ai : AppSignalVariant.standard,
                                        orientation: Axis.horizontal,
                                        size: AppSignalSize.hero,
                                        thinking: _aiEntry && _aiResponse == null,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            if (_aiEntry)
                              DecoratedBox(
                                decoration: BoxDecoration(
                                  color: colors.surfaceAi,
                                  border: Border(top: BorderSide(color: colors.borderSubtle)),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(AppSpacing.space4),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _aiResponse ?? 'Thinking…',
                                        style: AppTypography.body(
                                          context,
                                        ).copyWith(color: _aiResponse == null ? colors.textAi : colors.textPrimary),
                                      ),
                                      const SizedBox(height: AppSpacing.space2),
                                      Text(
                                        'AI suggestions are human-gated. Review before acting.',
                                        style: AppTypography.caption(context).copyWith(color: colors.textSecondary),
                                      ),
                                    ],
                                  ),
                                ),
                              )
                            else
                              ConstrainedBox(
                                constraints: const BoxConstraints(maxHeight: 320),
                                child: filtered.isEmpty
                                    ? Padding(
                                        padding: const EdgeInsets.symmetric(vertical: AppSpacing.space6),
                                        child: Center(
                                          child: Text(
                                            'No results for "${_queryController.text}"',
                                            style: AppTypography.bodySm(context).copyWith(color: colors.textTertiary),
                                          ),
                                        ),
                                      )
                                    : ListView(
                                        controller: _scrollController,
                                        padding: const EdgeInsets.all(AppSpacing.space2),
                                        shrinkWrap: true,
                                        children: [
                                          for (final entry in grouped.entries) ...[
                                            Padding(
                                              padding: const EdgeInsets.fromLTRB(
                                                AppSpacing.space2,
                                                AppSpacing.space1,
                                                AppSpacing.space2,
                                                AppSpacing.space1,
                                              ),
                                              child: Text(
                                                entry.key.toUpperCase(),
                                                style: AppTypography.overline(context),
                                              ),
                                            ),
                                            for (final item in entry.value)
                                              _CommandBarRow(
                                                item: item,
                                                highlighted: filtered.indexOf(item) == _highlightIndex,
                                                onTap: () => _activateItem(item),
                                                onHover: () => setState(() => _highlightIndex = filtered.indexOf(item)),
                                              ),
                                          ],
                                        ],
                                      ),
                              ),
                            DecoratedBox(
                              decoration: BoxDecoration(
                                border: Border(top: BorderSide(color: colors.borderSubtle)),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: AppSpacing.space4,
                                  vertical: AppSpacing.space2,
                                ),
                                child: Row(
                                  children: [
                                    const AppKbd(keys: ['↑', '↓']),
                                    const SizedBox(width: AppSpacing.space1),
                                    Text(
                                      'navigate · ',
                                      style: AppTypography.caption(context).copyWith(color: colors.textTertiary),
                                    ),
                                    const AppKbd(keys: ['↵']),
                                    Text(
                                      ' select · ',
                                      style: AppTypography.caption(context).copyWith(color: colors.textTertiary),
                                    ),
                                    const AppKbd(keys: ['Esc']),
                                    Text(
                                      ' close',
                                      style: AppTypography.caption(context).copyWith(color: colors.textTertiary),
                                    ),
                                  ],
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
          ],
        ),
      ),
    );
  }
}

class _CommandBarRow extends StatefulWidget {
  const _CommandBarRow({required this.item, required this.highlighted, required this.onTap, required this.onHover});

  final AppCommandItem item;
  final bool highlighted;
  final VoidCallback onTap;
  final VoidCallback onHover;

  @override
  State<_CommandBarRow> createState() => _CommandBarRowState();
}

class _CommandBarRowState extends State<_CommandBarRow> {
  var _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final highlighted = widget.highlighted || _hovered;

    return MouseRegion(
      onEnter: (_) {
        setState(() => _hovered = true);
        widget.onHover();
      },
      onExit: (_) => setState(() => _hovered = false),
      child: Material(
        color: highlighted ? colors.surfaceSelected : Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(AppRadius.md),
          hoverColor: colors.surfaceHover,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space3, vertical: AppSpacing.space2),
            child: Row(
              children: [
                if (widget.item.avatarName != null)
                  AppAvatar(name: widget.item.avatarName!, size: AvatarSize.sm)
                else if (widget.item.icon != null)
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: colors.surfaceMuted,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                    child: SizedBox(width: 32, height: 32, child: Center(child: widget.item.icon)),
                  ),
                if (widget.item.avatarName != null || widget.item.icon != null)
                  const SizedBox(width: AppSpacing.space3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.item.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.body(context),
                      ),
                      if (widget.item.meta != null)
                        Text(
                          widget.item.meta!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.caption(context).copyWith(color: colors.textSecondary),
                        ),
                    ],
                  ),
                ),
                if (widget.item.shortcut != null) AppKbd(keys: widget.item.shortcut!),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Default mock command items for showcase (web `buildDefaultCommandItems`).
List<AppCommandItem> kDefaultCommandItems({void Function(String id)? onNavigate}) {
  AppCommandItem nav(String id, String label) =>
      AppCommandItem(id: id, group: 'Navigate', label: label, onSelect: () => onNavigate?.call(id));

  return [
    nav('patients', 'Patients'),
    nav('appointments', 'Appointments'),
    nav('invoices', 'Invoices'),
    nav('reports', 'Reports'),
    AppCommandItem(
      id: 'patient-1',
      group: 'Patients',
      label: 'Layla Hassan',
      meta: 'MRN · 10482 · Last visit 2 days ago',
      avatarName: 'Layla Hassan',
      onSelect: () => onNavigate?.call('patients'),
    ),
    AppCommandItem(
      id: 'patient-2',
      group: 'Patients',
      label: 'Omar Farouk',
      meta: 'MRN · 11029 · Appointment today',
      avatarName: 'Omar Farouk',
      onSelect: () => onNavigate?.call('patients'),
    ),
    AppCommandItem(
      id: 'patient-3',
      group: 'Patients',
      label: 'Nadia El-Sayed',
      meta: 'MRN · 9876 · Follow-up due',
      avatarName: 'Nadia El-Sayed',
      onSelect: () => onNavigate?.call('patients'),
    ),
    AppCommandItem(
      id: 'new-patient',
      group: 'Actions',
      label: 'New patient',
      icon: const Icon(Icons.person_add_outlined, size: 16),
      shortcut: const ['⌘', 'N'],
      onSelect: () {},
    ),
    AppCommandItem(
      id: 'new-invoice',
      group: 'Actions',
      label: 'New invoice',
      icon: const Icon(Icons.description_outlined, size: 16),
      shortcut: const ['⌘', 'I'],
      onSelect: () {},
    ),
    AppCommandItem(
      id: 'new-appointment',
      group: 'Actions',
      label: 'New appointment',
      icon: const Icon(Icons.add, size: 16),
      onSelect: () {},
    ),
  ];
}

/// Wraps the components showcase with ⌘K/Ctrl-K shortcuts and the command bar overlay.
class CommandBarScope extends ConsumerWidget {
  const CommandBarScope({required this.child, this.items = const [], this.enabled = true, super.key});

  final Widget child;
  final List<AppCommandItem> items;
  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!enabled) {
      return child;
    }

    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.keyK, meta: true): _ToggleCommandBarIntent(),
        SingleActivator(LogicalKeyboardKey.keyK, control: true): _ToggleCommandBarIntent(),
      },
      child: Actions(
        actions: {
          _ToggleCommandBarIntent: CallbackAction<_ToggleCommandBarIntent>(
            onInvoke: (_) {
              ref.read(commandBarProvider.notifier).toggleCommandBar();
              return null;
            },
          ),
        },
        child: Focus(
          autofocus: true,
          child: Stack(
            children: [
              child,
              AppCommandBar(items: items.isNotEmpty ? items : kDefaultCommandItems()),
            ],
          ),
        ),
      ),
    );
  }
}

class _ToggleCommandBarIntent extends Intent {
  const _ToggleCommandBarIntent();
}
