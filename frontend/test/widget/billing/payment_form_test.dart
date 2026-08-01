import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

<<<<<<< HEAD
=======
import 'package:ai_clinic/core/ui/components/app_button.dart';
>>>>>>> master
import 'package:ai_clinic/core/ui/components/app_money_field.dart';
import 'package:ai_clinic/core/ui/components/app_toast.dart';
import 'package:ai_clinic/core/ui/theme/app_theme.dart';
import 'package:ai_clinic/features/billing/data/payment_repository.dart';
import 'package:ai_clinic/features/billing/domain/billing_settings.dart';
import 'package:ai_clinic/features/billing/domain/invoice_detail.dart';
import 'package:ai_clinic/features/billing/domain/invoice_status.dart';
import 'package:ai_clinic/features/billing/domain/money.dart';
import 'package:ai_clinic/features/billing/domain/payment_method.dart';
import 'package:ai_clinic/features/billing/presentation/providers/billing_settings_notifier.dart';
import 'package:ai_clinic/features/billing/presentation/providers/payment_notifier.dart';
import 'package:ai_clinic/features/billing/presentation/widgets/payment_form.dart';
import 'package:ai_clinic/l10n/app_localizations.dart';

import '../../support/billing_rpc_test_client.dart';

<<<<<<< HEAD
InvoiceDetail _issuedInvoice({Money balance = Money.parse('100.00')}) {
=======
InvoiceDetail _issuedInvoice({Money? balance}) {
  final resolvedBalance = balance ?? Money.parse('100.00');
>>>>>>> master
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
<<<<<<< HEAD
    balance: balance,
=======
    balance: resolvedBalance,
>>>>>>> master
    createdAt: DateTime.parse('2026-06-01T10:00:00.000Z'),
    updatedAt: DateTime.parse('2026-06-02T12:00:00.000Z'),
    items: const [],
    payments: const [],
  );
}

class _FixedBillingSettingsNotifier extends BillingSettingsNotifier {
  _FixedBillingSettingsNotifier(this.settings);

  final BillingSettings settings;

  @override
  Future<BillingSettings> build() async => settings;
}

class _SlowPaymentNotifier extends PaymentNotifier {
  _SlowPaymentNotifier(super.ref);

  int callCount = 0;
  Completer<String>? pending;

  @override
  Future<String> recordPayment({
    required String invoiceId,
    required PaymentMethod method,
    required String amount,
    String? note,
  }) {
    callCount++;
    pending = Completer<String>();
    return pending!.future;
  }
}

Future<void> _pumpPaymentForm(
  WidgetTester tester, {
  required BillingRpcTestClient client,
  required InvoiceDetail invoice,
  required bool allowPartialPayments,
  Future<void> Function()? onRecorded,
}) async {
<<<<<<< HEAD
=======
  client.allowPartialPayments = allowPartialPayments;

>>>>>>> master
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        billingSettingsProvider.overrideWith(
          () => _FixedBillingSettingsNotifier(
            BillingSettings(allowPartialPayments: allowPartialPayments),
          ),
        ),
        paymentRepositoryProvider.overrideWithValue(PaymentRepository(client)),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: AppToastHost(
          child: Scaffold(
            body: PaymentForm(invoice: invoice, onRecorded: onRecorded ?? () async {}),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('PaymentForm builds balance due, method selector, amount field, and Record payment', (tester) async {
    final client = BillingRpcTestClient();

    await _pumpPaymentForm(
      tester,
      client: client,
      invoice: _issuedInvoice(),
      allowPartialPayments: true,
    );

    expect(find.text('Balance due'), findsOneWidget);
    expect(find.text('Method'), findsOneWidget);
    expect(find.text('Amount'), findsOneWidget);
    expect(find.text('Record payment'), findsOneWidget);
    expect(find.text('Cash'), findsOneWidget);
  });

  testWidgets('PaymentForm empty amount shows toast and performs no repository call', (tester) async {
    final client = BillingRpcTestClient();

    await _pumpPaymentForm(
      tester,
      client: client,
      invoice: _issuedInvoice(),
      allowPartialPayments: true,
    );

    await tester.tap(find.text('Record payment'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Enter a payment amount.'), findsOneWidget);
    expect(client.rpcLog, isEmpty);
  });

  testWidgets('PaymentForm valid submit calls notifier and fires onRecorded', (tester) async {
    final client = BillingRpcTestClient();
    var recorded = false;

    await _pumpPaymentForm(
      tester,
      client: client,
      invoice: _issuedInvoice(),
      allowPartialPayments: true,
      onRecorded: () async {
        recorded = true;
      },
    );

    await tester.enterText(find.byType(TextField).first, '50');
    await tester.pump();
<<<<<<< HEAD
    await tester.tap(find.text('Record payment'));
    await tester.pumpAndSettle();
=======
    await tester.tap(find.widgetWithText(AppButton, 'Record payment'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
>>>>>>> master

    expect(recorded, isTrue);
    expect(client.lastFunction, 'record_payment');
    expect(find.text('Payment recorded.'), findsOneWidget);
  });

  testWidgets('PaymentForm locks patient tender amount when partial payments are disabled', (tester) async {
    final client = BillingRpcTestClient();

    await _pumpPaymentForm(
      tester,
      client: client,
      invoice: _issuedInvoice(),
      allowPartialPayments: false,
    );

    expect(
      find.text('Full balance required for this payment method.'),
      findsOneWidget,
    );

    final moneyField = tester.widget<AppMoneyField>(
      find.byKey(const ValueKey('cash-100.00')),
    );
    expect(moneyField.disabled, isTrue);
  });

  testWidgets('PaymentForm does not lock insurance settlement amount', (tester) async {
    final client = BillingRpcTestClient();

    await _pumpPaymentForm(
      tester,
      client: client,
      invoice: _issuedInvoice(),
      allowPartialPayments: false,
    );

    await tester.tap(find.text('Cash'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Insurance'));
    await tester.pumpAndSettle();

    expect(find.text('Full balance required for this payment method.'), findsNothing);

    final moneyField = tester.widget<AppMoneyField>(
      find.byKey(const ValueKey('insuranceSettlement-100.00')),
    );
    expect(moneyField.disabled, isFalse);
  });

  testWidgets('PaymentForm amount field key changes when payment method changes', (tester) async {
    final client = BillingRpcTestClient();

    await _pumpPaymentForm(
      tester,
      client: client,
      invoice: _issuedInvoice(),
      allowPartialPayments: true,
    );

    expect(find.byKey(const ValueKey('cash-100.00')), findsOneWidget);

    await tester.tap(find.text('Cash'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Card'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('card-100.00')), findsOneWidget);
    expect(find.byKey(const ValueKey('cash-100.00')), findsNothing);
  });

  testWidgets('PaymentForm ignores duplicate submits while already submitting', (tester) async {
    final client = BillingRpcTestClient();
    _SlowPaymentNotifier? slowNotifier;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          billingSettingsProvider.overrideWith(
            () => _FixedBillingSettingsNotifier(
              const BillingSettings(allowPartialPayments: true),
            ),
          ),
          paymentRepositoryProvider.overrideWithValue(PaymentRepository(client)),
          paymentNotifierProvider.overrideWith((ref) {
            slowNotifier = _SlowPaymentNotifier(ref);
            return slowNotifier!;
          }),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: AppToastHost(
            child: Scaffold(
              body: PaymentForm(invoice: _issuedInvoice(), onRecorded: () async {}),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, '25');
    await tester.pump();
    await tester.tap(find.text('Record payment'));
    await tester.pump();
    await tester.tap(find.text('Record payment'));
    await tester.pump();

    expect(slowNotifier!.callCount, 1);
  });
}
