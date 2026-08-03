import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/core/ui/theme/app_theme.dart';
import 'package:ai_clinic/features/patients/presentation/widgets/patient_active_filters_bar.dart';

class _ActiveFiltersHarness extends StatefulWidget {
  const _ActiveFiltersHarness({required this.initialActive});

  final List<({String id, String label, VoidCallback onRemove})> initialActive;

  @override
  State<_ActiveFiltersHarness> createState() => _ActiveFiltersHarnessState();
}

class _ActiveFiltersHarnessState extends State<_ActiveFiltersHarness> {
  late List<({String id, String label, VoidCallback onRemove})> active;
  final removedIds = <String>[];
  var clearAllCalls = 0;

  @override
  void initState() {
    super.initState();
    active = widget.initialActive;
  }

  void _remove(String id) {
    setState(() {
      removedIds.add(id);
      active = active.where((filter) => filter.id != id).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return PatientActiveFiltersBar(
      active: active
          .map(
            (filter) => (
              id: filter.id,
              label: filter.label,
              onRemove: () => _remove(filter.id),
            ),
          )
          .toList(),
      onClearAll: () => setState(() => clearAllCalls++),
    );
  }
}

Future<_ActiveFiltersHarnessState> _pumpBar(
  WidgetTester tester, {
  List<({String id, String label, VoidCallback onRemove})> active = const [],
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(body: _ActiveFiltersHarness(initialActive: active)),
    ),
  );
  await tester.pumpAndSettle();

  return tester.state<_ActiveFiltersHarnessState>(find.byType(_ActiveFiltersHarness));
}

void main() {
  group('PatientActiveFiltersBar', () {
    testWidgets('trivial: renders empty sentinel when there are no active filters', (tester) async {
      await _pumpBar(tester);

      expect(
        find.byKey(const ValueKey<String>('patient-active-filters-empty')),
        findsOneWidget,
      );
      expect(find.text('Filtered by'), findsNothing);
      expect(find.text('Clear all'), findsNothing);
    });

    testWidgets('trivial: renders one chip per active filter keyed by id', (tester) async {
      await _pumpBar(
        tester,
        active: [
          (id: 'search', label: 'Search: Ahmed', onRemove: () {}),
          (id: 'last-visit', label: 'Last 30 days', onRemove: () {}),
        ],
      );

      expect(
        find.byKey(const ValueKey<String>('patient-active-filters')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey<String>('search')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('last-visit')), findsOneWidget);
      expect(find.text('Search: Ahmed'), findsOneWidget);
      expect(find.text('Last 30 days'), findsOneWidget);
      expect(find.text('Filtered by'), findsOneWidget);
    });

    testWidgets('advanced: removing a chip and Clear all invoke callbacks', (tester) async {
      final harness = await _pumpBar(
        tester,
        active: [
          (id: 'search', label: 'Search: Ahmed', onRemove: () {}),
          (id: 'last-visit', label: 'Last 30 days', onRemove: () {}),
        ],
      );

      await tester.tap(find.bySemanticsLabel('Remove Search: Ahmed'));
      await tester.pumpAndSettle();

      expect(harness.removedIds, ['search']);
      expect(find.byKey(const ValueKey<String>('search')), findsNothing);
      expect(find.byKey(const ValueKey<String>('last-visit')), findsOneWidget);

      await tester.tap(find.text('Clear all'));
      await tester.pumpAndSettle();

      expect(harness.clearAllCalls, 1);
    });
  });
}
