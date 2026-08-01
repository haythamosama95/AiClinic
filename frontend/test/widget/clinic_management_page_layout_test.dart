import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/core/ui/components/app_tabs.dart';
import 'package:ai_clinic/features/billing/domain/money.dart';
import 'package:ai_clinic/features/service_catalog/domain/global_status.dart';
import 'package:ai_clinic/features/service_catalog/domain/service_list_item.dart';

import 'clinic_management/clinic_management_widget_test_harness.dart';

void main() {
  testWidgets('ClinicManagementPage mounts without layout errors', (tester) async {
    await pumpClinicManagementPage(tester);
    await pumpClinicManagementFrames(tester);

    final exception = tester.takeException();
    expect(exception, isNull, reason: exception?.toString());

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
  });

  testWidgets('ClinicManagementPage services tab scrolls in bounded viewport', (tester) async {
    final catalogState = buildServiceCatalogListState(
      items: [
        for (var index = 0; index < 12; index++)
          ServiceListItem(
            serviceId: '33333333-3333-4333-8333-${index.toString().padLeft(12, '0')}',
            name: 'Service $index',
            defaultPrice: Money.parse('150.00'),
            globalStatus: GlobalStatus.active,
            assignedBranchCount: 1,
            updatedAt: DateTime.utc(2026, 1, 1),
          ),
      ],
      total: 12,
    );

    await pumpClinicManagementPage(
      tester,
      overrides: clinicManagementProviderOverrides(
        clinicState: buildClinicManagementState(staff: const []),
        catalogState: catalogState,
      ),
      surfaceSize: const Size(1280, 554),
      scrollable: false,
    );

    await tester.pump();
    await tester.pump(const Duration(seconds: 2));

    await tester.tap(find.text('Services'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(tester.takeException(), isNull);
    expect(find.text('Service 0'), findsOneWidget);
    expect(find.text('Service 11'), findsOneWidget);
    expect(find.byType(SingleChildScrollView), findsWidgets);
  });
}
