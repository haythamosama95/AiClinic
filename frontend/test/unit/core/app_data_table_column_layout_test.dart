import 'package:ai_clinic/core/ui/components/app_data_table.dart';
import 'package:ai_clinic/core/ui/components/app_data_table_column_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppDataTableColumnLayout.initialWidths', () {
    const columns = [
      TableColumn<Object>(id: 'patient', header: 'Patient', accessor: _cell, minWidth: 160),
      TableColumn<Object>(id: 'time', header: 'Time', accessor: _cell, minWidth: 112),
      TableColumn<Object>(id: 'actions', header: 'Actions', accessor: _cell, minWidth: 180),
    ];

    test('distributes available width across stored columns and leaves fill column implicit', () {
      final widths = AppDataTableColumnLayout.initialWidths(
        columns: columns,
        availableWidth: 900,
        selectable: false,
        hasRowActions: false,
      );

      expect(widths.keys, containsAll(['patient', 'time']));
      expect(widths, isNot(contains('actions')));
      expect(
        AppDataTableColumnLayout.minimumTableWidth(
          columns: columns,
          widths: widths,
          selectable: false,
          hasRowActions: false,
        ),
        lessThanOrEqualTo(900),
      );
      for (final column in AppDataTableColumnLayout.storedColumns(columns)) {
        expect(widths[column.id], greaterThanOrEqualTo(column.minWidth!));
      }
    });

    test('reuses persisted widths for known stored columns', () {
      final widths = AppDataTableColumnLayout.initialWidths(
        columns: columns,
        availableWidth: 900,
        selectable: false,
        hasRowActions: false,
        persisted: const {'patient': 240, 'time': 140, 'actions': 220},
      );

      expect(widths['patient'], 240);
      expect(widths['time'], 140);
      expect(widths.containsKey('actions'), isFalse);
    });

    test('splits remaining width equally when explicit widths are present', () {
      const explicitColumns = [
        TableColumn<Object>(id: 'patient', header: 'Patient', accessor: _cell, width: 220, minWidth: 160),
        TableColumn<Object>(id: 'time', header: 'Time', accessor: _cell, minWidth: 112),
        TableColumn<Object>(id: 'doctor', header: 'Doctor', accessor: _cell, width: 200, minWidth: 160),
        TableColumn<Object>(id: 'actions', header: 'Actions', accessor: _cell, minWidth: 180),
      ];

      final widths = AppDataTableColumnLayout.initialWidths(
        columns: explicitColumns,
        availableWidth: 900,
        selectable: false,
        hasRowActions: false,
      );

      expect(widths['patient'], 220);
      expect(widths['doctor'], 200);
      expect(widths['time'], closeTo(240, 0.01));
      expect(widths.containsKey('actions'), isFalse);
    });
  });

  group('AppDataTableColumnLayout.resizeColumn', () {
    const columns = [
      TableColumn<Object>(id: 'patient', header: 'Patient', accessor: _cell, minWidth: 160),
      TableColumn<Object>(id: 'actions', header: 'Actions', accessor: _cell, minWidth: 180),
    ];

    test('increases width but not below minWidth', () {
      final resized = AppDataTableColumnLayout.resizeColumn(
        widths: const {'patient': 180},
        columns: columns,
        columnId: 'patient',
        delta: 24,
      );

      expect(resized['patient'], 204);
    });

    test('clamps to min width when shrinking', () {
      final resized = AppDataTableColumnLayout.resizeColumn(
        widths: const {'patient': 170},
        columns: columns,
        columnId: 'patient',
        delta: -40,
      );

      expect(resized['patient'], 160);
    });
  });

  group('AppDataTableColumnLayout.isFillColumn', () {
    const columns = [
      TableColumn<Object>(id: 'patient', header: 'Patient', accessor: _cell),
      TableColumn<Object>(id: 'actions', header: 'Actions', accessor: _cell),
    ];

    test('treats the last column as fill', () {
      expect(AppDataTableColumnLayout.isFillColumn(columns, 'actions'), isTrue);
      expect(AppDataTableColumnLayout.isFillColumn(columns, 'patient'), isFalse);
    });
  });
}

Widget _cell(Object _) => const SizedBox.shrink();
