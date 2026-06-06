// US5 acceptance scenarios 1–6.
import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/auth/domain/branch_summary.dart';
import 'package:ai_clinic/features/auth/domain/permission_keys.dart';
import 'package:ai_clinic/features/auth/presentation/providers/staff_assignable_branches_provider.dart';
import 'package:ai_clinic/features/billing/data/invoice_repository.dart';
import 'package:ai_clinic/features/billing/presentation/pages/invoice_detail_page.dart';
import 'package:ai_clinic/features/billing/presentation/pages/invoice_list_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../helpers/auth_test_support.dart';
import '../../support/billing_rpc_test_client.dart';

class _PresetAuth extends AuthSessionNotifier {
  _PresetAuth(this._state);

  final AuthSessionState _state;

  @override
  AuthSessionState build() => _state;
}

const _mainBranchId = '44444444-4444-4444-8444-444444444444';
const _sideBranchId = '77777777-7777-4777-8777-777777777777';
Future<void> _pumpHost(WidgetTester tester, Widget host) async {
  await tester.binding.setSurfaceSize(const Size(1280, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(host);
  await tester.pump();
  await tester.pumpAndSettle(const Duration(milliseconds: 700));
}

AuthSessionState _auth({Set<String>? permissions, List<String>? branchIds}) {
  return AuthSessionState(
    status: AuthSessionStatus.authenticated,
    context: sampleAuthSessionContext(
      permissions: permissions ?? {PermissionKeys.invoicesView},
      activeBranchId: _mainBranchId,
      branchIds: branchIds ?? [_mainBranchId, _sideBranchId],
    ),
  );
}

Widget _scope({required Widget child, required BillingRpcTestClient client, AuthSessionState? auth}) {
  return ProviderScope(
    overrides: [
      authSessionProvider.overrideWith(() => _PresetAuth(auth ?? _auth())),
      invoiceRepositoryProvider.overrideWith((ref) => InvoiceRepository(client)),
      staffAssignableBranchesProvider.overrideWith(
        (ref) async => const [
          BranchSummary(id: _mainBranchId, name: 'Main Branch', code: 'MAIN'),
          BranchSummary(id: _sideBranchId, name: 'Side Branch', code: 'SIDE'),
        ],
      ),
    ],
    child: MaterialApp.router(
      routerConfig: GoRouter(
        initialLocation: '/host',
        routes: [
          GoRoute(
            path: '/host',
            builder: (context, state) => Scaffold(body: child),
          ),
          GoRoute(path: AppRoutes.billingInvoices, builder: (context, state) => const InvoiceListPage()),
          GoRoute(
            path: '${AppRoutes.billingInvoices}/:invoiceId',
            builder: (context, state) => InvoiceDetailPage(invoiceId: state.pathParameters['invoiceId']),
          ),
        ],
      ),
    ),
  );
}

void main() {
  group('Invoice list US5', () {
    testWidgets('scenario 1: list shows invoice columns and load-more affordance', (tester) async {
      final client = BillingRpcTestClient();

      await _pumpHost(tester, _scope(child: const InvoiceListPage(), client: client));

      expect(find.byKey(const Key('invoice_list_table')), findsOneWidget);
      expect(find.text('INV-MAIN-000001'), findsOneWidget);
      expect(find.text('Test Patient'), findsWidgets);
      expect(find.text('100.00'), findsWidgets);
      expect(client.rpcLog, contains('list_invoices'));
    });

    testWidgets('scenario 2: status filter paid shows only paid invoices', (tester) async {
      final client = BillingRpcTestClient();

      await _pumpHost(tester, _scope(child: const InvoiceListPage(), client: client));
      await tester.tap(find.byKey(const Key('invoice_list_filter_status')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Paid').last);
      await tester.pumpAndSettle(const Duration(milliseconds: 700));

      expect(find.text('INV-MAIN-000002'), findsOneWidget);
      expect(find.text('INV-MAIN-000001'), findsNothing);
      expect(client.lastParams?['p_filters']?['statuses'], ['paid']);
    });

    testWidgets('scenario 3: patient search filters results', (tester) async {
      final client = BillingRpcTestClient();

      await _pumpHost(tester, _scope(child: const InvoiceListPage(), client: client));
      await tester.enterText(find.byKey(const Key('invoice_list_patient_search')), 'Other');
      await tester.pumpAndSettle(const Duration(milliseconds: 700));

      expect(find.text('Other Patient'), findsOneWidget);
      expect(find.text('INV-SIDE-000001'), findsOneWidget);
      expect(find.text('INV-MAIN-000001'), findsNothing);
    });

    testWidgets('scenario 4: patients.view without invoices.view is blocked', (tester) async {
      await _pumpHost(
        tester,
        _scope(
          child: const InvoiceListPage(),
          client: BillingRpcTestClient(),
          auth: _auth(permissions: {PermissionKeys.patientsView}),
        ),
      );

      expect(find.text('You do not have permission to view invoices.'), findsOneWidget);
      expect(find.byKey(const Key('invoice_list_table')), findsNothing);
    });

    testWidgets('scenario 5: opening detail performs backend-first fetch', (tester) async {
      final client = BillingRpcTestClient();

      await _pumpHost(tester, _scope(child: const InvoiceListPage(), client: client));
      await tester.tap(find.text('INV-MAIN-000001').first);
      await tester.pumpAndSettle(const Duration(milliseconds: 700));

      expect(find.byKey(const Key('invoice_detail_loading')), findsNothing);
      expect(find.byKey(const Key('invoice_detail_body')), findsOneWidget);
      expect(client.rpcLog, contains('get_invoice_detail'));
    });

    testWidgets('scenario 6: branch filter limits results', (tester) async {
      final client = BillingRpcTestClient();

      await _pumpHost(tester, _scope(child: const InvoiceListPage(), client: client));
      await tester.tap(find.byKey(const Key('invoice_list_filter_branch')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Main Branch').last);
      await tester.pumpAndSettle(const Duration(milliseconds: 700));

      expect(find.text('INV-SIDE-000001'), findsNothing);
      expect(find.text('INV-MAIN-000001'), findsOneWidget);
      expect(client.lastParams?['p_filters']?['branch_ids'], [_mainBranchId]);
    });
  });
}
