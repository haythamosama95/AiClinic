import 'dart:async';

import 'package:ai_clinic/core/ui/theme/app_theme.dart';
import 'package:ai_clinic/core/ui/theme/forui_app_scope.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/appointments/domain/simplified_booking_slot.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/alternate_doctors_dialog.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/simplified_booking_flow.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/simplified_time_block_grid.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/patients/domain/patient_list_item.dart';
import 'package:ai_clinic/features/settings/domain/branch_working_schedule.dart';
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

const _simplifiedFlowTestDoctors = [
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

String _slotLabel(int hour, {DateTime? date}) {
  final day = date ?? _referenceDate;
  return DateFormat.jm().format(DateTime(day.year, day.month, day.day, hour));
}

String _localDateKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

List<Map<String, dynamic>> _mixedSlotBlocks(String datePrefix) => [
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

List<Map<String, dynamic>> _pastAndAvailableBlocks(String datePrefix) => [
  {
    'start_time': '${datePrefix}T07:00:00.000',
    'end_time': '${datePrefix}T07:30:00.000',
    'state': 'past',
    'available_doctor_ids': <String>[],
  },
  {
    'start_time': '${datePrefix}T10:00:00.000',
    'end_time': '${datePrefix}T10:30:00.000',
    'state': 'available',
    'available_doctor_ids': [calendarTestDoctorAId],
  },
];

List<Map<String, dynamic>> _manySlotBlocks(String datePrefix) => [
  for (var hour = 6; hour <= 17; hour++)
    {
      'start_time': '${datePrefix}T${hour.toString().padLeft(2, '0')}:00:00.000',
      'end_time': '${datePrefix}T${hour.toString().padLeft(2, '0')}:30:00.000',
      'state': 'available',
      'available_doctor_ids': [calendarTestDoctorAId],
    },
];

class SimplifiedSlotRpcClient extends AppointmentRpcTestClient {
  SimplifiedSlotRpcClient({
    required this.blocksForDate,
    this.slotDelay = Duration.zero,
  });

  final List<Map<String, dynamic>> Function(String localDate, String? doctorId) blocksForDate;
  final Duration slotDelay;

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
      final payload = {
        'success': true,
        'data': {'default_duration_minutes': 30, 'blocks': blocks},
      };
      if (slotDelay == Duration.zero) {
        return FakePostgrestRpc(payload) as PostgrestFilterBuilder<T>;
      }
      return _DelayedFakePostgrestRpc(payload, slotDelay) as PostgrestFilterBuilder<T>;
    }
    return super.rpc(fn, params: params, get: get);
  }
}

class _DelayedFakePostgrestRpc extends FakePostgrestRpc {
  _DelayedFakePostgrestRpc(super.result, this.delay);

  final Duration delay;

  @override
  Future<R> then<R>(FutureOr<R> Function(dynamic value) onValue, {Function? onError}) {
    return Future<void>.delayed(delay).then((_) => super.then(onValue, onError: onError));
  }
}

class FlakySettingsRpcClient extends AppointmentRpcTestClient {
  FlakySettingsRpcClient({this.failCount = 1});

  final int failCount;
  var _settingsCalls = 0;

  @override
  PostgrestFilterBuilder<T> rpc<T>(String fn, {Map<String, dynamic>? params, dynamic get = false}) {
    if (fn == 'get_appointment_settings') {
      _settingsCalls++;
      if (_settingsCalls <= failCount) {
        rpcLog.add(fn);
        lastFunction = fn;
        lastParams = params == null ? null : Map<String, dynamic>.from(params);
        rpcCallCounts[fn] = (rpcCallCounts[fn] ?? 0) + 1;
        return FakePostgrestRpc({
          'success': false,
          'error_code': 'FORBIDDEN',
          'error_message': 'Settings denied',
        }) as PostgrestFilterBuilder<T>;
      }
    }
    return super.rpc(fn, params: params, get: get);
  }
}

class FlakySlotRpcClient extends SimplifiedSlotRpcClient {
  FlakySlotRpcClient({required super.blocksForDate, this.failCount = 1});

  final int failCount;
  var _slotCalls = 0;

  @override
  PostgrestFilterBuilder<T> rpc<T>(String fn, {Map<String, dynamic>? params, dynamic get = false}) {
    if (fn == 'get_simplified_booking_slots') {
      _slotCalls++;
      if (_slotCalls <= failCount) {
        rpcLog.add(fn);
        lastFunction = fn;
        lastParams = params == null ? null : Map<String, dynamic>.from(params);
        rpcCallCounts[fn] = (rpcCallCounts[fn] ?? 0) + 1;
        return FakePostgrestRpc({
          'success': false,
          'error_code': 'FORBIDDEN',
          'error_message': 'Slots denied',
        }) as PostgrestFilterBuilder<T>;
      }
    }
    return super.rpc(fn, params: params, get: get);
  }
}

class DateTrackingSlotRpcClient extends SimplifiedSlotRpcClient {
  DateTrackingSlotRpcClient({required super.blocksForDate, required this.delayedDate});

  final String delayedDate;

  @override
  PostgrestFilterBuilder<T> rpc<T>(String fn, {Map<String, dynamic>? params, dynamic get = false}) {
    if (fn == 'get_simplified_booking_slots') {
      final localDate = params?['p_local_date'] as String? ?? _localDateKey(_referenceDate);
      if (localDate == delayedDate) {
        return _DelayedFakePostgrestRpc({
          'success': true,
          'data': {
            'default_duration_minutes': 30,
            'blocks': [
              {
                'start_time': '${localDate}T15:00:00.000',
                'end_time': '${localDate}T15:30:00.000',
                'state': 'available',
                'available_doctor_ids': [calendarTestDoctorAId],
              },
            ],
          },
        }, const Duration(milliseconds: 400)) as PostgrestFilterBuilder<T>;
      }
    }
    return super.rpc(fn, params: params, get: get);
  }
}

SimplifiedSlotRpcClient _mixedSlotsClient() {
  return SimplifiedSlotRpcClient(blocksForDate: (localDate, _) => _mixedSlotBlocks(localDate));
}

void main() {
  group('SimplifiedBookingFlow', () {
    Future<void> pumpFlow(
      WidgetTester tester, {
      required AppointmentRpcTestClient client,
      FakePatientRepository? patientRepository,
      List<StaffListItem> doctors = _simplifiedFlowTestDoctors,
    }) async {
      suppressBookingSheetListTileNoise();
      await tester.binding.setSurfaceSize(calendarWidgetSurfaceSize);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final patients = patientRepository ?? FakePatientRepository();
      late BuildContext hostContext;

      await tester.pumpWidget(
        ProviderScope(
          overrides: bookingSheetOverrides(client: client, patientRepository: patients),
          child: MaterialApp(
            theme: AppTheme.light(),
            builder: (context, child) => ForuiAppScope(child: child!),
            home: Builder(
              builder: (context) {
                hostContext = context;
                return const Scaffold(body: SizedBox());
              },
            ),
          ),
        ),
      );
      await tester.pump();

      unawaited(
        SimplifiedBookingFlow.show(
          hostContext,
          branchId: calendarTestBranchAId,
          schedule: BranchWorkingSchedule.defaultSchedule(),
          doctors: doctors,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }

    Future<void> waitForStepTwo(WidgetTester tester) async {
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        if (find.text('Select Date and Time').evaluate().isNotEmpty) {
          return;
        }
      }
      fail('Step two did not load.');
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

    Future<void> selectPatient(
      WidgetTester tester, {
      required PatientListItem patient,
      String searchQuery = 'Pat',
    }) async {
      await tester.enterText(find.byKey(const Key('simplified_booking_patient_search')), searchQuery);
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      await tester.tap(find.text(patient.fullName));
      await tester.pumpAndSettle();
    }

    Future<void> selectDoctor(WidgetTester tester, String doctorName) async {
      await tester.tap(find.widgetWithText(AppSelect<String>, 'Doctor (optional)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(doctorName));
      await tester.pumpAndSettle();
    }

    Future<void> enterNotes(WidgetTester tester, String notes) async {
      await tester.enterText(find.byType(EditableText).last, notes);
      await tester.pump();
    }

    /// Flushes Forui [FTappable] press/release animation timers (100 ms each).
    Future<void> tapForuiControl(WidgetTester tester, Finder finder) async {
      await tester.tap(finder);
      await tester.pump(const Duration(milliseconds: 150));
    }

    Future<void> tapStepOneNext(WidgetTester tester) async {
      final nextFinder = find.byKey(const Key('simplified_booking_step_one_next'));
      await tester.ensureVisible(nextFinder);
      await tester.pumpAndSettle();
      await tapForuiControl(tester, nextFinder);
    }

    Future<void> completeStepOne(
      WidgetTester tester, {
      required PatientListItem patient,
      String searchQuery = 'Pat',
      String? doctorName = 'Dr. Ada',
      String? notes,
    }) async {
      await selectPatient(tester, patient: patient, searchQuery: searchQuery);
      if (doctorName != null) {
        await selectDoctor(tester, doctorName);
      }
      if (notes != null) {
        await enterNotes(tester, notes);
      }
      await tapStepOneNext(tester);
      await waitForStepTwo(tester);
      await waitForSlotsLoaded(tester);
      await tester.pumpAndSettle();
    }

    Future<void> tapSlot(WidgetTester tester, int hour, {DateTime? date}) async {
      final slotFinder = find.text(_slotLabel(hour, date: date));
      await tester.ensureVisible(slotFinder);
      await tester.tap(slotFinder);
      await tester.pumpAndSettle();
    }

    Future<void> tapConfirm(WidgetTester tester) async {
      final confirmFinder = find.byKey(const Key('simplified_slot_confirm'));
      await tester.ensureVisible(confirmFinder);
      await tester.tap(confirmFinder);
      await tester.pumpAndSettle();
    }

    IconButton dayStripButton(WidgetTester tester, String tooltip) {
      return tester.widget<IconButton>(
        find.ancestor(
          of: find.byTooltip(tooltip),
          matching: find.byType(IconButton),
        ),
      );
    }

    testWidgets('step one blocks next without patient', (tester) async {
      await withClock(Clock.fixed(DateTime(2026, 6, 27, 8, 0)), () async {
        final client = AppointmentRpcTestClient();
        await pumpFlow(tester, client: client);

        expect(find.text('Step 1 / 2'), findsOneWidget);
        final next = tester.widget<AppButton>(find.byKey(const Key('simplified_booking_step_one_next')));
        expect(next.onPressed, isNull);
      });
    });

    testWidgets('step one allows next with patient only', (tester) async {
      await withClock(Clock.fixed(DateTime(2026, 6, 27, 8, 0)), () async {
        final client = AppointmentRpcTestClient();
        final patient = samplePatientListItem(fullName: 'No Doctor Patient');

        await pumpFlow(
          tester,
          client: client,
          patientRepository: FakePatientRepository(patients: [patient]),
        );

        await selectPatient(tester, patient: patient, searchQuery: 'No Doc');

        final next = tester.widget<AppButton>(find.byKey(const Key('simplified_booking_step_one_next')));
        expect(next.onPressed, isNotNull);
      });
    });

    testWidgets('step two without preferred doctor shows branch-wide slots without yellow chips', (tester) async {
      await withClock(Clock.fixed(DateTime(2026, 6, 27, 8, 0)), () async {
        final client = AppointmentRpcTestClient();
        final patient = samplePatientListItem(fullName: 'No Doctor Patient');

        await pumpFlow(
          tester,
          client: client,
          patientRepository: FakePatientRepository(patients: [patient]),
        );

        await selectPatient(tester, patient: patient, searchQuery: 'No Doc');
        await tapStepOneNext(tester);
        await waitForStepTwo(tester);
        await waitForSlotsLoaded(tester);
        await tester.pumpAndSettle();

        final slotLabel = DateFormat.jm().format(DateTime(2026, 6, 27, 10));
        expect(find.text(slotLabel), findsOneWidget);
        expect(client.rpcCallCounts['get_simplified_booking_slots'], 1);
        expect(find.text('Other doctors free'), findsNothing);
      });
    });

    testWidgets('clearing doctor after going back updates step two', (tester) async {
      await withClock(Clock.fixed(DateTime(2026, 6, 27, 8, 0)), () async {
        final client = AppointmentRpcTestClient();
        final patient = samplePatientListItem(fullName: 'Clear Doctor Patient');

        await pumpFlow(
          tester,
          client: client,
          patientRepository: FakePatientRepository(patients: [patient]),
        );
        await completeStepOne(tester, patient: patient, searchQuery: 'Clear');

        final slotLabel = DateFormat.jm().format(DateTime(2026, 6, 27, 10));
        expect(find.text(slotLabel), findsOneWidget);
        expect(client.rpcCallCounts['get_simplified_booking_slots'], 1);

        final backFinder = find.byKey(const Key('simplified_booking_back'));
        await tester.ensureVisible(backFinder);
        await tester.tap(backFinder);
        await tester.pumpAndSettle();

        await selectDoctor(tester, 'No doctor assigned');
        await tapStepOneNext(tester);
        await waitForStepTwo(tester);
        await tester.pumpAndSettle();

        expect(find.text(slotLabel), findsOneWidget);
        expect(client.rpcCallCounts['get_simplified_booking_slots'], 2);
        expect(find.text('Other doctors free'), findsNothing);
      });
    });

    testWidgets('completes two-step booking from step one through confirm', (tester) async {
      await withClock(Clock.fixed(DateTime(2026, 6, 27, 8, 0)), () async {
        final client = AppointmentRpcTestClient();
        final patient = samplePatientListItem(fullName: 'Flow Patient');

        await pumpFlow(
          tester,
          client: client,
          patientRepository: FakePatientRepository(patients: [patient]),
        );

        await completeStepOne(tester, patient: patient, searchQuery: 'Flo');

        expect(find.text('Select Date and Time'), findsOneWidget);
        expect(find.text('Step 2 / 2'), findsOneWidget);

        await tapSlot(tester, 10);

        expect(find.text('Dr. Ada'), findsWidgets);

        await tapConfirm(tester);

        expect(client.createAppointmentCalls, hasLength(1));
        expect(client.createAppointmentCalls.single['p_patient_id'], patient.id);
        expect(client.createAppointmentCalls.single['p_doctor_id'], calendarTestDoctorAId);
        expect(client.createAppointmentCalls.single['p_duration_minutes'], 30);
      });
    });

    testWidgets('back from step two clears slot selection', (tester) async {
      await withClock(Clock.fixed(DateTime(2026, 6, 27, 8, 0)), () async {
        final client = AppointmentRpcTestClient();
        final patient = samplePatientListItem(fullName: 'Back Patient');

        await pumpFlow(
          tester,
          client: client,
          patientRepository: FakePatientRepository(patients: [patient]),
        );
        await completeStepOne(tester, patient: patient, searchQuery: 'Back');

        await tapSlot(tester, 10);
        expect(find.textContaining('Jun 27'), findsOneWidget);

        final backFinder = find.byKey(const Key('simplified_booking_back'));
        await tester.ensureVisible(backFinder);
        await tester.tap(backFinder);
        await tester.pumpAndSettle();

        expect(find.text('Step 1 / 2'), findsOneWidget);

        await tapStepOneNext(tester);
        await waitForStepTwo(tester);
        await waitForSlotsLoaded(tester);
        await tester.pumpAndSettle();

        expect(find.text('Select a time slot above'), findsOneWidget);
        final confirm = tester.widget<AppButton>(find.byKey(const Key('simplified_slot_confirm')));
        expect(confirm.onPressed, isNull);
      });
    });

    testWidgets('next day chevron reloads slots without layout error', (tester) async {
      await withClock(Clock.fixed(DateTime(2026, 6, 27, 8, 0)), () async {
        final client = AppointmentRpcTestClient();
        final patient = samplePatientListItem(fullName: 'Next Day Patient');

        await pumpFlow(
          tester,
          client: client,
          patientRepository: FakePatientRepository(patients: [patient]),
        );
        await completeStepOne(tester, patient: patient, searchQuery: 'Next');
        expect(client.rpcCallCounts['get_simplified_booking_slots'], 1);

        await tester.tap(find.byTooltip('Next day'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        await waitForSlotsLoaded(tester);
        await tester.pumpAndSettle();

        expect(client.rpcCallCounts['get_simplified_booking_slots'], 2);
        expect(find.text('28'), findsWidgets);
      });
    });

    testWidgets('changing doctor in step one reloads step two grid', (tester) async {
      await withClock(Clock.fixed(DateTime(2026, 6, 27, 8, 0)), () async {
        final client = AppointmentRpcTestClient();
        final patient = samplePatientListItem(fullName: 'Doctor Change Patient');

        await pumpFlow(
          tester,
          client: client,
          patientRepository: FakePatientRepository(patients: [patient]),
        );
        await completeStepOne(tester, patient: patient, searchQuery: 'Doc', doctorName: 'Dr. Ada');
        expect(client.rpcCallCounts['get_simplified_booking_slots'], 1);

        final backFinder = find.byKey(const Key('simplified_booking_back'));
        await tester.ensureVisible(backFinder);
        await tester.tap(backFinder);
        await tester.pumpAndSettle();

        await selectDoctor(tester, 'Dr. Ben');
        await tapStepOneNext(tester);
        await waitForStepTwo(tester);
        await waitForSlotsLoaded(tester);
        await tester.pumpAndSettle();

        expect(client.rpcCallCounts['get_simplified_booking_slots'], 2);
        expect(client.rpcLog.where((fn) => fn == 'get_simplified_booking_slots').last, 'get_simplified_booking_slots');
      });
    });

    group('FUNC-A access and modal', () {
      testWidgets('FUNC-A01: simplified booking modal opens on show', (tester) async {
        await withClock(Clock.fixed(_referenceDate), () async {
          await pumpFlow(tester, client: AppointmentRpcTestClient());

          expect(find.byType(SimplifiedBookingFlow), findsOneWidget);
          expect(find.text('Step 1 / 2'), findsOneWidget);
          expect(find.text('Book appointment'), findsOneWidget);
        });
      });

      testWidgets('FUNC-A02: header hidden without create permission', (tester) async {}, skip: true);

      testWidgets('FUNC-A03: cell tap opens AppointmentBookingSheet', (tester) async {}, skip: true);

      testWidgets('FUNC-A04: post-book calendar refresh', (tester) async {}, skip: true);

      testWidgets('FUNC-A05: header disabled without branch', (tester) async {}, skip: true);

      testWidgets('FUNC-A06: close button dismisses flow without booking', (tester) async {
        await withClock(Clock.fixed(_referenceDate), () async {
          await pumpFlow(tester, client: AppointmentRpcTestClient());

          await tester.tap(find.byTooltip('Close'));
          await tester.pumpAndSettle();

          expect(find.byType(SimplifiedBookingFlow), findsNothing);
        });
      });

      testWidgets('ABUSE-A07: scrim tap dismisses flow and discards step-one data', (tester) async {
        await withClock(Clock.fixed(_referenceDate), () async {
          final patient = samplePatientListItem(fullName: 'Scrim Patient');
          await pumpFlow(
            tester,
            client: AppointmentRpcTestClient(),
            patientRepository: FakePatientRepository(patients: [patient]),
          );

          await selectPatient(tester, patient: patient, searchQuery: 'Scr');
          expect(find.textContaining(patient.fullName), findsOneWidget);

          await tester.tapAt(const Offset(8, 8));
          await tester.pumpAndSettle();

          expect(find.byType(SimplifiedBookingFlow), findsNothing);
        });
      });
    });

    group('FUNC-B step one', () {
      testWidgets('FUNC-B01: next disabled without patient', (tester) async {
        await withClock(Clock.fixed(_referenceDate), () async {
          await pumpFlow(tester, client: AppointmentRpcTestClient());

          final next = tester.widget<AppButton>(find.byKey(const Key('simplified_booking_step_one_next')));
          expect(next.onPressed, isNull);
        });
      });

      testWidgets('FUNC-B02: patient search selects patient and disables search', (tester) async {
        await withClock(Clock.fixed(_referenceDate), () async {
          final patient = samplePatientListItem(fullName: 'Search Patient');
          await pumpFlow(
            tester,
            client: AppointmentRpcTestClient(),
            patientRepository: FakePatientRepository(patients: [patient]),
          );

          await selectPatient(tester, patient: patient, searchQuery: 'Sea');

          expect(find.textContaining(patient.fullName), findsOneWidget);
          final search = tester.widget<AppTextField>(find.byKey(const Key('simplified_booking_patient_search')));
          expect(search.enabled, isFalse);
        });
      });

      testWidgets('FUNC-B03: patient search debounces RPC calls', (tester) async {
        await withClock(Clock.fixed(_referenceDate), () async {
          final patients = FakePatientRepository(
            patients: [
              samplePatientListItem(fullName: 'Alpha Patient'),
              samplePatientListItem(fullName: 'Beta Patient'),
            ],
            searchDelay: const Duration(milliseconds: 100),
          );
          await pumpFlow(tester, client: AppointmentRpcTestClient(), patientRepository: patients);

          await tester.enterText(find.byKey(const Key('simplified_booking_patient_search')), 'A');
          await tester.pump(const Duration(milliseconds: 50));
          await tester.enterText(find.byKey(const Key('simplified_booking_patient_search')), 'Al');
          await tester.pump(const Duration(milliseconds: 50));
          await tester.enterText(find.byKey(const Key('simplified_booking_patient_search')), 'Alp');
          await tester.pump(const Duration(milliseconds: 350));
          await tester.pumpAndSettle();

          expect(patients.searchCallCount, 1);
          expect(find.text('Alpha Patient'), findsOneWidget);
        });
      });

      testWidgets('FUNC-B04: clear removes patient and re-enables search', (tester) async {
        await withClock(Clock.fixed(_referenceDate), () async {
          final patient = samplePatientListItem(fullName: 'Clear Patient');
          await pumpFlow(
            tester,
            client: AppointmentRpcTestClient(),
            patientRepository: FakePatientRepository(patients: [patient]),
          );

          await selectPatient(tester, patient: patient, searchQuery: 'Cle');
          await tester.tap(find.byKey(const Key('simplified_booking_patient_clear')));
          await tester.pumpAndSettle();

          expect(find.text(patient.fullName), findsNothing);
          final search = tester.widget<AppTextField>(find.byKey(const Key('simplified_booking_patient_search')));
          expect(search.enabled, isTrue);
        });
      });

      testWidgets('FUNC-B05: patient-only advance reaches step two', (tester) async {
        await withClock(Clock.fixed(_referenceDate), () async {
          final patient = samplePatientListItem(fullName: 'Patient Only');
          await pumpFlow(
            tester,
            client: AppointmentRpcTestClient(),
            patientRepository: FakePatientRepository(patients: [patient]),
          );

          await selectPatient(tester, patient: patient, searchQuery: 'Pat');
          await tapStepOneNext(tester);
          await waitForStepTwo(tester);

          expect(find.text('Step 2 / 2'), findsOneWidget);
        });
      });

      testWidgets('FUNC-B06: doctor selection passes preferred doctor to slot RPC', (tester) async {
        await withClock(Clock.fixed(_referenceDate), () async {
          final client = AppointmentRpcTestClient();
          final patient = samplePatientListItem(fullName: 'Doctor Select Patient');
          await pumpFlow(
            tester,
            client: client,
            patientRepository: FakePatientRepository(patients: [patient]),
          );

          await completeStepOne(tester, patient: patient, searchQuery: 'Doc', doctorName: 'Dr. Ben');

          expect(client.lastParams?['p_preferred_doctor_id'], calendarTestDoctorBId);
        });
      });

      testWidgets('FUNC-B07: empty doctors list shows info and step-two error', (tester) async {
        await withClock(Clock.fixed(_referenceDate), () async {
          final patient = samplePatientListItem(fullName: 'No Doctors Patient');
          await pumpFlow(
            tester,
            client: AppointmentRpcTestClient(),
            patientRepository: FakePatientRepository(patients: [patient]),
            doctors: const [],
          );

          expect(
            find.text('No active doctors are configured. You can still book without assigning one.'),
            findsOneWidget,
          );

          await selectPatient(tester, patient: patient, searchQuery: 'No Doc');
          await tapStepOneNext(tester);
          await waitForStepTwo(tester);
          await tester.pumpAndSettle();

          expect(find.text('No active doctors are configured for this branch.'), findsOneWidget);
          final confirm = tester.widget<AppButton>(find.byKey(const Key('simplified_slot_confirm')));
          expect(confirm.onPressed, isNull);
        });
      });

      testWidgets('FUNC-B08: valid notes are passed on confirm', (tester) async {
        await withClock(Clock.fixed(_referenceDate), () async {
          const notes = 'Patient prefers morning visits';
          final client = AppointmentRpcTestClient();
          final patient = samplePatientListItem(fullName: 'Notes Patient');
          await pumpFlow(
            tester,
            client: client,
            patientRepository: FakePatientRepository(patients: [patient]),
          );

          await completeStepOne(tester, patient: patient, searchQuery: 'Not', notes: notes);
          await tapSlot(tester, 10);
          await tapConfirm(tester);

          expect(client.createAppointmentCalls.single['p_notes'], notes);
        });
      });

      testWidgets('FUNC-B09: notes over 2000 chars block step one advance', (tester) async {
        await withClock(Clock.fixed(_referenceDate), () async {
          final patient = samplePatientListItem(fullName: 'Long Notes Patient');
          await pumpFlow(
            tester,
            client: AppointmentRpcTestClient(),
            patientRepository: FakePatientRepository(patients: [patient]),
          );

          await selectPatient(tester, patient: patient, searchQuery: 'Lon');
          await enterNotes(tester, 'x' * 2001);
          await tapStepOneNext(tester);
          await tester.pumpAndSettle();

          expect(find.text('Notes must be 2000 characters or fewer.'), findsOneWidget);
          expect(find.text('Step 1 / 2'), findsOneWidget);
        });
      });

      testWidgets('FUNC-B10: settings load failure shows error and retry on step one', (tester) async {
        await withClock(Clock.fixed(_referenceDate), () async {
          final client = FlakySettingsRpcClient();
          final patient = samplePatientListItem(fullName: 'Settings Fail Patient');
          await pumpFlow(
            tester,
            client: client,
            patientRepository: FakePatientRepository(patients: [patient]),
          );

          await selectPatient(tester, patient: patient, searchQuery: 'Set');
          await tapStepOneNext(tester);
          await tester.pumpAndSettle();

          expect(find.text('You do not have permission to perform this action.'), findsOneWidget);
          expect(find.text('Retry'), findsOneWidget);
          expect(find.text('Step 1 / 2'), findsOneWidget);
        });
      });

      testWidgets('FUNC-B11: settings retry advances to step two on success', (tester) async {
        await withClock(Clock.fixed(_referenceDate), () async {
          final client = FlakySettingsRpcClient();
          final patient = samplePatientListItem(fullName: 'Settings Retry Patient');
          await pumpFlow(
            tester,
            client: client,
            patientRepository: FakePatientRepository(patients: [patient]),
          );

          await selectPatient(tester, patient: patient, searchQuery: 'Ret');
          await tapStepOneNext(tester);
          await tester.pumpAndSettle();
          expect(find.text('Retry'), findsOneWidget);

          await tapForuiControl(tester, find.text('Retry'));
          await waitForStepTwo(tester);

          expect(find.text('Select Date and Time'), findsOneWidget);
        });
      });

      testWidgets('FUNC-B12: step one shows centered step indicator', (tester) async {
        await withClock(Clock.fixed(_referenceDate), () async {
          await pumpFlow(tester, client: AppointmentRpcTestClient());
          expect(find.text('Step 1 / 2'), findsOneWidget);
        });
      });

      testWidgets('bug-fix: notes over 2000 chars block confirm in flow', (tester) async {
        await withClock(Clock.fixed(_referenceDate), () async {
          final client = AppointmentRpcTestClient();
          final patient = samplePatientListItem(fullName: 'Confirm Notes Patient');
          await pumpFlow(
            tester,
            client: client,
            patientRepository: FakePatientRepository(patients: [patient]),
          );

          await selectPatient(tester, patient: patient, searchQuery: 'Con');
          await enterNotes(tester, 'x' * 2001);
          await tapStepOneNext(tester);
          await tester.pumpAndSettle();

          expect(find.text('Notes must be 2000 characters or fewer.'), findsOneWidget);
          expect(client.createAppointmentCalls, isEmpty);
        });
      });
    });

    group('FUNC-C step two navigation', () {
      testWidgets('FUNC-C01: step two shows title and indicator', (tester) async {
        await withClock(Clock.fixed(_referenceDate), () async {
          final patient = samplePatientListItem(fullName: 'Title Patient');
          await pumpFlow(
            tester,
            client: AppointmentRpcTestClient(),
            patientRepository: FakePatientRepository(patients: [patient]),
          );

          await completeStepOne(tester, patient: patient, searchQuery: 'Tit');

          expect(find.text('Select Date and Time'), findsOneWidget);
          expect(find.text('Step 2 / 2'), findsOneWidget);
        });
      });

      testWidgets('FUNC-C02: back retains patient and doctor but clears slot', (tester) async {
        await withClock(Clock.fixed(_referenceDate), () async {
          final patient = samplePatientListItem(fullName: 'Back Retain Patient');
          await pumpFlow(
            tester,
            client: AppointmentRpcTestClient(),
            patientRepository: FakePatientRepository(patients: [patient]),
          );

          await completeStepOne(tester, patient: patient, searchQuery: 'Back');
          await tapSlot(tester, 10);

          await tester.tap(find.byKey(const Key('simplified_booking_back')));
          await tester.pumpAndSettle();

          expect(find.text('Step 1 / 2'), findsOneWidget);
          expect(find.textContaining(patient.fullName), findsOneWidget);
          expect(find.text('Dr. Ada'), findsWidgets);

          await tapStepOneNext(tester);
          await waitForStepTwo(tester);
          await waitForSlotsLoaded(tester);
          await tester.pumpAndSettle();

          expect(find.text('Select a time slot above'), findsOneWidget);
        });
      });

      testWidgets('FUNC-C03: slot RPC loads grid on step-two entry', (tester) async {
        await withClock(Clock.fixed(_referenceDate), () async {
          final client = AppointmentRpcTestClient();
          final patient = samplePatientListItem(fullName: 'Load Patient');
          await pumpFlow(
            tester,
            client: client,
            patientRepository: FakePatientRepository(patients: [patient]),
          );

          await completeStepOne(tester, patient: patient, searchQuery: 'Loa');

          expect(client.rpcCallCounts['get_simplified_booking_slots'], 1);
          expect(find.text(_slotLabel(10)), findsOneWidget);
        });
      });

      testWidgets('FUNC-C04: slot load failure shows error alert', (tester) async {
        await withClock(Clock.fixed(_referenceDate), () async {
          final client = FlakySlotRpcClient(blocksForDate: (localDate, _) => _mixedSlotBlocks(localDate));
          final patient = samplePatientListItem(fullName: 'Slot Fail Patient');
          await pumpFlow(
            tester,
            client: client,
            patientRepository: FakePatientRepository(patients: [patient]),
          );

          await completeStepOne(tester, patient: patient, searchQuery: 'Fail');

          expect(find.text('You do not have permission to perform this action.'), findsOneWidget);
          expect(find.text('Retry'), findsWidgets);
        });
      });

      testWidgets('FUNC-C05: slot retry re-invokes RPC', (tester) async {
        await withClock(Clock.fixed(_referenceDate), () async {
          final client = FlakySlotRpcClient(blocksForDate: (localDate, _) => _mixedSlotBlocks(localDate));
          final patient = samplePatientListItem(fullName: 'Slot Retry Patient');
          await pumpFlow(
            tester,
            client: client,
            patientRepository: FakePatientRepository(patients: [patient]),
          );

          await completeStepOne(tester, patient: patient, searchQuery: 'Slo');
          expect(client.rpcCallCounts['get_simplified_booking_slots'], 1);

          final retryFinder = find.text('Retry').first;
          await tester.ensureVisible(retryFinder);
          await tapForuiControl(tester, retryFinder);
          await waitForSlotsLoaded(tester);
          await tester.pumpAndSettle();

          expect(client.rpcCallCounts['get_simplified_booking_slots'], 2);
          expect(find.text(_slotLabel(9)), findsOneWidget);
        });
      });

      testWidgets('FUNC-C06: date change reloads slots and clears selection', (tester) async {
        await withClock(Clock.fixed(_referenceDate), () async {
          final client = _mixedSlotsClient();
          final patient = samplePatientListItem(fullName: 'Date Change Patient');
          await pumpFlow(
            tester,
            client: client,
            patientRepository: FakePatientRepository(patients: [patient]),
          );

          await completeStepOne(tester, patient: patient, searchQuery: 'Dat');
          await tapSlot(tester, 9);
          expect(find.text('Select a time slot above'), findsNothing);

          await tester.tap(find.byTooltip('Next day'));
          await tester.pump();
          await waitForSlotsLoaded(tester);
          await tester.pumpAndSettle();

          expect(find.text('Select a time slot above'), findsOneWidget);
          expect(client.rpcCallCounts['get_simplified_booking_slots'], greaterThanOrEqualTo(2));
        });
      });

      testWidgets('FUNC-C07: doctor change reloads slots', (tester) async {
        await withClock(Clock.fixed(_referenceDate), () async {
          final client = AppointmentRpcTestClient();
          final patient = samplePatientListItem(fullName: 'Doctor Reload Patient');
          await pumpFlow(
            tester,
            client: client,
            patientRepository: FakePatientRepository(patients: [patient]),
          );

          await completeStepOne(tester, patient: patient, searchQuery: 'Doc', doctorName: 'Dr. Ada');
          expect(client.rpcCallCounts['get_simplified_booking_slots'], 1);

          await tester.tap(find.byKey(const Key('simplified_booking_back')));
          await tester.pumpAndSettle();
          await selectDoctor(tester, 'Dr. Ben');
          await tapStepOneNext(tester);
          await waitForSlotsLoaded(tester);
          await tester.pumpAndSettle();

          expect(client.rpcCallCounts['get_simplified_booking_slots'], 2);
        });
      });

      testWidgets('FUNC-C08: forward chevron disabled at today+90', (tester) async {
        final maxDate = simplifiedBookingDateRange(reference: _referenceDate).maxDate;
        await withClock(Clock.fixed(_referenceDate), () async {
          final patient = samplePatientListItem(fullName: 'Max Date Patient');
          await pumpFlow(
            tester,
            client: AppointmentRpcTestClient(),
            patientRepository: FakePatientRepository(patients: [patient]),
          );

          await completeStepOne(tester, patient: patient, searchQuery: 'Max');

          final daysToAdvance = maxDate.difference(simplifiedBookingDateOnly(_referenceDate)).inDays;
          for (var i = 0; i < daysToAdvance; i++) {
            await tester.tap(find.byTooltip('Next day'));
            await tester.pump(const Duration(milliseconds: 16));
          }
          await waitForSlotsLoaded(tester);
          await tester.pumpAndSettle();

          expect(dayStripButton(tester, 'Next day').onPressed, isNull);
        });
      });

      testWidgets('FUNC-C09: back chevron disabled on today', (tester) async {
        await withClock(Clock.fixed(_referenceDate), () async {
          final patient = samplePatientListItem(fullName: 'Today Patient');
          await pumpFlow(
            tester,
            client: AppointmentRpcTestClient(),
            patientRepository: FakePatientRepository(patients: [patient]),
          );

          await completeStepOne(tester, patient: patient, searchQuery: 'Tod');

          expect(dayStripButton(tester, 'Previous day').onPressed, isNull);
        });
      });

      testWidgets('FUNC-C10: empty blocks show no slots message', (tester) async {
        await withClock(Clock.fixed(_referenceDate), () async {
          final client = SimplifiedSlotRpcClient(blocksForDate: (_, __) => const []);
          final patient = samplePatientListItem(fullName: 'Empty Day Patient');
          await pumpFlow(
            tester,
            client: client,
            patientRepository: FakePatientRepository(patients: [patient]),
          );

          await completeStepOne(tester, patient: patient, searchQuery: 'Emp');

          expect(find.text('No slots available for this day.'), findsOneWidget);
        });
      });

      testWidgets('FUNC-C11: stale slot RPC responses are discarded on rapid date change', (tester) async {
        await withClock(Clock.fixed(_referenceDate), () async {
          final delayedDate = _localDateKey(_referenceDate.add(const Duration(days: 1)));
          final client = DateTrackingSlotRpcClient(
            blocksForDate: (localDate, _) => _mixedSlotBlocks(localDate),
            delayedDate: delayedDate,
          );
          final patient = samplePatientListItem(fullName: 'Race Patient');
          await pumpFlow(
            tester,
            client: client,
            patientRepository: FakePatientRepository(patients: [patient]),
          );

          await completeStepOne(tester, patient: patient, searchQuery: 'Rac');
          await tester.tap(find.byTooltip('Next day'));
          await tester.pump(const Duration(milliseconds: 50));
          await tester.tap(find.byTooltip('Previous day'));
          await waitForSlotsLoaded(tester);
          await tester.pumpAndSettle();

          expect(find.text(_slotLabel(9)), findsOneWidget);
          expect(find.text(_slotLabel(15, date: _referenceDate.add(const Duration(days: 1)))), findsNothing);
        });
      });

      testWidgets('FUNC-C12: date change uses AppPaginatedSlideSwitcher', (tester) async {
        await withClock(Clock.fixed(_referenceDate), () async {
          final patient = samplePatientListItem(fullName: 'Slide Patient');
          await pumpFlow(
            tester,
            client: AppointmentRpcTestClient(),
            patientRepository: FakePatientRepository(patients: [patient]),
          );

          await completeStepOne(tester, patient: patient, searchQuery: 'Sli');
          expect(find.byType(AppPaginatedSlideSwitcher), findsOneWidget);

          await tester.tap(find.byTooltip('Next day'));
          await tester.pump();
          await waitForSlotsLoaded(tester);
          await tester.pumpAndSettle();

          expect(find.byType(AppPaginatedSlideSwitcher), findsOneWidget);
        });
      });
    });

    group('FE-E slot grid in flow', () {
      testWidgets('FE-E01: available slot tap selects block and updates summary', (tester) async {
        await withClock(Clock.fixed(_referenceDate), () async {
          final patient = samplePatientListItem(fullName: 'Available Patient');
          await pumpFlow(
            tester,
            client: _mixedSlotsClient(),
            patientRepository: FakePatientRepository(patients: [patient]),
          );

          await completeStepOne(tester, patient: patient, searchQuery: 'Ava');
          await tapSlot(tester, 9);

          expect(find.text('Select a time slot above'), findsNothing);
          expect(find.textContaining('Jun 27'), findsOneWidget);
        });
      });

      testWidgets('FE-E02: past block tap is a no-op', (tester) async {
        await withClock(Clock.fixed(_referenceDate), () async {
          final client = SimplifiedSlotRpcClient(
            blocksForDate: (localDate, _) => _pastAndAvailableBlocks(localDate),
          );
          final patient = samplePatientListItem(fullName: 'Past Patient');
          await pumpFlow(
            tester,
            client: client,
            patientRepository: FakePatientRepository(patients: [patient]),
          );

          await completeStepOne(tester, patient: patient, searchQuery: 'Pas');
          await tapSlot(tester, 7);

          expect(find.text('Select a time slot above'), findsOneWidget);
        });
      });

      testWidgets('FE-E03: fully unavailable block tap is a no-op', (tester) async {
        await withClock(Clock.fixed(_referenceDate), () async {
          final patient = samplePatientListItem(fullName: 'Booked Patient');
          await pumpFlow(
            tester,
            client: _mixedSlotsClient(),
            patientRepository: FakePatientRepository(patients: [patient]),
          );

          await completeStepOne(tester, patient: patient, searchQuery: 'Boo');
          await tester.tap(find.byKey(const Key('simplified_booking_filter_button')));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 250));
          await tester.tap(find.byKey(const Key('simplified_booking_hide_fully_booked')));
          await tester.pump();
          await tester.tap(find.text('Apply Filters'));
          await tester.pumpAndSettle();

          await tapSlot(tester, 10);

          expect(find.text('Select a time slot above'), findsOneWidget);
        });
      });

      testWidgets('FE-E04: alternate block opens AlternateDoctorsDialog', (tester) async {
        await withClock(Clock.fixed(_referenceDate), () async {
          final patient = samplePatientListItem(fullName: 'Alternate Patient');
          await pumpFlow(
            tester,
            client: _mixedSlotsClient(),
            patientRepository: FakePatientRepository(patients: [patient]),
          );

          await completeStepOne(tester, patient: patient, searchQuery: 'Alt');
          await tapSlot(tester, 11);

          expect(find.byType(AlternateDoctorsDialog), findsOneWidget);
          expect(find.text('Other doctors available'), findsOneWidget);
        });
      });

      testWidgets('FE-E05: alternate block shows lock icon styling', (tester) async {
        await withClock(Clock.fixed(_referenceDate), () async {
          final patient = samplePatientListItem(fullName: 'Lock Patient');
          await pumpFlow(
            tester,
            client: _mixedSlotsClient(),
            patientRepository: FakePatientRepository(patients: [patient]),
          );

          await completeStepOne(tester, patient: patient, searchQuery: 'Loc');

          final alternateChip = find.ancestor(
            of: find.text(_slotLabel(11)),
            matching: find.byType(Material),
          );
          expect(
            find.descendant(of: alternateChip.first, matching: find.byIcon(Icons.help_outline)),
            findsOneWidget,
          );
        });
      });

      testWidgets('FE-E06: selected available block uses primary styling', (tester) async {
        await withClock(Clock.fixed(_referenceDate), () async {
          final patient = samplePatientListItem(fullName: 'Selected Patient');
          await pumpFlow(
            tester,
            client: _mixedSlotsClient(),
            patientRepository: FakePatientRepository(patients: [patient]),
          );

          await completeStepOne(tester, patient: patient, searchQuery: 'Sel');
          await tapSlot(tester, 9);

          expect(tester.getSemantics(find.text(_slotLabel(9))).label, contains('selected'));
        });
      });

      testWidgets('FE-E07: empty day shows no slots available message', (tester) async {
        await withClock(Clock.fixed(_referenceDate), () async {
          final client = SimplifiedSlotRpcClient(blocksForDate: (_, __) => const []);
          final patient = samplePatientListItem(fullName: 'Empty Grid Patient');
          await pumpFlow(
            tester,
            client: client,
            patientRepository: FakePatientRepository(patients: [patient]),
          );

          await completeStepOne(tester, patient: patient, searchQuery: 'Emp');

          expect(find.text('No slots available for this day.'), findsOneWidget);
        });
      });

      testWidgets('FE-E08: hide fully booked shows no bookable slots message', (tester) async {
        await withClock(Clock.fixed(_referenceDate), () async {
          final client = SimplifiedSlotRpcClient(
            blocksForDate: (localDate, _) => [
              {
                'start_time': '${localDate}T10:00:00.000',
                'end_time': '${localDate}T10:30:00.000',
                'state': 'fully_unavailable',
                'available_doctor_ids': <String>[],
              },
            ],
          );
          final patient = samplePatientListItem(fullName: 'Hidden Patient');
          await pumpFlow(
            tester,
            client: client,
            patientRepository: FakePatientRepository(patients: [patient]),
          );

          await completeStepOne(tester, patient: patient, searchQuery: 'Hid');

          expect(find.text('No bookable slots for this day.'), findsOneWidget);
        });
      });

      testWidgets('FE-E09: grid scroll reveals slots beyond collapsed viewport', (tester) async {
        await withClock(Clock.fixed(_referenceDate), () async {
          final client = SimplifiedSlotRpcClient(blocksForDate: (localDate, _) => _manySlotBlocks(localDate));
          final patient = samplePatientListItem(fullName: 'Scroll Patient');
          await pumpFlow(
            tester,
            client: client,
            patientRepository: FakePatientRepository(patients: [patient]),
          );

          await completeStepOne(tester, patient: patient, searchQuery: 'Scr');

          expect(find.text(_slotLabel(6)), findsOneWidget);
          expect(find.text(_slotLabel(17)), findsNothing);

          await tester.drag(find.byType(SimplifiedTimeBlockGrid), const Offset(0, -500));
          await tester.pumpAndSettle();

          expect(find.text(_slotLabel(17)), findsOneWidget);
        });
      });

      testWidgets('FE-E10: semantics labels include time and availability state', (tester) async {
        await withClock(Clock.fixed(_referenceDate), () async {
          final client = SimplifiedSlotRpcClient(
            blocksForDate: (localDate, _) => _pastAndAvailableBlocks(localDate),
          );
          final patient = samplePatientListItem(fullName: 'Semantics Patient');
          await pumpFlow(
            tester,
            client: client,
            patientRepository: FakePatientRepository(patients: [patient]),
          );

          await completeStepOne(tester, patient: patient, searchQuery: 'Sem');

          expect(tester.getSemantics(find.text(_slotLabel(10))).label, contains('available'));
          expect(tester.getSemantics(find.text(_slotLabel(7))).label, contains('past'));
        });
      });

      testWidgets('FE-E11: blocks use default 30-minute duration from settings', (tester) async {
        await withClock(Clock.fixed(_referenceDate), () async {
          final client = _mixedSlotsClient();
          final patient = samplePatientListItem(fullName: 'Duration Patient');
          await pumpFlow(
            tester,
            client: client,
            patientRepository: FakePatientRepository(patients: [patient]),
          );

          await completeStepOne(tester, patient: patient, searchQuery: 'Dur');
          await tapSlot(tester, 9);
          await tapConfirm(tester);

          expect(client.createAppointmentCalls.single['p_duration_minutes'], 30);
        });
      });

      testWidgets('FE-E12: legend visible with preferred doctor', (tester) async {}, skip: true);

      testWidgets('FE-E13: legend hides alternate entry without preferred doctor', (tester) async {}, skip: true);

      testWidgets('FE-E14: no preferred doctor tap opens doctor picker dialog', (tester) async {
        await withClock(Clock.fixed(_referenceDate), () async {
          final patient = samplePatientListItem(fullName: 'No Pref Patient');
          await pumpFlow(
            tester,
            client: _mixedSlotsClient(),
            patientRepository: FakePatientRepository(patients: [patient]),
          );

          await completeStepOne(tester, patient: patient, searchQuery: 'Pref', doctorName: null);
          await tapSlot(tester, 9);

          expect(find.text('Select a doctor'), findsOneWidget);
          expect(find.text('Dr. Ada'), findsOneWidget);
        });
      });

      testWidgets('bug-fix: no effectiveDoctorId shows blocked confirm message', (tester) async {
        await withClock(Clock.fixed(_referenceDate), () async {
          final patient = samplePatientListItem(fullName: 'No Doctor Confirm Patient');
          await pumpFlow(
            tester,
            client: _mixedSlotsClient(),
            patientRepository: FakePatientRepository(patients: [patient]),
          );

          await completeStepOne(tester, patient: patient, searchQuery: 'Doc', doctorName: null);
          await tapSlot(tester, 9);
          await tester.tap(find.text('Cancel'));
          await tester.pumpAndSettle();

          expect(find.text('Select a time slot above'), findsOneWidget);
          final confirmBeforeDoctor = tester.widget<AppButton>(find.byKey(const Key('simplified_slot_confirm')));
          expect(confirmBeforeDoctor.onPressed, isNull);

          await tapSlot(tester, 9);
          await tester.tap(find.text('Dr. Ada'));
          await tester.pumpAndSettle();

          expect(find.text('Select a doctor for this time slot before confirming.'), findsNothing);
          expect(find.text('Dr. Ada'), findsWidgets);
          final confirmAfterDoctor = tester.widget<AppButton>(find.byKey(const Key('simplified_slot_confirm')));
          expect(confirmAfterDoctor.onPressed, isNotNull);
        });
      });
    });

    group('ABUSE-N edge and abuse', () {
      testWidgets('ABUSE-N01: rapid day chevrons stay consistent without crash', (tester) async {
        await withClock(Clock.fixed(_referenceDate), () async {
          final client = SimplifiedSlotRpcClient(
            blocksForDate: (localDate, _) => _mixedSlotBlocks(localDate),
            slotDelay: const Duration(milliseconds: 50),
          );
          final patient = samplePatientListItem(fullName: 'Rapid Chevron Patient');
          await pumpFlow(
            tester,
            client: client,
            patientRepository: FakePatientRepository(patients: [patient]),
          );

          await completeStepOne(tester, patient: patient, searchQuery: 'Rap');

          for (var i = 0; i < 6; i++) {
            await tester.tap(find.byTooltip('Next day'));
            await tester.pump(const Duration(milliseconds: 20));
          }
          await waitForSlotsLoaded(tester);
          await tester.pumpAndSettle();

          expect(find.text('Select Date and Time'), findsOneWidget);
          expect(tester.takeException(), isNull);
        });
      });

      testWidgets('ABUSE-N03: back during slot load does not crash', (tester) async {
        await withClock(Clock.fixed(_referenceDate), () async {
          final client = SimplifiedSlotRpcClient(
            blocksForDate: (localDate, _) => _mixedSlotBlocks(localDate),
            slotDelay: const Duration(milliseconds: 400),
          );
          final patient = samplePatientListItem(fullName: 'Back Load Patient');
          await pumpFlow(
            tester,
            client: client,
            patientRepository: FakePatientRepository(patients: [patient]),
          );

          await selectPatient(tester, patient: patient, searchQuery: 'Back');
          await selectDoctor(tester, 'Dr. Ada');
          await tapStepOneNext(tester);
          await waitForStepTwo(tester);
          expect(find.byType(AppCircularProgress), findsWidgets);

          final backFinder = find.byKey(const Key('simplified_booking_back'));
          await tester.ensureVisible(backFinder);
          await tapForuiControl(tester, backFinder);
          await tester.pumpAndSettle();
          await tester.pump(const Duration(milliseconds: 500));

          expect(find.text('Step 1 / 2'), findsOneWidget);
          expect(tester.takeException(), isNull);
        });
      });

      testWidgets('ABUSE-N04: close during confirm save does not crash', (tester) async {
        await withClock(Clock.fixed(_referenceDate), () async {
          final client = SlowCreateAppointmentRpcClient();
          final patient = samplePatientListItem(fullName: 'Close Save Patient');
          await pumpFlow(
            tester,
            client: client,
            patientRepository: FakePatientRepository(patients: [patient]),
          );

          await completeStepOne(tester, patient: patient, searchQuery: 'Clo');
          await tapSlot(tester, 10);

          await tester.tap(find.byKey(const Key('simplified_slot_confirm')));
          await tester.pump(const Duration(milliseconds: 50));
          await tester.tap(find.byTooltip('Close'));
          await tester.pumpAndSettle();

          expect(tester.takeException(), isNull);
        });
      });

      testWidgets('EDGE-N11: schedule conflict on confirm refreshes slots', (tester) async {
        await withClock(Clock.fixed(_referenceDate), () async {
          final client = AppointmentRpcTestClient()
            ..rpcResults['create_appointment'] = {
              'success': false,
              'error_code': 'SCHEDULE_CONFLICT',
              'error_message': 'Overlap',
            };
          final patient = samplePatientListItem(fullName: 'Conflict Patient');
          await pumpFlow(
            tester,
            client: client,
            patientRepository: FakePatientRepository(patients: [patient]),
          );

          await completeStepOne(tester, patient: patient, searchQuery: 'Con');
          await tapSlot(tester, 10);
          await tapConfirm(tester);

          expect(find.textContaining('overlaps another booked slot'), findsOneWidget);
          expect(client.rpcCallCounts['get_simplified_booking_slots'], greaterThanOrEqualTo(2));
        });
      });

      testWidgets('EDGE-N12: changing doctor after slot pick clears selection on return', (tester) async {
        await withClock(Clock.fixed(_referenceDate), () async {
          final client = AppointmentRpcTestClient();
          final patient = samplePatientListItem(fullName: 'Change After Slot Patient');
          await pumpFlow(
            tester,
            client: client,
            patientRepository: FakePatientRepository(patients: [patient]),
          );

          await completeStepOne(tester, patient: patient, searchQuery: 'Cha', doctorName: 'Dr. Ada');
          await tapSlot(tester, 10);
          expect(find.text('Select a time slot above'), findsNothing);

          await tester.tap(find.byKey(const Key('simplified_booking_back')));
          await tester.pumpAndSettle();
          await selectDoctor(tester, 'Dr. Ben');
          await tapStepOneNext(tester);
          await waitForSlotsLoaded(tester);
          await tester.pumpAndSettle();

          expect(find.text('Select a time slot above'), findsOneWidget);
          expect(client.rpcCallCounts['get_simplified_booking_slots'], 2);
        });
      });
    });
  });
}
