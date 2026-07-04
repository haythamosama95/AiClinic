import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:ai_clinic/core/ui/foundation.dart';
import 'package:ai_clinic/core/ui/widgets/actions/actions.dart';

/// Logical edge from which an [AppDrawer] enters.
enum AppDrawerSide {
  inlineStart,
  inlineEnd,
  bottom,
}

/// Width preset for side [AppDrawer] panels.
enum AppDrawerSize {
  sm,
  md,
  lg,
}

/// Side panel for detail or edit flows without leaving page context.
///
/// Prefer [showAppDrawer] for imperative presentation with backdrop, motion,
/// and focus management.
class AppDrawer extends StatelessWidget {
  const AppDrawer({
    required this.title,
    required this.body,
    this.description,
    this.footer,
    this.side = AppDrawerSide.inlineEnd,
    this.size = AppDrawerSize.md,
    this.onClose,
    this.semanticLabel,
    super.key,
  });

  final String title;
  final String? description;
  final Widget body;
  final Widget? footer;
  final AppDrawerSide side;
  final AppDrawerSize size;
  final VoidCallback? onClose;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final brightness = Theme.of(context).brightness;
    final resolvedSide = _AppDrawerLayout.resolveSide(side, context);
    final borderRadius = _AppDrawerLayout.panelBorderRadius(resolvedSide);

    return Semantics(
      label: semanticLabel,
      scopesRoute: true,
      namesRoute: true,
      explicitChildNodes: true,
      child: Material(
        type: MaterialType.transparency,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.surfaceRaised,
            borderRadius: borderRadius,
            border: Border.all(color: colors.borderDefault),
            boxShadow: AppShadows.forLevel(3, brightness),
          ),
          child: ClipRRect(
            borderRadius: borderRadius,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _AppDrawerHeader(
                  title: title,
                  description: description,
                  onClose: onClose,
                ),
                Expanded(child: _AppDrawerBody(child: body)),
                if (footer != null) _AppDrawerFooter(child: footer!),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Callback passed to [showAppDrawer] builders to dismiss the drawer.
typedef AppDrawerCloseCallback<T> = Future<void> Function([T? result]);

/// Presents an [AppDrawer] with optional modal scrim and drawer motion.
Future<T?> showAppDrawer<T>(
  BuildContext context, {
  required Widget Function(BuildContext context, AppDrawerCloseCallback<T> close)
      builder,
  AppDrawerSide side = AppDrawerSide.inlineEnd,
  AppDrawerSize size = AppDrawerSize.md,
  bool modal = true,
  bool barrierDismissible = true,
  Future<bool> Function()? onWillDismiss,
  String? semanticLabel,
}) {
  final focusBeforeOpen = FocusManager.instance.primaryFocus;
  final reduced = AppMotion.reduced(context);
  final enterSpec = AppMotion.resolvePreset(
    AppMotionPreset.drawer,
    reduced: reduced,
  );

  if (modal) {
    return showGeneralDialog<T>(
      context: context,
      barrierDismissible: false,
      barrierLabel: semanticLabel ??
          MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: Colors.transparent,
      transitionDuration: enterSpec.duration,
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        return _AppDrawerHost<T>(
          animation: animation,
          side: side,
          size: size,
          modal: modal,
          barrierDismissible: barrierDismissible,
          onWillDismiss: onWillDismiss,
          semanticLabel: semanticLabel,
          focusBeforeOpen: focusBeforeOpen,
          builder: builder,
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) =>
          child,
    ).then((result) {
      final node = focusBeforeOpen;
      if (node != null && node.canRequestFocus) {
        node.requestFocus();
      }
      return result;
    });
  }

  final overlayState = Overlay.of(context, rootOverlay: true);
  late OverlayEntry entry;
  final completer = Completer<T?>();
  var dismissed = false;
  late _AppDrawerHost<T> host;

  void dismiss([T? result]) {
    if (dismissed) return;
    dismissed = true;
    entry.remove();
    final node = focusBeforeOpen;
    if (node != null && node.canRequestFocus) {
      node.requestFocus();
    }
    if (!completer.isCompleted) {
      completer.complete(result);
    }
  }

  host = _AppDrawerHost<T>(
    animation: AlwaysStoppedAnimation<double>(1),
    side: side,
    size: size,
    modal: modal,
    barrierDismissible: barrierDismissible,
    onWillDismiss: onWillDismiss,
    semanticLabel: semanticLabel,
    focusBeforeOpen: focusBeforeOpen,
    builder: builder,
    onClosed: dismiss,
  );

  entry = OverlayEntry(builder: (overlayContext) => host);
  overlayState.insert(entry);
  return completer.future;
}

class _AppDrawerHost<T> extends StatefulWidget {
  const _AppDrawerHost({
    required this.animation,
    required this.side,
    required this.size,
    required this.modal,
    required this.barrierDismissible,
    required this.onWillDismiss,
    required this.semanticLabel,
    required this.focusBeforeOpen,
    required this.builder,
    this.onClosed,
  });

  final Animation<double> animation;
  final AppDrawerSide side;
  final AppDrawerSize size;
  final bool modal;
  final bool barrierDismissible;
  final Future<bool> Function()? onWillDismiss;
  final String? semanticLabel;
  final FocusNode? focusBeforeOpen;
  final Widget Function(
    BuildContext context,
    AppDrawerCloseCallback<T> close,
  ) builder;
  final void Function(T? result)? onClosed;

  @override
  State<_AppDrawerHost<T>> createState() => _AppDrawerHostState<T>();
}

class _AppDrawerHostState<T> extends State<_AppDrawerHost<T>> {
  final FocusScopeNode _focusScopeNode = FocusScopeNode();
  var _isClosing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focusScopeNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _focusScopeNode.dispose();
    super.dispose();
  }

  Future<void> _close([T? result]) async {
    if (_isClosing || !mounted) return;
    if (widget.onWillDismiss != null) {
      final canDismiss = await widget.onWillDismiss!();
      if (!canDismiss || !mounted) return;
    }
    _isClosing = true;
    if (widget.onClosed != null) {
      widget.onClosed!(result);
      return;
    }
    Navigator.of(context).pop<T>(result);
  }

  Future<void> _handleBarrierTap() async {
    if (!widget.barrierDismissible) return;
    await _close();
  }

  @override
  Widget build(BuildContext context) {
    final resolvedSide = _AppDrawerLayout.resolveSide(widget.side, context);
    final panelConstraints =
        _AppDrawerLayout.panelConstraints(resolvedSide, widget.size, context);

    final panel = FocusScope(
      node: _focusScopeNode,
      autofocus: true,
      child: Shortcuts(
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.escape): _DismissOverlayIntent(),
        },
        child: Actions(
          actions: {
            _DismissOverlayIntent: CallbackAction<_DismissOverlayIntent>(
              onInvoke: (_) {
                unawaited(_close());
                return null;
              },
            ),
          },
          child: _AppDrawerMotion(
            animation: widget.animation,
            side: resolvedSide,
            child: Align(
              alignment: _AppDrawerLayout.panelAlignment(resolvedSide).resolve(
                Directionality.of(context),
              ),
              child: ConstrainedBox(
                constraints: panelConstraints,
                child: widget.builder(context, _close),
              ),
            ),
          ),
        ),
      ),
    );

    if (!widget.modal) {
      return panel;
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await _close();
      },
      child: AnimatedBuilder(
        animation: widget.animation,
        builder: (context, child) {
          return _AppDrawerScrim(
            animation: widget.animation,
            onDismiss: widget.barrierDismissible ? _handleBarrierTap : null,
            semanticLabel: widget.semanticLabel,
            child: child!,
          );
        },
        child: panel,
      ),
    );
  }
}

class _AppDrawerHeader extends StatelessWidget {
  const _AppDrawerHeader({
    required this.title,
    required this.onClose,
    this.description,
  });

  final String title;
  final String? description;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: colors.borderSubtle),
        ),
      ),
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(
          AppSpacing.s5,
          AppSpacing.s4,
          AppSpacing.s4,
          AppSpacing.s4,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: typography.h3.copyWith(color: colors.textPrimary),
                  ),
                  if (description != null) ...[
                    const SizedBox(height: AppSpacing.s1),
                    Text(
                      description!,
                      style: typography.bodySm.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.s4),
            AppIconButton(
              icon: LucideIcons.x,
              semanticLabel: 'Close',
              size: AppIconButtonSize.sm,
              onPressed: onClose,
            ),
          ],
        ),
      ),
    );
  }
}

class _AppDrawerBody extends StatelessWidget {
  const _AppDrawerBody({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: AppSpacing.s5,
        vertical: AppSpacing.s4,
      ),
      child: child,
    );
  }
}

class _AppDrawerFooter extends StatelessWidget {
  const _AppDrawerFooter({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: colors.borderSubtle),
        ),
      ),
      child: Padding(
        padding: const EdgeInsetsDirectional.all(AppSpacing.s5),
        child: child,
      ),
    );
  }
}

class _AppDrawerMotion extends StatelessWidget {
  const _AppDrawerMotion({
    required this.animation,
    required this.side,
    required this.child,
  });

  final Animation<double> animation;
  final AppDrawerSide side;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final reduced = AppMotion.reduced(context);
    final curve = CurvedAnimation(
      parent: animation,
      curve: AppMotion.resolvePreset(
        AppMotionPreset.drawer,
        reduced: reduced,
      ).curve,
      reverseCurve: AppMotion.resolvePreset(
        AppMotionPreset.drawer,
        reduced: reduced,
        isExit: true,
      ).curve,
    );
    final isRtl = Directionality.of(context) == TextDirection.rtl;

    final begin = switch (side) {
      AppDrawerSide.bottom => const Offset(0, 1),
      AppDrawerSide.inlineEnd =>
        Offset(reduced ? 0 : (isRtl ? -1 : 1), 0),
      AppDrawerSide.inlineStart =>
        Offset(reduced ? 0 : (isRtl ? 1 : -1), 0),
    };

    return SlideTransition(
      position: Tween<Offset>(begin: begin, end: Offset.zero).animate(curve),
      child: FadeTransition(
        opacity: curve,
        child: child,
      ),
    );
  }
}

class _AppDrawerScrim extends StatelessWidget {
  const _AppDrawerScrim({
    required this.animation,
    required this.child,
    this.onDismiss,
    this.semanticLabel,
  });

  final Animation<double> animation;
  final Widget child;
  final Future<void> Function()? onDismiss;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final reduced = AppMotion.reduced(context);
    final useFrost = !reduced;

    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(
          child: FadeTransition(
            opacity: animation,
            child: Semantics(
              button: onDismiss != null,
              label: semanticLabel ?? 'Close drawer',
              onTap: onDismiss == null ? null : () => onDismiss!(),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onDismiss == null ? null : () => onDismiss!(),
                child: useFrost
                    ? ClipRect(
                        child: BackdropFilter(
                          filter: ImageFilter.blur(
                            sigmaX: AppSpacing.s1,
                            sigmaY: AppSpacing.s1,
                          ),
                          child: ColoredBox(
                            color: colors.surfaceBackdrop,
                          ),
                        ),
                      )
                    : ColoredBox(color: colors.surfaceBackdrop),
              ),
            ),
          ),
        ),
        child,
      ],
    );
  }
}

class _DismissOverlayIntent extends Intent {
  const _DismissOverlayIntent();
}

abstract final class _AppDrawerLayout {
  static AppDrawerSide resolveSide(AppDrawerSide side, BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width < AppBreakpoints.md &&
        (side == AppDrawerSide.inlineStart ||
            side == AppDrawerSide.inlineEnd)) {
      return AppDrawerSide.bottom;
    }
    return side;
  }

  static AlignmentDirectional panelAlignment(AppDrawerSide side) {
    return switch (side) {
      AppDrawerSide.inlineStart => AlignmentDirectional.centerStart,
      AppDrawerSide.inlineEnd => AlignmentDirectional.centerEnd,
      AppDrawerSide.bottom => AlignmentDirectional.bottomCenter,
    };
  }

  static BoxConstraints panelConstraints(
    AppDrawerSide side,
    AppDrawerSize size,
    BuildContext context,
  ) {
    final viewport = MediaQuery.sizeOf(context);
    return switch (side) {
      AppDrawerSide.bottom => BoxConstraints(
          maxWidth: viewport.width,
          maxHeight: viewport.height * 0.85,
        ),
      AppDrawerSide.inlineStart || AppDrawerSide.inlineEnd => BoxConstraints(
          maxWidth: _sideMaxWidth(size),
          minWidth: _sideMaxWidth(size),
          maxHeight: viewport.height,
          minHeight: viewport.height,
        ),
    };
  }

  static double _sideMaxWidth(AppDrawerSize size) => switch (size) {
        AppDrawerSize.sm => 384,
        AppDrawerSize.md => 448,
        AppDrawerSize.lg => 576,
      };

  static BorderRadiusGeometry panelBorderRadius(AppDrawerSide side) {
    return switch (side) {
      AppDrawerSide.bottom => const BorderRadius.vertical(
          top: Radius.circular(AppRadii.xl),
        ),
      AppDrawerSide.inlineStart => const BorderRadiusDirectional.horizontal(
          end: Radius.circular(AppRadii.xl),
        ),
      AppDrawerSide.inlineEnd => const BorderRadiusDirectional.horizontal(
          start: Radius.circular(AppRadii.xl),
        ),
    };
  }
}
