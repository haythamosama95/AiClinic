import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_clinic/core/ui/components/app_badge.dart';
import 'package:ai_clinic/core/ui/theme/app_theme.dart';

void main() {
  testWidgets('badge hugs content inside a wide parent', (tester) async {
    const parentWidth = 320.0;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: SizedBox(
            width: parentWidth,
            child: Wrap(
              spacing: 8,
              children: const [
                AppBadge(label: 'Active', color: BadgeColor.success),
                AppBadge(label: 'Pending', color: BadgeColor.warning),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final activeBadge = tester.getSize(find.text('Active'));
    final pendingBadge = tester.getSize(find.text('Pending'));

    expect(activeBadge.width, lessThan(parentWidth));
    expect(pendingBadge.width, lessThan(parentWidth));
    expect(activeBadge.width, isNot(equals(pendingBadge.width)));
  });
}
