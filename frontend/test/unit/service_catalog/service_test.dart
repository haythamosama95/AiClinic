import 'package:ai_clinic/core/money/money.dart';
import 'package:ai_clinic/features/service_catalog/domain/global_status.dart';
import 'package:ai_clinic/features/service_catalog/domain/service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Service.fromRow', () {
    test('parses a valid service row', () {
      final service = Service.fromRow({
        'id': '00000000-0000-4000-8000-000000000101',
        'name': 'Consultation',
        'default_price': '200.00',
        'global_status': 'active',
        'created_at': '2026-01-01T10:00:00.000Z',
        'updated_at': '2026-01-02T10:00:00.000Z',
      });

      expect(service, isNotNull);
      expect(service!.name, 'Consultation');
      expect(service.defaultPrice, Money.parse('200.00'));
      expect(service.globalStatus, GlobalStatus.active);
      expect(service.updatedAt, isNotNull);
    });

    test('returns null for incomplete rows', () {
      expect(Service.fromRow({'id': 'x', 'name': 'Consultation'}), isNull);
      expect(
        Service.fromRow({
          'id': 'x',
          'name': 'Consultation',
          'default_price': 'bad',
          'global_status': 'active',
          'created_at': '2026-01-01T10:00:00.000Z',
        }),
        isNull,
      );
    });
  });
}
