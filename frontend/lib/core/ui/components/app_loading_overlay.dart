import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';

/// Spinner diameter for the medium size (web `Spinner` md / `size-5`).
const _spinnerMdSize = 20.0;

/// Full-screen or scoped loading overlay (web `LoadingOverlay`).
class AppLoadingOverlay extends StatefulWidget {
  const AppLoadingOverlay({this.loading = true, this.label = 'Loading', this.scoped = false, this.child, super.key});

  final bool loading;
  final String label;
  final bool scoped;
  final Widget? child;

  @override
  State<AppLoadingOverlay> createState() => _AppLoadingOverlayState();
}

class _AppLoadingOverlayState extends State<AppLoadingOverlay> {
  OverlayEntry? _overlayEntry;
  int _overlaySyncGeneration = 0;

  @override
  void initState() {
    super.initState();
    _syncOverlay();
  }

  @override
  void didUpdateWidget(covariant AppLoadingOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.loading != widget.loading || oldWidget.label != widget.label || oldWidget.scoped != widget.scoped) {
      _syncOverlay();
    } else if (oldWidget.label != widget.label && _overlayEntry != null) {
      _overlayEntry!.markNeedsBuild();
    }
  }

  @override
  void dispose() {
    _overlaySyncGeneration++;
    _removeOverlay();
    super.dispose();
  }

  void _syncOverlay() {
    if (widget.scoped) {
      _removeOverlay();
      return;
    }

    final generation = ++_overlaySyncGeneration;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || generation != _overlaySyncGeneration) {
        return;
      }

      if (widget.scoped) {
        _removeOverlay();
        return;
      }

      if (widget.loading) {
        _showOverlay();
      } else {
        _removeOverlay();
      }
    });
  }

  void _showOverlay() {
    if (_overlayEntry != null) {
      _overlayEntry!.markNeedsBuild();
      return;
    }

    final overlay = Overlay.of(context, rootOverlay: true);
    _overlayEntry = OverlayEntry(
      builder: (context) => Positioned.fill(child: _LoadingOverlayPanel(label: widget.label)),
    );
    overlay.insert(_overlayEntry!);
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry?.dispose();
    _overlayEntry = null;
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.loading && widget.child == null) {
      return const SizedBox.shrink();
    }

    if (widget.scoped) {
      final overlay = widget.loading ? Positioned.fill(child: _LoadingOverlayPanel(label: widget.label)) : null;

      if (widget.child != null) {
        return Stack(children: [widget.child!, ?overlay]);
      }

      return overlay ?? const SizedBox.shrink();
    }

    return const SizedBox.shrink();
  }
}

class _LoadingOverlayPanel extends StatelessWidget {
  const _LoadingOverlayPanel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Semantics(
      label: label,
      liveRegion: true,
      child: ColoredBox(
        color: colors.surfaceDefault.withValues(alpha: 0.8),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: _spinnerMdSize,
                height: _spinnerMdSize,
                child: CircularProgressIndicator(strokeWidth: 2, color: colors.iconMuted),
              ),
              const SizedBox(height: AppSpacing.space3),
              Text(label, style: AppTypography.bodySm(context).copyWith(color: colors.textSecondary)),
            ],
          ),
        ),
      ),
    );
  }
}
