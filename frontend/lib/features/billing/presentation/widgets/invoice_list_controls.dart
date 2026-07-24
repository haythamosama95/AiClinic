import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/ui/components/app_filter_menu_panel.dart';
import 'package:ai_clinic/core/ui/components/app_list_control_bar.dart';
import 'package:ai_clinic/features/billing/domain/invoice_status.dart';
import 'package:ai_clinic/features/billing/presentation/models/invoice_list_controls.dart';
import 'package:ai_clinic/features/billing/presentation/models/invoice_sort_key.dart';
import 'package:ai_clinic/features/clinic-management/domain/usecases/clinic_management_use_case_providers.dart';

/// Branch options for the invoice list filter popover.
final invoiceBranchFilterOptionsProvider =
    FutureProvider<List<({String id, String name})>>((ref) async {
      final auth = ref.watch(authSessionProvider);
      final organizationId = auth.context?.organizationId;
      final branchIds = auth.context?.branchIds ?? const <String>[];
      if (organizationId == null ||
          organizationId.isEmpty ||
          branchIds.isEmpty) {
        return const [];
      }

      final branches = await ref.read(listBranchesUseCaseProvider)(
        organizationId: organizationId,
      );
      return [
        for (final branchId in branchIds)
          (
            id: branchId,
            name:
                branches
                    .where((branch) => branch.id == branchId)
                    .map((branch) => branch.name)
                    .firstOrNull ??
                branchId,
          ),
      ];
    });

/// Search, sort, and filter controls for the invoices list (web `ListControlBar`).
class InvoiceListControlsBar extends ConsumerWidget {
  const InvoiceListControlsBar({
    required this.controls,
    required this.onApply,
    super.key,
  });

  final InvoiceListControls controls;
  final ValueChanged<InvoiceListControls> onApply;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authSessionProvider);
    final branchIds = auth.context?.branchIds ?? const <String>[];
    final multiBranch = branchIds.length > 1;
    final branchesAsync = ref.watch(invoiceBranchFilterOptionsProvider);
    final branches =
        branchesAsync.value ?? const <({String id, String name})>[];

    String branchName(String branchId) {
      return branches
              .where((branch) => branch.id == branchId)
              .map((branch) => branch.name)
              .firstOrNull ??
          branchId;
    }

    final activeFilters = controls.activeFilters(
      multiBranch: multiBranch,
      branchName: branchName,
      onRemoveStatus: () =>
          onApply(controls.copyWith(clearStatus: true, page: 1)),
      onRemoveBranch: () =>
          onApply(controls.copyWith(clearBranch: true, page: 1)),
      onRemoveSearch: () => onApply(controls.copyWith(search: '', page: 1)),
    );

    return AppListControlBar(
      searchPlaceholder: 'Search by invoice number, patient, or MRN…',
      searchAriaLabel: 'Search invoices',
      searchValue: controls.search,
      onSearchChange: (search) =>
          onApply(controls.copyWith(search: search, page: 1)),
      debounceMs: 300,
      sortValue: controls.sort.value,
      defaultSortValue: InvoiceSortKey.dateDesc.value,
      sortOptions: InvoiceSortKey.options,
      onSortChange: (value) {
        final sort = InvoiceSortKey.tryParse(value) ?? InvoiceSortKey.dateDesc;
        onApply(controls.copyWith(sort: sort, page: 1));
      },
      sortAriaLabel: 'Sort invoices',
      filterActiveCount: controls.filterActiveCount,
      onClearFilters: controls.filterActiveCount > 0
          ? () => onApply(
              controls.copyWith(clearStatus: true, clearBranch: true, page: 1),
            )
          : null,
      filterMenu: AppFilterMenuPanel(
        sections: [
          AppFilterMenuSection(
            id: 'status',
            label: 'Status',
            value: controls.status?.wireValue ?? 'all',
            options: [
              const AppFilterMenuOption(value: 'all', label: 'All statuses'),
              for (final status in InvoiceStatus.values)
                AppFilterMenuOption(
                  value: status.wireValue,
                  label: status.label,
                ),
            ],
            onChange: (value) {
              final status = value == 'all'
                  ? null
                  : InvoiceStatus.tryParse(value);
              onApply(controls.copyWith(status: status, page: 1));
            },
          ),
          if (multiBranch)
            AppFilterMenuSection(
              id: 'branch',
              label: 'Branch',
              value: controls.branch ?? 'all',
              options: [
                const AppFilterMenuOption(value: 'all', label: 'All branches'),
                for (final branch in branches)
                  AppFilterMenuOption(value: branch.id, label: branch.name),
              ],
              onChange: (value) {
                final branch = value == 'all' ? null : value;
                onApply(controls.copyWith(branch: branch, page: 1));
              },
            ),
        ],
      ),
      activeFilters: activeFilters,
      hasActiveFilters: controls.isFiltered,
      onClearAll: controls.isFiltered
          ? () => onApply(
              InvoiceListControls.defaultControls.copyWith(
                pageSize: controls.pageSize,
              ),
            )
          : null,
    );
  }
}
