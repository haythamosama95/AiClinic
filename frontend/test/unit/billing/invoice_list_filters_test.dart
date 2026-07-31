import 'package:ai_clinic/core/ui/components/app_data_table.dart';
import 'package:ai_clinic/features/billing/presentation/models/invoice_list_filters.dart';
import 'package:ai_clinic/features/billing/presentation/models/invoice_sort_key.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('InvoiceListFilters defaults', () {
    test('uses expected initial values', () {
      const filters = InvoiceListFilters();

      expect(filters.statuses, isEmpty);
      expect(filters.patientSearch, '');
      expect(filters.invoiceNumber, '');
      expect(filters.branchId, isNull);
      expect(filters.dateFrom, isNull);
      expect(filters.dateTo, isNull);
      expect(filters.sortField, isNull);
      expect(filters.sortDirection, SortDirection.desc);
      expect(filters.page, 1);
      expect(filters.pageSize, 10);
    });
  });

  group('InvoiceListFilters.offset', () {
    test('page 1 yields zero offset', () {
      const filters = InvoiceListFilters(page: 1, pageSize: 10);

      expect(filters.offset, 0);
    });

    test('computes offset from page and pageSize', () {
      const filters = InvoiceListFilters(page: 3, pageSize: 25);

      expect(filters.offset, 50);
    });
  });

  group('InvoiceListFilters.hasActiveFilters', () {
    test('is false when every filter field is empty', () {
      const filters = InvoiceListFilters();

      expect(filters.hasActiveFilters, isFalse);
    });

    test('is true when statuses are set', () {
      const filters = InvoiceListFilters(statuses: ['issued']);

      expect(filters.hasActiveFilters, isTrue);
    });

    test('is true when trimmed patientSearch is non-empty', () {
      const filters = InvoiceListFilters(patientSearch: '  alice  ');

      expect(filters.hasActiveFilters, isTrue);
    });

    test('is false when patientSearch is whitespace only', () {
      const filters = InvoiceListFilters(patientSearch: '   ');

      expect(filters.hasActiveFilters, isFalse);
    });

    test('is true when trimmed invoiceNumber is non-empty', () {
      const filters = InvoiceListFilters(invoiceNumber: ' INV-1 ');

      expect(filters.hasActiveFilters, isTrue);
    });

    test('is false when invoiceNumber is whitespace only', () {
      const filters = InvoiceListFilters(invoiceNumber: '  ');

      expect(filters.hasActiveFilters, isFalse);
    });

    test('is true when branchId is set', () {
      const filters = InvoiceListFilters(branchId: 'branch-1');

      expect(filters.hasActiveFilters, isTrue);
    });

    test('is true when dateFrom is set', () {
      final filters = InvoiceListFilters(dateFrom: DateTime.utc(2026, 1, 1));

      expect(filters.hasActiveFilters, isTrue);
    });

    test('is true when dateTo is set', () {
      final filters = InvoiceListFilters(dateTo: DateTime.utc(2026, 12, 31));

      expect(filters.hasActiveFilters, isTrue);
    });
  });

  group('InvoiceListFilters.toRpcFilters', () {
    const branchA = '00000000-0000-4000-8000-000000000001';
    const branchB = '00000000-0000-4000-8000-000000000002';
    const explicitBranch = '00000000-0000-4000-8000-000000000099';

    test('includes session branchIds when provided', () {
      const filters = InvoiceListFilters();

      final rpc = filters.toRpcFilters(branchIds: [branchA, branchB]);

      expect(rpc['branch_ids'], [branchA, branchB]);
    });

    test('explicit branchId overrides session branchIds', () {
      const filters = InvoiceListFilters(branchId: explicitBranch);

      final rpc = filters.toRpcFilters(branchIds: [branchA, branchB]);

      expect(rpc['branch_ids'], [explicitBranch]);
    });

    test('trims patientSearch and invoiceNumber', () {
      const filters = InvoiceListFilters(
        patientSearch: '  patient  ',
        invoiceNumber: ' INV-42 ',
        statuses: ['issued'],
      );

      final rpc = filters.toRpcFilters();

      expect(rpc['patient_search'], 'patient');
      expect(rpc['invoice_number'], 'INV-42');
      expect(rpc['statuses'], ['issued']);
    });

    test('emits date_from and date_to as UTC ISO8601 strings', () {
      final localFrom = DateTime(2026, 6, 15, 10, 30);
      final localTo = DateTime(2026, 6, 20, 18, 0);
      final filters = InvoiceListFilters(dateFrom: localFrom, dateTo: localTo);

      final rpc = filters.toRpcFilters();

      expect(rpc['date_from'], localFrom.toUtc().toIso8601String());
      expect(rpc['date_to'], localTo.toUtc().toIso8601String());
    });

    test('omits sort_field and sort_direction when sortField is null', () {
      const filters = InvoiceListFilters(sortDirection: SortDirection.asc);

      final rpc = filters.toRpcFilters();

      expect(rpc.containsKey('sort_field'), isFalse);
      expect(rpc.containsKey('sort_direction'), isFalse);
    });

    test('includes sort_field and sort_direction when sortField is set', () {
      const filters = InvoiceListFilters(
        sortField: InvoiceSortField.balance,
        sortDirection: SortDirection.asc,
      );

      final rpc = filters.toRpcFilters();

      expect(rpc['sort_field'], 'balance');
      expect(rpc['sort_direction'], 'asc');
    });
  });

  group('InvoiceListFilters.copyWith', () {
    test('clearBranchId resets branchId while null without flag preserves it', () {
      const filters = InvoiceListFilters(branchId: 'branch-1');

      expect(filters.copyWith(branchId: null).branchId, 'branch-1');
      expect(filters.copyWith(clearBranchId: true).branchId, isNull);
    });

    test('clearDateFrom resets dateFrom while null without flag preserves it', () {
      final date = DateTime.utc(2026, 1, 1);
      final filters = InvoiceListFilters(dateFrom: date);

      expect(filters.copyWith(dateFrom: null).dateFrom, date);
      expect(filters.copyWith(clearDateFrom: true).dateFrom, isNull);
    });

    test('clearDateTo resets dateTo while null without flag preserves it', () {
      final date = DateTime.utc(2026, 12, 31);
      final filters = InvoiceListFilters(dateTo: date);

      expect(filters.copyWith(dateTo: null).dateTo, date);
      expect(filters.copyWith(clearDateTo: true).dateTo, isNull);
    });

    test('clearSortField resets sortField while null without flag preserves it', () {
      const filters = InvoiceListFilters(sortField: InvoiceSortField.subtotal);

      expect(filters.copyWith(sortField: null).sortField, InvoiceSortField.subtotal);
      expect(filters.copyWith(clearSortField: true).sortField, isNull);
    });
  });
}
