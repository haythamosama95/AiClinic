// US2 acceptance scenarios 1, 1a, 2, 3, 6 (concurrent), and 7 (refund).
import 'dart:io';

import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/auth/domain/permission_keys.dart';
import 'package:ai_clinic/features/billing/data/billing_settings_repository.dart';
import 'package:ai_clinic/features/billing/data/invoice_repository.dart';
import 'package:ai_clinic/features/billing/data/payment_repository.dart';
import 'package:ai_clinic/features/billing/domain/payment_method.dart';
import 'package:ai_clinic/features/billing/presentation/pages/invoice_detail_page.dart';
import 'package:ai_clinic/features/billing/presentation/providers/payment_notifier.dart';
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

Future<void> _scrollTo(WidgetTester tester, Key key) async {
  await tester.scrollUntilVisible(find.byKey(key), 48, scrollable: find.byType(Scrollable).first);
  await tester.pumpAndSettle();
}

Future<void> _pumpHost(WidgetTester tester, Widget host) async {
  await tester.binding.setSurfaceSize(const Size(1100, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(host);
  await tester.pump();
  await tester.pumpAndSettle();
}

AuthSessionState _auth({Set<String>? permissions}) {
  return AuthSessionState(
    status: AuthSessionStatus.authenticated,
    context: sampleAuthSessionContext(
      permissions:
          permissions ?? {PermissionKeys.invoicesView, PermissionKeys.paymentsRecord, PermissionKeys.paymentsRefund},
      activeBranchId: '44444444-4444-4444-8444-444444444444',
      branchIds: ['44444444-4444-4444-8444-444444444444'],
    ),
  );
}

Widget _scope({required Widget child, required BillingRpcTestClient client, AuthSessionState? auth}) {
  return ProviderScope(
    overrides: [
      authSessionProvider.overrideWith(() => _PresetAuth(auth ?? _auth())),
      invoiceRepositoryProvider.overrideWith((ref) => InvoiceRepository(client)),
      paymentRepositoryProvider.overrideWith((ref) => PaymentRepository(client)),
      billingSettingsRepositoryProvider.overrideWith((ref) => BillingSettingsRepository(client)),
    ],
    child: MaterialApp.router(
      routerConfig: GoRouter(
        initialLocation: AppRoutes.billingInvoiceDetail(BillingRpcTestClient.issuedInvoiceId),
        routes: [
          GoRoute(
            path: AppRoutes.billingInvoiceDetail(BillingRpcTestClient.issuedInvoiceId),
            builder: (context, state) => const InvoiceDetailPage(invoiceId: BillingRpcTestClient.issuedInvoiceId),
          ),
        ],
      ),
    ),
  );
}

void main() {
  group('Record payment US2', () {
    testWidgets('scenario 1: partial payment accepted when setting enabled', (tester) async {
      final client = BillingRpcTestClient()..allowPartialPayments = true;

      await _pumpHost(tester, _scope(child: const SizedBox.shrink(), client: client));

      await _scrollTo(tester, const Key('payment_amount_field'));
      await tester.enterText(find.byKey(const Key('payment_amount_field')), '40');
      await _scrollTo(tester, const Key('payment_submit_button'));
      await tester.tap(find.byKey(const Key('payment_submit_button')));
      await tester.pumpAndSettle();

      expect(client.rpcLog, contains('record_payment'));
      expect(find.byKey(const Key('payment_success_message')), findsOneWidget);
    });

    testWidgets('scenario 1a: partial patient payment rejected when setting disabled', (tester) async {
      final client = BillingRpcTestClient()..allowPartialPayments = false;

      await _pumpHost(tester, _scope(child: const SizedBox.shrink(), client: client));

      await _scrollTo(tester, const Key('payment_amount_field'));
      final amountField = tester.widget<TextFormField>(find.byKey(const Key('payment_amount_field')));
      expect(amountField.enabled, isFalse);
      expect(amountField.controller?.text, '100.00');
    });

    testWidgets('scenario 2: overpayment rejected', (tester) async {
      final client = BillingRpcTestClient()..allowPartialPayments = true;

      await _pumpHost(tester, _scope(child: const SizedBox.shrink(), client: client));

      await _scrollTo(tester, const Key('payment_amount_field'));
      await tester.enterText(find.byKey(const Key('payment_amount_field')), '150');
      await _scrollTo(tester, const Key('payment_submit_button'));
      await tester.tap(find.byKey(const Key('payment_submit_button')));
      await tester.pumpAndSettle();

      expect(client.rpcLog, isNot(contains('record_payment')));
      expect(find.textContaining('exceed'), findsOneWidget);
    });

    testWidgets('scenario 3: payments summing to balance close invoice', (tester) async {
      final client = BillingRpcTestClient()..allowPartialPayments = true;

      await _pumpHost(tester, _scope(child: const SizedBox.shrink(), client: client));

      await _scrollTo(tester, const Key('payment_amount_field'));
      await tester.enterText(find.byKey(const Key('payment_amount_field')), '60');
      await _scrollTo(tester, const Key('payment_submit_button'));
      await tester.tap(find.byKey(const Key('payment_submit_button')));
      await tester.pumpAndSettle();

      await _scrollTo(tester, const Key('payment_amount_field'));
      await tester.enterText(find.byKey(const Key('payment_amount_field')), '40');
      await _scrollTo(tester, const Key('payment_submit_button'));
      await tester.tap(find.byKey(const Key('payment_submit_button')));
      await tester.pumpAndSettle();

      expect(client.issuedStatus, 'paid');
      expect(client.issuedBalance, '0.00');
    });

    testWidgets('scenario 6: second concurrent payment rejected as overpayment', (tester) async {
      final client = BillingRpcTestClient()..allowPartialPayments = true;

      await _pumpHost(tester, _scope(child: const SizedBox.shrink(), client: client));

      await _scrollTo(tester, const Key('payment_amount_field'));
      await tester.enterText(find.byKey(const Key('payment_amount_field')), '60');
      await _scrollTo(tester, const Key('payment_submit_button'));
      await tester.tap(find.byKey(const Key('payment_submit_button')));
      await tester.pumpAndSettle();

      client.rpcResults['record_payment'] = {
        'success': false,
        'error_code': 'OVERPAYMENT',
        'error_message': 'Payment amount exceeds the current balance.',
      };

      final element = tester.element(find.byType(InvoiceDetailPage));
      final container = ProviderScope.containerOf(element);
      final success = await container
          .read(paymentPanelProvider(BillingRpcTestClient.issuedInvoiceId).notifier)
          .recordPayment(method: PaymentMethod.cash, amount: '60');

      expect(success, isFalse);
      expect(client.rpcLog.where((call) => call == 'record_payment').length, greaterThanOrEqualTo(2));
      final panelState = container.read(paymentPanelProvider(BillingRpcTestClient.issuedInvoiceId));
      expect(panelState.value?.errorMessage, contains('exceed'));
    });

    testWidgets('scenario 7: refund recorded on paid invoice', (tester) async {
      final client = BillingRpcTestClient()
        ..allowPartialPayments = true
        ..issuedBalance = '0.00'
        ..issuedStatus = 'paid'
        ..payments.add({
          'id': 'pay-1',
          'method': 'cash',
          'amount': '100.00',
          'reference': null,
          'note': null,
          'recorded_by': 'staff-1',
          'recorded_at': '2026-06-01T12:00:00.000Z',
        });

      await _pumpHost(tester, _scope(child: const SizedBox.shrink(), client: client));

      expect(find.byKey(const Key('refund_form_card')), findsOneWidget);
      await _scrollTo(tester, const Key('refund_amount_field'));
      await tester.enterText(find.byKey(const Key('refund_amount_field')), '50');
      await tester.enterText(find.byKey(const Key('refund_reason_field')), 'Patient overpaid');
      await _scrollTo(tester, const Key('refund_submit_button'));
      await tester.tap(find.byKey(const Key('refund_submit_button')));
      await tester.pumpAndSettle();

      expect(client.rpcLog, contains('record_refund'));
    });

    test('backend billing_crud.sql covers US2 payment scenarios', () {
      final crud = File('../backend/tests/billing_crud.sql');
      expect(crud.existsSync(), isTrue);
      final text = crud.readAsStringSync();
      expect(text, contains('PARTIAL_PAYMENTS_DISABLED'));
      expect(text, contains('OVERPAYMENT'));
      expect(text, contains('payment.refund'));
      expect(text, contains('record_payment_permission_denied_for_doctor'));
      expect(text, contains('record_payment_rejects_zero_amount'));
      expect(text, contains('record_refund_rejects_amount_exceeding_net_payments'));
    });

    testWidgets('scenario 4: insurance settlement partial allowed when setting disabled', (tester) async {
      final client = BillingRpcTestClient()..allowPartialPayments = false;

      await _pumpHost(tester, _scope(child: const SizedBox.shrink(), client: client));

      await _scrollTo(tester, const Key('payment_method_field'));
      await tester.tap(find.byKey(const Key('payment_method_field')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(PaymentMethod.insuranceSettlement.label).last);
      await tester.pumpAndSettle();

      await _scrollTo(tester, const Key('payment_amount_field'));
      await tester.enterText(find.byKey(const Key('payment_amount_field')), '30');
      await _scrollTo(tester, const Key('payment_submit_button'));
      await tester.tap(find.byKey(const Key('payment_submit_button')));
      await tester.pumpAndSettle();

      expect(client.rpcLog, contains('record_payment'));
      expect(find.byKey(const Key('payment_success_message')), findsOneWidget);
    });

    test('backend billing_concurrency.sql covers concurrent overpayment guard', () {
      final sql = File('../backend/tests/billing_concurrency.sql');
      expect(sql.existsSync(), isTrue);
      final text = sql.readAsStringSync();
      expect(text, contains('second_concurrent_payment_rejected_overpayment'));
    });
  });
}
