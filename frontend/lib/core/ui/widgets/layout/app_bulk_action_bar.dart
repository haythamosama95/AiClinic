import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/foundation.dart';
import 'package:ai_clinic/core/ui/widgets/actions/app_button.dart';

/// Bulk selection action bar with count, custom actions, and clear control.
///
/// Pair with table/list selection state in the parent; this widget does not
/// couple to [AppTable].
class AppBulkActionBar extends StatefulWidget {
  const AppBulkActionBar({
    required this.visible,
    required this.selectedCount,
    required this.onClear,
    this.itemLabel = 'selected',
    this.actions,
    super.key,
  });

  /// Whether the bar should be shown (typically `selectedCount > 0`).
  final bool visible;

  final int selectedCount;
  final String itemLabel;
  final VoidCallback onClear;
  final Widget? actions;

  @override
  State<AppBulkActionBar> createState() => _AppBulkActionBarState();
}

class _AppBulkActionBarState extends State<AppBulkActionBar> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<Offset> _slide;
  late final Animation<double> _heightFactor;
  var _motionReady = false;

  bool get _expanded => widget.visible && widget.selectedCount > 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_motionReady) {
      return;
    }
    _motionReady = true;
    final reduced = AppMotion.reduced(context);
    final spec = AppMotion.resolvePreset(AppMotionPreset.slideUp, reduced: reduced);
    _controller = AnimationController(vsync: this, duration: spec.duration);
    final curve = CurvedAnimation(parent: _controller, curve: spec.curve);
    _opacity = curve;
    _slide = Tween<Offset>(begin: Offset(0, reduced ? 0 : 0.08), end: Offset.zero).animate(curve);
    _heightFactor = curve;
    if (_expanded) {
      _controller.value = 1;
    }
  }

  @override
  void didUpdateWidget(covariant AppBulkActionBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_expanded != (oldWidget.visible && oldWidget.selectedCount > 0)) {
      if (_expanded) {
        _controller.forward();
      } else {
        final reduced = AppMotion.reduced(context);
        final spec = AppMotion.resolvePreset(AppMotionPreset.slideUp, reduced: reduced, isExit: true);
        _controller.duration = spec.duration;
        _controller.reverse();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_expanded && _controller.isDismissed) {
      return const SizedBox.shrink();
    }

    return ClipRect(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Align(
            alignment: Alignment.topCenter,
            heightFactor: _heightFactor.value.clamp(0.001, 1.0),
            child: FadeTransition(
              opacity: _opacity,
              child: SlideTransition(position: _slide, child: child),
            ),
          );
        },
        child: _BulkActionBarSurface(
          selectedCount: widget.selectedCount,
          itemLabel: widget.itemLabel,
          actions: widget.actions,
          onClear: widget.onClear,
        ),
      ),
    );
  }
}

class _BulkActionBarSurface extends StatelessWidget {
  const _BulkActionBarSurface({
    required this.selectedCount,
    required this.itemLabel,
    required this.onClear,
    this.actions,
  });

  final int selectedCount;
  final String itemLabel;
  final VoidCallback onClear;
  final Widget? actions;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;
    final brightness = Theme.of(context).brightness;
    final countLabel = _formatWesternInt(selectedCount);

    return Semantics(
      container: true,
      label: 'Bulk actions',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surfaceRaised,
          border: Border.all(color: colors.borderDefault),
          borderRadius: AppRadii.lgAll,
          boxShadow: AppShadows.forLevel(2, brightness),
        ),
        child: Padding(
          padding: const EdgeInsetsDirectional.symmetric(horizontal: AppSpacing.s4, vertical: AppSpacing.s3),
          child: Wrap(
            spacing: AppSpacing.s3,
            runSpacing: AppSpacing.s3,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                '$countLabel $itemLabel',
                style: typography.tabular(typography.bodyStrong).copyWith(color: colors.textPrimary),
              ),
              Wrap(
                spacing: AppSpacing.s2,
                runSpacing: AppSpacing.s2,
                alignment: WrapAlignment.end,
                children: [
                  ?actions,
                  AppButton(
                    label: 'Clear selection',
                    variant: AppButtonVariant.ghost,
                    size: AppButtonSize.sm,
                    leadingIcon: LucideIcons.x,
                    onPressed: onClear,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _formatWesternInt(int value) {
  const eastern = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];
  const persian = ['۰', '۱', '۲', '۳', '۴', '۵', '۶', '۷', '۸', '۹'];
  var text = value.toString();
  for (var i = 0; i < 10; i++) {
    text = text.replaceAll(eastern[i], '$i').replaceAll(persian[i], '$i');
  }
  return text;
}
