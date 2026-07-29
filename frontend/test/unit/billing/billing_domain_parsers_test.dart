import 'package:ai_clinic/features/billing/domain/billing_settings.dart';
import 'package:ai_clinic/features/billing/domain/discount_kind.dart';
import 'package:ai_clinic/features/billing/domain/insurance_provider.dart';
import 'package:ai_clinic/features/billing/domain/invoice_item.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> validInvoiceItemRow({
  Map<String, dynamic>? overrides,
}) {
  return {
    'id': 'item-1',
    'description': 'Consultation',
    'quantity': '2',
    'unit_price': '50.00',
    'line_subtotal': '100.00',
    'line_discount_amount': '0.00',
    'line_total': '100.00',
    ...?overrides,
  };
}

void main() {
  group('BillingSettings.fromRow', () {
    test('parses true bool as allowPartialPayments', () {
      final settings = BillingSettings.fromRow({'allow_partial_payments': true});
      expect(settings, isNotNull);
      expect(settings!.allowPartialPayments, isTrue);
    });

    test('parses "true" string as allowPartialPayments', () {
      final settings = BillingSettings.fromRow({'allow_partial_payments': 'true'});
      expect(settings!.allowPartialPayments, isTrue);
    });

    test('parses false bool as allowPartialPayments', () {
      final settings = BillingSettings.fromRow({'allow_partial_payments': false});
      expect(settings!.allowPartialPayments, isFalse);
    });

    test('parses "false" string as allowPartialPayments', () {
      final settings = BillingSettings.fromRow({'allow_partial_payments': 'false'});
      expect(settings!.allowPartialPayments, isFalse);
    });

    test('parses 0 as allowPartialPayments false', () {
      final settings = BillingSettings.fromRow({'allow_partial_payments': 0});
      expect(settings!.allowPartialPayments, isFalse);
    });

    test('returns null when key is missing', () {
      expect(BillingSettings.fromRow({}), isNull);
    });
  });

  group('InsuranceProvider.fromRow', () {
    test('parses valid row', () {
      final provider = InsuranceProvider.fromRow({
        'id': 'prov-1',
        'name': 'National Health',
        'is_active': true,
        'contact_info': 'support@health.example',
      });

      expect(provider, isNotNull);
      expect(provider!.id, 'prov-1');
      expect(provider.name, 'National Health');
      expect(provider.isActive, isTrue);
      expect(provider.contactInfo, 'support@health.example');
    });

    test('returns null when id is missing', () {
      expect(
        InsuranceProvider.fromRow({'name': 'National Health'}),
        isNull,
      );
    });

    test('returns null when id is empty', () {
      expect(
        InsuranceProvider.fromRow({'id': '', 'name': 'National Health'}),
        isNull,
      );
    });

    test('returns null when name is whitespace-only', () {
      expect(
        InsuranceProvider.fromRow({'id': 'prov-1', 'name': '   '}),
        isNull,
      );
    });

    test('parses is_active from "true" string', () {
      final provider = InsuranceProvider.fromRow({
        'id': 'prov-1',
        'name': 'National Health',
        'is_active': 'true',
      });

      expect(provider!.isActive, isTrue);
    });

    test('contact_info is optional when present', () {
      final provider = InsuranceProvider.fromRow({
        'id': 'prov-1',
        'name': 'National Health',
        'contact_info': 'phone: 123',
      });

      expect(provider!.contactInfo, 'phone: 123');
    });

    test('contact_info is null when absent', () {
      final provider = InsuranceProvider.fromRow({
        'id': 'prov-1',
        'name': 'National Health',
      });

      expect(provider!.contactInfo, isNull);
    });
  });

  group('InvoiceItem.fromRow', () {
    test('parses valid row', () {
      final item = InvoiceItem.fromRow(validInvoiceItemRow());

      expect(item, isNotNull);
      expect(item!.id, 'item-1');
      expect(item.description, 'Consultation');
      expect(item.quantity, '2');
      expect(item.unitPrice.wireValue, '50.00');
      expect(item.lineSubtotal.wireValue, '100.00');
      expect(item.lineDiscountAmount.wireValue, '0.00');
      expect(item.lineTotal.wireValue, '100.00');
    });

    test('returns null when id is missing', () {
      expect(
        InvoiceItem.fromRow(validInvoiceItemRow(overrides: {'id': null})),
        isNull,
      );
    });

    test('returns null when description is whitespace-only', () {
      expect(
        InvoiceItem.fromRow(validInvoiceItemRow(overrides: {'description': '   '})),
        isNull,
      );
    });

    test('returns null when unit_price is missing', () {
      expect(
        InvoiceItem.fromRow(validInvoiceItemRow(overrides: {'unit_price': null})),
        isNull,
      );
    });

    test('returns null when line_subtotal is missing', () {
      expect(
        InvoiceItem.fromRow(validInvoiceItemRow(overrides: {'line_subtotal': null})),
        isNull,
      );
    });

    test('returns null when line_discount_amount is missing', () {
      expect(
        InvoiceItem.fromRow(validInvoiceItemRow(overrides: {'line_discount_amount': null})),
        isNull,
      );
    });

    test('returns null when line_total is missing', () {
      expect(
        InvoiceItem.fromRow(validInvoiceItemRow(overrides: {'line_total': null})),
        isNull,
      );
    });

    test('defaults quantity to 0 when absent', () {
      final item = InvoiceItem.fromRow(
        validInvoiceItemRow(overrides: {'quantity': null}),
      );

      expect(item!.quantity, '0');
    });

    test('invalid line_discount_kind is null without rejecting row', () {
      final item = InvoiceItem.fromRow(
        validInvoiceItemRow(overrides: {'line_discount_kind': 'bogus'}),
      );

      expect(item, isNotNull);
      expect(item!.lineDiscountKind, isNull);
    });
  });
}
