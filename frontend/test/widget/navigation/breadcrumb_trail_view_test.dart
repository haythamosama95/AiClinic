import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/app/navigation/breadcrumb/breadcrumb_entry.dart';
import 'package:ai_clinic/app/navigation/breadcrumb/breadcrumb_trail.dart';
import 'package:ai_clinic/app/navigation/breadcrumb/breadcrumb_trail_view.dart';
import 'package:ai_clinic/core/ui/theme/app_theme.dart';
import 'package:ai_clinic/l10n/app_localizations.dart';

import '../../helpers/breadcrumb_test_support.dart';

void main() {
  group('BreadcrumbTrailView', () {
    Future<void> pumpTrailView(
      WidgetTester tester, {
      required BreadcrumbTrail trail,
      GoRouter? router,
    }) async {
      final child = const Scaffold(body: BreadcrumbTrailView());

      await tester.pumpWidget(
        ProviderScope(
          overrides: [breadcrumbTrailOverride(trail)],
          child: router == null
              ? MaterialApp(
                  theme: AppTheme.light(),
                  localizationsDelegates: AppLocalizations.localizationsDelegates,
                  supportedLocales: AppLocalizations.supportedLocales,
                  home: child,
                )
              : MaterialApp.router(
                  theme: AppTheme.light(),
                  localizationsDelegates: AppLocalizations.localizationsDelegates,
                  supportedLocales: AppLocalizations.supportedLocales,
                  routerConfig: router,
                ),
        ),
      );
      await tester.pump();
    }

    testWidgets('renders all trail labels', (tester) async {
      await pumpTrailView(
        tester,
        trail: BreadcrumbTrail([
          BreadcrumbEntries.hubInvoices(),
          BreadcrumbEntries.invoice('inv-1', number: 'INV-1'),
          BreadcrumbEntries.visitDocument('visit-1'),
        ]),
      );

      expect(find.text('Invoices'), findsOneWidget);
      expect(find.text('INV-1'), findsOneWidget);
      expect(find.text('Visit documentation'), findsOneWidget);
    });

    testWidgets('last segment is current page and not tappable', (tester) async {
      await pumpTrailView(
        tester,
        trail: BreadcrumbTrail([
          BreadcrumbEntries.hubCalendar(),
          BreadcrumbEntries.appointment('apt-1', label: 'Pat · Jan 1, 2026'),
        ]),
      );

      expect(find.text('Calendar'), findsOneWidget);
      expect(find.text('Pat · Jan 1, 2026'), findsOneWidget);
      expect(find.byType(InkWell), findsOneWidget);
    });

    testWidgets('earlier segment tap navigates via targetLocation', (tester) async {
      final router = GoRouter(
        initialLocation: '/start',
        routes: [
          GoRoute(
            path: '/start',
            builder: (_, _) => const Scaffold(body: BreadcrumbTrailView()),
          ),
          GoRoute(
            path: AppRoutes.billingInvoices,
            builder: (_, _) => const Scaffold(
              key: Key('invoices_stub'),
              body: Text('Invoices list'),
            ),
          ),
        ],
      );

      await pumpTrailView(
        tester,
        trail: BreadcrumbTrail([
          BreadcrumbEntries.hubInvoices(),
          BreadcrumbEntries.invoice('inv-1', number: 'INV-1'),
        ]),
        router: router,
      );

      await tester.tap(find.text('Invoices'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('invoices_stub')), findsOneWidget);
      expect(router.state.uri.path, AppRoutes.billingInvoices);
    });
  });
}
