import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/core/ui/components/app_button.dart';
import 'package:ai_clinic/core/ui/components/app_toast.dart';
import 'package:ai_clinic/core/ui/theme/app_theme.dart';
import 'package:ai_clinic/features/billing/data/invoice_repository.dart';
import 'package:ai_clinic/features/billing/domain/invoice_detail.dart';
import 'package:ai_clinic/features/billing/domain/invoice_status.dart';
import 'package:ai_clinic/features/billing/domain/money.dart';
import 'package:ai_clinic/features/billing/presentation/widgets/void_invoice_dialog.dart';

import '../../support/billing_rpc_test_client.dart';

InvoiceDetail _voidableInvoice() {
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
    updatedAt: DateTime.utc(2026, 6, 2, 11, 0),
    items: const [],
    payments: const [],
  );
}

Future<void> _openVoidDialog(
  WidgetTester tester, {
  required BillingRpcTestClient client,
  required InvoiceDetail invoice,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        invoiceRepositoryProvider.overrideWithValue(InvoiceRepository(client)),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: AppToastHost(
          child: Builder(
            builder: (context) {
              return Scaffold(
                body: ElevatedButton(
                  onPressed: () => VoidInvoiceDialog.show(context, invoice: invoice),
                  child: const Text('Open dialog'),
                ),
              );
            },
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();

  await tester.tap(find.text('Open dialog'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('VoidInvoiceDialog.show renders title, warning copy, and reason field', (tester) async {
    final client = BillingRpcTestClient();

    await _openVoidDialog(tester, client: client, invoice: _voidableInvoice());

    expect(find.text('Void invoice'), findsWidgets);
    expect(
      find.text('This cannot be undone. Payments must be refunded before voiding a paid invoice.'),
      findsOneWidget,
    );
    expect(find.text('Why is this invoice being voided?'), findsOneWidget);
  });

  testWidgets('VoidInvoiceDialog Void button is disabled until reason is entered', (tester) async {
    final client = BillingRpcTestClient();

    await _openVoidDialog(tester, client: client, invoice: _voidableInvoice());

    final voidButtons = tester.widgetList<AppButton>(find.byType(AppButton));
    final voidButton = voidButtons.firstWhere(
      (button) => button.child is Text && (button.child as Text).data == 'Void invoice',
    );
<<<<<<< HEAD
    expect(voidButton.disabled, isTrue);
=======
    expect(voidButton.onPressed, isNull);
>>>>>>> master

    await tester.enterText(find.byType(TextField), 'Duplicate invoice');
    await tester.pump();

    final enabledVoidButton = tester.widgetList<AppButton>(find.byType(AppButton)).firstWhere(
      (button) => button.child is Text && (button.child as Text).data == 'Void invoice',
    );
<<<<<<< HEAD
    expect(enabledVoidButton.disabled, isFalse);
=======
    expect(enabledVoidButton.onPressed, isNotNull);
>>>>>>> master
  });

  testWidgets('VoidInvoiceDialog Cancel dismisses without calling repository', (tester) async {
    final client = BillingRpcTestClient();

    await _openVoidDialog(tester, client: client, invoice: _voidableInvoice());

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('Why is this invoice being voided?'), findsNothing);
    expect(client.rpcLog, isEmpty);
  });

  testWidgets('VoidInvoiceDialog confirming calls voidInvoice on the repository', (tester) async {
    final client = BillingRpcTestClient();

    await _openVoidDialog(tester, client: client, invoice: _voidableInvoice());

    await tester.enterText(find.byType(TextField), 'Duplicate invoice');
    await tester.pump();

    await tester.tap(
      find.widgetWithText(AppButton, 'Void invoice'),
    );
    await tester.pumpAndSettle();

    expect(client.lastFunction, 'void_invoice');
    expect(client.lastParams?['p_invoice_id'], BillingRpcTestClient.issuedInvoiceId);
    expect(client.lastParams?['p_reason'], 'Duplicate invoice');
    expect(find.text('Why is this invoice being voided?'), findsNothing);
  });
}
