import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/core/ui/components/app_empty_state.dart';
import 'package:ai_clinic/core/ui/components/app_skeletonizer_zone.dart';
import 'package:ai_clinic/core/ui/components/app_tabs.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/auth/domain/permission_keys.dart';
import 'package:ai_clinic/features/clinic-management/presentation/pages/clinic_management_page.dart';
import 'package:ai_clinic/features/clinic-management/presentation/providers/clinic_management_notifier.dart';

import '../../helpers/role_permission_seed.dart';
import 'clinic_management_widget_test_harness.dart';

void main() {
  group('ClinicManagementPage', () {
    testWidgets('CLINIC-PAGE-01: default admin build shows all 6 tabs', (tester) async {
      await pumpClinicManagementPage(tester);
      await pumpClinicManagementFrames(tester);
      await pumpClinicManagementSkeletonTimer(tester);

      expect(tester.takeException(), isNull);
      expect(find.text('Clinic Management'), findsOneWidget);

      final tabs = tester.widget<AppTabs>(find.byType(AppTabs));
      expect(tabs.items, hasLength(6));
      expect(tabs.items.map((item) => item.label).toList(), [
        'Organization',
        'Branches',
        'Staff',
        'Roles',
        'Services',
        'Settings',
      ]);
      expect(find.text('Organization profile'), findsOneWidget);
    });

    testWidgets('CLINIC-PAGE-02: tab switching shows tab body content', (tester) async {
      await pumpClinicManagementPage(tester);
      await pumpClinicManagementFrames(tester);
      await pumpClinicManagementSkeletonTimer(tester);

      await tapClinicManagementTab(tester, 'Branches');
      expect(find.text('Add branch'), findsOneWidget);

      await tapClinicManagementTab(tester, 'Staff');
      expect(find.text('Add staff member'), findsOneWidget);
      expect(find.text('Jane Doe'), findsOneWidget);

      await tapClinicManagementTab(tester, 'Roles');
      expect(find.text('Roles & permissions'), findsOneWidget);

      await tapClinicManagementTab(tester, 'Organization');
      expect(find.text('Organization profile'), findsOneWidget);

      await tapClinicManagementTab(tester, 'Settings');
      expect(find.text('Clinic settings'), findsOneWidget);
    });

    testWidgets('CLINIC-PAGE-03: loading skeleton state while provider is loading', (tester) async {
      await pumpClinicManagementPage(
        tester,
        overrides: clinicManagementProviderOverrides(
          clinicManagementOverride: clinicManagementProvider.overrideWith(
            () => LoadingClinicManagementNotifier(),
          ),
        ),
      );
      await tester.pump();
      await pumpClinicManagementSkeletonTimer(tester);

      expect(find.byType(AppSkeletonizerZone), findsOneWidget);
      expect(find.text('Organization profile'), findsNothing);
      expect(find.text('Jane Doe'), findsNothing);
    });

    testWidgets('CLINIC-PAGE-04: provider error state shows error UI', (tester) async {
      const message = 'clinic load failed';

      await pumpClinicManagementPage(
        tester,
        overrides: clinicManagementProviderOverrides(
          clinicManagementOverride: clinicManagementProvider.overrideWith(
            () => ReloadErrorClinicManagementNotifier(buildClinicManagementState(), message),
          ),
        ),
      );
      await settleClinicMgmtWidget(tester);

      final container = ProviderScope.containerOf(
        tester.element(find.byType(ClinicManagementPage)),
      );
      await container.read(clinicManagementProvider.notifier).reload();
      await settleClinicMgmtWidget(tester);

      expect(container.read(clinicManagementProvider).hasError, isTrue);

      expect(find.byType(AppEmptyState), findsOneWidget);
      expect(find.text('Something went wrong'), findsOneWidget);
      expect(find.text('We could not load this content.'), findsOneWidget);
      expect(find.byType(AppSkeletonizerZone), findsNothing);
    });

    testWidgets('CLINIC-PAGE-05: doctor without permissions shows no-access empty state', (tester) async {
      await pumpClinicManagementPage(
        tester,
        auth: clinicManagementAuthSession(
          role: StaffRole.doctor,
          permissions: RolePermissionSeed.doctor,
        ),
      );
      await pumpClinicManagementFrames(tester);

      expect(find.text('No access'), findsOneWidget);
      expect(find.text('You do not have permission to view this content.'), findsOneWidget);
      expect(find.byType(AppTabs), findsNothing);
      expect(find.text('Clinic Management'), findsOneWidget);
    });

    testWidgets('CLINIC-PAGE-06: permission-scoped tab visibility for limited doctor', (tester) async {
      await pumpClinicManagementPage(
        tester,
        auth: clinicManagementAuthSession(
          role: StaffRole.doctor,
          permissions: const {PermissionKeys.servicesView},
        ),
      );
      await pumpClinicManagementFrames(tester);
      await pumpClinicManagementSkeletonTimer(tester);

      final tabs = tester.widget<AppTabs>(find.byType(AppTabs));
      expect(tabs.items, hasLength(1));
      expect(tabs.items.single.label, 'Services');
      expect(find.text('Branches'), findsNothing);
      expect(find.text('Staff'), findsNothing);
      expect(find.text('Roles'), findsNothing);
      expect(find.text('Settings'), findsNothing);
    });
  });
}
