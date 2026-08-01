import 'package:ai_clinic/features/billing/domain/money.dart';
import 'package:ai_clinic/features/clinic-management/presentation/models/service_form_values.dart';
import 'package:ai_clinic/features/service_catalog/domain/global_status.dart';
import 'package:ai_clinic/features/service_catalog/domain/service.dart';
import 'package:ai_clinic/features/service_catalog/domain/service_detail.dart';
import 'package:ai_clinic/features/service_catalog/domain/service_list_item.dart';
import 'package:flutter_test/flutter_test.dart';

ServiceListItem _sampleServiceListItem({Money? defaultPrice}) {
  return ServiceListItem(
    serviceId: 'svc-1',
    name: 'Consultation',
    defaultPrice: defaultPrice ?? Money.parse('150.00'),
    globalStatus: GlobalStatus.active,
    assignedBranchCount: 2,
    updatedAt: DateTime.utc(2026, 1, 15),
  );
}

ServiceDetail _sampleServiceDetail({Money? defaultPrice}) {
  return ServiceDetail(
    service: Service(
      id: 'svc-1',
      name: 'X-Ray',
      defaultPrice: defaultPrice ?? Money.parse('80.50'),
      globalStatus: GlobalStatus.active,
      createdAt: DateTime.utc(2026, 1, 1),
    ),
    branches: const [],
  );
}

void main() {
  group('emptyServiceFormValues', () {
    test('returns empty name and null price', () {
      final values = emptyServiceFormValues();

      expect(values.name, '');
      expect(values.price, isNull);
    });
  });

  group('serviceListItemToFormValues', () {
    test('maps name and non-zero default price', () {
      final values = serviceListItemToFormValues(_sampleServiceListItem());

      expect(values.name, 'Consultation');
      expect(values.price, 150.0);
    });

    test('clears price when default price is zero', () {
      final values = serviceListItemToFormValues(_sampleServiceListItem(defaultPrice: Money.zero));

      expect(values.name, 'Consultation');
      expect(values.price, isNull);
    });
  });

  group('serviceDetailToFormValues', () {
    test('maps nested service fields', () {
      final values = serviceDetailToFormValues(_sampleServiceDetail());

      expect(values.name, 'X-Ray');
      expect(values.price, 80.5);
    });
  });

  group('priceToWire', () {
    test('formats price with two decimal places', () {
      expect(priceToWire(12.3), '12.30');
      expect(priceToWire(99.999), '100.00');
    });
  });

  group('validateServiceFormValues', () {
    test('returns no errors for valid values', () {
      const values = ServiceFormValues(name: 'Consultation', price: 100);

      expect(validateServiceFormValues(values), isEmpty);
    });

    test('requires service name', () {
      const values = ServiceFormValues(name: '   ', price: 50);

      final errors = validateServiceFormValues(values);

      expect(errors['name'], 'Service name is required');
    });

    test('requires default price and rejects negative values', () {
      expect(validateServiceFormValues(const ServiceFormValues(name: 'A'))['price'], 'Default price is required');

      const negative = ServiceFormValues(name: 'A', price: -1);
      expect(validateServiceFormValues(negative)['price'], 'Price must be zero or greater');
    });

    test('allows zero price', () {
      const values = ServiceFormValues(name: 'Free check', price: 0);

      expect(validateServiceFormValues(values), isEmpty);
    });
  });
}
