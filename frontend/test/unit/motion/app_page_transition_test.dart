import 'package:ai_clinic/core/ui/motion/app_page_transition.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppPageTransitionMotion.valuesFor', () {
    test('enter starts hidden and ends visible', () {
      final hidden = AppPageTransitionMotion.valuesFor(0, exiting: false);
      final visible = AppPageTransitionMotion.valuesFor(1, exiting: false);

      expect(hidden.opacity, 0);
      expect(hidden.offset.dy, AppPageTransitionMotion.enterOffsetY);
      expect(visible.opacity, 1);
      expect(visible.offset.dy, 0);
    });

    test('exit starts visible and ends hidden when controller reverses', () {
      final visible = AppPageTransitionMotion.valuesFor(1, exiting: true);
      final hidden = AppPageTransitionMotion.valuesFor(0, exiting: true);

      expect(visible.opacity, 1);
      expect(visible.offset.dy, 0);
      expect(hidden.opacity, 0);
      expect(hidden.offset.dy, AppPageTransitionMotion.exitOffsetY);
    });
  });
}
