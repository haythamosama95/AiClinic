import 'package:ai_clinic/core/ui/components/app_data_table.dart';
import 'package:ai_clinic/core/ui/components/app_list_control_bar.dart';
import 'package:ai_clinic/features/billing/domain/invoice_list_item.dart';
import 'package:ai_clinic/features/billing/presentation/models/invoice_list_filters.dart';

/// Server-side sort fields for `list_invoices` (`sort_field` filter key).
enum InvoiceSortField {
  createdAt,
  balance,
  subtotal;

  String get wireValue => switch (this) {
    InvoiceSortField.createdAt => 'created_at',
    InvoiceSortField.balance => 'balance',
    InvoiceSortField.subtotal => 'subtotal',
  };
}

/// UI sort keys for the invoices list (web `InvoiceSortKey`).
enum InvoiceSortKey {
  dateDesc,
  dateAsc,
  balanceDesc,
  balanceAsc,
  amountDesc,
  amountAsc;

  String get value => switch (this) {
    InvoiceSortKey.dateDesc => 'date-desc',
    InvoiceSortKey.dateAsc => 'date-asc',
    InvoiceSortKey.balanceDesc => 'balance-desc',
    InvoiceSortKey.balanceAsc => 'balance-asc',
    InvoiceSortKey.amountDesc => 'amount-desc',
    InvoiceSortKey.amountAsc => 'amount-asc',
  };

  String get label => switch (this) {
    InvoiceSortKey.dateDesc => 'Created (newest)',
    InvoiceSortKey.dateAsc => 'Created (oldest)',
    InvoiceSortKey.balanceDesc => 'Remaining (highest)',
    InvoiceSortKey.balanceAsc => 'Remaining (lowest)',
    InvoiceSortKey.amountDesc => 'Subtotal (highest)',
    InvoiceSortKey.amountAsc => 'Subtotal (lowest)',
  };

  (InvoiceSortField field, SortDirection direction)
  get backendSort => switch (this) {
    InvoiceSortKey.dateDesc => (InvoiceSortField.createdAt, SortDirection.desc),
    InvoiceSortKey.dateAsc => (InvoiceSortField.createdAt, SortDirection.asc),
    InvoiceSortKey.balanceDesc => (
      InvoiceSortField.balance,
      SortDirection.desc,
    ),
    InvoiceSortKey.balanceAsc => (InvoiceSortField.balance, SortDirection.asc),
    InvoiceSortKey.amountDesc => (
      InvoiceSortField.subtotal,
      SortDirection.desc,
    ),
    InvoiceSortKey.amountAsc => (InvoiceSortField.subtotal, SortDirection.asc),
  };

  static InvoiceSortKey? tryParse(String? value) {
    final normalized = value?.trim().toLowerCase();
    if (normalized == null || normalized.isEmpty) {
      return null;
    }
    for (final key in InvoiceSortKey.values) {
      if (key.value == normalized) {
        return key;
      }
    }
    return null;
  }

  static InvoiceSortKey fromFilters(InvoiceListFilters filters) {
    final field = filters.sortField ?? InvoiceSortField.createdAt;
    final direction = filters.sortDirection;

    return switch ((field, direction)) {
      (InvoiceSortField.createdAt, SortDirection.asc) => InvoiceSortKey.dateAsc,
      (InvoiceSortField.balance, SortDirection.desc) =>
        InvoiceSortKey.balanceDesc,
      (InvoiceSortField.balance, SortDirection.asc) =>
        InvoiceSortKey.balanceAsc,
      (InvoiceSortField.subtotal, SortDirection.desc) =>
        InvoiceSortKey.amountDesc,
      (InvoiceSortField.subtotal, SortDirection.asc) =>
        InvoiceSortKey.amountAsc,
      _ => InvoiceSortKey.dateDesc,
    };
  }

  static const List<AppSortOption> options = [
    AppSortOption(value: 'date-desc', label: 'Created (newest)'),
    AppSortOption(value: 'date-asc', label: 'Created (oldest)'),
    AppSortOption(value: 'balance-desc', label: 'Remaining (highest)'),
    AppSortOption(value: 'balance-asc', label: 'Remaining (lowest)'),
    AppSortOption(value: 'amount-desc', label: 'Subtotal (highest)'),
    AppSortOption(value: 'amount-asc', label: 'Subtotal (lowest)'),
  ];
}

extension InvoiceSortDirectionWire on SortDirection {
  String get wireValue => switch (this) {
    SortDirection.asc => 'asc',
    SortDirection.desc => 'desc',
  };
}

/// Client-side sort over a loaded invoice page.
///
<<<<<<< HEAD
/// TODO(invoices-page-implementation-plan §6): remove when `list_invoices` honours
/// `sort_field` / `sort_direction` server-side.
=======
/// Remove when `list_invoices` honours `sort_field` / `sort_direction`
/// server-side (invoices-page-implementation-plan §6).
>>>>>>> master
List<InvoiceListItem> sortInvoiceListItemsClientSide(
  List<InvoiceListItem> items,
  InvoiceListFilters filters,
) {
  final field = filters.sortField;
  if (field == null) {
    return items;
  }

  final sorted = List<InvoiceListItem>.from(items);
  final ascending = filters.sortDirection == SortDirection.asc;

  int compare<T extends Comparable<T>>(T a, T b) =>
      ascending ? a.compareTo(b) : b.compareTo(a);

  sorted.sort((a, b) {
    return switch (field) {
      InvoiceSortField.createdAt => compare(a.createdAt, b.createdAt),
      InvoiceSortField.balance => compare(a.balance, b.balance),
      InvoiceSortField.subtotal => compare(a.subtotal, b.subtotal),
    };
  });

  return sorted;
}
