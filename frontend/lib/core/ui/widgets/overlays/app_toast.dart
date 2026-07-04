import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/foundation.dart';
import 'package:ai_clinic/core/ui/widgets/actions/actions.dart';

/// Semantic tone for [AppToast].
enum AppToastVariant { success, danger, info, neutral }

/// Transient toast payload managed by [ToastController].
class AppToastData {
  const AppToastData({
    required this.id,
    required this.message,
    this.variant = AppToastVariant.neutral,
    this.title,
    this.actionLabel,
    this.onAction,
    this.duration,
    this.persistent = false,
  });

  final String id;
  final AppToastVariant variant;
  final String message;
  final String? title;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Duration? duration;
  final bool persistent;

  bool get hasAction => actionLabel != null && onAction != null;
}

const int _kMaxToasts = 3;
const Duration _kDefaultDismissDuration = Duration(seconds: 4);
const Duration _kDangerDismissDuration = Duration(seconds: 8);
const double _kToastMaxWidth = 384;
const double _kSlideOffset = 8;

/// Riverpod controller for the global toast queue.
final toastControllerProvider = NotifierProvider<ToastController, List<AppToastData>>(ToastController.new);

/// Manages the toast queue, auto-dismiss timers, and hover pause/resume.
class ToastController extends Notifier<List<AppToastData>> {
  final Map<String, _ToastTimerEntry> _timers = {};

  @override
  List<AppToastData> build() {
    ref.onDispose(_cancelAllTimers);
    return const [];
  }

  /// Enqueues a toast and returns its generated or supplied [id].
  String show({
    String? id,
    required String message,
    AppToastVariant variant = AppToastVariant.neutral,
    String? title,
    String? actionLabel,
    VoidCallback? onAction,
    Duration? duration,
    bool persistent = false,
  }) {
    return showData(
      AppToastData(
        id: id ?? _generateId(),
        message: message,
        variant: variant,
        title: title,
        actionLabel: actionLabel,
        onAction: onAction,
        duration: duration,
        persistent: persistent,
      ),
    );
  }

  /// Enqueues a pre-built [AppToastData] and returns its [id].
  String showData(AppToastData data) {
    state = [...state, data].sublist(math.max(0, state.length + 1 - _kMaxToasts));
    _scheduleDismiss(data);
    return data.id;
  }

  /// Removes a toast by [id] and cancels its timer.
  void dismiss(String id) {
    _cancelTimer(id);
    state = state.where((toast) => toast.id != id).toList(growable: false);
  }

  /// Clears every visible toast and cancels all timers.
  void dismissAll() {
    _cancelAllTimers();
    state = const [];
  }

  /// Pauses the auto-dismiss timer while the user hovers a toast.
  void pause(String id) {
    final entry = _timers[id];
    if (entry == null) return;

    entry.timer?.cancel();
    final elapsed = entry.stopwatch?.elapsed ?? Duration.zero;
    final remaining = entry.total - elapsed;
    _timers.remove(id);
    if (remaining > Duration.zero) {
      _timers[id] = _ToastTimerEntry.paused(remaining);
    }
  }

  /// Resumes a paused auto-dismiss timer after hover ends.
  void resume(String id) {
    final entry = _timers[id];
    if (entry == null || !entry.isPaused) return;

    final remaining = entry.pausedRemaining!;
    _timers.remove(id);
    if (remaining <= Duration.zero) {
      dismiss(id);
      return;
    }

    final timer = Timer(remaining, () => dismiss(id));
    _timers[id] = _ToastTimerEntry.active(total: remaining, timer: timer);
  }

  void _scheduleDismiss(AppToastData data) {
    final duration = _resolveDismissDuration(data);
    if (duration <= Duration.zero) return;

    _cancelTimer(data.id);
    final stopwatch = Stopwatch()..start();
    final timer = Timer(duration, () => dismiss(data.id));
    _timers[data.id] = _ToastTimerEntry.active(total: duration, timer: timer, stopwatch: stopwatch);
  }

  Duration _resolveDismissDuration(AppToastData data) {
    if (data.persistent) return Duration.zero;
    if (data.duration != null) return data.duration!;
    return switch (data.variant) {
      AppToastVariant.danger => _kDangerDismissDuration,
      _ => _kDefaultDismissDuration,
    };
  }

  void _cancelTimer(String id) {
    _timers[id]?.timer?.cancel();
    _timers.remove(id);
  }

  void _cancelAllTimers() {
    for (final entry in _timers.values) {
      entry.timer?.cancel();
    }
    _timers.clear();
  }

  String _generateId() {
    final random = math.Random().nextInt(0x7fffffff).toRadixString(36);
    return 'toast-${DateTime.now().millisecondsSinceEpoch}-$random';
  }
}

class _ToastTimerEntry {
  _ToastTimerEntry._({required this.total, this.timer, this.stopwatch, this.pausedRemaining});

  factory _ToastTimerEntry.active({required Duration total, required Timer timer, Stopwatch? stopwatch}) {
    return _ToastTimerEntry._(total: total, timer: timer, stopwatch: stopwatch ?? (Stopwatch()..start()));
  }

  factory _ToastTimerEntry.paused(Duration remaining) {
    return _ToastTimerEntry._(total: remaining, pausedRemaining: remaining);
  }

  final Duration total;
  final Timer? timer;
  final Stopwatch? stopwatch;
  final Duration? pausedRemaining;

  bool get isPaused => pausedRemaining != null;
}

/// Convenience helpers for enqueueing toasts from Riverpod consumers.
extension AppToastRef on WidgetRef {
  /// Shows a toast via [toastControllerProvider].
  String showAppToast({
    String? id,
    required String message,
    AppToastVariant variant = AppToastVariant.neutral,
    String? title,
    String? actionLabel,
    VoidCallback? onAction,
    Duration? duration,
    bool persistent = false,
  }) {
    return read(toastControllerProvider.notifier).show(
      id: id,
      message: message,
      variant: variant,
      title: title,
      actionLabel: actionLabel,
      onAction: onAction,
      duration: duration,
      persistent: persistent,
    );
  }
}

/// Single toast surface — presentation only; queue logic lives in [ToastController].
class AppToast extends StatelessWidget {
  const AppToast({
    required this.data,
    required this.onDismiss,
    required this.onPause,
    required this.onResume,
    super.key,
  });

  final AppToastData data;
  final VoidCallback onDismiss;
  final VoidCallback onPause;
  final VoidCallback onResume;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;
    final scheme = _resolveScheme(colors, data.variant);
    final isAlert = data.variant == AppToastVariant.danger;
    final brightness = Theme.of(context).brightness;

    return Semantics(
      container: true,
      liveRegion: isAlert,
      label: data.title ?? data.message,
      hint: data.title != null ? data.message : null,
      child: MouseRegion(
        onEnter: (_) => onPause(),
        onExit: (_) => onResume(),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.surfaceRaised,
            border: Border.all(color: scheme.border),
            borderRadius: AppRadii.lgAll,
            boxShadow: AppShadows.forLevel(2, brightness),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _kToastMaxWidth),
            child: Padding(
              padding: const EdgeInsetsDirectional.all(AppSpacing.s4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsetsDirectional.only(top: AppSpacing.s0_5),
                    child: AppIcon(icon: _iconForVariant(data.variant), size: AppIconSize.sm, color: scheme.icon),
                  ),
                  const SizedBox(width: AppSpacing.s3),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (data.title != null) ...[
                          Text(data.title!, style: typography.bodyStrong.copyWith(color: colors.textPrimary)),
                          const SizedBox(height: AppSpacing.s1),
                        ],
                        Text(data.message, style: typography.body.copyWith(color: colors.textPrimary)),
                        if (data.hasAction) ...[
                          const SizedBox(height: AppSpacing.s1),
                          Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: AppButton(
                              label: data.actionLabel!,
                              variant: AppButtonVariant.link,
                              size: AppButtonSize.sm,
                              onPressed: () {
                                data.onAction?.call();
                                onDismiss();
                              },
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.s2),
                  AppIconButton(
                    icon: LucideIcons.x,
                    semanticLabel: isAlert ? 'Dismiss alert' : 'Dismiss',
                    size: AppIconButtonSize.sm,
                    variant: AppIconButtonVariant.ghost,
                    onPressed: onDismiss,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Overlay host that renders the toast stack at the logical inline-end bottom corner.
///
/// Mount once inside an [Stack] in [AppShell] (or equivalent root layout):
///
/// ```dart
/// Stack(
///   fit: StackFit.expand,
///   children: [
///     child,
///     const AppToastOverlayHost(),
///   ],
/// )
/// ```
class AppToastOverlayHost extends ConsumerStatefulWidget {
  const AppToastOverlayHost({super.key});

  @override
  ConsumerState<AppToastOverlayHost> createState() => _AppToastOverlayHostState();
}

class _AppToastOverlayHostState extends ConsumerState<AppToastOverlayHost> {
  final List<_DisplayedToast> _displayed = <_DisplayedToast>[];

  @override
  void initState() {
    super.initState();
    ref.listenManual<List<AppToastData>>(toastControllerProvider, (_, next) => _syncDisplayedToasts(next));
  }

  @override
  Widget build(BuildContext context) {
    final toasts = ref.watch(toastControllerProvider);
    if (_displayed.isEmpty && toasts.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _syncDisplayedToasts(toasts);
      });
    }

    final reduced = ref.watch(reducedMotionProvider) || AppMotion.reduced(context);

    return PositionedDirectional(
      end: AppSpacing.s4,
      bottom: AppSpacing.s4,
      child: SafeArea(
        child: Semantics(
          container: true,
          child: AnimatedSize(
            duration: reduced ? Duration.zero : AppMotion.presets[AppMotionPreset.slideUp]!.duration,
            curve: AppMotion.presets[AppMotionPreset.tab]!.easing,
            alignment: AlignmentDirectional.bottomEnd,
            clipBehavior: Clip.none,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var index = 0; index < _displayed.length; index++)
                  Padding(
                    padding: EdgeInsetsDirectional.only(top: index == 0 ? 0 : AppSpacing.s2),
                    child: _AppToastMotionItem(
                      key: ValueKey(_displayed[index].data.id),
                      exiting: _displayed[index].exiting,
                      onExitComplete: () => _removeDisplayed(_displayed[index].data.id),
                      child: AppToast(
                        data: _displayed[index].data,
                        onDismiss: () => ref.read(toastControllerProvider.notifier).dismiss(_displayed[index].data.id),
                        onPause: () => ref.read(toastControllerProvider.notifier).pause(_displayed[index].data.id),
                        onResume: () => ref.read(toastControllerProvider.notifier).resume(_displayed[index].data.id),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _syncDisplayedToasts(List<AppToastData> controllerToasts) {
    final controllerIds = controllerToasts.map((toast) => toast.id).toSet();
    var changed = false;

    for (final toast in controllerToasts) {
      if (!_displayed.any((entry) => entry.data.id == toast.id)) {
        _displayed.add(_DisplayedToast(data: toast));
        changed = true;
      }
    }

    for (final entry in _displayed) {
      if (!controllerIds.contains(entry.data.id) && !entry.exiting) {
        entry.exiting = true;
        changed = true;
      }
    }

    if (changed && mounted) {
      setState(() {});
    }
  }

  void _removeDisplayed(String id) {
    if (!mounted) return;
    setState(() {
      _displayed.removeWhere((entry) => entry.data.id == id);
    });
  }
}

class _DisplayedToast {
  _DisplayedToast({required this.data});

  final AppToastData data;
  bool exiting = false;
}

class _AppToastMotionItem extends StatefulWidget {
  const _AppToastMotionItem({required this.exiting, required this.onExitComplete, required this.child, super.key});

  final bool exiting;
  final VoidCallback onExitComplete;
  final Widget child;

  @override
  State<_AppToastMotionItem> createState() => _AppToastMotionItemState();
}

class _AppToastMotionItemState extends State<_AppToastMotionItem> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late Animation<double> _opacity;
  late Animation<Offset> _slide;
  var _motionReady = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_motionReady) {
      return;
    }
    _motionReady = true;
    _initEnterAnimation();
    _controller.forward();
  }

  @override
  void didUpdateWidget(covariant _AppToastMotionItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.exiting && widget.exiting) {
      _runExit();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _initEnterAnimation() {
    final reduced = AppMotion.reduced(context);
    final spec = AppMotion.resolvePreset(AppMotionPreset.slideUp, reduced: reduced);
    _controller = AnimationController(vsync: this, duration: spec.duration);
    _configureSlideAnimation(spec.curve, reduced);
  }

  void _configureSlideAnimation(Curve curve, bool reduced) {
    final curved = CurvedAnimation(parent: _controller, curve: curve);
    _opacity = curved;
    _slide = Tween<Offset>(begin: Offset(0, reduced ? 0 : _kSlideOffset), end: Offset.zero).animate(curved);
  }

  Future<void> _runExit() async {
    final reduced = AppMotion.reduced(context);
    final spec = AppMotion.resolvePreset(AppMotionPreset.slideUp, reduced: reduced, isExit: true);
    _controller.duration = spec.duration;
    _configureSlideAnimation(spec.curve, reduced);
    await _controller.reverse(from: _controller.value);
    if (mounted) {
      widget.onExitComplete();
    }
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: SlideTransition(position: _slide, child: widget.child),
    );
  }
}

({Color border, Color icon}) _resolveScheme(AppColors colors, AppToastVariant variant) {
  return switch (variant) {
    AppToastVariant.success => (border: colors.statusSuccessBorder, icon: colors.statusSuccessFg),
    AppToastVariant.danger => (border: colors.statusDangerBorder, icon: colors.statusDangerFg),
    AppToastVariant.info => (border: colors.statusInfoBorder, icon: colors.statusInfoFg),
    AppToastVariant.neutral => (border: colors.borderDefault, icon: colors.iconDefault),
  };
}

IconData _iconForVariant(AppToastVariant variant) {
  return switch (variant) {
    AppToastVariant.success => LucideIcons.checkCircle2,
    AppToastVariant.danger => LucideIcons.alertTriangle,
    AppToastVariant.info => LucideIcons.info,
    AppToastVariant.neutral => LucideIcons.info,
  };
}
