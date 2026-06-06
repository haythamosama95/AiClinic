// US3 acceptance scenarios 1, 2, 2a, 3, 4, 5, 6 (UI orchestration with fake RPC).
import 'dart:io';

import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/auth/domain/permission_keys.dart';
import 'package:ai_clinic/features/billing/data/invoice_repository.dart';
import 'package:ai_clinic/features/billing/presentation/pages/invoice_editor_page.dart';
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

Future<void> _pumpEditor(WidgetTester tester, {BillingRpcTestClient? client, AuthSessionState? auth}) async {
  final rpcClient = client ?? BillingRpcTestClient();
  await tester.binding.setSurfaceSize(const Size(1100, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authSessionProvider.overrideWith(() => _PresetAuth(auth ?? _ownerAuth())),
        invoiceRepositoryProvider.overrideWith((ref) => InvoiceRepository(rpcClient)),
      ],
      child: MaterialApp.router(
        routerConfig: GoRouter(
          routes: [
            GoRoute(
              path: '/',
              builder: (context, state) => const InvoiceEditorPage(invoiceId: BillingRpcTestClient.draftInvoiceId),
            ),
          ],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

AuthSessionState _ownerAuth({Set<String>? permissions}) {
  return AuthSessionState(
    status: AuthSessionStatus.authenticated,
    context: sampleAuthSessionContext(
      permissions:
          permissions ??
          {PermissionKeys.invoicesView, PermissionKeys.invoicesCreate, PermissionKeys.invoicesApplyDiscount},
      activeBranchId: '44444444-4444-4444-8444-444444444444',
      branchIds: ['44444444-4444-4444-8444-444444444444'],
    ),
  );
}

Future<void> _addSampleItem(WidgetTester tester) async {
  await tester.enterText(find.byKey(const Key('invoice_item_description')), 'Consultation');
  await tester.enterText(find.byKey(const Key('invoice_item_unit_price')), '100');
  await tester.tap(find.byKey(const Key('invoice_item_add_button')));
  await tester.pumpAndSettle();
}

Future<void> _scrollTo(WidgetTester tester, Key key) async {
  await tester.scrollUntilVisible(find.byKey(key), 48, scrollable: find.byType(Scrollable).first);
  await tester.pumpAndSettle();
}

void main() {
  group('Discount scopes US3', () {
    testWidgets('scenario 1: apply line-level percentage discount', (tester) async {
      final client = BillingRpcTestClient();
      await _pumpEditor(tester, client: client);
      await _addSampleItem(tester);

      await _scrollTo(tester, Key('line_discount_apply_${BillingRpcTestClient.itemId}'));
      await tester.enterText(find.byKey(Key('line_discount_value_${BillingRpcTestClient.itemId}')), '10');
      await tester.tap(find.byKey(Key('line_discount_apply_${BillingRpcTestClient.itemId}')));
      await tester.pumpAndSettle();

      expect(client.rpcLog, contains('apply_line_discount'));
      expect(find.textContaining('Applied: 10.00 off'), findsOneWidget);
    });

    testWidgets('scenario 2: apply invoice-level discount after clearing line scope', (tester) async {
      final client = BillingRpcTestClient();
      await _pumpEditor(tester, client: client);
      await _addSampleItem(tester);

      await _scrollTo(tester, Key('line_discount_apply_${BillingRpcTestClient.itemId}'));
      await tester.enterText(find.byKey(Key('line_discount_value_${BillingRpcTestClient.itemId}')), '10');
      await tester.tap(find.byKey(Key('line_discount_apply_${BillingRpcTestClient.itemId}')));
      await tester.pumpAndSettle();

      await _scrollTo(tester, Key('line_discount_clear_${BillingRpcTestClient.itemId}'));
      await tester.tap(find.byKey(Key('line_discount_clear_${BillingRpcTestClient.itemId}')));
      await tester.pumpAndSettle();

      await _scrollTo(tester, const Key('invoice_discount_apply'));
      await tester.enterText(find.byKey(const Key('invoice_discount_value')), '15');
      await tester.tap(find.byKey(const Key('invoice_discount_apply')));
      await tester.pumpAndSettle();

      expect(client.rpcLog.where((name) => name == 'apply_invoice_discount').length, 1);
      expect(find.textContaining('Applied invoice discount: 15.00'), findsOneWidget);
    });

    testWidgets('scenario 2a: mutual exclusion blocks invoice discount while line scope active', (tester) async {
      final client = BillingRpcTestClient();
      await _pumpEditor(tester, client: client);
      await _addSampleItem(tester);

      await _scrollTo(tester, Key('line_discount_apply_${BillingRpcTestClient.itemId}'));
      await tester.enterText(find.byKey(Key('line_discount_value_${BillingRpcTestClient.itemId}')), '10');
      await tester.tap(find.byKey(Key('line_discount_apply_${BillingRpcTestClient.itemId}')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('discount_line_scope_active')), findsOneWidget);
      expect(find.byKey(const Key('invoice_discount_apply')), findsOneWidget);
      final applyButton = tester.widget<FilledButton>(find.byKey(const Key('invoice_discount_apply')));
      expect(applyButton.onPressed, isNull);
    });

    testWidgets('scenario 3: user without discount permission does not see discount section', (tester) async {
      await _pumpEditor(
        tester,
        auth: _ownerAuth(permissions: {PermissionKeys.invoicesView, PermissionKeys.invoicesCreate}),
      );
      await _addSampleItem(tester);

      expect(find.text('Discounts'), findsNothing);
      expect(find.byKey(const Key('invoice_discount_apply')), findsNothing);
    });

    testWidgets('scenario 4: invalid line discount shows validation message', (tester) async {
      final client = BillingRpcTestClient();
      await _pumpEditor(tester, client: client);
      await _addSampleItem(tester);

      await _scrollTo(tester, Key('line_discount_apply_${BillingRpcTestClient.itemId}'));
      await tester.enterText(find.byKey(Key('line_discount_value_${BillingRpcTestClient.itemId}')), '150');
      await tester.tap(find.byKey(Key('line_discount_apply_${BillingRpcTestClient.itemId}')));
      await tester.pumpAndSettle();

      expect(find.text('Percentage cannot exceed 100.'), findsOneWidget);
      expect(client.rpcLog.where((name) => name == 'apply_line_discount'), isEmpty);
    });

    testWidgets('scenario 5: issued invoice editor is not reachable for discount edits', (tester) async {
      final client = BillingRpcTestClient();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authSessionProvider.overrideWith(() => _PresetAuth(_ownerAuth())),
            invoiceRepositoryProvider.overrideWith((ref) => InvoiceRepository(client)),
          ],
          child: MaterialApp(home: const InvoiceEditorPage(invoiceId: BillingRpcTestClient.issuedInvoiceId)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Only draft invoices'), findsOneWidget);
      expect(find.text('Discounts'), findsNothing);
    });

    testWidgets('scenario 7: fixed line discount applies successfully', (tester) async {
      final client = BillingRpcTestClient();
      await _pumpEditor(tester, client: client);
      await _addSampleItem(tester);

      await _scrollTo(tester, Key('line_discount_kind_${BillingRpcTestClient.itemId}'));
      await tester.tap(find.byKey(Key('line_discount_kind_${BillingRpcTestClient.itemId}')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Fixed amount').last);
      await tester.pumpAndSettle();

      await _scrollTo(tester, Key('line_discount_apply_${BillingRpcTestClient.itemId}'));
      await tester.enterText(find.byKey(Key('line_discount_value_${BillingRpcTestClient.itemId}')), '25');
      await tester.tap(find.byKey(Key('line_discount_apply_${BillingRpcTestClient.itemId}')));
      await tester.pumpAndSettle();

      expect(client.rpcLog, contains('apply_line_discount'));
      expect(
        client.rpcLog.lastIndexOf('get_invoice_detail'),
        greaterThan(client.rpcLog.lastIndexOf('apply_line_discount')),
      );
    });

    testWidgets('scenario 8: clear other scope enables invoice discount', (tester) async {
      final client = BillingRpcTestClient();
      await _pumpEditor(tester, client: client);
      await _addSampleItem(tester);

      await _scrollTo(tester, Key('line_discount_apply_${BillingRpcTestClient.itemId}'));
      await tester.enterText(find.byKey(Key('line_discount_value_${BillingRpcTestClient.itemId}')), '10');
      await tester.tap(find.byKey(Key('line_discount_apply_${BillingRpcTestClient.itemId}')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('discount_line_scope_active')), findsOneWidget);

      await tester.tap(find.byKey(const Key('discount_clear_other_scope_line')));
      await tester.pumpAndSettle();

      await _scrollTo(tester, const Key('invoice_discount_apply'));
      await tester.enterText(find.byKey(const Key('invoice_discount_value')), '5');
      await tester.tap(find.byKey(const Key('invoice_discount_apply')));
      await tester.pumpAndSettle();

      expect(client.rpcLog, contains('apply_invoice_discount'));
    });

    testWidgets('scenario 9: invalid invoice discount shows validation message', (tester) async {
      final client = BillingRpcTestClient();
      await _pumpEditor(tester, client: client);
      await _addSampleItem(tester);

      await _scrollTo(tester, const Key('invoice_discount_apply'));
      await tester.enterText(find.byKey(const Key('invoice_discount_value')), '150');
      await tester.tap(find.byKey(const Key('invoice_discount_apply')));
      await tester.pumpAndSettle();

      expect(find.text('Percentage cannot exceed 100.'), findsOneWidget);
      expect(client.rpcLog.where((name) => name == 'apply_invoice_discount'), isEmpty);
    });

    testWidgets('scenario 6: discount apply records audit via RPC', (tester) async {
      final client = BillingRpcTestClient();
      await _pumpEditor(tester, client: client);
      await _addSampleItem(tester);

      await _scrollTo(tester, Key('line_discount_apply_${BillingRpcTestClient.itemId}'));
      await tester.enterText(find.byKey(Key('line_discount_value_${BillingRpcTestClient.itemId}')), '5');
      await tester.tap(find.byKey(Key('line_discount_apply_${BillingRpcTestClient.itemId}')));
      await tester.pumpAndSettle();

      expect(client.rpcLog, contains('apply_line_discount'));
      expect(client.rpcLog, contains('get_invoice_detail'));
      final applyIndex = client.rpcLog.lastIndexOf('apply_line_discount');
      final refreshIndex = client.rpcLog.lastIndexOf('get_invoice_detail');
      expect(refreshIndex, greaterThan(applyIndex));
    });
  });
}
