import 'dart:ui' show Tristate;

import 'package:ai_clinic/core/ui/theme/app_theme.dart';
import 'package:ai_clinic/core/ui/theme/forui_app_scope.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/appointments/domain/simplified_booking_session.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/simplified_booking_step_two.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/simplified_day_strip.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/settings/domain/staff_list_item.dart';
import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../helpers/patient_test_support.dart';
import '../../support/appointment_calendar_test_support.dart';
import '../../support/appointment_rpc_test_client.dart';
import '../../support/fake_postgrest_rpc.dart';
import 'appointment_booking_sheet_test_support.dart';
import 'appointment_calendar_test_support.dart';

final _referenceDate = DateTime(2026, 6, 27);

const _testDoctors = [
  StaffListItem(
    id: calendarTestDoctorAId,
    fullName: 'Dr. Ada',
    role: StaffRole.doctor,
    isActive: true,
    branches: [StaffBranchLabel(id: calendarTestBranchAId, name: 'Branch A', isPrimary: true)],
  ),
  StaffListItem(
    id: calendarTestDoctorBId,
    fullName: 'Dr. Ben',
    role: StaffRole.doctor,
    isActive: true,
    branches: [StaffBranchLabel(id: calendarTestBranchAId, name: 'Branch A', isPrimary: true)],
  ),
];

String _slotLabel(int hour, {String? datePrefix}) {
  final date = datePrefix == null ? _referenceDate : DateTime.parse(datePrefix);
  return DateFormat.jm().format(DateTime(date.year, date.month, date.day, hour));
}

String _localDateKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

List<Map<String, dynamic>> mixedSlotBlocks(String datePrefix) => [
  {
    'start_time': '${datePrefix}T09:00:00.000',
    'end_time': '${datePrefix}T09:30:00.000',
    'state': 'available',
    'available_doctor_ids': [calendarTestDoctorAId],
  },
  {
    'start_time': '${datePrefix}T10:00:00.000',
    'end_time': '${datePrefix}T10:30:00.000',
    'state': 'fully_unavailable',
    'available_doctor_ids': <String>[],
  },
  {
    'start_time': '${datePrefix}T11:00:00.000',
    'end_time': '${datePrefix}T11:30:00.000',
    'state': 'alternate_doctors_available',
    'available_doctor_ids': [calendarTestDoctorBId],
  },
];

List<Map<String, dynamic>> onlyFullyUnavailableBlocks(String datePrefix) => [
  {
    'start_time': '${datePrefix}T10:00:00.000',
    'end_time': '${datePrefix}T10:30:00.000',
    'state': 'fully_unavailable',
    'available_doctor_ids': <String>[],
  },
];

/// Returns slot blocks keyed by RPC `p_local_date` (YYYY-MM-DD).
class SimplifiedSlotRpcClient extends AppointmentRpcTestClient {
  SimplifiedSlotRpcClient({required this.blocksForDate});

  final List<Map<String, dynamic>> Function(String localDate, String? doctorId) blocksForDate;

  @override
  PostgrestFilterBuilder<T> rpc<T>(String fn, {Map<String, dynamic>? params, dynamic get = false}) {
    if (fn == 'get_simplified_booking_slots') {
      rpcLog.add(fn);
      lastFunction = fn;
      lastParams = params == null ? null : Map<String, dynamic>.from(params);
      rpcCallCounts[fn] = (rpcCallCounts[fn] ?? 0) + 1;
      final localDate = lastParams?['p_local_date'] as String? ?? _localDateKey(_referenceDate);
      final doctorId = lastParams?['p_preferred_doctor_id'] as String?;
      final blocks = blocksForDate(localDate, doctorId);
      return FakePostgrestRpc({
        'success': true,
        'data': {'default_duration_minutes': 30, 'blocks': blocks},
      }) as PostgrestFilterBuilder<T>;
    }
    return super.rpc(fn, params: params, get: get);
  }
}

class StepTwoHarness extends StatefulWidget {
  const StepTwoHarness({
    super.key,
    required this.initialSession,
    required this.doctors,
    this.enabled = true,
  });

  final SimplifiedBookingSession initialSession;
  final List<StaffListItem> doctors;
  final bool enabled;

  @override
  State<StepTwoHarness> createState() => StepTwoHarnessState();
}

class StepTwoHarnessState extends State<StepTwoHarness> {
  late SimplifiedBookingSession _session;
  late bool _enabled;

  @override
  void initState() {
    super.initState();
    _session = widget.initialSession;
    _enabled = widget.enabled;
  }

  void setEnabled(bool value) => setState(() => _enabled = value);

  @override
  Widget build(BuildContext context) {
    return SimplifiedBookingStepTwo(
      session: _session,
      doctors: widget.doctors,
      enabled: _enabled,
      onSessionChanged: (session) => setState(() => _session = session),
      onBookingComplete: () {},
    );
  }
}

SimplifiedBookingSession _defaultSession({String? preferredDoctorId}) {
  final patient = samplePatientListItem(fullName: 'Filter Patient');
  final doctorId = preferredDoctorId ?? calendarTestDoctorAId;
  return SimplifiedBookingSession(
    branchId: calendarTestBranchAId,
    patient: patient,
    preferredDoctorId: doctorId,
    effectiveDoctorId: doctorId,
    selectedDate: _referenceDate,
    defaultDurationMinutes: 30,
  );
}

Future<void> pumpStepTwo(
  WidgetTester tester, {
  required AppointmentRpcTestClient client,
  SimplifiedBookingSession? session,
  List<StaffListItem> doctors = _testDoctors,
  bool enabled = true,
  GlobalKey<StepTwoHarnessState>? harnessKey,
}) async {
  suppressBookingSheetListTileNoise();
  await tester.binding.setSurfaceSize(calendarWidgetSurfaceSize);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    ProviderScope(
      overrides: bookingSheetOverrides(client: client, patientRepository: FakePatientRepository()),
      child: MaterialApp(
        theme: AppTheme.light(),
        builder: (context, child) => ForuiAppScope(child: child!),
        home: Scaffold(
          body: SingleChildScrollView(
            child: StepTwoHarness(
              key: harnessKey,
              initialSession: session ?? _defaultSession(),
              doctors: doctors,
              enabled: enabled,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

Future<void> waitForSlotsLoaded(WidgetTester tester) async {
  for (var i = 0; i < 40; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    if (find.text('Select Date and Time').evaluate().isNotEmpty &&
        find.byType(AppCircularProgress).evaluate().isEmpty) {
      return;
    }
  }
  fail('Slots did not finish loading.');
}

Future<void> openFilterPopover(WidgetTester tester) async {
  final filterButton = find.byKey(const Key('simplified_booking_filter_button'));
  await tester.scrollUntilVisible(
    filterButton,
    100,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pump();
  // Visual child is under IgnorePointer; FTappable sibling still receives the press.
  await tester.tap(filterButton, warnIfMissed: false);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 250));
}

Badge filterBadge(WidgetTester tester) {
  return tester.widget<Badge>(
    find.descendant(of: find.byKey(const Key('simplified_booking_filter_button')), matching: find.byType(Badge)),
  );
}

Future<void> selectViewDoctorFilter(WidgetTester tester, String doctorName) async {
  await tester.tap(
    find.descendant(of: find.byKey(const Key('simplified_booking_view_doctor')), matching: find.byType(EditableText)),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
  await tester.tap(find.text(doctorName).last);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
}

Future<void> setHideFullyBookedDraft(WidgetTester tester, {required bool value}) async {
  final switchFinder = find.byKey(const Key('simplified_booking_hide_fully_booked'));
  final current = tester.widget<AppSwitch>(switchFinder).value;
  if (current != value) {
    await tester.tap(switchFinder);
    await tester.pump();
  }
}

Future<void> applyFilterPopover(WidgetTester tester) async {
  await tester.tap(find.text('Apply Filters'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> clearFilterPopover(WidgetTester tester) async {
  await tester.tap(find.text('Clear Filters'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> selectFilterPopoverDay(WidgetTester tester, int day) async {
  await tester.tap(find.byKey(const Key('simplified_booking_pick_date')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.tap(
    find.byElementPredicate((element) {
      final widget = element.widget;
      if (widget is! Text || widget.data != '$day') {
        return false;
      }
      return element.findAncestorWidgetOfExactType<SimplifiedDayStrip>() == null;
    }),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
}

void expectStripSelectedDay(WidgetTester tester, DateTime date) {
  final label = 'Selected, ${DateFormat.yMMMMd().format(date)}';
  final stripFinder = find.byType(SimplifiedDayStrip);
  final dayFinder = find.descendant(of: stripFinder, matching: find.text('${date.day}'));
  expect(dayFinder, findsOneWidget);
  final semantics = tester.getSemantics(dayFinder);
  expect(semantics.label.split('\n').first, label);
  expect(semantics.flagsCollection.isSelected, Tristate.isTrue);
}

Finder slotInGrid(int hour, {String? datePrefix}) {
  return find.descendant(
    of: find.byKey(const Key('simplified_time_block_grid')),
    matching: find.text(_slotLabel(hour, datePrefix: datePrefix)),
  );
}

Finder slotChipInGrid(int hour, {String? datePrefix}) {
  return find.ancestor(
    of: slotInGrid(hour, datePrefix: datePrefix),
    matching: find.byType(InkWell),
  );
}

Finder slotIconInGrid(int hour, IconData icon, {String? datePrefix}) {
  return find.descendant(
    of: slotChipInGrid(hour, datePrefix: datePrefix),
    matching: find.byIcon(icon),
  );
}

Finder gridIcons(IconData icon) {
  return find.descendant(
    of: find.byKey(const Key('simplified_time_block_grid')),
    matching: find.byIcon(icon),
  );
}

Finder summaryPlaceholder() {
  return find.descendant(
    of: find.ancestor(
      of: find.byKey(const Key('simplified_slot_confirm')),
      matching: find.byType(DecoratedBox),
    ),
    matching: find.text('Select a time slot above'),
  );
}

void main() {
  group('SimplifiedBookingStepTwo filter popover', () {
    SimplifiedSlotRpcClient mixedSlotsClient() {
      return SimplifiedSlotRpcClient(
        blocksForDate: (localDate, _) => mixedSlotBlocks(localDate),
      );
    }

    Future<void> loadStepTwo(
      WidgetTester tester, {
      required AppointmentRpcTestClient client,
      SimplifiedBookingSession? session,
      bool enabled = true,
      GlobalKey<StepTwoHarnessState>? harnessKey,
    }) async {
      await withClock(Clock.fixed(_referenceDate), () async {
        await pumpStepTwo(
          tester,
          client: client,
          session: session,
          enabled: enabled,
          harnessKey: harnessKey,
        );
        await waitForSlotsLoaded(tester);
        await tester.pumpAndSettle();
      });
    }

    testWidgets('FE-D01: opens filter popover with hide, doctor, and date controls', (tester) async {
      await loadStepTwo(tester, client: mixedSlotsClient());

      await openFilterPopover(tester);

      expect(find.text('Filter by'), findsOneWidget);
      expect(find.text('Date'), findsOneWidget);
      expect(find.text('Doctor'), findsOneWidget);
      expect(find.text('Hide fully booked'), findsOneWidget);
      expect(find.byKey(const Key('simplified_booking_hide_fully_booked')), findsOneWidget);
      expect(find.byKey(const Key('simplified_booking_view_doctor')), findsOneWidget);
      expect(find.byKey(const Key('simplified_booking_pick_date')), findsOneWidget);
    });

    testWidgets('FE-D02: turning off hide fully booked reveals fully unavailable chips', (tester) async {
      await loadStepTwo(tester, client: mixedSlotsClient());

      expect(find.text(_slotLabel(10)), findsNothing);

      await openFilterPopover(tester);
      await setHideFullyBookedDraft(tester, value: false);
      await applyFilterPopover(tester);
      await tester.pumpAndSettle();

      expect(find.text(_slotLabel(10)), findsOneWidget);
      expect(find.byIcon(Icons.lock_outline), findsWidgets);
    });

    testWidgets('FE-D03: hide fully booked on hides unavailable blocks and shows empty message', (tester) async {
      final client = SimplifiedSlotRpcClient(
        blocksForDate: (localDate, _) => onlyFullyUnavailableBlocks(localDate),
      );
      await loadStepTwo(tester, client: client);

      expect(find.text('No bookable slots for this day.'), findsOneWidget);
      expect(find.text(_slotLabel(10)), findsNothing);
    });

    testWidgets('FE-D04: view doctor filter reloads slots for doctor and clears selection', (tester) async {
      final client = mixedSlotsClient();
      await loadStepTwo(tester, client: client);

      final availableSlot = slotInGrid(9);
      await tester.ensureVisible(availableSlot);
      await tester.tap(availableSlot);
      await tester.pumpAndSettle();
      expect(summaryPlaceholder(), findsNothing);

      await openFilterPopover(tester);
      await selectViewDoctorFilter(tester, 'Dr. Ben');
      await applyFilterPopover(tester);
      await waitForSlotsLoaded(tester);
      await tester.pumpAndSettle();

      expect(summaryPlaceholder(), findsOneWidget);
      expect(client.lastParams?['p_preferred_doctor_id'], calendarTestDoctorBId);
      expect(client.rpcCallCounts['get_simplified_booking_slots'], greaterThanOrEqualTo(2));
    });

    testWidgets('FE-D05: all doctors view remaps alternate slots to available styling', (tester) async {
      await loadStepTwo(tester, client: mixedSlotsClient());

      expect(slotIconInGrid(11, Icons.help_outline), findsOneWidget);

      await openFilterPopover(tester);
      await selectViewDoctorFilter(tester, 'All doctors');
      await applyFilterPopover(tester);
      await waitForSlotsLoaded(tester);
      await tester.pumpAndSettle();

      expect(gridIcons(Icons.help_outline), findsNothing);
      expect(slotInGrid(11), findsOneWidget);
      expect(slotIconInGrid(11, Icons.check_circle_outline), findsOneWidget);
    });


    testWidgets('FE-D06: default filters do not show active filter badge', (tester) async {
      await loadStepTwo(tester, client: mixedSlotsClient());

      expect(filterBadge(tester).isLabelVisible, isFalse);
    });

    testWidgets('FE-D07: clear filters resets hide, doctor, and date to day strip selection', (tester) async {
      await withClock(Clock.fixed(_referenceDate), () async {
        final client = mixedSlotsClient();
        await loadStepTwo(tester, client: client);

        final stripDate = _referenceDate.add(const Duration(days: 1));
        await tester.tap(find.byTooltip('Next day'));
        await tester.pump();
        await waitForSlotsLoaded(tester);
        await tester.pumpAndSettle();
        expectStripSelectedDay(tester, stripDate);

        await openFilterPopover(tester);
        await setHideFullyBookedDraft(tester, value: false);
        await selectViewDoctorFilter(tester, 'Dr. Ben');
        await selectFilterPopoverDay(tester, stripDate.day + 2);
        await applyFilterPopover(tester);
        await waitForSlotsLoaded(tester);
        await tester.pumpAndSettle();
        expect(filterBadge(tester).isLabelVisible, isTrue);

        await openFilterPopover(tester);
        await clearFilterPopover(tester);
        await waitForSlotsLoaded(tester);
        await tester.pumpAndSettle();

        expect(filterBadge(tester).isLabelVisible, isFalse);
        expectStripSelectedDay(tester, stripDate);
        expect(find.text(_slotLabel(10, datePrefix: _localDateKey(stripDate))), findsNothing);
        expect(client.lastParams?['p_local_date'], _localDateKey(stripDate));
        expect(client.lastParams?['p_preferred_doctor_id'], calendarTestDoctorAId);
      });
    });

    testWidgets('FE-D08: popover date apply updates strip and reloads slots', (tester) async {
      await withClock(Clock.fixed(_referenceDate), () async {
        final client = mixedSlotsClient();
        await loadStepTwo(tester, client: client);
        final targetDate = _referenceDate.add(const Duration(days: 1));

        await openFilterPopover(tester);
        await selectFilterPopoverDay(tester, targetDate.day);
        await applyFilterPopover(tester);
        await waitForSlotsLoaded(tester);
        await tester.pumpAndSettle();

        expectStripSelectedDay(tester, targetDate);
        expect(client.lastParams?['p_local_date'], _localDateKey(targetDate));
        expect(client.rpcCallCounts['get_simplified_booking_slots'], greaterThanOrEqualTo(2));
      });
    });

    testWidgets('FE-D09: apply closes the filter popover', (tester) async {
      await loadStepTwo(tester, client: mixedSlotsClient());

      await openFilterPopover(tester);
      expect(find.text('Filter by'), findsOneWidget);

      await setHideFullyBookedDraft(tester, value: false);
      await applyFilterPopover(tester);
      await tester.pumpAndSettle();

      expect(find.text('Filter by'), findsNothing);
    });

    testWidgets('FE-D10: filter controls disabled while step two is not enabled', (tester) async {
      final harnessKey = GlobalKey<StepTwoHarnessState>();
      await loadStepTwo(tester, client: mixedSlotsClient(), harnessKey: harnessKey);

      await openFilterPopover(tester);
      expect(find.text('Filter by'), findsOneWidget);

      harnessKey.currentState!.setEnabled(false);
      await tester.pumpAndSettle();

      final hideSwitch = tester.widget<AppSwitch>(find.byKey(const Key('simplified_booking_hide_fully_booked')));
      expect(hideSwitch.enabled, isFalse);

      final applyButton = tester.widget<AppButton>(find.widgetWithText(AppButton, 'Apply Filters'));
      expect(applyButton.onPressed, isNull);

      final clearButton = tester.widget<AppButton>(find.widgetWithText(AppButton, 'Clear Filters'));
      expect(clearButton.onPressed, isNull);
    });
  });
}
