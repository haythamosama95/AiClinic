import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/ui/components/app_button.dart';
import 'package:ai_clinic/core/ui/theme/app_theme.dart';
import 'package:ai_clinic/features/billing/domain/invoice_detail.dart';
import 'package:ai_clinic/features/billing/domain/invoice_item.dart';
import 'package:ai_clinic/features/billing/domain/invoice_status.dart';
import 'package:ai_clinic/features/billing/domain/money.dart';
import 'package:ai_clinic/features/billing/domain/visit_billing_models.dart';
import 'package:ai_clinic/features/billing/presentation/providers/organization_currency_provider.dart';
import 'package:ai_clinic/features/billing/presentation/widgets/visit_billing/visit_invoice_review_step.dart';
import 'package:ai_clinic/features/billing/presentation/widgets/visit_billing/visit_invoice_summary_dialog.dart';
import 'package:ai_clinic/features/billing/presentation/widgets/visit_billing/visit_invoice_summary_panel.dart';
import 'package:ai_clinic/features/clinic-management/presentation/providers/clinic_setup_providers.dart';
import 'package:ai_clinic/l10n/app_localizations.dart';

import '../../helpers/auth_test_support.dart';
import '../../helpers/role_permission_seed.dart';
import '../../helpers/settings_test_support.dart';

InvoiceDetail _issuedInvoice() {
  return InvoiceDetail(
    id: '22222222-2222-4222-8222-222222222222',
    invoiceNumber: 'INV-MAIN-000001',
    status: InvoiceStatus.issued,
    branchId: '44444444-4444-4444-8444-444444444444',
    patientId: 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
    visitId: 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',
    subtotal: Money.parse('150.00'),
    discountAmount: Money.parse('10.00'),
    insuranceCoveredAmount: Money.zero,
    currency: 'USD',
    balance: Money.parse('140.00'),
    createdAt: DateTime.parse('2026-06-01T10:00:00.000Z'),
    updatedAt: DateTime.parse('2026-06-02T12:00:00.000Z'),
    issuedAt: DateTime.parse('2026-06-02T11:00:00.000Z'),
    items: [
      InvoiceItem(
        id: 'item-1',
        description: 'Consultation',
        quantity: '1',
        unitPrice: Money.parse('100.00'),
        lineSubtotal: Money.parse('100.00'),
        lineDiscountAmount: Money.zero,
        lineTotal: Money.parse('100.00'),
      ),
      InvoiceItem(
        id: 'item-2',
        description: 'Labs',
        quantity: '1',
        unitPrice: Money.parse('50.00'),
        lineSubtotal: Money.parse('50.00'),
        lineDiscountAmount: Money.zero,
        lineTotal: Money.parse('50.00'),
      ),
    ],
    payments: const [],
    patientDisplayName: 'Test Patient',
  );
}

VisitBillingInvoicePreview _preview() {
  return const VisitBillingInvoicePreview(
    number: 'INV-PREVIEW-0001',
    lines: [
      VisitSelectedServiceLine(
        id: 'line-1',
        serviceId: 'svc-1',
        name: 'Consultation',
        unitPrice: 100,
        quantity: 1,
      ),
    ],
    discountType: VisitBillingDiscountType.none,
    discountValue: 0,
    subtotal: 100,
    discountAmount: 0,
    total: 100,
  );
}

List<Override> _currencyOverrides({String currencyCode = 'EGP'}) {
  return [
    organizationCurrencyProvider.overrideWith((ref) => currencyCode.toUpperCase()),
    clinicSetupOrganizationProvider.overrideWith(
      (ref) => Future.value(sampleOrganizationProfile(currencyCode: currencyCode)),
    ),
  ];
}

Future<void> _pumpPanel(
  WidgetTester tester, {
  required Widget child,
  List<Override> overrides = const [],
}) async {
  await tester.binding.setSurfaceSize(const Size(900, 700));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(child: child),
        ),
      ),
    ),
  );
}

Future<void> _tapVisibleButton(WidgetTester tester, String label) async {
  final finder = find.widgetWithText(AppButton, label);
  await tester.ensureVisible(finder);
  await tester.tap(finder);
}

GoRouter _dialogRouter() {
  return GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => Scaffold(
          body: Center(
            child: AppButton(
              onPressed: () => VisitInvoiceSummaryDialog.show(context, invoice: _issuedInvoice()),
              child: const Text('Show summary'),
            ),
          ),
        ),
      ),
      GoRoute(
        path: '/billing/invoices/:invoiceId/review',
        builder: (context, state) => Scaffold(
          body: Text('review:${state.pathParameters['invoiceId']}'),
        ),
      ),
    ],
  );
}

Future<void> _pumpDialogHost(
  WidgetTester tester, {
  required Set<String> permissions,
}) async {
  await tester.binding.setSurfaceSize(const Size(900, 700));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authSessionProvider.overrideWith(
          () => MutableAuthSessionNotifier(
            AuthSessionState(
              status: AuthSessionStatus.authenticated,
              context: sampleAuthSessionContext(permissions: permissions),
            ),
          ),
        ),
        ..._currencyOverrides(),
      ],
      child: MaterialApp.router(
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: _dialogRouter(),
      ),
    ),
  );
}

void main() {
  group('VisitInvoiceSummaryPanel', () {
    testWidgets('renders compact invoice-backed summary', (tester) async {
      await _pumpPanel(
        tester,
        overrides: _currencyOverrides(),
        child: VisitInvoiceSummaryPanel(invoice: _issuedInvoice()),
      );

      expect(find.text('INV-MAIN-000001'), findsOneWidget);
      expect(find.text('Issued'), findsOneWidget);
      expect(find.text('2 services · Discount applied'), findsOneWidget);
      expect(find.text('Consultation'), findsNothing);
    });

    testWidgets('renders expanded invoice-backed summary with line items', (tester) async {
      await _pumpPanel(
        tester,
        overrides: _currencyOverrides(),
        child: VisitInvoiceSummaryPanel(invoice: _issuedInvoice(), expanded: true),
      );

      expect(find.text('Consultation'), findsOneWidget);
      expect(find.text('Labs'), findsOneWidget);
      expect(find.text('Subtotal'), findsOneWidget);
      expect(find.text('Discount'), findsOneWidget);
      expect(find.text('Total'), findsOneWidget);
      expect(find.text('Balance due'), findsOneWidget);
    });

    testWidgets('preview-backed summary ignores expanded and stays compact', (tester) async {
      await _pumpPanel(
        tester,
        overrides: _currencyOverrides(currencyCode: 'egp'),
        child: VisitInvoiceSummaryPanel(preview: _preview(), expanded: true),
      );

      expect(find.text('INV-PREVIEW-0001'), findsOneWidget);
      expect(find.text('1 service'), findsOneWidget);
      expect(find.text('Consultation'), findsNothing);
    });

    testWidgets('renders preview-backed summary using organization currency', (tester) async {
      await _pumpPanel(
        tester,
        overrides: _currencyOverrides(currencyCode: 'egp'),
        child: VisitInvoiceSummaryPanel(preview: _preview()),
      );

      expect(find.text('INV-PREVIEW-0001'), findsOneWidget);
      expect(find.text('Draft'), findsOneWidget);
      expect(find.textContaining('EGP'), findsWidgets);
    });
  });

  group('VisitInvoiceSummaryDialog', () {
    testWidgets('shows Open invoice when session permits invoice detail access', (tester) async {
      await _pumpDialogHost(tester, permissions: RolePermissionSeed.receptionist);

      await tester.tap(find.text('Show summary'));
      await tester.pumpAndSettle();

      expect(find.text('Invoice summary'), findsOneWidget);
      expect(find.text('Open invoice'), findsOneWidget);
    });

    testWidgets('hides Open invoice without invoice detail permission', (tester) async {
      await _pumpDialogHost(tester, permissions: RolePermissionSeed.doctor);

      await tester.tap(find.text('Show summary'));
      await tester.pumpAndSettle();

      expect(find.text('Open invoice'), findsNothing);
      expect(find.text('Close'), findsOneWidget);
    });

    testWidgets('Open invoice navigates to the billing review route', (tester) async {
      await _pumpDialogHost(tester, permissions: RolePermissionSeed.receptionist);

      await tester.tap(find.text('Show summary'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open invoice'));
      await tester.pumpAndSettle();

      expect(find.text('review:22222222-2222-4222-8222-222222222222'), findsOneWidget);
    });

    testWidgets('Close dismisses the dialog', (tester) async {
      await _pumpDialogHost(tester, permissions: RolePermissionSeed.receptionist);

      await tester.tap(find.text('Show summary'));
      await tester.pumpAndSettle();

      expect(find.text('Invoice summary'), findsOneWidget);

      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();

      expect(find.text('Invoice summary'), findsNothing);
    });
  });

  group('VisitInvoiceReadOnlyReview', () {
    testWidgets('renders issued invoice read-only with back control', (tester) async {
      var backTapped = false;

      await _pumpPanel(
        tester,
        overrides: _currencyOverrides(),
        child: VisitInvoiceReadOnlyReview(
          invoice: _issuedInvoice(),
          onBack: () => backTapped = true,
        ),
      );
      await tester.pump();

      expect(find.text('Invoice'), findsOneWidget);
      expect(find.text('Consultation'), findsOneWidget);
      expect(find.text('Issued'), findsOneWidget);

      await _tapVisibleButton(tester, 'Back');
      await tester.pump();

      expect(backTapped, isTrue);
    });
  });
}
