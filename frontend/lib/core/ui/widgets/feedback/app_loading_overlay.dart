import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/foundation.dart';
import 'package:ai_clinic/core/ui/widgets/actions/actions.dart';

/// Whether the loading overlay covers a local surface or the full route.
enum AppLoadingOverlayScope { scoped, global }

/// Dimmed loading layer with spinner or skeleton content.
///
/// When [child] is provided, stacks the overlay above [child] while [isLoading]
/// is true. For [AppLoadingOverlayScope.scoped], the overlay clips to the child
/// bounds; for [AppLoadingOverlayScope.global], it covers the full viewport.
class AppLoadingOverlay extends StatelessWidget {
  const AppLoadingOverlay({
    this.isLoading = true,
    this.scope = AppLoadingOverlayScope.scoped,
    this.label = 'Loading',
    this.skeleton,
    this.child,
    super.key,
  });

  final bool isLoading;
  final AppLoadingOverlayScope scope;
  final String label;
  final Widget? skeleton;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    if (!isLoading && child == null) {
      return const SizedBox.shrink();
    }

    final overlay = isLoading ? _LoadingOverlayLayer(scope: scope, label: label, skeleton: skeleton) : null;

    if (child == null) {
      return overlay ?? const SizedBox.shrink();
    }

    if (scope == AppLoadingOverlayScope.scoped) {
      return Stack(
        clipBehavior: Clip.none,
        children: [
          child!,
          if (overlay != null) Positioned.fill(child: overlay),
        ],
      );
    }

    return Stack(
      fit: StackFit.passthrough,
      children: [
        child!,
        if (overlay != null) Positioned.fill(child: overlay),
      ],
    );
  }
}

class _LoadingOverlayLayer extends StatefulWidget {
  const _LoadingOverlayLayer({required this.scope, required this.label, this.skeleton});

  final AppLoadingOverlayScope scope;
  final String label;
  final Widget? skeleton;

  @override
  State<_LoadingOverlayLayer> createState() => _LoadingOverlayLayerState();
}

class _LoadingOverlayLayerState extends State<_LoadingOverlayLayer> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  var _motionReady = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_motionReady) {
      return;
    }
    _motionReady = true;
    final reduced = AppMotion.reduced(context);
    final spec = AppMotion.resolvePreset(AppMotionPreset.fade, reduced: reduced);
    _controller = AnimationController(vsync: this, duration: spec.duration);
    _opacity = CurvedAnimation(parent: _controller, curve: spec.curve);
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;
    final background = switch (widget.scope) {
      AppLoadingOverlayScope.scoped => colors.surfaceDefault.withValues(alpha: 0.8),
      AppLoadingOverlayScope.global => colors.surfaceBackdrop,
    };

    return FadeTransition(
      opacity: _opacity,
      child: Material(
        color: background,
        elevation: 0,
        child: Semantics(
          label: widget.label,
          liveRegion: true,
          child: Stack(
            children: [
              if (widget.scope == AppLoadingOverlayScope.global) const SizedBox.expand(),
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    widget.skeleton ?? const AppSpinner(size: AppSpinnerSize.md, semanticLabel: 'Loading'),
                    if (widget.skeleton == null) ...[
                      const SizedBox(height: AppSpacing.s3),
                      Text(widget.label, style: typography.bodySm.copyWith(color: colors.textSecondary)),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
