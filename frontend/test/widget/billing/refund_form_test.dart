import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/auth/domain/permission_keys.dart';
import 'package:ai_clinic/features/billing/data/billing_settings_repository.dart';
import 'package:ai_clinic/features/billing/data/invoice_repository.dart';
import 'package:ai_clinic/features/billing/domain/invoice_detail.dart';
import 'package:ai_clinic/features/billing/domain/invoice_status.dart';
import 'package:ai_clinic/features/billing/domain/payment.dart';
import 'package:ai_clinic/features/billing/domain/payment_method.dart';
import 'package:ai_clinic/features/billing/presentation/widgets/refund_form.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/auth_test_support.dart';
import '../../support/billing_rpc_test_client.dart';

class _PresetAuth extends AuthSessionNotifier {
  _PresetAuth(this._state);

  final AuthSessionState _state;

  @override
  AuthSessionState build() => _state;
}

InvoiceDetail _detailWithPayments(List<Payment> payments) {
  return InvoiceDetail(
    id: BillingRpcTestClient.issuedInvoiceId,
    visitId: BillingRpcTestClient.visitId,
    patientId: 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
    branchId: '44444444-4444-4444-8444-444444444444',
    status: InvoiceStatus.partiallyPaid,
    currency: 'USD',
    subtotal: '100.00',
    discountAmount: '0.00',
    insuranceCoveredAmount: '0.00',
    balance: '20.00',
    updatedAt: DateTime.utc(2026, 6, 2),
    items: const [],
    payments: payments,
  );
}

void main() {
  testWidgets('refund form caps amount at net payments after prior refunds', (tester) async {
    final client = BillingRpcTestClient();
    final detail = _detailWithPayments([
      Payment(
        id: 'pay-1',
        method: PaymentMethod.cash,
        amount: '100.00',
        reference: null,
        note: null,
        recordedById: 'staff-1',
        recordedAt: DateTime.utc(2026, 6, 2, 12),
      ),
      Payment(
        id: 'ref-1',
        method: PaymentMethod.cash,
        amount: '-30.00',
        reference: null,
        note: 'Partial refund',
        recordedById: 'staff-1',
        recordedAt: DateTime.utc(2026, 6, 2, 13),
      ),
    ]);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authSessionProvider.overrideWith(
            () => _PresetAuth(
              AuthSessionState(
                status: AuthSessionStatus.authenticated,
                context: sampleAuthSessionContext(
                  permissions: {PermissionKeys.invoicesView, PermissionKeys.paymentsRefund},
                  activeBranchId: '44444444-4444-4444-8444-444444444444',
                  branchIds: ['44444444-4444-4444-8444-444444444444'],
                ),
              ),
            ),
          ),
          invoiceRepositoryProvider.overrideWith((ref) => InvoiceRepository(client)),
          billingSettingsRepositoryProvider.overrideWith((ref) => BillingSettingsRepository(client)),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: RefundForm(invoiceId: BillingRpcTestClient.issuedInvoiceId, detail: detail),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Maximum refundable: 70.00'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('refund_amount_field')), '80');
    await tester.enterText(find.byKey(const Key('refund_reason_field')), 'Too much');
    await tester.tap(find.byKey(const Key('refund_submit_button')));
    await tester.pumpAndSettle();

    expect(find.text('Refund cannot exceed net payments on this invoice.'), findsOneWidget);
    expect(client.rpcLog, isNot(contains('record_refund')));
  });

  testWidgets('refund form renders for issued invoices with net positive payments', (tester) async {
    final client = BillingRpcTestClient();
    final detail = InvoiceDetail(
      id: BillingRpcTestClient.issuedInvoiceId,
      visitId: BillingRpcTestClient.visitId,
      patientId: 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
      branchId: '44444444-4444-4444-8444-444444444444',
      status: InvoiceStatus.issued,
      currency: 'USD',
      subtotal: '100.00',
      discountAmount: '0.00',
      insuranceCoveredAmount: '0.00',
      balance: '40.00',
      updatedAt: DateTime.utc(2026, 6, 2),
      items: const [],
      payments: [
        Payment(
          id: 'pay-1',
          method: PaymentMethod.cash,
          amount: '60.00',
          recordedById: 'staff-1',
          recordedAt: DateTime.utc(2026, 6, 2, 12),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authSessionProvider.overrideWith(
            () => _PresetAuth(
              AuthSessionState(
                status: AuthSessionStatus.authenticated,
                context: sampleAuthSessionContext(
                  permissions: {PermissionKeys.invoicesView, PermissionKeys.paymentsRefund},
                  activeBranchId: '44444444-4444-4444-8444-444444444444',
                  branchIds: ['44444444-4444-4444-8444-444444444444'],
                ),
              ),
            ),
          ),
          invoiceRepositoryProvider.overrideWith((ref) => InvoiceRepository(client)),
          billingSettingsRepositoryProvider.overrideWith((ref) => BillingSettingsRepository(client)),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: RefundForm(invoiceId: BillingRpcTestClient.issuedInvoiceId, detail: detail),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('refund_form_card')), findsOneWidget);
    expect(find.textContaining('Maximum refundable: 60.00'), findsOneWidget);
  });

  testWidgets('refund form hidden for voided invoices with payments', (tester) async {
    final client = BillingRpcTestClient();
    final detail = InvoiceDetail(
      id: BillingRpcTestClient.issuedInvoiceId,
      visitId: BillingRpcTestClient.visitId,
      patientId: 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
      branchId: '44444444-4444-4444-8444-444444444444',
      status: InvoiceStatus.voided,
      currency: 'USD',
      subtotal: '100.00',
      discountAmount: '0.00',
      insuranceCoveredAmount: '0.00',
      balance: '0.00',
      updatedAt: DateTime.utc(2026, 6, 2),
      items: const [],
      payments: [
        Payment(
          id: 'pay-1',
          method: PaymentMethod.cash,
          amount: '100.00',
          recordedById: 'staff-1',
          recordedAt: DateTime.utc(2026, 6, 2, 12),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authSessionProvider.overrideWith(
            () => _PresetAuth(
              AuthSessionState(
                status: AuthSessionStatus.authenticated,
                context: sampleAuthSessionContext(
                  permissions: {PermissionKeys.invoicesView, PermissionKeys.paymentsRefund},
                  activeBranchId: '44444444-4444-4444-8444-444444444444',
                  branchIds: ['44444444-4444-4444-8444-444444444444'],
                ),
              ),
            ),
          ),
          invoiceRepositoryProvider.overrideWith((ref) => InvoiceRepository(client)),
          billingSettingsRepositoryProvider.overrideWith((ref) => BillingSettingsRepository(client)),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: RefundForm(invoiceId: BillingRpcTestClient.issuedInvoiceId, detail: detail),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('refund_form_card')), findsNothing);
  });
}
