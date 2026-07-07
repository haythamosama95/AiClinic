import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/components/app_badge.dart';
import 'package:ai_clinic/core/ui/components/app_bulk_action_bar.dart';
import 'package:ai_clinic/core/ui/components/app_data_table.dart';
import 'package:ai_clinic/core/ui/components/app_empty_state.dart';
import 'package:ai_clinic/core/ui/components/app_error_state.dart';
import 'package:ai_clinic/core/ui/components/app_money_display.dart';
import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';
import 'package:ai_clinic/features/design_system/presentation/components/showcase_primitives.dart';
import 'package:ai_clinic/features/design_system/presentation/providers/dev_preview_provider.dart';

class _PatientRow {
  const _PatientRow({required this.id, required this.name, required this.phone, required this.balance});

  final String id;
  final String name;
  final String phone;
  final double balance;
}

const _mockPatients = <_PatientRow>[
  _PatientRow(id: '1', name: 'Layla Hassan', phone: '+20 100 234 5678', balance: 1250),
  _PatientRow(id: '2', name: 'Omar Farouk', phone: '+20 101 345 6789', balance: 0),
  _PatientRow(id: '3', name: 'Nadia El-Sayed', phone: '+20 102 456 7890', balance: -320),
];

enum _DemoState { defaultState, loading, empty, error }

class _DataTableCopy {
  const _DataTableCopy({
    required this.description,
    required this.patient,
    required this.phone,
    required this.balance,
    required this.status,
    required this.active,
    required this.patientsSelected,
    required this.export,
    required this.errorMessage,
    required this.totalBalance,
    required this.demoDefault,
    required this.demoLoading,
    required this.demoEmpty,
    required this.demoError,
  });

  final String description;
  final String patient;
  final String phone;
  final String balance;
  final String status;
  final String active;
  final String patientsSelected;
  final String export;
  final String errorMessage;
  final String totalBalance;
  final String demoDefault;
  final String demoLoading;
  final String demoEmpty;
  final String demoError;

  String demoLabel(_DemoState state) => switch (state) {
    _DemoState.defaultState => demoDefault,
    _DemoState.loading => demoLoading,
    _DemoState.empty => demoEmpty,
    _DemoState.error => demoError,
  };
}

const _copyEn = _DataTableCopy(
  description: 'Sortable columns, row selection, loading skeletons, and empty/error slots.',
  patient: 'Patient',
  phone: 'Phone',
  balance: 'Balance',
  status: 'Status',
  active: 'Active',
  patientsSelected: 'patients selected',
  export: 'Export',
  errorMessage: 'Could not load patients. Check your connection.',
  totalBalance: 'Total balance:',
  demoDefault: 'default',
  demoLoading: 'loading',
  demoEmpty: 'empty',
  demoError: 'error',
);

const _copyAr = _DataTableCopy(
  description: 'أعمدة قابلة للفرز، تحديد الصفوف، هياكل التحميل، وحالات فارغة/خطأ.',
  patient: 'المريض',
  phone: 'الهاتف',
  balance: 'الرصيد',
  status: 'الحالة',
  active: 'نشط',
  patientsSelected: 'مرضى محددون',
  export: 'تصدير',
  errorMessage: 'تعذر تحميل المرضى. تحقق من اتصالك.',
  totalBalance: 'إجمالي الرصيد:',
  demoDefault: 'افتراضي',
  demoLoading: 'تحميل',
  demoEmpty: 'فارغ',
  demoError: 'خطأ',
);

_DataTableCopy _copyFor(String locale) => locale == 'ar' ? _copyAr : _copyEn;

/// Data table showcase (web `DataTableShowcase`).
class DataTableShowcaseSection extends ConsumerStatefulWidget {
  const DataTableShowcaseSection({super.key});

  @override
  ConsumerState<DataTableShowcaseSection> createState() => _DataTableShowcaseSectionState();
}

class _DataTableShowcaseSectionState extends ConsumerState<DataTableShowcaseSection> {
  final _selected = <String>{};
  var _sortColumn = 'name';
  var _sortDirection = SortDirection.asc;
  var _demo = _DemoState.defaultState;

  void _handleSort(String columnId) {
    setState(() {
      if (_sortColumn == columnId) {
        _sortDirection = _sortDirection == SortDirection.asc ? SortDirection.desc : SortDirection.asc;
      } else {
        _sortColumn = columnId;
        _sortDirection = SortDirection.asc;
      }
    });
  }

  void _setDemo(_DemoState demo) {
    setState(() => _demo = demo);
  }

  List<_PatientRow> _sortedData(List<_PatientRow> data) {
    final sorted = List<_PatientRow>.from(data);
    sorted.sort((a, b) {
      final cmp = switch (_sortColumn) {
        'balance' => a.balance.compareTo(b.balance),
        _ => a.name.compareTo(b.name),
      };
      return _sortDirection == SortDirection.asc ? cmp : -cmp;
    });
    return sorted;
  }

  @override
  Widget build(BuildContext context) {
    final copy = _copyFor(ref.watch(devPreviewProvider).locale);
    final colors = context.appColors;
    final data = _demo == _DemoState.defaultState ? _mockPatients : <_PatientRow>[];
    final sortedData = _sortedData(data);

    return ShowcaseSection(
      id: 'data-table',
      title: 'Table / Data grid',
      componentName: 'DataTable',
      description: copy.description,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: AppSpacing.space2,
            runSpacing: AppSpacing.space2,
            children: [
              for (final state in _DemoState.values)
                _DemoToggleButton(
                  label: copy.demoLabel(state),
                  selected: _demo == state,
                  onPressed: () => _setDemo(state),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.space4),
          if (_selected.isNotEmpty) ...[
            AppBulkActionBar(
              count: _selected.length,
              itemLabel: copy.patientsSelected,
              onClear: () => setState(_selected.clear),
              actions: TextButton(
                onPressed: () {},
                child: Text(copy.export, style: AppTypography.bodySm(context).copyWith(color: colors.textLink)),
              ),
            ),
            const SizedBox(height: AppSpacing.space4),
          ],
          AppDataTable<_PatientRow>(
            columns: [
              TableColumn(id: 'name', header: copy.patient, sortable: true, accessor: (row) => Text(row.name)),
              TableColumn(id: 'phone', header: copy.phone, accessor: (row) => Text(row.phone)),
              TableColumn(
                id: 'balance',
                header: copy.balance,
                sortable: true,
                accessor: (row) => AppMoneyDisplay(amount: row.balance, negative: row.balance < 0),
              ),
              TableColumn(
                id: 'status',
                header: copy.status,
                accessor: (_) => AppBadge(label: copy.active, color: BadgeColor.success, variant: BadgeVariant.soft),
              ),
            ],
            data: sortedData,
            density: TableDensity.standard,
            zebra: true,
            selectable: true,
            selectedIds: _selected,
            onSelectionChange: (ids) => setState(() {
              _selected
                ..clear()
                ..addAll(ids);
            }),
            getRowId: (row) => row.id,
            sortColumn: _sortColumn,
            sortDirection: _sortDirection,
            onSort: _handleSort,
            loading: _demo == _DemoState.loading,
            emptyState: const AppEmptyState(variant: EmptyStateVariant.noResults),
            errorState: _demo == _DemoState.error
                ? AppErrorState(message: copy.errorMessage, onRetry: () => _setDemo(_DemoState.defaultState))
                : null,
            footer: DefaultTextStyle(
              style: AppTypography.bodySm(context).copyWith(color: colors.textSecondary),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [Text('${copy.totalBalance} '), const AppMoneyDisplay(amount: 1250, emphasis: true)],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DemoToggleButton extends StatelessWidget {
  const _DemoToggleButton({required this.label, required this.selected, required this.onPressed});

  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return TextButton(
      style: TextButton.styleFrom(
        foregroundColor: colors.textPrimary,
        backgroundColor: selected ? colors.surfaceHover : Colors.transparent,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.space3,
          vertical: AppSpacing.space1 + AppSpacing.space05,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          side: BorderSide(color: colors.borderDefault),
        ),
      ),
      onPressed: onPressed,
      child: Text(label, style: AppTypography.bodySm(context)),
    );
  }
}
