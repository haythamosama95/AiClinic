import 'package:ai_clinic/features/billing/domain/money.dart';
import 'package:ai_clinic/features/service_catalog/domain/global_status.dart';
import 'package:ai_clinic/features/service_catalog/domain/service_detail.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const serviceId = '00000000-0000-4000-8000-000000000101';
  const branchId = '00000000-0000-4000-8000-000000000201';

  Map<String, dynamic> validService() => {
        'id': serviceId,
        'name': 'Consultation',
        'default_price': '200.00',
        'global_status': 'active',
        'created_at': '2026-01-01T10:00:00.000Z',
        'updated_at': '2026-01-02T10:00:00.000Z',
      };

  Map<String, dynamic> validBranchRow({String? serviceBranchId}) => {
        'service_branch_id': serviceBranchId ?? '00000000-0000-4000-8000-000000000301',
        'branch_id': branchId,
        'status': 'active',
      };

  group('ServiceDetail.fromRpcData', () {
    test('parses valid service with branches', () {
      final detail = ServiceDetail.fromRpcData({
        'service': validService(),
        'branches': [
          validBranchRow(),
          validBranchRow(serviceBranchId: '00000000-0000-4000-8000-000000000302'),
        ],
      });

      expect(detail, isNotNull);
      expect(detail!.service.id, serviceId);
      expect(detail.service.name, 'Consultation');
      expect(detail.service.defaultPrice, Money.parse('200.00'));
      expect(detail.service.globalStatus, GlobalStatus.active);
      expect(detail.branches.length, 2);
      expect(detail.branches.first.branchId, branchId);
    });

    test('returns null for null data', () {
      expect(ServiceDetail.fromRpcData(null), isNull);
    });

    test('returns null when service is missing or not a Map', () {
      expect(ServiceDetail.fromRpcData({'branches': []}), isNull);
      expect(ServiceDetail.fromRpcData({'service': 'not-a-map'}), isNull);
    });

    test('returns null when service row is invalid', () {
      expect(
        ServiceDetail.fromRpcData({
          'service': {'id': serviceId},
          'branches': [],
        }),
        isNull,
      );
    });

    test('skips invalid branch rows and keeps valid ones', () {
      final detail = ServiceDetail.fromRpcData({
        'service': validService(),
        'branches': [
          validBranchRow(),
          {'branch_id': branchId},
          'not-a-map',
          validBranchRow(serviceBranchId: '00000000-0000-4000-8000-000000000303'),
        ],
      });

      expect(detail!.branches.length, 2);
    });

    test('parses branches from generic Map entries', () {
      final detail = ServiceDetail.fromRpcData({
        'service': validService(),
        'branches': [
          Map<Object, Object>.from({
            'service_branch_id': '00000000-0000-4000-8000-000000000301',
            'branch_id': branchId,
            'status': 'inactive',
          }),
        ],
      });

      expect(detail!.branches.length, 1);
      expect(detail.branches.first.status, 'inactive');
    });

    test('returns empty branches when branches list is absent', () {
      final detail = ServiceDetail.fromRpcData({'service': validService()});

      expect(detail!.branches, isEmpty);
    });
  });
}
