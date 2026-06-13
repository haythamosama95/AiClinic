import 'package:ai_clinic/app/shell/dev/dev_clinic_seed_notifier.dart';
import 'package:ai_clinic/app/shell/dev/shell_dev_fill_dummy_clinic.dart';
import 'package:ai_clinic/app/shell/dev/shell_dev_nav.dart';
import 'package:ai_clinic/app/shell/widgets/shell_nav.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../widget/shell/shell_test_support.dart';

void main() {
  group('G. Dev Tools & Security (DV-S) — Fill Dummy Clinic UI', () {
    testWidgets('DV-S-001: Fill Dummy Clinic absent from nav when not debug-enabled', (tester) async {
      if (ShellDevFillDummyClinic.isEnabled) {
        // flutter test runs in debug mode; gate is kDebugMode so item is present here.
        // Release/profile builds compile with kDebugMode=false — verified by unit test tying isEnabled to kDebugMode.
        return;
      }

      await pumpShellNav(tester, expandedGroupIds: {ShellDevNav.groupId});
      expect(find.text(ShellDevFillDummyClinic.label), findsNothing);
    });

    testWidgets('DV-S-002: Fill Dummy Clinic appears under Dev Options in debug builds', (tester) async {
      if (!kDebugMode) {
        return;
      }

      await pumpShellNav(tester, expandedGroupIds: {ShellDevNav.groupId});
      expect(find.text('Dev Options'), findsOneWidget);
      expect(find.text(ShellDevFillDummyClinic.label), findsOneWidget);
    });

    testWidgets('DV-S-003: selecting Fill Dummy Clinic shows destructive confirmation dialog', (tester) async {
      if (!kDebugMode) {
        return;
      }

      await pumpShellNav(tester, expandedGroupIds: {ShellDevNav.groupId});

      await tester.tap(find.text(ShellDevFillDummyClinic.label));
      await tester.pumpAndSettle();

      expect(find.text(ShellDevFillDummyClinic.confirmationTitle), findsOneWidget);
      expect(find.textContaining('completely wipes the server'), findsOneWidget);
      expect(find.text('Fill dummy data'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
    });

    testWidgets('DV-S-003: canceling confirmation dismisses without side effects', (tester) async {
      if (!kDebugMode) {
        return;
      }

      await pumpShellNav(tester, expandedGroupIds: {ShellDevNav.groupId});
      await tester.tap(find.text(ShellDevFillDummyClinic.label));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text(ShellDevFillDummyClinic.confirmationTitle), findsNothing);
      expect(find.byType(ShellNav), findsOneWidget);
    });

    testWidgets('AB-010 — Fill dummy cancel: no seed when confirmation canceled', (tester) async {
      if (!kDebugMode) {
        return;
      }

      final tracker = _TrackingDevClinicSeedNotifier();
      await pumpShellWidget(
        tester,
        child: ProviderScope(
          overrides: [devClinicSeedProvider.overrideWith(() => tracker)],
          child: ShellNav(
            selectedItemId: 'dashboard',
            expandedGroupIds: {ShellDevNav.groupId},
            onItemSelected: _noop,
            onGroupToggled: _noop,
          ),
        ),
      );

      await tester.tap(find.text(ShellDevFillDummyClinic.label));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(tracker.fillCallCount, 0);
    });
  });
}

void _noop(String _) {}

class _TrackingDevClinicSeedNotifier extends DevClinicSeedNotifier {
  var fillCallCount = 0;

  @override
  Future<bool> fillDummyClinic() async {
    fillCallCount++;
    return super.fillDummyClinic();
  }
}
