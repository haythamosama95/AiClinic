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

  /// Presents a dialog and returns when it is dismissed.
  static Future<T?> show<T>(
    BuildContext context, {
    required String title,
    String? description,
    AppDialogSize size = AppDialogSize.md,
    required Widget child,
    Widget? footer,
    bool barrierDismissible = true,
    bool blur = true,
  }) {
    return showDialog<T>(
      context: context,
      barrierDismissible: barrierDismissible,
      barrierColor: Colors.transparent,
      builder: (dialogContext) => _AppDialogShell(
        title: title,
        description: description,
        size: size,
        footer: footer,
        barrierDismissible: barrierDismissible,
        blur: blur,
        onClose: () => Navigator.of(dialogContext).pop(),
        child: child,
      ),
    );
  }

  @override
  State<AppDialog> createState() => _AppDialogState();
}

class _AppDialogState extends State<AppDialog> {
  var _presented = false;
  NavigatorState? _navigator;

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
    }
  }

  @override
  void dispose() {
    if (_presented) {
      _navigator?.maybePop();
    }
    super.dispose();
  }

  Future<void> _syncPresentation() async {
    if (!mounted) return;

    if (widget.open && !_presented) {
      _presented = true;
      _navigator = Navigator.of(context, rootNavigator: true);
      await AppDialog.show<void>(
        context,
        title: widget.title,
        description: widget.description,
        size: widget.size,
        barrierDismissible: widget.barrierDismissible,
        blur: widget.blur,
        footer: widget.footer,
        child: widget.child,
      );
      _presented = false;
      _navigator = null;
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
    this.footer,
  });

  final String title;
  final String? description;
  final AppDialogSize size;
  final Widget child;
  final Widget? footer;
  final VoidCallback onClose;
  final bool barrierDismissible;
  final bool blur;

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
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: EdgeInsets.zero,
      child: _AppDialogTransition(
        animation: _animation,
        barrierDismissible: widget.barrierDismissible,
        blur: widget.blur,
        child: _AppDialogPanel(
          title: widget.title,
          description: widget.description,
          size: widget.size,
          footer: widget.footer,
          onClose: widget.onClose,
          child: widget.child,
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

class _AppDialogPanel extends StatelessWidget {
  const _AppDialogPanel({
    required this.title,
    required this.description,
    required this.size,
    required this.child,
    required this.onClose,
    this.footer,
  });

  final String title;
  final String? description;
  final AppDialogSize size;
  final Widget child;
  final Widget? footer;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final elevation = context.appElevation;
    final isFull = size == AppDialogSize.full;
    final constraints = _sizeConstraints(context, size);

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
              child: Column(
                mainAxisSize: isFull ? MainAxisSize.max : MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
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
                          const SizedBox(width: AppSpacing.space4),
                          AppIconButton(
                            icon: const Icon(Icons.close, size: 18),
                            label: 'Close',
                            size: AppIconButtonSize.sm,
                            onPressed: onClose,
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (isFull)
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space6, vertical: AppSpacing.space4),
                        child: child,
                      ),
                    )
                  else
                    SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space6, vertical: AppSpacing.space4),
                      child: child,
                    ),
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
              ),
            ),
          ),
        ),
      ),
    );
  }

  BoxConstraints _sizeConstraints(BuildContext context, AppDialogSize size) {
    final screen = MediaQuery.sizeOf(context);
    return switch (size) {
      AppDialogSize.sm => const BoxConstraints(maxWidth: 384),
      AppDialogSize.md => const BoxConstraints(maxWidth: 512),
      AppDialogSize.lg => const BoxConstraints(maxWidth: 672),
      AppDialogSize.full => BoxConstraints(
        maxWidth: screen.width - AppSpacing.space8,
        maxHeight: screen.height - AppSpacing.space8,
      ),
    };
  }
}
