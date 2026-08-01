import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Registry for scroll-to-section navigation in the design system showcase.
abstract final class DevSectionRegistry {
  static final _keys = <String, GlobalKey>{};

  static GlobalKey keyFor(String sectionId) => _keys.putIfAbsent(sectionId, GlobalKey.new);

  static void scrollToSection(BuildContext context, String sectionId) {
    final targetContext = _keys[sectionId]?.currentContext;
    if (targetContext == null) return;

    final target = targetContext.findRenderObject();
    if (target == null || !target.attached) return;

    // DevSectionLayout scrolls the main pane inside the design system page.
    final controller = PrimaryScrollController.maybeOf(targetContext);
    if (controller != null && controller.hasClients) {
      final viewport = RenderAbstractViewport.of(target);
      final reveal = viewport.getOffsetToReveal(target, 0);
      final offset = reveal.offset.clamp(0.0, controller.position.maxScrollExtent);
      controller.animateTo(offset, duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
      return;
    }

    Scrollable.ensureVisible(
      targetContext,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      alignment: 0,
      alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
    );
  }
}
