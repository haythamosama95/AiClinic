import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/auth/domain/permission_keys.dart';
import 'package:ai_clinic/features/billing/data/billing_settings_repository.dart';
import 'package:ai_clinic/features/billing/data/invoice_repository.dart';
import 'package:ai_clinic/features/billing/data/payment_repository.dart';
import 'package:ai_clinic/features/billing/domain/payment_method.dart';
import 'package:ai_clinic/features/billing/presentation/pages/invoice_detail_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../helpers/auth_test_support.dart';
import '../../support/billing_rpc_test_client.dart';

void main() {
  group('Billing payment permission guards', () {
    testWidgets('payment form hidden without payments.record', (tester) async {
      final client = BillingRpcTestClient()..issuedStatus = 'issued';

      await tester.pumpWidget(_host(client: client, permissions: {PermissionKeys.invoicesView}));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('payment_form_card')), findsNothing);
    });

    testWidgets('refund form hidden without payments.refund', (tester) async {
      final client = BillingRpcTestClient()
        ..issuedStatus = 'paid'
        ..issuedBalance = '0.00'
        ..payments.add({
          'id': 'pay-1',
          'method': 'cash',
          'amount': '100.00',
          'reference': null,
          'note': null,
          'recorded_by': {'id': 'staff-1', 'display_name': 'Test Staff'},
          'recorded_at': '2026-06-01T12:00:00.000Z',
        });

      await tester.pumpWidget(
        _host(client: client, permissions: {PermissionKeys.invoicesView, PermissionKeys.paymentsRecord}),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('payment_form_card')), findsNothing);
      expect(find.byKey(const Key('refund_form_card')), findsNothing);
    });

    testWidgets('insurance settlement keeps amount editable when partial payments disabled', (tester) async {
      final client = BillingRpcTestClient()..allowPartialPayments = false;

      await tester.pumpWidget(
        _host(client: client, permissions: {PermissionKeys.invoicesView, PermissionKeys.paymentsRecord}),
      );
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.byKey(const Key('payment_method_field')),
        48,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('payment_method_field')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(PaymentMethod.insuranceSettlement.label).last);
      await tester.pumpAndSettle();

      final amountField = tester.widget<TextFormField>(find.byKey(const Key('payment_amount_field')));
      expect(amountField.enabled, isTrue);
    });
  });
}

Widget _host({required BillingRpcTestClient client, required Set<String> permissions}) {
  return ProviderScope(
    overrides: [
      authSessionProvider.overrideWith(
        () => _PresetAuth(
          AuthSessionState(
            status: AuthSessionStatus.authenticated,
            context: sampleAuthSessionContext(permissions: permissions),
          ),
        ),
      ),
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

class _PresetAuth extends AuthSessionNotifier {
  _PresetAuth(this._state);

  final AuthSessionState _state;

  @override
  AuthSessionState build() => _state;
}
