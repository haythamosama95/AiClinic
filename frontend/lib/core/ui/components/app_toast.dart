import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/components/app_button.dart';
import 'package:ai_clinic/core/ui/components/app_icon_button.dart';
import 'package:ai_clinic/core/ui/motion/app_motion.dart';
import 'package:ai_clinic/core/ui/theme/app_elevation.dart';
import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';

/// Toast visual variant (web `ToastVariant`).
enum AppToastVariant { success, danger, info, neutral }

/// Optional action affordance on a toast (web `ToastInput.action`).
class AppToastAction {
  const AppToastAction({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;
}

/// Imperative toast input (web `ToastInput`).
class AppToastInput {
  const AppToastInput({
    required this.message,
    this.variant = AppToastVariant.neutral,
    this.action,
    this.autoDismiss = true,
    this.duration,
    this.id,
  });

  final String message;
  final AppToastVariant variant;
  final AppToastAction? action;

  /// When `true` (default), the toast auto-dismisses after [duration] or the
  /// variant default (4s, 8s for danger). Set to `false` to keep it until
  /// manually dismissed.
  final bool autoDismiss;

  /// Custom auto-dismiss delay. Only used when [autoDismiss] is `true`.
  /// Defaults to 4s (8s for [AppToastVariant.danger]).
  final Duration? duration;
  final String? id;
}

const _maxToasts = 3;
const _toastMaxWidth = 384.0;

/// Mount once near the app root to host global toasts (web `ToastProvider`).
class AppToastHost extends StatefulWidget {
  const AppToastHost({required this.child, super.key});

  final Widget child;

  @override
  State<AppToastHost> createState() => _AppToastHostState();
}

class _AppToastHostState extends State<AppToastHost> {
  late final AppToastController _controller = AppToastController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _AppToastHostScope(controller: _controller, child: widget.child);
  }
}

class _AppToastHostScope extends InheritedWidget {
  const _AppToastHostScope({required this.controller, required super.child});

  final AppToastController controller;

  static AppToastController? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<_AppToastHostScope>()?.controller;
  }

  @override
  bool updateShouldNotify(covariant _AppToastHostScope oldWidget) {
    return controller != oldWidget.controller;
  }
}

/// Active toast registry consumed by [AppToastHost].
class AppToastController extends ChangeNotifier {
  final List<_ToastRecord> _toasts = [];
  final Map<String, Timer> _dismissTimers = {};
  OverlayEntry? _overlayEntry;
  var _disposed = false;

  /// Binds the toast stack to the root overlay reachable from [context].
  ///
  /// [AppToastHost] wraps [MaterialApp]'s navigator child, so the host's own
  /// context cannot see [Overlay] — the first `appToast` call supplies a route
  /// context instead.
  void ensureOverlay(BuildContext context) {
    if (_disposed || _overlayEntry != null) return;

    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;

    _overlayEntry = OverlayEntry(
      builder: (overlayContext) {
        return ListenableBuilder(
          listenable: this,
          builder: (context, _) {
            return _ToastOverlayStack(controller: this);
          },
        );
      },
    );
    overlay.insert(_overlayEntry!);
  }

  void show(AppToastInput input) {
    if (_disposed) return;

    final id = input.id ?? _createId();
    final dismissAfter = input.autoDismiss
        ? (input.duration ??
              (input.variant == AppToastVariant.danger ? const Duration(seconds: 8) : const Duration(seconds: 4)))
        : null;

    if (_toasts.length >= _maxToasts) {
      final oldest = _toasts.first;
      _dismissTimers.remove(oldest.id)?.cancel();
      _toasts.removeAt(0);
    }

    _toasts.add(_ToastRecord(id: id, message: input.message, variant: input.variant, action: input.action));
    notifyListeners();

    if (dismissAfter != null && dismissAfter > Duration.zero) {
      _dismissTimers[id]?.cancel();
      _dismissTimers[id] = Timer(dismissAfter, () => dismiss(id));
    }
  }

  void dismiss(String id) {
    _dismissTimers.remove(id)?.cancel();
    final record = _toasts.cast<_ToastRecord?>().firstWhere((t) => t?.id == id, orElse: () => null);
    if (record == null || record.dismissing) return;

    record.dismissing = true;
    notifyListeners();
  }

  void onToastRemoved(String id) {
    _dismissTimers.remove(id)?.cancel();
    _toasts.removeWhere((toast) => toast.id == id);
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    for (final timer in _dismissTimers.values) {
      timer.cancel();
    }
    _dismissTimers.clear();
    _overlayEntry?.remove();
    _overlayEntry = null;
    super.dispose();
  }

  static String _createId() {
    final random = math.Random().nextInt(1 << 32).toRadixString(36);
    return 'toast-${DateTime.now().millisecondsSinceEpoch}-$random';
  }
}

class _ToastRecord {
  _ToastRecord({required this.id, required this.message, required this.variant, this.action});

  final String id;
  final String message;
  final AppToastVariant variant;
  final AppToastAction? action;
  bool dismissing = false;
}

/// Shows a global toast via the nearest [AppToastHost] (web `useToast().toast`).
void appToast(BuildContext context, AppToastInput input) {
  final controller = _AppToastHostScope.maybeOf(context);
  assert(controller != null, 'appToast called without an AppToastHost ancestor. Mount AppToastHost near the app root.');
  if (controller == null) return;
  controller.ensureOverlay(context);
  controller.show(input);
}

class _ToastOverlayStack extends StatelessWidget {
  const _ToastOverlayStack({required this.controller});

  final AppToastController controller;

  @override
  Widget build(BuildContext context) {
    final direction = Directionality.of(context);
    final toasts = controller._toasts;
    if (toasts.isEmpty) {
      return const SizedBox.shrink();
    }

    return Positioned(
      left: direction == TextDirection.rtl ? AppSpacing.space4 : null,
      right: direction == TextDirection.ltr ? AppSpacing.space4 : null,
      bottom: AppSpacing.space4,
      child: Semantics(
        container: true,
        liveRegion: true,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _toastMaxWidth),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final toast in toasts)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.space2),
                  child: _ToastView(
                    key: ValueKey<String>(toast.id),
                    record: toast,
                    dismissing: toast.dismissing,
                    onDismiss: () => controller.dismiss(toast.id),
                    onRemoved: () => controller.onToastRemoved(toast.id),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ToastView extends StatefulWidget {
  const _ToastView({
    required this.record,
    required this.dismissing,
    required this.onDismiss,
    required this.onRemoved,
    super.key,
  });

  final _ToastRecord record;
  final bool dismissing;
  final VoidCallback onDismiss;
  final VoidCallback onRemoved;

  @override
  State<_ToastView> createState() => _ToastViewState();
}

class _ToastViewState extends State<_ToastView> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;
  var _removed = false;
  var _durationConfigured = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: AppMotion.resolveDuration(AppMotionPreset.slideUp));
    _animation = CurvedAnimation(parent: _controller, curve: AppMotion.resolveCurve(AppMotionPreset.slideUp));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_durationConfigured) {
      _durationConfigured = true;
      _controller.duration = AppMotion.resolveDuration(
        AppMotionPreset.slideUp,
        reducedMotion: AppMotion.prefersReducedMotion(context),
      );
      _controller.forward();
    }
  }

  @override
  void didUpdateWidget(covariant _ToastView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.dismissing && widget.dismissing) {
      _exit();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _exit() async {
    if (_removed) return;

    final reducedMotion = AppMotion.prefersReducedMotion(context);
    if (reducedMotion) {
      _finishRemoval();
      return;
    }

    await _controller.reverse();
    _finishRemoval();
  }

  void _finishRemoval() {
    if (_removed || !mounted) return;
    _removed = true;
    widget.onRemoved();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final elevation = context.appElevation;
    final variant = widget.record.variant;
    final iconData = _iconFor(variant);
    final iconColor = _iconColorFor(colors, variant);
    final borderColor = _borderColorFor(colors, variant);
    final isAlert = variant == AppToastVariant.danger;
    final borderRadius = BorderRadius.circular(AppRadius.lg);

    return AppMotion.animatedPreset(
      context: context,
      preset: AppMotionPreset.slideUp,
      animation: _animation,
      child: Semantics(
        liveRegion: isAlert,
        container: true,
        label: widget.record.message,
        child: Material(
          color: Colors.transparent,
          child: Container(
            decoration: BoxDecoration(
              gradient: _backgroundGradientFor(context, colors, variant),
              borderRadius: borderRadius,
              border: Border.all(color: borderColor),
              boxShadow: elevation.shadowsFor(2),
            ),
            padding: const EdgeInsets.all(AppSpacing.space4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(iconData, size: 16, color: iconColor),
                const SizedBox(width: AppSpacing.space3),
                Expanded(
                  child: Text(
                    widget.record.message,
                    style: AppTypography.body(context).copyWith(color: colors.textPrimary),
                  ),
                ),
                if (widget.record.action != null) ...[
                  AppButton(
                    variant: AppButtonVariant.link,
                    size: AppButtonSize.sm,
                    onPressed: () {
                      widget.record.action?.onPressed();
                      widget.onDismiss();
                    },
                    child: Text(widget.record.action!.label),
                  ),
                ],
                AppIconButton(
                  icon: const Icon(Icons.close, size: 14),
                  label: 'Dismiss',
                  variant: AppIconButtonVariant.ghost,
                  size: AppIconButtonSize.sm,
                  onPressed: widget.onDismiss,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

IconData _iconFor(AppToastVariant variant) {
  return switch (variant) {
    AppToastVariant.success => Icons.check_circle,
    AppToastVariant.danger => Icons.cancel,
    AppToastVariant.info => Icons.info,
    AppToastVariant.neutral => Icons.info,
  };
}

Color _iconColorFor(AppSemanticColors colors, AppToastVariant variant) {
  return switch (variant) {
    AppToastVariant.success => colors.statusSuccessFg,
    AppToastVariant.danger => colors.statusDangerFg,
    AppToastVariant.info => colors.statusInfoFg,
    AppToastVariant.neutral => colors.iconDefault,
  };
}

Color _borderColorFor(AppSemanticColors colors, AppToastVariant variant) {
  return switch (variant) {
    AppToastVariant.success => colors.statusSuccessBorder,
    AppToastVariant.danger => colors.statusDangerBorder,
    AppToastVariant.info => colors.statusInfoBorder,
    AppToastVariant.neutral => colors.borderDefault,
  };
}

Color _surfaceColorFor(AppSemanticColors colors, AppToastVariant variant) {
  return switch (variant) {
    AppToastVariant.success => colors.statusSuccessSurface,
    AppToastVariant.danger => colors.statusDangerSurface,
    AppToastVariant.info => colors.statusInfoSurface,
    AppToastVariant.neutral => colors.surfaceMuted,
  };
}

/// Variant tint on the inline-end edge, fading into [AppSemanticColors.surfaceRaised].
LinearGradient _backgroundGradientFor(BuildContext context, AppSemanticColors colors, AppToastVariant variant) {
  final isRtl = Directionality.of(context) == TextDirection.rtl;
  final variantSurface = _surfaceColorFor(colors, variant);

  return LinearGradient(
    begin: isRtl ? Alignment.centerLeft : Alignment.centerRight,
    end: isRtl ? Alignment.centerRight : Alignment.centerLeft,
    colors: [variantSurface, colors.surfaceRaised],
  );
}
