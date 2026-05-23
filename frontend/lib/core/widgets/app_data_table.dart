import 'package:flutter/material.dart';

import 'package:ai_clinic/app/theme/app_colors.dart';

/// Column definition for [AppDataTable].
class AppDataColumn {
  const AppDataColumn({required this.label, this.numeric = false});

  final String label;
  final bool numeric;
}

/// Lightweight data table with consistent header styling for desktop views.
class AppDataTable extends StatelessWidget {
  const AppDataTable({
    super.key,
    required this.columns,
    required this.rows,
    this.emptyMessage = 'No records to display',
    this.isLoading = false,
    this.onRowTap,
  });

  final List<AppDataColumn> columns;
  final List<List<String>> rows;
  final String emptyMessage;
  final bool isLoading;

  /// Called when a data row is tapped (index matches [rows]).
  final void Function(int index)? onRowTap;

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
                label: Expanded(child: Text(column.label, style: Theme.of(context).textTheme.labelLarge)),
              ),
          ],
          rows: [
            for (var rowIndex = 0; rowIndex < rows.length; rowIndex++)
              DataRow(
                cells: [
                  for (var index = 0; index < columns.length; index++)
                    DataCell(
                      Text(index < rows[rowIndex].length ? rows[rowIndex][index] : ''),
                      onTap: onRowTap == null ? null : () => onRowTap!(rowIndex),
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
