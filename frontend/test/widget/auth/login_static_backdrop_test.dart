import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/core/ui/theme/app_theme.dart';
import 'package:ai_clinic/features/auth/presentation/widgets/login_static_backdrop.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const smallSurface = Size(320, 480);
  const largeSurface = Size(1920, 1080);

  // Skeleton blocks in login_static_backdrop.dart: 1 sidebar logo + 6 sidebar nav
  // items + 2 top-bar blocks + 2 content blocks. Each renders a single Container.
  const skeletonBlockCount = 11;

  Finder skeletonBlockFinder() {
    return find.descendant(
      of: find.byType(LoginStaticBackdrop),
      matching: find.byType(Container),
    );
  }

  Future<void> pumpBackdrop(
    WidgetTester tester, {
    required ThemeData theme,
    Size surfaceSize = const Size(800, 700),
  }) async {
    await tester.binding.setSurfaceSize(surfaceSize);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: const Scaffold(body: LoginStaticBackdrop()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }

  group('LoginStaticBackdrop', () {
    testWidgets('builds without exception under AppTheme.light()', (tester) async {
      await pumpBackdrop(tester, theme: AppTheme.light());

      expect(tester.takeException(), isNull);
      expect(find.byType(LoginStaticBackdrop), findsOneWidget);
    });

    testWidgets('builds without exception under AppTheme.dark()', (tester) async {
      await pumpBackdrop(tester, theme: AppTheme.dark());

      expect(tester.takeException(), isNull);
      expect(find.byType(LoginStaticBackdrop), findsOneWidget);
    });

    testWidgets('contains structural skeleton blocks and a background pattern painter', (tester) async {
      await pumpBackdrop(tester, theme: AppTheme.light());

      expect(skeletonBlockFinder(), findsNWidgets(skeletonBlockCount));
      expect(
        find.descendant(of: find.byType(LoginStaticBackdrop), matching: find.byType(CustomPaint)),
        findsOneWidget,
      );
    });

    testWidgets('builds at a small surface size without overflow exceptions', (tester) async {
      await pumpBackdrop(tester, theme: AppTheme.light(), surfaceSize: smallSurface);

      expect(tester.takeException(), isNull);
    });

    testWidgets('builds at a large surface size without overflow exceptions', (tester) async {
      await pumpBackdrop(tester, theme: AppTheme.light(), surfaceSize: largeSurface);

      expect(tester.takeException(), isNull);
    });

    testWidgets('builds without a ProviderScope or auth session dependency', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: LoginStaticBackdrop()),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      expect(tester.takeException(), isNull);
      expect(find.byType(LoginStaticBackdrop), findsOneWidget);
    });
  });
}
