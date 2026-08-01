import 'package:ai_clinic/features/billing/domain/invoice_status.dart';
import 'package:ai_clinic/features/billing/presentation/models/invoice_list_controls.dart';
import 'package:ai_clinic/features/billing/presentation/models/invoice_list_filters.dart';
import 'package:ai_clinic/features/billing/presentation/models/invoice_sort_key.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('InvoiceListControls.copyWith', () {
    test('clearing status via null requires clearStatus flag', () {
      const controls = InvoiceListControls(status: InvoiceStatus.issued);

      expect(
        controls.copyWith(status: null).status,
        InvoiceStatus.issued,
        reason: 'nullable copyWith fields must use clearStatus to reset',
      );
      expect(controls.copyWith(clearStatus: true).status, isNull);
    });

    test('replacing status with another value works', () {
      const controls = InvoiceListControls(status: InvoiceStatus.issued);

      expect(
        controls.copyWith(status: InvoiceStatus.paid).status,
        InvoiceStatus.paid,
      );
    });

    test('clearing branch via null requires clearBranch flag', () {
      const controls = InvoiceListControls(branch: 'branch-1');

      expect(
        controls.copyWith(branch: null).branch,
        'branch-1',
        reason: 'nullable copyWith fields must use clearBranch to reset',
      );
      expect(controls.copyWith(clearBranch: true).branch, isNull);
    });
  });

  group('InvoiceListControls backend mapping', () {
    const branchId = '00000000-0000-4000-8000-000000000099';

    test('toBackendFilters and fromBackendFilters round-trip', () {
      const controls = InvoiceListControls(
        search: 'patient query',
        status: InvoiceStatus.partiallyPaid,
        branch: branchId,
        sort: InvoiceSortKey.balanceAsc,
        page: 2,
        pageSize: 25,
      );

      final backend = controls.toBackendFilters(multiBranch: true);
      final roundTrip = InvoiceListControls.fromBackendFilters(backend);

      expect(roundTrip.search, controls.search);
      expect(roundTrip.status, controls.status);
      expect(roundTrip.branch, controls.branch);
      expect(roundTrip.sort, controls.sort);
      expect(roundTrip.page, controls.page);
      expect(roundTrip.pageSize, controls.pageSize);
    });

    test('toBackendFilters drops branch when multiBranch is false', () {
      const controls = InvoiceListControls(branch: branchId, status: InvoiceStatus.issued);

      final backend = controls.toBackendFilters(multiBranch: false);

      expect(backend.branchId, isNull);
      expect(backend.statuses, ['issued']);
    });

    test('fromBackendFilters maps only the first status', () {
      const filters = InvoiceListFilters(statuses: ['issued', 'paid']);

      final controls = InvoiceListControls.fromBackendFilters(filters);

      expect(controls.status, InvoiceStatus.issued);
    });

    test('fromBackendFilters yields null status for unknown status strings', () {
      const filters = InvoiceListFilters(statuses: ['not-a-real-status']);

      final controls = InvoiceListControls.fromBackendFilters(filters);

      expect(controls.status, isNull);
    });
  });

  group('InvoiceListControls filter indicators', () {
    test('isFiltered is true when search, status, branch, or custom sort is set', () {
      expect(const InvoiceListControls().isFiltered, isFalse);
      expect(const InvoiceListControls(search: '  query ').isFiltered, isTrue);
      expect(const InvoiceListControls(status: InvoiceStatus.draft).isFiltered, isTrue);
      expect(const InvoiceListControls(branch: 'branch-1').isFiltered, isTrue);
      expect(const InvoiceListControls(sort: InvoiceSortKey.balanceDesc).sortIsCustom, isTrue);
      expect(const InvoiceListControls(sort: InvoiceSortKey.balanceDesc).isFiltered, isTrue);
    });

    test('filterActiveCount counts status and branch only', () {
      expect(const InvoiceListControls().filterActiveCount, 0);
      expect(const InvoiceListControls(status: InvoiceStatus.issued).filterActiveCount, 1);
      expect(const InvoiceListControls(branch: 'branch-1').filterActiveCount, 1);
      expect(
        const InvoiceListControls(
          search: 'needle',
          status: InvoiceStatus.paid,
          branch: 'branch-1',
          sort: InvoiceSortKey.amountAsc,
        ).filterActiveCount,
        2,
      );
    });
  });

  group('InvoiceListControls.activeFilters', () {
    test('builds chips for status, branch (multi-branch only), and search', () {
      const controls = InvoiceListControls(
        search: '  alice  ',
        status: InvoiceStatus.issued,
        branch: 'branch-1',
      );
      var statusRemoved = false;
      var branchRemoved = false;
      var searchRemoved = false;

      final chips = controls.activeFilters(
        multiBranch: true,
        branchName: (id) => 'Branch $id',
        onRemoveStatus: () => statusRemoved = true,
        onRemoveBranch: () => branchRemoved = true,
        onRemoveSearch: () => searchRemoved = true,
      );

      expect(chips, hasLength(3));
      expect(chips[0].id, 'status');
      expect(chips[0].label, InvoiceStatus.issued.label);
      expect(chips[1].id, 'branch');
      expect(chips[1].label, 'Branch branch-1');
      expect(chips[2].id, 'search');
      expect(chips[2].label, 'Search: alice');

      chips[0].onRemove();
      chips[1].onRemove();
      chips[2].onRemove();
      expect(statusRemoved, isTrue);
      expect(branchRemoved, isTrue);
      expect(searchRemoved, isTrue);
    });

    test('omits branch chip when multiBranch is false', () {
      const controls = InvoiceListControls(branch: 'branch-1', search: 'bob');

      final chips = controls.activeFilters(
        multiBranch: false,
        branchName: (id) => id,
        onRemoveStatus: () {},
        onRemoveBranch: () {},
        onRemoveSearch: () {},
      );

      expect(chips.map((chip) => chip.id).toList(), ['search']);
    });
  });

  group('InvoiceListControls equality', () {
    test('== and hashCode include every field', () {
      const left = InvoiceListControls(
        search: 'query',
        status: InvoiceStatus.paid,
        branch: 'branch-1',
        sort: InvoiceSortKey.amountDesc,
        page: 2,
        pageSize: 25,
      );
      const right = InvoiceListControls(
        search: 'query',
        status: InvoiceStatus.paid,
        branch: 'branch-1',
        sort: InvoiceSortKey.amountDesc,
        page: 2,
        pageSize: 25,
      );
      const different = InvoiceListControls(
        search: 'query',
        status: InvoiceStatus.paid,
        branch: 'branch-1',
        sort: InvoiceSortKey.amountDesc,
        page: 3,
        pageSize: 25,
      );

      expect(left, right);
      expect(left.hashCode, right.hashCode);
      expect(left == different, isFalse);
    });
  });
}
