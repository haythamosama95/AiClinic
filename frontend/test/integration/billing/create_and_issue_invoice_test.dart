// US1 acceptance scenarios 1, 2, 3, 4, 7, 8 (UI orchestration with fake RPC).
import 'dart:io';

import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/auth/domain/permission_keys.dart';
import 'package:ai_clinic/features/billing/data/invoice_repository.dart';
import 'package:ai_clinic/features/billing/presentation/pages/invoice_editor_page.dart';
import 'package:ai_clinic/features/billing/presentation/pages/invoice_detail_page.dart';
import 'package:ai_clinic/features/visits/domain/visit_status.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_detail_actions.dart';
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

const _visitId = BillingRpcTestClient.visitId;
const _branchId = '44444444-4444-4444-8444-444444444444';

Future<void> _pumpHost(WidgetTester tester, Widget host) async {
  await tester.binding.setSurfaceSize(const Size(1100, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(host);
  await tester.pump();
  await tester.pumpAndSettle();
}

AuthSessionState _auth({Set<String>? permissions}) {
  return AuthSessionState(
    status: AuthSessionStatus.authenticated,
    context: sampleAuthSessionContext(
      permissions: permissions ?? {PermissionKeys.invoicesView, PermissionKeys.invoicesCreate},
      activeBranchId: _branchId,
      branchIds: [_branchId],
    ),
  );
}

Widget _scope({required Widget child, BillingRpcTestClient? client, AuthSessionState? auth}) {
  final rpcClient = client ?? BillingRpcTestClient();
  return ProviderScope(
    overrides: [
      authSessionProvider.overrideWith(() => _PresetAuth(auth ?? _auth())),
      invoiceRepositoryProvider.overrideWith((ref) => InvoiceRepository(rpcClient)),
    ],
    child: MaterialApp.router(routerConfig: _router(child: child)),
  );
}

GoRouter _router({required Widget child}) {
  return GoRouter(
    initialLocation: '/host',
    routes: [
      GoRoute(
        path: '/host',
        builder: (context, state) => Scaffold(body: child),
      ),
      GoRoute(
        path: AppRoutes.billingInvoiceEdit(BillingRpcTestClient.draftInvoiceId),
        builder: (context, state) => const InvoiceEditorPage(invoiceId: BillingRpcTestClient.draftInvoiceId),
      ),
      GoRoute(
        path: AppRoutes.billingInvoiceDetail(BillingRpcTestClient.issuedInvoiceId),
        builder: (context, state) => const InvoiceDetailPage(invoiceId: BillingRpcTestClient.issuedInvoiceId),
      ),
    ],
  );
}

void main() {
  group('Create and issue invoice US1', () {
    testWidgets('scenario 1: completed visit shows Create invoice and opens editor', (tester) async {
      final client = BillingRpcTestClient()
        ..rpcResults['list_invoices'] = {
          'success': true,
          'data': {'items': []},
        };

      await _pumpHost(
        tester,
        _scope(
          client: client,
          child: VisitDetailActions(visitId: _visitId, status: VisitStatus.completed),
        ),
      );

      expect(find.byKey(const Key('visit_create_invoice_button')), findsOneWidget);
      await tester.tap(find.byKey(const Key('visit_create_invoice_button')));
      await tester.pumpAndSettle();

      expect(client.rpcLog, contains('create_invoice_from_visit'));
    });

    testWidgets('scenario 2: editor adds item and issues invoice', (tester) async {
      final client = BillingRpcTestClient();

      await _pumpHost(
        tester,
        _scope(
          client: client,
          child: const InvoiceEditorPage(invoiceId: BillingRpcTestClient.draftInvoiceId),
        ),
      );

      await tester.enterText(find.byKey(const Key('invoice_item_description')), 'Consultation');
      await tester.enterText(find.byKey(const Key('invoice_item_unit_price')), '100');
      await tester.tap(find.byKey(const Key('invoice_item_add_button')));
      await tester.pumpAndSettle();

      expect(client.rpcLog, contains('add_invoice_item'));

      await tester.tap(find.byKey(const Key('invoice_issue_button')));
      await tester.pumpAndSettle();

      expect(client.rpcLog, contains('issue_invoice'));
    });

    testWidgets('scenario 3: duplicate active invoice surfaces message', (tester) async {
      final client = BillingRpcTestClient()
        ..rpcResults['list_invoices'] = {
          'success': true,
          'data': {'items': []},
        }
        ..rpcResults['create_invoice_from_visit'] = {
          'success': false,
          'error_code': 'ACTIVE_INVOICE_EXISTS',
          'error_message': 'One active invoice per visit is allowed.',
        };

      await _pumpHost(
        tester,
        _scope(
          client: client,
          child: VisitDetailActions(visitId: _visitId, status: VisitStatus.completed),
        ),
      );

      await tester.tap(find.byKey(const Key('visit_create_invoice_button')));
      await tester.pumpAndSettle();

      expect(find.textContaining('active invoice'), findsOneWidget);
    });

    testWidgets('scenario 4: open invoice navigates for existing draft', (tester) async {
      await _pumpHost(
        tester,
        _scope(
          child: VisitDetailActions(visitId: _visitId, status: VisitStatus.completed),
        ),
      );

      expect(find.byKey(const Key('visit_open_invoice_button')), findsOneWidget);
      await tester.tap(find.byKey(const Key('visit_open_invoice_button')));
      await tester.pumpAndSettle();
    });

    testWidgets('scenario 7a: add incomplete item shows field validation', (tester) async {
      final client = BillingRpcTestClient();

      await _pumpHost(
        tester,
        _scope(
          client: client,
          child: const InvoiceEditorPage(invoiceId: BillingRpcTestClient.draftInvoiceId),
        ),
      );

      await tester.enterText(find.byKey(const Key('invoice_item_description')), 'Consultation');
      await tester.tap(find.byKey(const Key('invoice_item_add_button')));
      await tester.pumpAndSettle();

      expect(find.text('Unit price is required.'), findsOneWidget);
      expect(client.rpcLog, isNot(contains('add_invoice_item')));
    });

    testWidgets('scenario 7b: issue with incomplete pending item shows validation', (tester) async {
      await _pumpHost(tester, _scope(child: const InvoiceEditorPage(invoiceId: BillingRpcTestClient.draftInvoiceId)));

      await tester.enterText(find.byKey(const Key('invoice_item_description')), 'Consultation');
      await tester.tap(find.byKey(const Key('invoice_issue_button')));
      await tester.pumpAndSettle();

      expect(find.text('Unit price is required.'), findsOneWidget);
      expect(find.byKey(const Key('invoice_issue_error_banner')), findsOneWidget);
      expect(find.text('Complete the line item below before issuing.'), findsOneWidget);
    });

    testWidgets('scenario 7: issue without items shows error banner', (tester) async {
      final client = BillingRpcTestClient()
        ..rpcResults['issue_invoice'] = {
          'success': false,
          'error_code': 'NO_ITEMS',
          'error_message': 'At least one line item is required before issuing.',
        };

      await _pumpHost(
        tester,
        _scope(
          client: client,
          child: const InvoiceEditorPage(invoiceId: BillingRpcTestClient.draftInvoiceId),
        ),
      );

      await tester.tap(find.byKey(const Key('invoice_issue_button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('invoice_issue_error_banner')), findsOneWidget);
      expect(find.text('Add at least one line item before issuing.'), findsOneWidget);
    });

    testWidgets('scenario 5: in-progress visit hides billing actions', (tester) async {
      await _pumpHost(
        tester,
        _scope(
          child: VisitDetailActions(visitId: _visitId, status: VisitStatus.inProgress),
        ),
      );

      expect(find.byKey(const Key('visit_create_invoice_button')), findsNothing);
      expect(find.byKey(const Key('visit_open_invoice_button')), findsNothing);
    });

    testWidgets('scenario 6: branch code missing shows inline issue error', (tester) async {
      final client = BillingRpcTestClient()
        ..rpcResults['issue_invoice'] = {
          'success': false,
          'error_code': 'BRANCH_CODE_MISSING',
          'error_message': 'Assign a branch code before issuing.',
        };

      await _pumpHost(
        tester,
        _scope(
          client: client,
          child: const InvoiceEditorPage(invoiceId: BillingRpcTestClient.draftInvoiceId),
        ),
      );

      await tester.enterText(find.byKey(const Key('invoice_item_description')), 'Consultation');
      await tester.enterText(find.byKey(const Key('invoice_item_unit_price')), '100');
      await tester.tap(find.byKey(const Key('invoice_item_add_button')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('invoice_issue_button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('invoice_issue_error_banner')), findsOneWidget);
      expect(find.textContaining('branch code'), findsOneWidget);
    });

    testWidgets('scenario 9: STALE_INVOICE on issue reloads detail without navigating away', (tester) async {
      final client = BillingRpcTestClient()
        ..rpcResults['issue_invoice'] = {'success': false, 'error_code': 'STALE_INVOICE', 'error_message': 'Stale'};

      await _pumpHost(
        tester,
        _scope(
          client: client,
          child: const InvoiceEditorPage(invoiceId: BillingRpcTestClient.draftInvoiceId),
        ),
      );

      await tester.enterText(find.byKey(const Key('invoice_item_description')), 'Consultation');
      await tester.enterText(find.byKey(const Key('invoice_item_unit_price')), '100');
      await tester.tap(find.byKey(const Key('invoice_item_add_button')));
      await tester.pumpAndSettle();

      final detailCallsBefore = client.rpcLog.where((name) => name == 'get_invoice_detail').length;
      await tester.tap(find.byKey(const Key('invoice_issue_button')));
      await tester.pumpAndSettle();

      expect(client.rpcLog, contains('issue_invoice'));
      expect(client.rpcLog.where((name) => name == 'get_invoice_detail').length, greaterThan(detailCallsBefore));
      expect(find.byKey(const Key('invoice_editor_body')), findsOneWidget);
      expect(find.textContaining('Invoice issued as'), findsNothing);
    });

    testWidgets('scenario 8: user without create permission hides billing action', (tester) async {
      await _pumpHost(
        tester,
        _scope(
          auth: _auth(permissions: {PermissionKeys.invoicesView}),
          child: VisitDetailActions(visitId: _visitId, status: VisitStatus.completed),
        ),
      );

      expect(find.byKey(const Key('visit_create_invoice_button')), findsNothing);
      expect(find.byKey(const Key('visit_open_invoice_button')), findsNothing);
    });

    test('backend billing_crud.sql covers visit_not_completed and duplicate guards', () {
      final crud = File('../backend/tests/billing_crud.sql');
      expect(crud.existsSync(), isTrue);
      final text = crud.readAsStringSync();
      expect(text, contains('VISIT_NOT_COMPLETED'));
      expect(text, contains('ACTIVE_INVOICE_EXISTS'));
      expect(text, contains('NO_ITEMS'));
      expect(text, contains('STALE_INVOICE'));
      expect(text, contains('discard_draft_invoice_success'));
      expect(text, contains('BRANCH_CODE_MISSING'));
    });
  });
}
