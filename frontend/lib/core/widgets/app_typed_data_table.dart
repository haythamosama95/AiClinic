import 'package:flutter/material.dart';

import 'package:ai_clinic/app/theme/app_colors.dart';

/// Type-safe column definition for [AppTypedDataTable].
class AppTypedDataColumn<T> {
  const AppTypedDataColumn({
    required this.label,
    required this.extract,
    this.numeric = false,
  });

  final String label;
  final String Function(T item) extract;
  final bool numeric;
}

/// Type-safe data table that enforces column/data consistency at compile time.
class AppTypedDataTable<T> extends StatelessWidget {
  const AppTypedDataTable({
    super.key,
    required this.columns,
    required this.rows,
    this.emptyMessage = 'No records to display',
    this.isLoading = false,
    this.onRowTap,
  });

  final List<AppTypedDataColumn<T>> columns;
  final List<T> rows;
  final String emptyMessage;
  final bool isLoading;
  final void Function(T item)? onRowTap;

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(
        child: Padding(padding: EdgeInsets.all(AppSpacing.lg), child: CircularProgressIndicator()),
      );
    }

    if (rows.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Text(emptyMessage, style: Theme.of(context).textTheme.bodyLarge),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        Widget table = DataTable(
          showCheckboxColumn: false,
          headingRowColor: WidgetStatePropertyAll(Theme.of(context).colorScheme.surfaceContainerHighest),
          columns: [
            for (final column in columns)
              DataColumn(
                numeric: column.numeric,
                label: Text(column.label, style: Theme.of(context).textTheme.labelLarge),
              ),
          ],
          rows: [
            for (final item in rows)
              DataRow(
                cells: [
                  for (final column in columns)
                    DataCell(
                      Text(column.extract(item)),
                      onTap: onRowTap != null ? () => onRowTap!(item) : null,
                    ),
                ],
              ),
          ],
        );

        if (constraints.maxHeight.isFinite) {
          table = SizedBox(
            height: constraints.maxHeight,
            child: SingleChildScrollView(child: table),
          );
        }

        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: constraints.maxWidth),
            child: table,
          ),
        );
      },
    );
  }
}
