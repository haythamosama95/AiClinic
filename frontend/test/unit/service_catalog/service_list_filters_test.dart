import 'package:ai_clinic/features/service_catalog/domain/global_status.dart';
import 'package:ai_clinic/features/service_catalog/presentation/models/service_list_filters.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ServiceListFilters', () {
    test('offset derives from page and pageSize', () {
      const filters = ServiceListFilters(page: 3, pageSize: 25);
      expect(filters.offset, 50);
    });

    test('hasActiveFilters detects query, status, and branch', () {
      expect(const ServiceListFilters().hasActiveFilters, isFalse);
      expect(const ServiceListFilters(query: 'consult').hasActiveFilters, isTrue);
      expect(const ServiceListFilters(globalStatus: GlobalStatus.inactive).hasActiveFilters, isTrue);
      expect(const ServiceListFilters(branchId: 'branch-1').hasActiveFilters, isTrue);
    });

    test('toRpcParams includes only active filters', () {
      const filters = ServiceListFilters(
        query: 'consult',
        globalStatus: GlobalStatus.inactive,
        branchId: 'branch-1',
        page: 2,
        pageSize: 10,
      );

      expect(filters.toRpcParams(), {
        'p_query': 'consult',
        'p_global_status': 'inactive',
        'p_branch_id': 'branch-1',
        'p_limit': 10,
        'p_offset': 10,
      });
    });
  });
}
