import 'package:ai_clinic/core/ui/components/app_data_table.dart';
import 'package:ai_clinic/features/billing/domain/invoice_list_item.dart';
import 'package:ai_clinic/features/billing/domain/invoice_status.dart';
import 'package:ai_clinic/features/billing/domain/money.dart';
import 'package:ai_clinic/features/billing/presentation/models/invoice_list_filters.dart';
import 'package:ai_clinic/features/billing/presentation/models/invoice_sort_key.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('InvoiceSortKey.backendSort', () {
    test('maps every sort key to backend field and direction', () {
      expect(
        InvoiceSortKey.dateDesc.backendSort,
        (InvoiceSortField.createdAt, SortDirection.desc),
      );
      expect(
        InvoiceSortKey.dateAsc.backendSort,
        (InvoiceSortField.createdAt, SortDirection.asc),
      );
      expect(
        InvoiceSortKey.balanceDesc.backendSort,
        (InvoiceSortField.balance, SortDirection.desc),
      );
      expect(
        InvoiceSortKey.balanceAsc.backendSort,
        (InvoiceSortField.balance, SortDirection.asc),
      );
      expect(
        InvoiceSortKey.amountDesc.backendSort,
        (InvoiceSortField.subtotal, SortDirection.desc),
      );
      expect(
        InvoiceSortKey.amountAsc.backendSort,
        (InvoiceSortField.subtotal, SortDirection.asc),
      );
    });
  });

  group('InvoiceSortKey.tryParse', () {
    test('parses valid values case-insensitively', () {
      expect(InvoiceSortKey.tryParse('date-desc'), InvoiceSortKey.dateDesc);
      expect(InvoiceSortKey.tryParse(' BALANCE-ASC '), InvoiceSortKey.balanceAsc);
    });

    test('returns null for unknown values', () {
      expect(InvoiceSortKey.tryParse('unknown-sort'), isNull);
    });

    test('returns null for empty and whitespace-only values', () {
      expect(InvoiceSortKey.tryParse(''), isNull);
      expect(InvoiceSortKey.tryParse('   '), isNull);
    });

    test('returns null for null input', () {
      expect(InvoiceSortKey.tryParse(null), isNull);
    });
  });

  group('InvoiceSortKey.fromFilters', () {
    test('maps all six field and direction combinations', () {
      expect(
        InvoiceSortKey.fromFilters(
          const InvoiceListFilters(sortField: InvoiceSortField.createdAt, sortDirection: SortDirection.asc),
        ),
        InvoiceSortKey.dateAsc,
      );
      expect(
        InvoiceSortKey.fromFilters(
          const InvoiceListFilters(sortField: InvoiceSortField.balance, sortDirection: SortDirection.desc),
        ),
        InvoiceSortKey.balanceDesc,
      );
      expect(
        InvoiceSortKey.fromFilters(
          const InvoiceListFilters(sortField: InvoiceSortField.balance, sortDirection: SortDirection.asc),
        ),
        InvoiceSortKey.balanceAsc,
      );
      expect(
        InvoiceSortKey.fromFilters(
          const InvoiceListFilters(sortField: InvoiceSortField.subtotal, sortDirection: SortDirection.desc),
        ),
        InvoiceSortKey.amountDesc,
      );
      expect(
        InvoiceSortKey.fromFilters(
          const InvoiceListFilters(sortField: InvoiceSortField.subtotal, sortDirection: SortDirection.asc),
        ),
        InvoiceSortKey.amountAsc,
      );
      expect(
        InvoiceSortKey.fromFilters(
          const InvoiceListFilters(sortField: InvoiceSortField.createdAt, sortDirection: SortDirection.desc),
        ),
        InvoiceSortKey.dateDesc,
      );
    });

    test('falls back to dateDesc for createdAt desc (default switch arm)', () {
      expect(
        InvoiceSortKey.fromFilters(
          const InvoiceListFilters(sortField: InvoiceSortField.createdAt, sortDirection: SortDirection.desc),
        ),
        InvoiceSortKey.dateDesc,
      );
    });

    test('falls back to dateDesc when sortField is null', () {
      expect(InvoiceSortKey.fromFilters(const InvoiceListFilters()), InvoiceSortKey.dateDesc);
    });
  });

  group('SortDirection.wireValue', () {
    test('maps asc and desc to wire strings', () {
      expect(SortDirection.asc.wireValue, 'asc');
      expect(SortDirection.desc.wireValue, 'desc');
    });
  });

  group('sortInvoiceListItemsClientSide', () {
    test('returns the list unchanged when sortField is null', () {
      final items = [
        _invoiceItem(id: 'a', createdAt: DateTime.utc(2026, 1, 2)),
        _invoiceItem(id: 'b', createdAt: DateTime.utc(2026, 1, 1)),
      ];

      final sorted = sortInvoiceListItemsClientSide(items, const InvoiceListFilters());

      expect(sorted, items);
      expect(sorted.map((item) => item.id).toList(), ['a', 'b']);
    });

    test('sorts createdAt ascending and descending', () {
      final items = [
        _invoiceItem(id: 'newest', createdAt: DateTime.utc(2026, 3, 1)),
        _invoiceItem(id: 'oldest', createdAt: DateTime.utc(2026, 1, 1)),
        _invoiceItem(id: 'middle', createdAt: DateTime.utc(2026, 2, 1)),
      ];

      final asc = sortInvoiceListItemsClientSide(
        items,
        const InvoiceListFilters(sortField: InvoiceSortField.createdAt, sortDirection: SortDirection.asc),
      );
      final desc = sortInvoiceListItemsClientSide(
        items,
        const InvoiceListFilters(sortField: InvoiceSortField.createdAt, sortDirection: SortDirection.desc),
      );

      expect(asc.map((item) => item.id).toList(), ['oldest', 'middle', 'newest']);
      expect(desc.map((item) => item.id).toList(), ['newest', 'middle', 'oldest']);
    });

    test('sorts balance ascending and descending', () {
      final items = [
        _invoiceItem(id: 'high', balance: '300.00'),
        _invoiceItem(id: 'low', balance: '10.00'),
        _invoiceItem(id: 'mid', balance: '150.00'),
      ];

      final asc = sortInvoiceListItemsClientSide(
        items,
        const InvoiceListFilters(sortField: InvoiceSortField.balance, sortDirection: SortDirection.asc),
      );
      final desc = sortInvoiceListItemsClientSide(
        items,
        const InvoiceListFilters(sortField: InvoiceSortField.balance, sortDirection: SortDirection.desc),
      );

      expect(asc.map((item) => item.id).toList(), ['low', 'mid', 'high']);
      expect(desc.map((item) => item.id).toList(), ['high', 'mid', 'low']);
    });

    test('sorts subtotal ascending and descending', () {
      final items = [
        _invoiceItem(id: 'high', subtotal: '500.00'),
        _invoiceItem(id: 'low', subtotal: '25.00'),
        _invoiceItem(id: 'mid', subtotal: '200.00'),
      ];

      final asc = sortInvoiceListItemsClientSide(
        items,
        const InvoiceListFilters(sortField: InvoiceSortField.subtotal, sortDirection: SortDirection.asc),
      );
      final desc = sortInvoiceListItemsClientSide(
        items,
        const InvoiceListFilters(sortField: InvoiceSortField.subtotal, sortDirection: SortDirection.desc),
      );

      expect(asc.map((item) => item.id).toList(), ['low', 'mid', 'high']);
      expect(desc.map((item) => item.id).toList(), ['high', 'mid', 'low']);
    });

    test('preserves input order for equal sort keys', () {
      final items = [
        _invoiceItem(id: 'first', balance: '50.00'),
        _invoiceItem(id: 'second', balance: '50.00'),
        _invoiceItem(id: 'third', balance: '50.00'),
      ];

      final sorted = sortInvoiceListItemsClientSide(
        items,
        const InvoiceListFilters(sortField: InvoiceSortField.balance, sortDirection: SortDirection.asc),
      );

      expect(sorted.map((item) => item.id).toList(), ['first', 'second', 'third']);
    });
  });
}

InvoiceListItem _invoiceItem({
  required String id,
  DateTime? createdAt,
  String balance = '100.00',
  String subtotal = '100.00',
}) {
  return InvoiceListItem(
    id: id,
    status: InvoiceStatus.issued,
    subtotal: Money.parse(subtotal),
    discountAmount: Money.zero,
    insuranceCoveredAmount: Money.zero,
    paidAmount: Money.zero,
    balance: Money.parse(balance),
    createdAt: createdAt ?? DateTime.utc(2026, 1, 1),
    currency: 'USD',
  );
}
