import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/app/shell/command/app_command_item.dart';
import 'package:ai_clinic/core/auth/permission_service.dart';
import 'package:ai_clinic/app/shell/command/command_bar_patient_search_provider.dart';
import 'package:ai_clinic/core/ui/foundation.dart';
import 'package:ai_clinic/core/ui/state/state.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/patients/domain/patient_list_item.dart';
import 'package:ai_clinic/features/patients/domain/patient_search_query.dart';
import 'package:ai_clinic/features/patients/presentation/utils/patient_presentation_formatting.dart';

/// Global ⌘K / Ctrl+K command palette overlay.
///
/// Mount once at shell level; visibility is driven by [commandBarProvider].
class AppCommandBar extends ConsumerWidget {
  const AppCommandBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final open = ref.watch(commandBarProvider);
    if (!open) {
      return const SizedBox.shrink();
    }
    return const Positioned.fill(child: _AppCommandBarSurface());
  }
}

class _AppCommandBarSurface extends ConsumerStatefulWidget {
  const _AppCommandBarSurface();

  @override
  ConsumerState<_AppCommandBarSurface> createState() => _AppCommandBarSurfaceState();
}

class _AppCommandBarSurfaceState extends ConsumerState<_AppCommandBarSurface> with SingleTickerProviderStateMixin {
  static const _placeholder = 'Search patients, pages, or actions…';
  static const _aiPlaceholder = 'Ask AI anything about your clinic…';

  final _queryController = TextEditingController();
  final _inputFocusNode = FocusNode();
  final _focusScopeNode = FocusScopeNode();
  final _listScrollController = ScrollController();
  final _itemKeys = <int, GlobalKey>{};

  late final AnimationController _motionController;
  late final Animation<double> _opacity;
  late final Animation<double> _scale;

  var _highlightIndex = 0;
  var _aiEntry = false;
  String? _aiResponse;
  String _debouncedQuery = '';
  Timer? _debounce;
  var _motionReady = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_motionReady) {
      return;
    }
    _motionReady = true;
    final reduced = AppMotion.reduced(context);
    final spec = AppMotion.resolvePreset(AppMotionPreset.command, reduced: reduced);
    _motionController = AnimationController(vsync: this, duration: spec.duration);
    final curve = CurvedAnimation(parent: _motionController, curve: spec.curve);
    _opacity = curve;
    _scale = Tween<double>(begin: reduced ? 1 : 0.98, end: 1).animate(curve);
    _motionController.forward();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focusScopeNode.requestFocus();
        _inputFocusNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _queryController.dispose();
    _inputFocusNode.dispose();
    _focusScopeNode.dispose();
    _listScrollController.dispose();
    _motionController.dispose();
    super.dispose();
  }

  void _reset() {
    _queryController.clear();
    _debouncedQuery = '';
    _highlightIndex = 0;
    _aiEntry = false;
    _aiResponse = null;
    ref.read(aiModeProvider.notifier).setAiMode(false);
  }

  void _close() {
    ref.read(commandBarProvider.notifier).closeCommandBar();
    _reset();
    ref.read(commandBarProvider.notifier).focusTrigger();
  }

  void _scheduleDebouncedQuery(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      setState(() => _debouncedQuery = value);
    });
  }

  List<AppCommandItem> _staticItems(PermissionService permissions) {
    return buildDefaultCommandItems(
      navigate: (route) => context.go(route),
      permissions: permissions,
    ).where((item) => item.isVisible?.call(permissions) ?? true).toList();
  }

  AppCommandItem _askAiItem() {
    return AppCommandItem(
      id: appCommandAskAiId,
      label: 'Ask AI…',
      group: AppCommandGroup.ai,
      meta: 'Natural language assistant',
      icon: LucideIcons.sparkles,
      iconAi: true,
      shortcutKeys: const ['↵'],
      onSelected: () {},
    );
  }

  AppCommandItem _patientItem(PatientListItem patient, void Function(String route) navigate) {
    return AppCommandItem(
      id: 'patient-${patient.id}',
      label: patient.fullName,
      group: AppCommandGroup.patients,
      meta: _patientMeta(patient),
      avatarName: patient.fullName,
      onSelected: () => navigate(AppRoutes.patientDetail(patient.id)),
    );
  }

  AppCommandItem _degradedPatientSearchItem(String query, void Function(String route) navigate) {
    return AppCommandItem(
      id: 'patient-search-fallback',
      label: "Search patients: '$query'",
      group: AppCommandGroup.search,
      icon: LucideIcons.search,
      keywords: [query],
      onSelected: () => navigate(AppRoutes.patients),
    );
  }

  String _patientMeta(PatientListItem patient) {
    final displayId = PatientPresentationFormatting.displayId(patient.id);
    final parts = <String>['MRN · $displayId'];
    if (patient.lastVisitAt != null) {
      parts.add('Last visit ${PatientPresentationFormatting.date.format(patient.lastVisitAt!)}');
    } else if (patient.nextAppointmentAt != null) {
      parts.add('Appointment ${PatientPresentationFormatting.dateTime.format(patient.nextAppointmentAt!)}');
    }
    return parts.join(' · ');
  }

  List<AppCommandItem> _composeItems({
    required PermissionService permissions,
    required List<PatientListItem> patientResults,
    required bool patientSearchLoading,
  }) {
    final query = _queryController.text;
    final trimmed = query.trim();
    final navigate = context.go;

    final staticFiltered = _staticItems(permissions).where((item) => item.matchesQuery(query)).toList();

    final patientItems = <AppCommandItem>[];
    if (permissions.canViewPatients() && trimmed.isNotEmpty) {
      if (PatientSearchQuery.canInvokeRpc(trimmed)) {
        patientItems.addAll(patientResults.map((patient) => _patientItem(patient, navigate)));
        if (!patientSearchLoading && patientResults.isEmpty && PatientSearchQuery.validationHint(trimmed) == null) {
          patientItems.add(_degradedPatientSearchItem(trimmed, navigate));
        }
      } else {
        patientItems.add(_degradedPatientSearchItem(trimmed, navigate));
      }
    }

    final merged = <AppCommandItem>[...staticFiltered, ...patientItems];

    final showAskAi = !_aiEntry && (trimmed.length > 8 || trimmed.contains('?'));
    if (showAskAi) {
      merged.add(_askAiItem());
    }

    return merged;
  }

  Map<AppCommandGroup, List<AppCommandItem>> _groupItems(List<AppCommandItem> items) {
    final map = <AppCommandGroup, List<AppCommandItem>>{};
    for (final item in items) {
      map.putIfAbsent(item.group, () => []).add(item);
    }
    final entries = map.entries.toList()..sort((a, b) => a.key.sortOrder.compareTo(b.key.sortOrder));
    return Map.fromEntries(entries);
  }

  void _setHighlight(int index, int itemCount) {
    if (itemCount == 0) {
      setState(() => _highlightIndex = 0);
      return;
    }
    setState(() => _highlightIndex = index.clamp(0, itemCount - 1));
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToHighlight());
  }

  void _scrollToHighlight() {
    final key = _itemKeys[_highlightIndex];
    final context = key?.currentContext;
    if (context == null) return;
    Scrollable.ensureVisible(
      context,
      alignment: 0.2,
      duration: AppMotion.reduced(this.context) ? Duration.zero : AppDurations.fast,
      curve: AppEasings.standard,
    );
  }

  void _activateItem(AppCommandItem item) {
    if (item.id == appCommandAskAiId) {
      setState(() {
        _aiEntry = true;
        _aiResponse = null;
      });
      ref.read(aiModeProvider.notifier).setAiMode(true);
      final trimmed = _queryController.text.trim();
      if (trimmed.isNotEmpty) {
        Future<void>.delayed(const Duration(milliseconds: 600), () {
          if (!mounted || !_aiEntry) return;
          setState(() {
            _aiResponse =
                'Here\'s a suggested starting point for "$trimmed": review recent patient charts and schedule a follow-up.';
          });
        });
      }
      return;
    }

    if (item.onSelected != null) {
      item.onSelected!();
    } else if (item.route != null) {
      context.go(item.route!);
    }
    _close();
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }

    if (event.logicalKey == LogicalKeyboardKey.escape) {
      if (_aiEntry) {
        setState(() {
          _aiEntry = false;
          _aiResponse = null;
        });
        ref.read(aiModeProvider.notifier).setAiMode(false);
        return KeyEventResult.handled;
      }
      _close();
      return KeyEventResult.handled;
    }

    if (_aiEntry) {
      return KeyEventResult.ignored;
    }

    final permissions = ref.read(permissionServiceProvider);
    final patientAsync = ref.read(commandBarPatientSearchProvider(_debouncedQuery));
    final patientResults = patientAsync.maybeWhen(data: (items) => items, orElse: () => const <PatientListItem>[]);
    final patientLoading = patientAsync.isLoading && _debouncedQuery.trim().isNotEmpty;
    final flat = _composeItems(
      permissions: permissions,
      patientResults: patientResults,
      patientSearchLoading: patientLoading,
    );

    if (flat.isEmpty) {
      return KeyEventResult.ignored;
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      _setHighlight((_highlightIndex + 1) % flat.length, flat.length);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      _setHighlight((_highlightIndex - 1 + flat.length) % flat.length, flat.length);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.home) {
      _setHighlight(0, flat.length);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.end) {
      _setHighlight(flat.length - 1, flat.length);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter) {
      _activateItem(flat[_highlightIndex]);
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<bool>(commandBarProvider, (previous, next) {
      if (next == false) {
        _reset();
      }
    });

    final colors = context.colors;
    final typography = context.typography;
    final reduced = AppMotion.reduced(context);
    final aiMode = ref.watch(aiModeProvider);
    final permissions = ref.watch(permissionServiceProvider);
    final patientAsync = ref.watch(commandBarPatientSearchProvider(_debouncedQuery));
    final patientResults = patientAsync.maybeWhen(data: (items) => items, orElse: () => const <PatientListItem>[]);
    final patientLoading = patientAsync.isLoading && _debouncedQuery.trim().isNotEmpty;
    final flatItems = _composeItems(
      permissions: permissions,
      patientResults: patientResults,
      patientSearchLoading: patientLoading,
    );
    final grouped = _groupItems(flatItems);
    final aiAccent = _aiEntry || aiMode;

    _itemKeys.clear();
    var runningIndex = 0;

    return Semantics(
      scopesRoute: true,
      namesRoute: true,
      explicitChildNodes: true,
      label: 'Command bar',
      child: Stack(
        fit: StackFit.expand,
        children: [
          FadeTransition(
            opacity: _opacity,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _close,
              child: reduced
                  ? ColoredBox(color: colors.surfaceBackdrop)
                  : ClipRect(
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: AppSpacing.s1, sigmaY: AppSpacing.s1),
                        child: ColoredBox(color: colors.surfaceBackdrop),
                      ),
                    ),
            ),
          ),
          SafeArea(
            child: Align(
              alignment: AlignmentDirectional.topCenter,
              child: Padding(
                padding: EdgeInsetsDirectional.only(
                  start: AppSpacing.s4,
                  end: AppSpacing.s4,
                  top: MediaQuery.sizeOf(context).height * 0.12,
                ),
                child: FadeTransition(
                  opacity: _opacity,
                  child: ScaleTransition(
                    scale: _scale,
                    child: FocusScope(
                      node: _focusScopeNode,
                      autofocus: true,
                      child: Focus(
                        onKeyEvent: _handleKeyEvent,
                        child: Material(
                          type: MaterialType.transparency,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 576),
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: colors.surfaceRaised,
                                borderRadius: AppRadii.xlAll,
                                border: Border.all(color: colors.borderDefault),
                                boxShadow: AppShadows.forLevel(3, Theme.of(context).brightness),
                              ),
                              child: ClipRRect(
                                borderRadius: AppRadii.xlAll,
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    _CommandBarSearchHeader(
                                      controller: _queryController,
                                      focusNode: _inputFocusNode,
                                      aiAccent: aiAccent,
                                      aiEntry: _aiEntry,
                                      thinking: _aiEntry && _aiResponse == null,
                                      placeholder: _aiEntry ? _aiPlaceholder : _placeholder,
                                      loading: patientLoading,
                                      onChanged: (value) {
                                        setState(() => _highlightIndex = 0);
                                        _scheduleDebouncedQuery(value);
                                      },
                                    ),
                                    if (_aiEntry)
                                      _CommandBarAiPanel(response: _aiResponse, thinking: _aiResponse == null)
                                    else
                                      _CommandBarResults(
                                        scrollController: _listScrollController,
                                        grouped: grouped,
                                        highlightIndex: _highlightIndex,
                                        query: _queryController.text,
                                        loading: patientLoading,
                                        itemIndexFor: (index) {
                                          _itemKeys[index] = GlobalKey();
                                          return _itemKeys[index]!;
                                        },
                                        runningIndex: () => runningIndex++,
                                        onHighlight: (index) => _setHighlight(index, flatItems.length),
                                        onActivate: _activateItem,
                                      ),
                                    _CommandBarFooter(typography: typography, colors: colors),
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
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CommandBarSearchHeader extends StatelessWidget {
  const _CommandBarSearchHeader({
    required this.controller,
    required this.focusNode,
    required this.aiAccent,
    required this.aiEntry,
    required this.thinking,
    required this.placeholder,
    required this.loading,
    required this.onChanged,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool aiAccent;
  final bool aiEntry;
  final bool thinking;
  final String placeholder;
  final bool loading;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.borderSubtle)),
      ),
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(AppSpacing.s4, AppSpacing.s4, AppSpacing.s4, AppSpacing.s3),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: AppRadii.mdAll,
                border: aiAccent ? Border.all(color: colors.borderAi) : null,
              ),
              child: AppInputFrame(
                focusNode: focusNode,
                size: AppFieldSize.md,
                leading: const AppInputIconSlot(icon: LucideIcons.search),
                trailing: loading ? const AppSpinner(size: AppSpinnerSize.sm) : null,
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  style: context.typography.body.copyWith(color: colors.textPrimary),
                  onChanged: onChanged,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: appBareInputDecoration(context: context, size: AppFieldSize.md, hintText: placeholder),
                  cursorColor: aiAccent ? colors.borderAi : colors.borderFocus,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.s1),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: SizedBox(
                width: double.infinity,
                height: AppSignal.thickness,
                child: AppSignalLine(ai: aiAccent, orientation: AppSignalOrientation.horizontal, thinking: thinking),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CommandBarAiPanel extends StatelessWidget {
  const _CommandBarAiPanel({required this.response, required this.thinking});

  final String? response;
  final bool thinking;

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
        padding: const EdgeInsetsDirectional.all(AppSpacing.s4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              thinking ? 'Thinking…' : response!,
              style: typography.body.copyWith(color: thinking ? colors.textAi : colors.textPrimary),
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

class _CommandBarResults extends StatelessWidget {
  const _CommandBarResults({
    required this.scrollController,
    required this.grouped,
    required this.highlightIndex,
    required this.query,
    required this.loading,
    required this.itemIndexFor,
    required this.runningIndex,
    required this.onHighlight,
    required this.onActivate,
  });

  final ScrollController scrollController;
  final Map<AppCommandGroup, List<AppCommandItem>> grouped;
  final int highlightIndex;
  final String query;
  final bool loading;
  final GlobalKey Function(int index) itemIndexFor;
  final int Function() runningIndex;
  final ValueChanged<int> onHighlight;
  final ValueChanged<AppCommandItem> onActivate;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;
    final totalCount = grouped.values.fold<int>(0, (sum, list) => sum + list.length);

    if (totalCount == 0 && !loading) {
      return Padding(
        padding: const EdgeInsetsDirectional.symmetric(horizontal: AppSpacing.s3, vertical: AppSpacing.s6),
        child: AppEmptyState(
          variant: AppEmptyStateVariant.noResults,
          title: 'No results',
          description: query.trim().isEmpty
              ? 'Try searching for a patient, page, or action.'
              : 'No results for "${query.trim()}".',
        ),
      );
    }

    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 320),
      child: SingleChildScrollView(
        controller: scrollController,
        padding: const EdgeInsetsDirectional.all(AppSpacing.s2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final entry in grouped.entries) ...[
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(
                  AppSpacing.s2,
                  AppSpacing.s1,
                  AppSpacing.s2,
                  AppSpacing.s1,
                ),
                child: Text(entry.key.label, style: typography.overline.copyWith(color: colors.textTertiary)),
              ),
              for (final item in entry.value)
                Builder(
                  builder: (context) {
                    final index = runningIndex();
                    final highlighted = index == highlightIndex;
                    return KeyedSubtree(
                      key: itemIndexFor(index),
                      child: _CommandBarRow(
                        item: item,
                        highlighted: highlighted,
                        onHighlight: () => onHighlight(index),
                        onActivate: () => onActivate(item),
                      ),
                    );
                  },
                ),
            ],
            if (loading)
              const Padding(
                padding: EdgeInsetsDirectional.all(AppSpacing.s4),
                child: Center(child: AppSpinner(size: AppSpinnerSize.sm)),
              ),
          ],
        ),
      ),
    );
  }
}

class _CommandBarRow extends StatelessWidget {
  const _CommandBarRow({
    required this.item,
    required this.highlighted,
    required this.onHighlight,
    required this.onActivate,
  });

  final AppCommandItem item;
  final bool highlighted;
  final VoidCallback onHighlight;
  final VoidCallback onActivate;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;

    Widget? leading;
    if (item.avatarName != null) {
      leading = AppAvatar(name: item.avatarName!, size: AppAvatarSize.sm);
    } else if (item.icon != null) {
      leading = Container(
        width: AppSpacing.s8,
        height: AppSpacing.s8,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: colors.surfaceMuted, borderRadius: AppRadii.mdAll),
        child: AppIcon(icon: item.icon!, size: AppIconSize.sm, color: item.iconAi ? colors.textAi : colors.iconDefault),
      );
    }

    return MouseRegion(
      onEnter: (_) => onHighlight(),
      child: AppPressable.builder(
        onTap: onActivate,
        borderRadius: AppRadii.mdAll,
        builder: (context, states, _) {
          final pressed = states.contains(WidgetState.pressed);
          final hovered = states.contains(WidgetState.hovered);
          final background = highlighted || pressed || hovered ? colors.surfaceSelected : Colors.transparent;

          return AnimatedContainer(
            duration: AppDurations.instant,
            curve: AppEasings.standard,
            padding: const EdgeInsetsDirectional.symmetric(horizontal: AppSpacing.s3, vertical: AppSpacing.s2),
            decoration: BoxDecoration(color: background, borderRadius: AppRadii.mdAll),
            child: Row(
              children: [
                if (leading != null) ...[leading, const SizedBox(width: AppSpacing.s3)],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: typography.body.copyWith(color: colors.textPrimary),
                      ),
                      if (item.meta != null)
                        Text(
                          item.meta!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: typography.caption.copyWith(color: colors.textSecondary),
                        ),
                    ],
                  ),
                ),
                if (item.shortcutKeys != null) ...[
                  const SizedBox(width: AppSpacing.s2),
                  AppKbd(keys: item.shortcutKeys),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _CommandBarFooter extends StatelessWidget {
  const _CommandBarFooter({required this.typography, required this.colors});

  final AppTypography typography;
  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: colors.borderSubtle)),
      ),
      child: Padding(
        padding: const EdgeInsetsDirectional.symmetric(horizontal: AppSpacing.s4, vertical: AppSpacing.s2),
        child: Text.rich(
          TextSpan(
            style: typography.caption.copyWith(color: colors.textTertiary),
            children: [
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: AppKbd(keys: const ['↑', '↓']),
              ),
              const TextSpan(text: ' navigate · '),
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: AppKbd(keys: const ['↵']),
              ),
              const TextSpan(text: ' select · '),
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: AppKbd(keys: const ['Esc']),
              ),
              const TextSpan(text: ' close'),
            ],
          ),
        ),
      ),
    );
  }
}
