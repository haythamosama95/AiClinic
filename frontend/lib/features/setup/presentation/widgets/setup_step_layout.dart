import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/theme/theme.dart';

/// Viewports below this height use page-level scrolling; taller screens grow the modal instead.
abstract final class SetupLayoutBreakpoints {
  static const compactViewportHeight = 760.0;
}

/// Whether wizard steps should expand to the shared step area height.
class SetupStepFillScope extends InheritedWidget {
  const SetupStepFillScope({required this.fillHeight, required super.child, super.key});

  final bool fillHeight;

  static bool of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<SetupStepFillScope>()?.fillHeight ?? false;
  }

  @override
  bool updateShouldNotify(SetupStepFillScope oldWidget) => fillHeight != oldWidget.fillHeight;
}

/// Reports the natural height a step needs (body + footer) so the shared step area can grow.
class SetupStepHeightScope extends InheritedWidget {
  const SetupStepHeightScope({required this.onRequiredHeight, required super.child, super.key});

  final ValueChanged<double> onRequiredHeight;

  static SetupStepHeightScope? maybeOf(BuildContext context) {
    return context.getInheritedWidgetOfExactType<SetupStepHeightScope>();
  }

  @override
  bool updateShouldNotify(SetupStepHeightScope oldWidget) => false;
}

/// Wizard step chrome: scrollable body, optional actions pinned to the bottom.
class SetupStepLayout extends StatefulWidget {
  const SetupStepLayout({required this.body, this.actions, super.key});

  final Widget body;
  final Widget? actions;

  @override
  State<SetupStepLayout> createState() => _SetupStepLayoutState();
}

class _SetupStepLayoutState extends State<SetupStepLayout> {
  final _actionsKey = GlobalKey();
  var _actionsHeight = 48.0;

  @override
  Widget build(BuildContext context) {
    final fillHeight = SetupStepFillScope.of(context);

    WidgetsBinding.instance.addPostFrameCallback((_) => _syncActionsHeight());

    final actions = widget.actions;

    if (!fillHeight) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          widget.body,
          if (actions != null) ...[
            const SizedBox(height: SpacingTokens.xl),
            KeyedSubtree(key: _actionsKey, child: actions),
          ],
        ],
      );
    }

    final footerHeight = actions == null ? 0.0 : _actionsHeight + SpacingTokens.xl;

    return SizedBox(
      width: double.infinity,
      height: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: _MeasureSize(
                onChange: (size) => _reportRequiredHeight(size.height + footerHeight),
                child: widget.body,
              ),
            ),
          ),
          if (actions != null) ...[
            const SizedBox(height: SpacingTokens.xl),
            KeyedSubtree(key: _actionsKey, child: actions),
          ],
        ],
      ),
    );
  }

  void _syncActionsHeight() {
    if (!mounted || widget.actions == null) return;
    final box = _actionsKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final next = box.size.height;
    if (next == _actionsHeight) return;
    setState(() => _actionsHeight = next);
  }

  void _reportRequiredHeight(double height) {
    SetupStepHeightScope.maybeOf(context)?.onRequiredHeight(height);
  }
}

class _MeasureSize extends StatefulWidget {
  const _MeasureSize({required this.onChange, required this.child});

  final ValueChanged<Size> onChange;
  final Widget child;

  @override
  State<_MeasureSize> createState() => _MeasureSizeState();
}

class _MeasureSizeState extends State<_MeasureSize> {
  Size? _lastSize;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _notify());
  }

  @override
  void didUpdateWidget(covariant _MeasureSize oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback((_) => _notify());
  }

  void _notify() {
    if (!mounted) return;
    final size = context.size;
    if (size == null || size == _lastSize) return;
    _lastSize = size;
    widget.onChange(size);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
