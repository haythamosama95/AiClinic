import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/components/app_button.dart';
import 'package:ai_clinic/core/ui/components/app_icon_button.dart';
import 'package:ai_clinic/core/ui/components/app_text_input.dart';
import 'package:ai_clinic/core/ui/motion/app_motion.dart';
import 'package:ai_clinic/core/ui/theme/app_color_primitives.dart';
import 'package:ai_clinic/core/ui/theme/app_elevation.dart';
import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';

/// Dialog panel width tokens (web `max-w-sm` / `lg` / `2xl`).
enum AppDialogSize { sm, md, lg, full }

enum AppConfirmationDialogVariant { destructive, financial }

/// Application-owned modal dialog (web `Dialog`).
///
/// Use as a controlled widget with [open] / [onOpenChange], or imperatively via
/// [AppDialog.show].
class AppDialog extends StatefulWidget {
  const AppDialog({
    required this.open,
    required this.onOpenChange,
    required this.title,
    this.description,
    this.size = AppDialogSize.md,
    required this.child,
    this.footer,
    this.barrierDismissible = true,
    this.blur = true,
    this.showCloseButton = true,
    this.showHeader = true,
    super.key,
  });

  final bool open;
  final ValueChanged<bool> onOpenChange;
  final String title;
  final String? description;
  final AppDialogSize size;
  final Widget child;
  final Widget? footer;
  final bool barrierDismissible;
  final bool blur;
  final bool showCloseButton;
  final bool showHeader;

  /// Presents a dialog and returns when it is dismissed.
  static Future<T?> show<T>(
    BuildContext context, {
    required String title,
    String? description,
    AppDialogSize size = AppDialogSize.md,
    double? maxWidth,
    required Widget child,
    Widget? footer,
    bool barrierDismissible = true,
    bool blur = true,
    bool showCloseButton = true,
    bool showHeader = true,
  }) {
    return showDialog<T>(
      context: context,
      barrierDismissible: barrierDismissible,
      barrierColor: Colors.transparent,
      builder: (dialogContext) => _AppDialogShell(
        title: title,
        description: description,
        size: size,
        maxWidth: maxWidth,
        footer: footer,
        barrierDismissible: barrierDismissible,
        blur: blur,
        showCloseButton: showCloseButton,
        showHeader: showHeader,
        onClose: () => Navigator.of(dialogContext).pop(),
        child: child,
      ),
    );
  }

  @override
  State<AppDialog> createState() => _AppDialogState();
}

<<<<<<< HEAD
class _AppDialogState extends State<AppDialog> {
  var _presented = false;
  NavigatorState? _navigator;
=======
/// Live snapshot of [AppDialog] props for the presented overlay route.
///
/// Controlled [AppDialog] captures [child] when `showDialog` runs; this notifier
/// pushes prop updates into the overlay while the dialog stays open.
class _AppDialogPresentation extends ChangeNotifier {
  _AppDialogPresentation(AppDialog dialog) {
    _sync(dialog);
  }

  late String title;
  String? description;
  late AppDialogSize size;
  late Widget child;
  Widget? footer;
  late bool barrierDismissible;
  late bool blur;
  late bool showCloseButton;
  late bool showHeader;

  void syncFrom(AppDialog dialog) {
    _sync(dialog);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (hasListeners) {
        notifyListeners();
      }
    });
  }

  void _sync(AppDialog dialog) {
    title = dialog.title;
    description = dialog.description;
    size = dialog.size;
    child = dialog.child;
    footer = dialog.footer;
    barrierDismissible = dialog.barrierDismissible;
    blur = dialog.blur;
    showCloseButton = dialog.showCloseButton;
    showHeader = dialog.showHeader;
  }
}

class _AppDialogState extends State<AppDialog> {
  var _presented = false;
  NavigatorState? _navigator;
  _AppDialogPresentation? _presentation;
>>>>>>> master

  @override
  void initState() {
    super.initState();
    if (widget.open) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _syncPresentation());
    }
  }

  @override
  void didUpdateWidget(covariant AppDialog oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.open != oldWidget.open) {
      // showDialog / maybePop mutate the overlay and must not run during build.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _syncPresentation();
      });
<<<<<<< HEAD
=======
      return;
    }

    if (widget.open && _presented) {
      _presentation?.syncFrom(widget);
>>>>>>> master
    }
  }

  @override
  void dispose() {
<<<<<<< HEAD
=======
    _presentation?.dispose();
>>>>>>> master
    if (_presented) {
      _navigator?.maybePop();
    }
    super.dispose();
  }

  Future<void> _syncPresentation() async {
    if (!mounted) return;

    if (widget.open && !_presented) {
<<<<<<< HEAD
      _presented = true;
      _navigator = Navigator.of(context, rootNavigator: true);
      await AppDialog.show<void>(
        context,
        title: widget.title,
        description: widget.description,
        size: widget.size,
        barrierDismissible: widget.barrierDismissible,
        blur: widget.blur,
        showCloseButton: widget.showCloseButton,
        showHeader: widget.showHeader,
        footer: widget.footer,
        child: widget.child,
      );
      _presented = false;
      _navigator = null;
=======
      _presentation = _AppDialogPresentation(widget);
      _presented = true;
      _navigator = Navigator.of(context, rootNavigator: true);
      final presentation = _presentation!;
      await showDialog<void>(
        context: context,
        barrierDismissible: presentation.barrierDismissible,
        barrierColor: Colors.transparent,
        builder: (dialogContext) => ListenableBuilder(
          listenable: presentation,
          builder: (context, _) => _AppDialogShell(
            title: presentation.title,
            description: presentation.description,
            size: presentation.size,
            footer: presentation.footer,
            barrierDismissible: presentation.barrierDismissible,
            blur: presentation.blur,
            showCloseButton: presentation.showCloseButton,
            showHeader: presentation.showHeader,
            onClose: () => Navigator.of(dialogContext).pop(),
            child: presentation.child,
          ),
        ),
      );
      _presented = false;
      _navigator = null;
      _presentation?.dispose();
      _presentation = null;
>>>>>>> master
      if (mounted && widget.open) {
        widget.onOpenChange(false);
      }
      return;
    }

    if (!widget.open && _presented) {
      _navigator?.maybePop();
    }
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

/// Confirmation dialog — always [AppDialogSize.sm] (web `ConfirmationDialog`).
class AppConfirmationDialog extends StatefulWidget {
  const AppConfirmationDialog({
    required this.open,
    required this.onOpenChange,
    required this.title,
    required this.description,
    this.confirmLabel = 'Confirm',
    this.cancelLabel = 'Cancel',
    this.variant = AppConfirmationDialogVariant.destructive,
    this.requireTypedConfirmation,
    required this.onConfirm,
    this.loading = false,
    this.barrierDismissible = true,
    this.blur = true,
    super.key,
  });

  final bool open;
  final ValueChanged<bool> onOpenChange;
  final String title;
  final String description;
  final String confirmLabel;
  final String cancelLabel;
  final AppConfirmationDialogVariant variant;
  final String? requireTypedConfirmation;
  final VoidCallback onConfirm;
  final bool loading;
  final bool barrierDismissible;
  final bool blur;

  /// Imperatively presents a small confirmation dialog; returns `true` when confirmed.
  static Future<bool> show(
    BuildContext context, {
    required String title,
    required String description,
    String confirmLabel = 'Confirm',
    String cancelLabel = 'Cancel',
    AppConfirmationDialogVariant variant = AppConfirmationDialogVariant.destructive,
    bool barrierDismissible = true,
    bool blur = true,
  }) async {
    final result = await AppDialog.show<bool>(
      context,
      title: title,
      size: AppDialogSize.sm,
      barrierDismissible: barrierDismissible,
      blur: blur,
      child: Builder(
        builder: (context) =>
            Text(description, style: AppTypography.body(context).copyWith(color: context.appColors.textSecondary)),
      ),
      footer: Builder(
        builder: (dialogContext) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppButton(
              variant: AppButtonVariant.secondary,
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(cancelLabel),
            ),
            const SizedBox(width: AppSpacing.space2),
            AppButton(
              variant: variant == AppConfirmationDialogVariant.destructive
                  ? AppButtonVariant.danger
                  : AppButtonVariant.primary,
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(confirmLabel),
            ),
          ],
        ),
      ),
    );

    return result ?? false;
  }

  @override
  State<AppConfirmationDialog> createState() => _AppConfirmationDialogState();
}

class _AppConfirmationDialogState extends State<AppConfirmationDialog> {
  final _typedController = TextEditingController();

  @override
  void dispose() {
    _typedController.dispose();
    super.dispose();
  }

  void _handleOpenChange(bool open) {
    if (!open) {
      _typedController.clear();
    }
    widget.onOpenChange(open);
  }

  bool get _canConfirm {
    final required = widget.requireTypedConfirmation;
    if (required == null) return true;
    return _typedController.text == required;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final requiredText = widget.requireTypedConfirmation;

    return AppDialog(
      open: widget.open,
      onOpenChange: _handleOpenChange,
      title: widget.title,
      size: AppDialogSize.sm,
      barrierDismissible: widget.barrierDismissible,
      blur: widget.blur,
      footer: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppButton(
            variant: AppButtonVariant.secondary,
            onPressed: widget.loading ? null : () => _handleOpenChange(false),
            child: Text(widget.cancelLabel),
          ),
          const SizedBox(width: AppSpacing.space2),
          AppButton(
            variant: widget.variant == AppConfirmationDialogVariant.destructive
                ? AppButtonVariant.danger
                : AppButtonVariant.primary,
            loading: widget.loading,
            disabled: !_canConfirm,
            onPressed: _canConfirm && !widget.loading
                ? () {
                    widget.onConfirm();
                    _handleOpenChange(false);
                  }
                : null,
            child: Text(widget.confirmLabel),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.description, style: AppTypography.body(context).copyWith(color: colors.textSecondary)),
          if (requiredText != null) ...[
            const SizedBox(height: AppSpacing.space4),
            Text.rich(
              TextSpan(
                style: AppTypography.bodySm(context).copyWith(color: colors.textSecondary),
                children: [
                  const TextSpan(text: 'Type '),
                  TextSpan(
                    text: requiredText,
                    style: AppTypography.bodySm(
                      context,
                    ).copyWith(color: colors.textSecondary, fontWeight: FontWeight.w600),
                  ),
                  const TextSpan(text: ' to confirm'),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.space2),
            AppTextInput(controller: _typedController, onChanged: (_) => setState(() {})),
          ],
        ],
      ),
    );
  }
}

class _AppDialogShell extends StatefulWidget {
  const _AppDialogShell({
    required this.title,
    required this.description,
    required this.size,
    required this.child,
    required this.onClose,
    required this.barrierDismissible,
    required this.blur,
    required this.showCloseButton,
    required this.showHeader,
    this.maxWidth,
    this.footer,
  });

  final String title;
  final String? description;
  final AppDialogSize size;
  final double? maxWidth;
  final Widget child;
  final Widget? footer;
  final VoidCallback onClose;
  final bool barrierDismissible;
  final bool blur;
  final bool showCloseButton;
  final bool showHeader;

  @override
  State<_AppDialogShell> createState() => _AppDialogShellState();
}

class _AppDialogShellState extends State<_AppDialogShell> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;
  var _motionConfigured = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: AppMotion.resolveDuration(AppMotionPreset.modal));
    _animation = CurvedAnimation(parent: _controller, curve: AppMotion.resolveCurve(AppMotionPreset.modal));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_motionConfigured) return;
    _motionConfigured = true;
    final reducedMotion = AppMotion.prefersReducedMotion(context);
    _controller.duration = AppMotion.resolveDuration(AppMotionPreset.modal, reducedMotion: reducedMotion);
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
<<<<<<< HEAD
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: EdgeInsets.zero,
      child: _AppDialogTransition(
        animation: _animation,
        barrierDismissible: widget.barrierDismissible,
        blur: widget.blur,
        child: AppDialogPanel(
          title: widget.title,
          description: widget.description,
          size: widget.size,
          maxWidth: widget.maxWidth,
          footer: widget.footer,
          onClose: widget.onClose,
          showCloseButton: widget.showCloseButton,
          showHeader: widget.showHeader,
          child: widget.child,
=======
    return PopScope(
      canPop: widget.barrierDismissible,
      child: Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        insetPadding: EdgeInsets.zero,
        child: _AppDialogTransition(
          animation: _animation,
          barrierDismissible: widget.barrierDismissible,
          blur: widget.blur,
          child: AppDialogPanel(
            title: widget.title,
            description: widget.description,
            size: widget.size,
            maxWidth: widget.maxWidth,
            footer: widget.footer,
            onClose: widget.onClose,
            showCloseButton: widget.showCloseButton,
            showHeader: widget.showHeader,
            child: widget.child,
          ),
>>>>>>> master
        ),
      ),
    );
  }
}

class _AppDialogTransition extends StatelessWidget {
  const _AppDialogTransition({
    required this.animation,
    required this.barrierDismissible,
    required this.blur,
    required this.child,
  });

  final Animation<double> animation;
  final bool barrierDismissible;
  final bool blur;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final backdropColor = isDark ? AppColorPrimitives.surfaceBackdropDark : AppColorPrimitives.surfaceBackdropLight;
    final reducedMotion = AppMotion.prefersReducedMotion(context);
    final showBlur = blur && !reducedMotion;

    return Stack(
      fit: StackFit.expand,
      children: [
        FadeTransition(
          opacity: animation,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: barrierDismissible ? () => Navigator.of(context).pop() : null,
            child: showBlur
                ? BackdropFilter(
                    filter: ui.ImageFilter.blur(sigmaX: 4, sigmaY: 4),
                    child: ColoredBox(color: backdropColor),
                  )
                : ColoredBox(color: backdropColor),
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.space4),
            child: Center(
              child: AppMotion.animatedPreset(
                context: context,
                preset: AppMotionPreset.modal,
                animation: animation,
                child: child,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Dialog panel chrome (header, scroll body, footer) for custom dialog hosts.
class AppDialogPanel extends StatelessWidget {
  const AppDialogPanel({
    required this.title,
    required this.description,
    required this.size,
    required this.child,
    required this.onClose,
    required this.showCloseButton,
    required this.showHeader,
    this.maxWidth,
    this.footer,
    super.key,
  });

  final String title;
  final String? description;
  final AppDialogSize size;
  final double? maxWidth;
  final Widget child;
  final Widget? footer;
  final VoidCallback onClose;
  final bool showCloseButton;
  final bool showHeader;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final elevation = context.appElevation;
    final constraints = _sizeConstraints(context, size, maxWidth: maxWidth);

    return Semantics(
      scopesRoute: true,
      explicitChildNodes: true,
      namesRoute: true,
      label: title,
      child: ConstrainedBox(
        constraints: constraints,
        child: Material(
          color: Colors.transparent,
          elevation: 0,
          child: DecoratedBox(
            decoration: elevation.decoration(
              level: 3,
              color: colors.surfaceRaised,
              borderRadius: BorderRadius.circular(AppRadius.xl),
              border: Border.all(color: colors.borderDefault),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.xl),
              child: LayoutBuilder(
                builder: (context, layoutConstraints) {
                  final bodyPadding = EdgeInsets.symmetric(
                    horizontal: showHeader ? AppSpacing.space6 : 0,
                    vertical: showHeader ? AppSpacing.space4 : 0,
                  );
                  final scrollBody = SingleChildScrollView(padding: bodyPadding, child: child);

                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (showHeader)
                        DecoratedBox(
                          decoration: BoxDecoration(
                            border: Border(bottom: BorderSide(color: colors.borderSubtle)),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(
                              AppSpacing.space6,
                              AppSpacing.space4,
                              AppSpacing.space4,
                              AppSpacing.space4,
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(title, style: AppTypography.h3(context).copyWith(color: colors.textPrimary)),
                                      if (description != null) ...[
                                        const SizedBox(height: AppSpacing.space1),
                                        Text(
                                          description!,
                                          style: AppTypography.bodySm(context).copyWith(color: colors.textSecondary),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                if (showCloseButton) ...[
                                  const SizedBox(width: AppSpacing.space4),
                                  AppIconButton(
                                    icon: const Icon(Icons.close, size: 18),
                                    label: 'Close',
                                    size: AppIconButtonSize.sm,
                                    onPressed: onClose,
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      if (layoutConstraints.maxHeight.isFinite) Flexible(child: scrollBody) else scrollBody,
                      if (footer != null)
                        DecoratedBox(
                          decoration: BoxDecoration(
                            border: Border(top: BorderSide(color: colors.borderSubtle)),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(AppSpacing.space4),
                            child: Align(alignment: AlignmentDirectional.centerEnd, child: footer),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  BoxConstraints _sizeConstraints(BuildContext context, AppDialogSize size, {double? maxWidth}) {
    final screen = MediaQuery.sizeOf(context);
    final maxHeight = screen.height - AppSpacing.space8;
    final tokenMaxWidth = switch (size) {
      AppDialogSize.sm => 384.0,
      AppDialogSize.md => 512.0,
      AppDialogSize.lg => 672.0,
      AppDialogSize.full => screen.width - AppSpacing.space8,
    };
    return BoxConstraints(maxWidth: maxWidth ?? tokenMaxWidth, maxHeight: maxHeight);
  }
}
