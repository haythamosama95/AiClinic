import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/core/ui/components/app_badge.dart';
import 'package:ai_clinic/core/ui/components/app_button.dart';
import 'package:ai_clinic/core/ui/theme/app_theme.dart';
import 'package:ai_clinic/features/patients/presentation/models/patient_list_filters.dart';
import 'package:ai_clinic/features/patients/presentation/widgets/patient_list_controls.dart';

class _ControlsHarness extends StatefulWidget {
  const _ControlsHarness({required this.initialFilters});

  final PatientListFilters initialFilters;

  @override
  State<_ControlsHarness> createState() => _ControlsHarnessState();
}

class _ControlsHarnessState extends State<_ControlsHarness> {
  late PatientListFilters filters;
  String? lastSearch;
  PatientSortField? lastSort;
  PatientLastVisitFilter? lastLastVisit;
  var clearFiltersCalls = 0;

  @override
  void initState() {
    super.initState();
    filters = widget.initialFilters;
  }

  @override
  Widget build(BuildContext context) {
    return PatientListControls(
      filters: filters,
      onSearchChange: (value) => setState(() => lastSearch = value),
      onSortChange: (value) => setState(() {
        lastSort = value;
        filters = filters.copyWith(sortField: value);
      }),
      onLastVisitChange: (value) => setState(() {
        lastLastVisit = value;
        filters = filters.copyWith(lastVisitFilter: value);
      }),
      onClearFilters: () => setState(() => clearFiltersCalls++),
      activeFilters: const [],
    );
  }
}

const _controlsSurfaceSize = Size(1800, 900);

Finder _filterButtonFinder() {
  return find.ancestor(
    of: find.text('Filter'),
    matching: find.byType(AppButton),
  );
}

Future<void> _tapFilterButton(WidgetTester tester) async {
  final button = _filterButtonFinder();
  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.pumpAndSettle();
}

Future<_ControlsHarnessState> _pumpControls(
  WidgetTester tester, {
  PatientListFilters initialFilters = const PatientListFilters(),
}) async {
  if (find.byType(MaterialApp).evaluate().isNotEmpty) {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }

  await tester.binding.setSurfaceSize(_controlsSurfaceSize);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: SizedBox(
          width: _controlsSurfaceSize.width,
          height: _controlsSurfaceSize.height,
          child: _ControlsHarness(initialFilters: initialFilters),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();

  return tester.state<_ControlsHarnessState>(find.byType(_ControlsHarness));
}

void main() {
  group('PatientListControls', () {
    testWidgets('trivial: search field renders and typing invokes onSearchChange', (tester) async {
      final harness = await _pumpControls(tester);

      expect(find.bySemanticsLabel('Search patients'), findsOneWidget);
      expect(
        find.text('Search patients by name, MRN, email, or phone…'),
        findsOneWidget,
      );

      await tester.enterText(find.bySemanticsLabel('Search patients'), 'Ahmed');
      await tester.pump(const Duration(milliseconds: 350));

      expect(harness.lastSearch, 'Ahmed');
    });

    testWidgets('advanced: filter popover selects last visit and clears filters', (tester) async {
      final harness = await _pumpControls(tester);

      await _tapFilterButton(tester);

      expect(find.text('Last visit'), findsOneWidget);

      await tester.tap(find.text('Last 30 days'));
      await tester.pumpAndSettle();

      expect(harness.lastLastVisit, PatientLastVisitFilter.last30Days);

      await _tapFilterButton(tester);
      await tester.tap(find.text('Clear filters'));
      await tester.pump(const Duration(milliseconds: 100));

      expect(harness.clearFiltersCalls, 1);
    });

    testWidgets('advanced: sort menu selects field and clear sorting resets default', (tester) async {
      final harness = await _pumpControls(
        tester,
        initialFilters: const PatientListFilters(
          sortField: PatientSortField.lastVisitDesc,
        ),
      );

      await tester.tap(find.bySemanticsLabel('Sort patients'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Name (Z → A)'));
      await tester.pumpAndSettle();

      expect(harness.lastSort, PatientSortField.nameDesc);

      await tester.tap(find.bySemanticsLabel('Sort patients'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Clear sorting'));
      await tester.pumpAndSettle();

      expect(harness.lastSort, PatientSortField.nameAsc);
    });

    testWidgets('edge case: active filter badge appears only when last-visit filter is active', (tester) async {
      await _pumpControls(tester);

      expect(
        find.descendant(
          of: find.ancestor(of: find.text('Filter'), matching: find.byType(AppButton)),
          matching: find.byType(AppBadge),
        ),
        findsNothing,
      );

      await _pumpControls(
        tester,
        initialFilters: const PatientListFilters(
          lastVisitFilter: PatientLastVisitFilter.last90Days,
        ),
      );

      expect(
        find.descendant(
          of: _filterButtonFinder(),
          matching: find.byType(AppBadge),
        ),
        findsOneWidget,
      );
    });
  });
}
