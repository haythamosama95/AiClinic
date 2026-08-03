import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/core/ui/components/app_filter_menu_panel.dart';
import 'package:ai_clinic/core/ui/components/app_list_control_bar.dart';
import 'package:ai_clinic/core/ui/theme/app_theme.dart';

class _FilterBarHarness extends StatefulWidget {
  const _FilterBarHarness();

  @override
  State<_FilterBarHarness> createState() => _FilterBarHarnessState();
}

class _FilterBarHarnessState extends State<_FilterBarHarness> {
  var status = 'all';

  @override
  Widget build(BuildContext context) {
    return AppListControlBar(
      searchPlaceholder: 'Search',
      searchAriaLabel: 'Search',
      searchValue: '',
      sortValue: 'date_desc',
      defaultSortValue: 'date_desc',
      sortOptions: const [AppSortOption(value: 'date_desc', label: 'Newest')],
      onSortChange: (_) {},
      sortAriaLabel: 'Sort',
      filterActiveCount: status == 'all' ? 0 : 1,
      onClearFilters: status == 'all' ? null : () => setState(() => status = 'all'),
      filterMenu: AppFilterMenuPanel(
        sections: [
          AppFilterMenuSection(
            id: 'status',
            label: 'Status',
            value: status,
            options: const [
              AppFilterMenuOption(value: 'all', label: 'All statuses'),
              AppFilterMenuOption(value: 'draft', label: 'Draft'),
              AppFilterMenuOption(value: 'issued', label: 'Issued'),
              AppFilterMenuOption(value: 'paid', label: 'Paid'),
            ],
            onChange: (value) => setState(() => status = value),
          ),
        ],
      ),
      activeFilters: status == 'all'
          ? const []
          : [
              AppActiveFilter(
                id: 'status',
                label: status,
                onRemove: () => setState(() => status = 'all'),
              ),
            ],
      hasActiveFilters: status != 'all',
    );
  }
}

void main() {
  testWidgets('AppListControlBar filter menu allows switching status after first selection', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 600));

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(body: _FilterBarHarness()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Filter'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Draft'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final harness = tester.state<_FilterBarHarnessState>(find.byType(_FilterBarHarness));
    expect(harness.status, 'draft');
    expect(find.text('Clear filters'), findsOneWidget);

    await tester.tap(find.text('Issued'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(harness.status, 'issued');
  });
}
