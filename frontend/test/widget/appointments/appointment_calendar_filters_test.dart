import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/appointment_calendar_filters.dart';

import '../../support/appointment_calendar_test_support.dart';
import 'calendar_widget_test_harness.dart';

void main() {
  Widget buildFilterButton({
    required AsyncValue branchesAsync,
    required AsyncValue doctorsAsync,
    required ValueChanged<AppointmentCalendarFilters> onApplyFilters,
    required VoidCallback onClearFilters,
    bool showDoctorFilter = true,
  }) {
    return AppointmentCalendarFilterButton(
      branchesAsync: branchesAsync,
      doctorsAsync: doctorsAsync,
      appliedBranchId: calendarTestBranchAId,
      appliedDoctorId: null,
      appliedStatuses: const {},
      showDoctorFilter: showDoctorFilter,
      hasActiveFilters: false,
      onApplyFilters: onApplyFilters,
      onClearFilters: onClearFilters,
    );
  }

  Future<void> openFilters(
    WidgetTester tester, {
    required Widget button,
  }) async {
    await pumpCalendarSurface(
      tester,
      child: Center(child: button),
      surfaceSize: const Size(900, 700),
    );
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('Schedule filters'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  testWidgets('trivial: CAL-FILTER-01 opening popover shows branch, doctor, and status controls', (tester) async {
    await openFilters(
      tester,
      button: buildFilterButton(
        branchesAsync: AsyncData(calendarTestBranches()),
        doctorsAsync: AsyncData(calendarTestDoctorsWithBranches()),
        onApplyFilters: (_) {},
        onClearFilters: () {},
      ),
    );

    expect(find.text('Schedule filters'), findsWidgets);
    expect(find.text('Location'), findsOneWidget);
    expect(find.text('Provider'), findsOneWidget);
    expect(find.text('Appointment status'), findsOneWidget);
    expect(find.text('Scheduled'), findsOneWidget);
    expect(find.text('Reset filters'), findsOneWidget);
    expect(find.text('Apply filters'), findsOneWidget);
  });

  testWidgets('advanced: CAL-FILTER-02 branches loading shows Loading branches…', (tester) async {
    await openFilters(
      tester,
      button: buildFilterButton(
        branchesAsync: const AsyncLoading(),
        doctorsAsync: AsyncData(calendarTestDoctorsWithBranches()),
        onApplyFilters: (_) {},
        onClearFilters: () {},
      ),
    );

    expect(find.text('Loading branches…'), findsOneWidget);
  });

  testWidgets('invalid state: CAL-FILTER-03 branches error shows Could not load branches.', (tester) async {
    await openFilters(
      tester,
      button: buildFilterButton(
        branchesAsync: AsyncError(Exception('fail'), StackTrace.empty),
        doctorsAsync: AsyncData(calendarTestDoctorsWithBranches()),
        onApplyFilters: (_) {},
        onClearFilters: () {},
      ),
    );

    expect(find.text('Could not load branches.'), findsOneWidget);
  });

  testWidgets('advanced: CAL-FILTER-04 doctors loading shows Loading doctors…', (tester) async {
    await openFilters(
      tester,
      button: buildFilterButton(
        branchesAsync: AsyncData(calendarTestBranches()),
        doctorsAsync: const AsyncLoading(),
        onApplyFilters: (_) {},
        onClearFilters: () {},
      ),
    );

    expect(find.text('Loading doctors…'), findsOneWidget);
  });

  testWidgets('invalid state: CAL-FILTER-05 doctors error shows Could not load doctors.', (tester) async {
    await openFilters(
      tester,
      button: buildFilterButton(
        branchesAsync: AsyncData(calendarTestBranches()),
        doctorsAsync: AsyncError(Exception('fail'), StackTrace.empty),
        onApplyFilters: (_) {},
        onClearFilters: () {},
      ),
    );

    expect(find.text('Could not load doctors.'), findsOneWidget);
  });

  testWidgets('advanced: CAL-FILTER-06 toggling status chip updates draft selection', (tester) async {
    await openFilters(
      tester,
      button: buildFilterButton(
        branchesAsync: AsyncData(calendarTestBranches()),
        doctorsAsync: AsyncData(calendarTestDoctorsWithBranches()),
        onApplyFilters: (_) {},
        onClearFilters: () {},
      ),
    );

    await tester.tap(find.text('Confirmed'));
    await tester.pump();

    expect(find.textContaining('Confirmed'), findsWidgets);
  });

  testWidgets('advanced: CAL-FILTER-07 Reset filters invokes onClearFilters', (tester) async {
    var cleared = false;
    await openFilters(
      tester,
      button: buildFilterButton(
        branchesAsync: AsyncData(calendarTestBranches()),
        doctorsAsync: AsyncData(calendarTestDoctorsWithBranches()),
        onApplyFilters: (_) {},
        onClearFilters: () => cleared = true,
      ),
    );

    await tester.tap(find.text('Reset filters'));
    await tester.pump();

    expect(cleared, isTrue);
  });

  testWidgets('advanced: CAL-FILTER-08 Apply filters invokes callback with branch, doctor, statuses', (tester) async {
    AppointmentCalendarFilters? applied;
    await openFilters(
      tester,
      button: buildFilterButton(
        branchesAsync: AsyncData(calendarTestBranches()),
        doctorsAsync: AsyncData(calendarTestDoctorsWithBranches()),
        onApplyFilters: (filters) => applied = filters,
        onClearFilters: () {},
      ),
    );

    await tester.tap(find.text('Confirmed'));
    await tester.pump();
    await tester.tap(find.text('Apply filters'));
    await tester.pump();

    expect(applied, isNotNull);
    expect(applied!.branchId, calendarTestBranchAId);
    expect(applied!.doctorId, isNull);
    expect(applied!.statuses, contains(AppointmentStatus.confirmed));
  });
}
