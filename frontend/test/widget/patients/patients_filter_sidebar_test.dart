import 'package:ai_clinic/core/ui/theme/app_theme.dart';
import 'package:ai_clinic/core/ui/theme/forui_app_scope.dart';
import 'package:ai_clinic/features/patients/presentation/models/patient_list_filters.dart';
import 'package:ai_clinic/features/patients/presentation/widgets/patients_filter_sidebar.dart';
import 'package:ai_clinic/features/settings/domain/branch_list_item.dart';
import 'package:ai_clinic/features/settings/presentation/providers/clinic_setup_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PatientsFilterSidebar high-severity regressions', () {
    testWidgets('H1: hides assigned doctor filter until backend support exists', (tester) async {
      var appliedFilters = const PatientListFilters();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            clinicSetupBranchesProvider.overrideWith(
              (ref) async => const [BranchListItem(id: 'branch-1', name: 'Main', code: 'M1', isActive: true)],
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            builder: (context, child) => ForuiAppScope(child: child ?? const SizedBox.shrink()),
            home: Scaffold(
              body: PatientsFilterSidebar(
                filters: appliedFilters,
                onFiltersChanged: (filters) => appliedFilters = filters,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Assigned Doctor'), findsNothing);
      expect(find.text('Last Visit'), findsOneWidget);
      expect(find.text('Branch'), findsOneWidget);
    });
  });
}
