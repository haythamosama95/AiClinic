import 'package:ai_clinic/features/billing/domain/money.dart';
import 'package:ai_clinic/features/service_catalog/domain/global_status.dart';
import 'package:ai_clinic/features/service_catalog/domain/service_list_item.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const validServiceId = '00000000-0000-4000-8000-000000000101';

  Map<String, dynamic> validRow({Map<String, dynamic>? branchSummary}) {
    return {
      'service_id': validServiceId,
      'name': 'Consultation',
      'default_price': '200.00',
      'global_status': 'active',
      'assigned_branch_count': 3,
      'updated_at': '2026-01-02T10:00:00.000Z',
      if (branchSummary != null) 'branch_summary': branchSummary,
    };
  }

  group('ServiceBranchSummary.fromRow', () {
    test('parses a valid branch summary', () {
      final summary = ServiceBranchSummary.fromRow({
        'status': 'active',
        'effective_price': '150.00',
        'on_promotion': true,
      });

      expect(summary, isNotNull);
      expect(summary!.status, 'active');
      expect(summary.effectivePrice, Money.parse('150.00'));
      expect(summary.onPromotion, isTrue);
    });

    test('returns null for null input', () {
      expect(ServiceBranchSummary.fromRow(null), isNull);
    });

    test('returns null when status or price is missing or invalid', () {
      expect(ServiceBranchSummary.fromRow({'effective_price': '100.00'}), isNull);
      expect(ServiceBranchSummary.fromRow({'status': 'active'}), isNull);
      expect(
        ServiceBranchSummary.fromRow({'status': '', 'effective_price': '100.00'}),
        isNull,
      );
      expect(
        ServiceBranchSummary.fromRow({'status': 'active', 'effective_price': 'bad'}),
        isNull,
      );
    });

    test('on_promotion defaults to false when absent', () {
      final summary = ServiceBranchSummary.fromRow({
        'status': 'active',
        'effective_price': '100.00',
      });

      expect(summary!.onPromotion, isFalse);
    });
  });

  group('ServiceListItem.fromRow', () {
    test('parses a valid row without branch_summary', () {
      final item = ServiceListItem.fromRow(validRow());

      expect(item, isNotNull);
      expect(item!.serviceId, validServiceId);
      expect(item.name, 'Consultation');
      expect(item.defaultPrice, Money.parse('200.00'));
      expect(item.globalStatus, GlobalStatus.active);
      expect(item.assignedBranchCount, 3);
      expect(item.updatedAt, DateTime.parse('2026-01-02T10:00:00.000Z'));
      expect(item.branchSummary, isNull);
    });

    test('parses branch_summary as Map<String, dynamic>', () {
      final item = ServiceListItem.fromRow(
        validRow(
          branchSummary: {
            'status': 'active',
            'effective_price': '175.00',
            'on_promotion': false,
          },
        ),
      );

      expect(item!.branchSummary, isNotNull);
      expect(item.branchSummary!.status, 'active');
      expect(item.branchSummary!.effectivePrice, Money.parse('175.00'));
      expect(item.branchSummary!.onPromotion, isFalse);
    });

    test('parses branch_summary from generic Map', () {
      final row = validRow();
      row['branch_summary'] = Map<Object, Object>.from({
        'status': 'inactive',
        'effective_price': '200.00',
        'on_promotion': true,
      });
      final item = ServiceListItem.fromRow(row);

      expect(item!.branchSummary, isNotNull);
      expect(item.branchSummary!.status, 'inactive');
      expect(item.branchSummary!.onPromotion, isTrue);
    });

    test('returns null when required fields are missing', () {
      expect(ServiceListItem.fromRow({'name': 'Consultation'}), isNull);
      expect(
        ServiceListItem.fromRow({
          'service_id': validServiceId,
          'name': 'Consultation',
          'default_price': '200.00',
          'global_status': 'active',
        }),
        isNull,
      );
    });

    test('returns null for bad price, status, or dates', () {
      expect(
        ServiceListItem.fromRow(validRow()..['default_price'] = 'bad'),
        isNull,
      );
      expect(
        ServiceListItem.fromRow(validRow()..['global_status'] = 'unknown'),
        isNull,
      );
      expect(
        ServiceListItem.fromRow(validRow()..['updated_at'] = 'not-a-date'),
        isNull,
      );
    });

    test('returns null when assigned_branch_count is not numeric', () {
      expect(
        ServiceListItem.fromRow(validRow()..['assigned_branch_count'] = 'three'),
        isNull,
      );
    });
  });
}
