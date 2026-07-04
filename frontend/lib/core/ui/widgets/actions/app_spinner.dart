import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/foundation.dart';

/// Spinner size tokens matching the web reference.
enum AppSpinnerSize {
  /// 16 logical pixels.
  sm,

  /// 20 logical pixels.
  md,
}

/// Continuous loading indicator used by buttons and async surfaces.
class AppSpinner extends StatefulWidget {
  const AppSpinner({this.size = AppSpinnerSize.sm, this.color, this.semanticLabel = 'Loading', super.key});

  final AppSpinnerSize size;
  final Color? color;
  final String semanticLabel;

  double get _dimension => switch (size) {
    AppSpinnerSize.sm => AppIconSize.sm.value,
    AppSpinnerSize.md => AppIconSize.md.value,
  };

  @override
  State<AppSpinner> createState() => _AppSpinnerState();
}

class _AppSpinnerState extends State<AppSpinner> with SingleTickerProviderStateMixin {
  AnimationController? _controller;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncAnimation();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _syncAnimation() {
    final reduced = AppMotion.reduced(context);
    if (reduced) {
      _controller?.dispose();
      _controller = null;
      return;
    }

    _controller ??= AnimationController(vsync: this, duration: AppDurations.deliberate)..repeat();

    if (!_controller!.isAnimating) {
      _controller!.repeat();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final color = widget.color ?? colors.iconMuted;

    Widget icon = AppIcon(
      icon: LucideIcons.loader2,
      dimension: widget._dimension,
      color: color,
      semanticLabel: widget.semanticLabel,
    );

    if (_controller != null) {
      icon = RotationTransition(turns: _controller!, child: icon);
    }

    return Semantics(label: widget.semanticLabel, liveRegion: true, child: icon);
  }
}
