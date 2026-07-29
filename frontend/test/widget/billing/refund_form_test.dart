import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/core/ui/components/app_toast.dart';
import 'package:ai_clinic/core/ui/theme/app_theme.dart';
import 'package:ai_clinic/features/billing/data/payment_repository.dart';
import 'package:ai_clinic/features/billing/domain/invoice_detail.dart';
import 'package:ai_clinic/features/billing/domain/invoice_status.dart';
import 'package:ai_clinic/features/billing/domain/money.dart';
import 'package:ai_clinic/features/billing/presentation/widgets/refund_form.dart';
import 'package:ai_clinic/l10n/app_localizations.dart';

import '../../support/billing_rpc_test_client.dart';

InvoiceDetail _issuedInvoice() {
  return InvoiceDetail(
    id: BillingRpcTestClient.issuedInvoiceId,
    invoiceNumber: 'INV-MAIN-000001',
    status: InvoiceStatus.issued,
    branchId: '44444444-4444-4444-8444-444444444444',
    patientId: 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
    visitId: BillingRpcTestClient.visitId,
    subtotal: Money.parse('100.00'),
    discountAmount: Money.zero,
    insuranceCoveredAmount: Money.zero,
    currency: 'USD',
    balance: Money.parse('100.00'),
    createdAt: DateTime.parse('2026-06-01T10:00:00.000Z'),
    updatedAt: DateTime.parse('2026-06-02T12:00:00.000Z'),
    items: const [],
    payments: const [],
  );
}

Future<void> _pumpRefundForm(
  WidgetTester tester, {
  required BillingRpcTestClient client,
  VoidCallback? onRecorded,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        paymentRepositoryProvider.overrideWithValue(PaymentRepository(client)),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: AppToastHost(
          child: Scaffold(
            body: RefundForm(
              invoice: _issuedInvoice(),
              onRecorded: onRecorded ?? () {},
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('RefundForm builds', (tester) async {
    final client = BillingRpcTestClient();
    client.payments.add({
      'id': 'pay-1',
      'method': 'card',
      'amount': '80.00',
      'note': null,
      'recorded_by': {'id': 'staff-1', 'display_name': 'Reception'},
      'recorded_at': '2026-06-01T12:00:00.000Z',
    });

    await _pumpRefundForm(tester, client: client);

    expect(find.text('Record refund'), findsOneWidget);
    expect(find.text('Method'), findsOneWidget);
    expect(find.text('Amount'), findsOneWidget);
    expect(find.text('Reason'), findsOneWidget);
  });

  testWidgets('RefundForm empty amount shows Enter a refund amount toast', (tester) async {
    final client = BillingRpcTestClient();

    await _pumpRefundForm(tester, client: client);

    await tester.enterText(find.byType(TextField).last, 'Patient requested refund');
    await tester.pump();
    await tester.tap(find.text('Record refund'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Enter a refund amount.'), findsOneWidget);
    expect(client.rpcLog, isEmpty);
  });

  testWidgets('RefundForm empty note shows A reason is required for refunds toast', (tester) async {
    final client = BillingRpcTestClient();

    await _pumpRefundForm(tester, client: client);

    await tester.enterText(find.byType(TextField).first, '25');
    await tester.pump();
    await tester.tap(find.text('Record refund'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('A reason is required for refunds.'), findsOneWidget);
    expect(client.rpcLog, isEmpty);
  });

  testWidgets('RefundForm valid submit calls notifier and fires onRecorded', (tester) async {
    final client = BillingRpcTestClient();
    client.payments.add({
      'id': 'pay-1',
      'method': 'card',
      'amount': '80.00',
      'note': null,
      'recorded_by': {'id': 'staff-1', 'display_name': 'Reception'},
      'recorded_at': '2026-06-01T12:00:00.000Z',
    });
    var recorded = false;

    await _pumpRefundForm(
      tester,
      client: client,
      onRecorded: () => recorded = true,
    );

    final fields = tester.widgetList<TextField>(find.byType(TextField));
    await tester.enterText(find.byType(TextField).at(0), '25');
    await tester.pump();
    await tester.enterText(find.byType(TextField).at(1), 'Patient overpaid');
    await tester.pump();

    await tester.tap(find.text('Record refund'));
    await tester.pumpAndSettle();

    expect(recorded, isTrue);
    expect(client.lastFunction, 'record_refund');
    expect(find.text('Refund recorded.'), findsOneWidget);
    expect(fields.length, greaterThanOrEqualTo(2));
  });
}
