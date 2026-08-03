import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/components/app_icon_button.dart';
import 'package:ai_clinic/core/ui/motion/app_motion.dart';
import 'package:ai_clinic/core/ui/theme/app_color_primitives.dart';
import 'package:ai_clinic/core/ui/theme/app_elevation.dart';
import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';

/// Logical side for a drawer panel (`inline-end` mirrors under RTL).
enum AppDrawerSide { inlineEnd, inlineStart, bottom }

/// Width preset for side-anchored drawers (web `max-w-sm|md|xl`).
enum AppDrawerSize { sm, md, lg }

/// Slide-in side panel or bottom sheet (web `Drawer`).
///
/// Use [AppDrawer.show] imperatively, or place [AppDrawer] in the tree with
/// [open] / [onOpenChange] for controlled usage.
class AppDrawer extends StatefulWidget {
  const AppDrawer({
    required this.title,
    this.open = false,
    this.onOpenChange,
    this.description,
    this.side = AppDrawerSide.inlineEnd,
    this.size = AppDrawerSize.md,
    this.modal = true,
    this.children = const [],
    this.footer,
    super.key,
  });

  final bool open;
  final ValueChanged<bool>? onOpenChange;
  final String title;
  final String? description;
  final AppDrawerSide side;
  final AppDrawerSize size;
  final bool modal;
  final List<Widget> children;
  final Widget? footer;

  /// Presents the drawer and returns when it is dismissed.
  static Future<T?> show<T>(
    BuildContext context, {
    required String title,
    String? description,
    AppDrawerSide side = AppDrawerSide.inlineEnd,
    AppDrawerSize size = AppDrawerSize.md,
    bool modal = true,
    List<Widget> children = const [],
    Widget? footer,
    ValueChanged<bool>? onOpenChange,
    bool barrierDismissible = true,
  }) {
    onOpenChange?.call(true);

    final reducedMotion = AppMotion.prefersReducedMotion(context);
    final duration = AppMotion.resolveDuration(AppMotionPreset.drawer, reducedMotion: reducedMotion);

    return showGeneralDialog<T>(
      context: context,
      barrierDismissible: modal && barrierDismissible,
      barrierLabel: modal ? MaterialLocalizations.of(context).modalBarrierDismissLabel : '',
      barrierColor: Colors.transparent,
      transitionDuration: duration,
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        return _AppDrawerDialog(
          animation: animation,
          title: title,
          description: description,
          side: side,
          size: size,
          modal: modal,
          footer: footer,
          onClose: () => Navigator.of(dialogContext).pop(),
          children: children,
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) => child,
    ).whenComplete(() => onOpenChange?.call(false));
  }

  @override
  State<AppDrawer> createState() => _AppDrawerState();
}

class _AppDrawerState extends State<AppDrawer> {
  var _presenting = false;

  @override
  void initState() {
    super.initState();
    if (widget.open) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _presentIfNeeded());
    }
  }

  @override
  void didUpdateWidget(covariant AppDrawer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.open != oldWidget.open) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _presentIfNeeded());
    }
  }

  Future<void> _presentIfNeeded() async {
    if (!widget.open || _presenting || !mounted) return;
    _presenting = true;
    await AppDrawer.show<void>(
      context,
      title: widget.title,
      description: widget.description,
      side: widget.side,
      size: widget.size,
      modal: widget.modal,
      children: widget.children,
      footer: widget.footer,
      onOpenChange: widget.onOpenChange,
    );
    _presenting = false;
    if (mounted && widget.open) {
      widget.onOpenChange?.call(false);
    }
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

class _AppDrawerDialog extends StatelessWidget {
  const _AppDrawerDialog({
    required this.animation,
    required this.title,
    this.description,
    required this.side,
    required this.size,
    required this.modal,
    this.footer,
    required this.onClose,
    required this.children,
  });

  final Animation<double> animation;
  final String title;
  final String? description;
  final AppDrawerSide side;
  final AppDrawerSize size;
  final bool modal;
  final List<Widget> children;
  final Widget? footer;
  final VoidCallback onClose;

  static double _widthForSize(AppDrawerSize size) {
    return switch (size) {
      AppDrawerSize.sm => 384,
      AppDrawerSize.md => 448,
      AppDrawerSize.lg => 576,
    };
  }

  static AlignmentDirectional _alignmentForSide(AppDrawerSide side) {
    return switch (side) {
      AppDrawerSide.inlineEnd => AlignmentDirectional.centerEnd,
      AppDrawerSide.inlineStart => AlignmentDirectional.centerStart,
      AppDrawerSide.bottom => AlignmentDirectional.bottomCenter,
    };
  }

  static Offset _slideBegin(AppDrawerSide side, TextDirection direction) {
    return switch (side) {
      AppDrawerSide.inlineEnd => Offset(direction == TextDirection.rtl ? -1 : 1, 0),
      AppDrawerSide.inlineStart => Offset(direction == TextDirection.rtl ? 1 : -1, 0),
      AppDrawerSide.bottom => const Offset(0, 1),
    };
  }

  static BorderRadius _panelRadius(AppDrawerSide side, TextDirection direction) {
    return switch (side) {
      AppDrawerSide.inlineEnd => BorderRadiusDirectional.only(
        topStart: Radius.circular(AppRadius.xl),
        bottomStart: Radius.circular(AppRadius.xl),
      ).resolve(direction),
      AppDrawerSide.inlineStart => BorderRadiusDirectional.only(
        topEnd: Radius.circular(AppRadius.xl),
        bottomEnd: Radius.circular(AppRadius.xl),
      ).resolve(direction),
      AppDrawerSide.bottom => const BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
    };
  }

  @override
  Widget build(BuildContext context) {
    final reducedMotion = AppMotion.prefersReducedMotion(context);
    final curve = AppMotion.resolveCurve(AppMotionPreset.drawer, reducedMotion: reducedMotion);
    final curved = CurvedAnimation(parent: animation, curve: curve);
    final direction = Directionality.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final backdropColor = isDark ? AppColorPrimitives.surfaceBackdropDark : AppColorPrimitives.surfaceBackdropLight;
    final showBlur = !reducedMotion;

    return Material(
      type: MaterialType.transparency,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (modal)
            FadeTransition(
              opacity: curved,
              child: GestureDetector(
                onTap: onClose,
                behavior: HitTestBehavior.opaque,
                child: showBlur
                    ? BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
                        child: ColoredBox(color: backdropColor),
                      )
                    : ColoredBox(color: backdropColor),
              ),
            ),
          SlideTransition(
            position: Tween<Offset>(
              begin: _slideBegin(side, direction),
              end: Offset.zero,
            ).animate(curved),
            child: Align(
              alignment: _alignmentForSide(side),
              child: _AppDrawerPanel(
                title: title,
                description: description,
                side: side,
                size: size,
                borderRadius: _panelRadius(side, direction),
                onClose: onClose,
                footer: footer,
                children: children,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AppDrawerPanel extends StatelessWidget {
  const _AppDrawerPanel({
    required this.title,
    this.description,
    required this.side,
    required this.size,
    required this.borderRadius,
    required this.onClose,
    this.footer,
    required this.children,
  });

  final String title;
  final String? description;
  final AppDrawerSide side;
  final AppDrawerSize size;
  final BorderRadius borderRadius;
  final VoidCallback onClose;
  final List<Widget> children;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final elevation = context.appElevation;
    final screenHeight = MediaQuery.sizeOf(context).height;
    final maxBottomHeight = screenHeight * 0.85;

    final panel = DecoratedBox(
      decoration: elevation.decoration(
        level: 3,
        color: colors.surfaceRaised,
        borderRadius: borderRadius,
        border: Border.all(color: colors.borderDefault),
      ),
      child: Column(
        mainAxisSize: side == AppDrawerSide.bottom ? MainAxisSize.min : MainAxisSize.max,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: colors.borderSubtle)),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space5, vertical: AppSpacing.space4),
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
          if (side == AppDrawerSide.bottom)
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space5, vertical: AppSpacing.space4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: children,
                ),
              ),
            )
          else
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space5, vertical: AppSpacing.space4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: children,
                ),
              ),
            ),
          if (footer != null)
            DecoratedBox(
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: colors.borderSubtle)),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space5, vertical: AppSpacing.space4),
                child: footer,
              ),
            ),
        ],
      ),
    );

    return switch (side) {
      AppDrawerSide.bottom => ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxBottomHeight),
        child: panel,
      ),
      AppDrawerSide.inlineEnd || AppDrawerSide.inlineStart => SizedBox(
        width: _AppDrawerDialog._widthForSize(size),
        height: screenHeight,
        child: panel,
      ),
    };
  }
}
