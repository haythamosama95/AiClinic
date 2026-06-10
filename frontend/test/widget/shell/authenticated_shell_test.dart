import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/app/shell/widgets/shell_content_panel.dart';
import 'package:ai_clinic/app/shell/widgets/shell_header.dart';
import 'package:ai_clinic/app/shell/widgets/shell_nav.dart';
import 'package:ai_clinic/app/shell/widgets/shell_nav_item_row.dart';
import 'package:flutter_test/flutter_test.dart';

import 'shell_test_support.dart';

void main() {
  group('AuthenticatedShell', () {
    testWidgets('renders nav, header, and content panel', (tester) async {
      await pumpAuthenticatedShell(tester);

      expect(find.byType(ShellNav), findsOneWidget);
      expect(find.byType(ShellHeader), findsOneWidget);
      expect(find.byType(ShellContentPanel), findsOneWidget);
      expect(find.text('Home content'), findsOneWidget);
    });

    testWidgets('header title reflects default selected nav item', (tester) async {
      await pumpAuthenticatedShell(tester, initialLocation: AppRoutes.home);

      expect(find.text('Dashboard'), findsWidgets);
    });

    testWidgets('selecting nav item navigates to route', (tester) async {
      await pumpAuthenticatedShell(tester, initialLocation: AppRoutes.home);

      await tester.tap(find.text('Dev Options'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ShellNavItemRow, 'Theme Showcase'));
      await tester.pumpAndSettle();

      expect(find.text('Theme showcase content'), findsOneWidget);
    });

    testWidgets('selecting group child navigates to child route', (tester) async {
      await pumpAuthenticatedShell(tester, initialLocation: AppRoutes.home);

      await tester.tap(find.text('Appointments'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ShellNavItemRow, 'Queue'));
      await tester.pumpAndSettle();

      expect(find.text('Queue content'), findsOneWidget);
      expect(find.text('Queue'), findsWidgets);
    });

    testWidgets('URL drives selected item', (tester) async {
      await pumpAuthenticatedShell(tester, initialLocation: AppRoutes.appointmentsQueue);

      final queueRows = find.text('Queue');
      expect(queueRows, findsWidgets);
      expect(find.text('Queue content'), findsOneWidget);
    });

    testWidgets('toggling group does not navigate', (tester) async {
      await pumpAuthenticatedShell(tester, initialLocation: AppRoutes.home);

      await tester.tap(find.text('Appointments'));
      await tester.pumpAndSettle();

      expect(find.text('Home content'), findsOneWidget);
    });

    testWidgets('header title updates when route changes via nav', (tester) async {
      await pumpAuthenticatedShell(tester, initialLocation: AppRoutes.home);

      await tester.tap(find.text('Appointments'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ShellNavItemRow, 'Calendar'));
      await tester.pumpAndSettle();

      expect(find.text('Calendar content'), findsOneWidget);
      expect(find.text('Calendar'), findsWidgets);
    });
  });
}
