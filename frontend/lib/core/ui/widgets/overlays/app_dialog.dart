import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:ai_clinic/core/ui/foundation.dart';
import 'package:ai_clinic/core/ui/widgets/actions/actions.dart';

/// Width preset for [AppDialog].
enum AppDialogSize {
  sm,
  md,
  lg,
  full,
}

/// Focused modal surface with sticky header, scrollable body, and optional footer.
///
/// Prefer [showAppDialog] for imperative presentation with focus management,
/// backdrop, and motion.
class AppDialog extends StatelessWidget {
  const AppDialog({
    required this.title,
    required this.body,
    this.description,
    this.footer,
    this.size = AppDialogSize.md,
    this.onClose,
    this.semanticLabel,
    super.key,
  });

  final String title;
  final String? description;
  final Widget body;
  final Widget? footer;
  final AppDialogSize size;
  final VoidCallback? onClose;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final brightness = Theme.of(context).brightness;
    final width = MediaQuery.sizeOf(context).width;
    final isFullScreen = _AppDialogLayout.isFullScreen(width, size);

    final panel = Semantics(
      label: semanticLabel,
      scopesRoute: true,
      namesRoute: true,
      explicitChildNodes: true,
      child: Material(
        type: MaterialType.transparency,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.surfaceRaised,
            borderRadius: isFullScreen ? BorderRadius.zero : AppRadii.xlAll,
            border: isFullScreen
                ? null
                : Border.all(color: colors.borderDefault),
            boxShadow: isFullScreen
                ? null
                : AppShadows.forLevel(3, brightness),
          ),
          child: ClipRRect(
            borderRadius: isFullScreen ? BorderRadius.zero : AppRadii.xlAll,
            child: Column(
              mainAxisSize:
                  isFullScreen ? MainAxisSize.max : MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _AppDialogHeader(
                  title: title,
                  description: description,
                  onClose: onClose,
                ),
                if (isFullScreen)
                  Expanded(
                    child: _AppDialogBody(child: body),
                  )
                else
                  Flexible(
                    child: _AppDialogBody(child: body),
                  ),
                if (footer != null) _AppDialogFooter(child: footer!),
              ],
            ),
          ),
        ),
      ),
    );

    if (isFullScreen) {
      return SizedBox(
        width: width,
        height: MediaQuery.sizeOf(context).height,
        child: panel,
      );
    }

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: _AppDialogLayout.maxWidth(size, width),
        maxHeight: _AppDialogLayout.maxHeight(size, context),
      ),
      child: panel,
    );
  }
}

/// Callback passed to [showAppDialog] builders to dismiss the dialog.
typedef AppDialogCloseCallback<T> = Future<void> Function([T? result]);

/// Presents an [AppDialog] with modal backdrop, focus trap, and motion.
Future<T?> showAppDialog<T>(
  BuildContext context, {
  required Widget Function(BuildContext context, AppDialogCloseCallback<T> close)
      builder,
  AppDialogSize size = AppDialogSize.md,
  bool barrierDismissible = true,
  Future<bool> Function()? onWillDismiss,
  String? semanticLabel,
}) {
  final focusBeforeOpen = FocusManager.instance.primaryFocus;
  final reduced = AppMotion.reduced(context);
  final enterSpec = AppMotion.resolvePreset(
    AppMotionPreset.modal,
    reduced: reduced,
  );

  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: false,
    barrierLabel:
        semanticLabel ?? MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.transparent,
    transitionDuration: enterSpec.duration,
    pageBuilder: (dialogContext, animation, secondaryAnimation) {
      return _AppDialogHost<T>(
        animation: animation,
        secondaryAnimation: secondaryAnimation,
        size: size,
        barrierDismissible: barrierDismissible,
        onWillDismiss: onWillDismiss,
        semanticLabel: semanticLabel,
        focusBeforeOpen: focusBeforeOpen,
        builder: builder,
      );
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) => child,
  ).then((result) {
    final node = focusBeforeOpen;
    if (node != null && node.canRequestFocus) {
      node.requestFocus();
    }
    return result;
  });
}

class _AppDialogHost<T> extends StatefulWidget {
  const _AppDialogHost({
    required this.animation,
    required this.secondaryAnimation,
    required this.size,
    required this.barrierDismissible,
    required this.onWillDismiss,
    required this.semanticLabel,
    required this.focusBeforeOpen,
    required this.builder,
  });

  final Animation<double> animation;
  final Animation<double> secondaryAnimation;
  final AppDialogSize size;
  final bool barrierDismissible;
  final Future<bool> Function()? onWillDismiss;
  final String? semanticLabel;
  final FocusNode? focusBeforeOpen;
  final Widget Function(
    BuildContext context,
    AppDialogCloseCallback<T> close,
  ) builder;

  @override
  State<_AppDialogHost<T>> createState() => _AppDialogHostState<T>();
}

class _AppDialogHostState<T> extends State<_AppDialogHost<T>> {
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
    Navigator.of(context).pop<T>(result);
  }

  Future<void> _handleBarrierTap() async {
    if (!widget.barrierDismissible) return;
    await _close();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final isFullScreen =
        _AppDialogLayout.isFullScreen(width, widget.size);
    final padding = isFullScreen
        ? EdgeInsets.zero
        : const EdgeInsets.all(AppSpacing.s4);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await _close();
      },
      child: AnimatedBuilder(
        animation: widget.animation,
        builder: (context, child) {
          return _AppOverlayScrim(
            animation: widget.animation,
            onDismiss: widget.barrierDismissible ? _handleBarrierTap : null,
            semanticLabel: widget.semanticLabel,
            child: child!,
          );
        },
        child: SafeArea(
          child: Padding(
            padding: padding,
            child: Center(
              child: FocusScope(
                node: _focusScopeNode,
                autofocus: true,
                child: Shortcuts(
                  shortcuts: const {
                    SingleActivator(LogicalKeyboardKey.escape):
                        _DismissOverlayIntent(),
                  },
                  child: Actions(
                    actions: {
                      _DismissOverlayIntent:
                          CallbackAction<_DismissOverlayIntent>(
                        onInvoke: (_) {
                          unawaited(_close());
                          return null;
                        },
                      ),
                    },
                    child: _AppDialogMotion(
                      animation: widget.animation,
                      child: widget.builder(context, _close),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AppDialogHeader extends StatelessWidget {
  const _AppDialogHeader({
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
          AppSpacing.s6,
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
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (description != null) ...[
                    const SizedBox(height: AppSpacing.s1),
                    Text(
                      description!,
                      style: typography.bodySm.copyWith(
                        color: colors.textSecondary,
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
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

class _AppDialogBody extends StatelessWidget {
  const _AppDialogBody({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: AppSpacing.s6,
        vertical: AppSpacing.s4,
      ),
      child: child,
    );
  }
}

class _AppDialogFooter extends StatelessWidget {
  const _AppDialogFooter({required this.child});

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
        padding: const EdgeInsetsDirectional.fromSTEB(
          AppSpacing.s6,
          AppSpacing.s4,
          AppSpacing.s6,
          AppSpacing.s4,
        ),
        child: Align(
          alignment: AlignmentDirectional.centerEnd,
          child: _AppDialogFooterActions(child: child),
        ),
      ),
    );
  }
}

/// Keeps the primary action at the logical inline-end when using [Wrap].
class _AppDialogFooterActions extends StatelessWidget {
  const _AppDialogFooterActions({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.s2,
      runSpacing: AppSpacing.s2,
      alignment: WrapAlignment.end,
      crossAxisAlignment: WrapCrossAlignment.center,
      textDirection: Directionality.of(context),
      children: _extractChildren(child),
    );
  }

  List<Widget> _extractChildren(Widget widget) {
    if (widget is Row) {
      return widget.children;
    }
    if (widget is Wrap) {
      return widget.children;
    }
    return [widget];
  }
}

class _AppDialogMotion extends StatelessWidget {
  const _AppDialogMotion({
    required this.animation,
    required this.child,
  });

  final Animation<double> animation;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final reduced = AppMotion.reduced(context);
    final curve = CurvedAnimation(
      parent: animation,
      curve: AppMotion.resolvePreset(
        AppMotionPreset.modal,
        reduced: reduced,
      ).curve,
      reverseCurve: AppMotion.resolvePreset(
        AppMotionPreset.modal,
        reduced: reduced,
        isExit: true,
      ).curve,
    );

    return FadeTransition(
      opacity: curve,
      child: ScaleTransition(
        scale: Tween<double>(begin: reduced ? 1 : 0.97, end: 1).animate(curve),
        child: SlideTransition(
          position: Tween<Offset>(
            begin: Offset(0, reduced ? 0 : 8 / MediaQuery.sizeOf(context).height),
            end: Offset.zero,
          ).animate(curve),
          child: child,
        ),
      ),
    );
  }
}

class _AppOverlayScrim extends StatelessWidget {
  const _AppOverlayScrim({
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
              label: semanticLabel ?? 'Close dialog',
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

abstract final class _AppDialogLayout {
  static bool isFullScreen(double width, AppDialogSize size) {
    return width < AppBreakpoints.sm || size == AppDialogSize.full;
  }

  static double maxWidth(AppDialogSize size, double viewportWidth) {
    if (isFullScreen(viewportWidth, size)) {
      return viewportWidth;
    }
    return switch (size) {
      AppDialogSize.sm => 384,
      AppDialogSize.md => 512,
      AppDialogSize.lg => 672,
      AppDialogSize.full => viewportWidth - AppSpacing.s8,
    };
  }

  static double maxHeight(AppDialogSize size, BuildContext context) {
    final viewportHeight = MediaQuery.sizeOf(context).height;
    if (size == AppDialogSize.full ||
        MediaQuery.sizeOf(context).width < AppBreakpoints.sm) {
      return viewportHeight;
    }
    return viewportHeight - AppSpacing.s8;
  }
}
