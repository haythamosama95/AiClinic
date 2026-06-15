import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Blocks Syncfusion calendar hover highlights while keeping pointer interaction.
///
/// Syncfusion paints slot hover borders from an internal [MouseRegion]. A sibling
/// opaque [MouseRegion] keeps that annotation out of the hover hit-test path.
/// Other pointer events are forwarded to the calendar subtree.
class SyncfusionCalendarHoverGuard extends StatefulWidget {
  const SyncfusionCalendarHoverGuard({required this.child, super.key});

  final Widget child;

  @override
  State<SyncfusionCalendarHoverGuard> createState() => _SyncfusionCalendarHoverGuardState();
}

class _SyncfusionCalendarHoverGuardState extends State<SyncfusionCalendarHoverGuard> {
  final GlobalKey _calendarKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        KeyedSubtree(key: _calendarKey, child: widget.child),
        Positioned.fill(
          child: MouseRegion(
            opaque: true,
            onHover: (_) {},
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: _forwardPointerEvent,
              onPointerMove: _forwardPointerEvent,
              onPointerUp: _forwardPointerEvent,
              onPointerCancel: _forwardPointerEvent,
              onPointerSignal: _forwardPointerEvent,
              child: const SizedBox.expand(),
            ),
          ),
        ),
      ],
    );
  }

  void _forwardPointerEvent(PointerEvent event) {
    final target = _calendarKey.currentContext?.findRenderObject();
    if (target is! RenderBox || !target.attached) {
      return;
    }

    final localPosition = target.globalToLocal(event.position);
    if (!target.size.contains(localPosition)) {
      return;
    }

    final result = BoxHitTestResult();
    if (!target.hitTest(result, position: localPosition)) {
      return;
    }

    for (final HitTestEntry entry in result.path) {
      entry.target.handleEvent(event, entry);
    }
  }
}
