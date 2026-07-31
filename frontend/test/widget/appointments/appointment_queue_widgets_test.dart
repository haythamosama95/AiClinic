import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/ui/theme/app_theme.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_list_item.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status_transitions.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_type.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/queue/domain/queue_display.dart';
import 'package:ai_clinic/features/queue/domain/queue_shift_doctors.dart';
import 'package:ai_clinic/features/queue/domain/queue_start_doctor.dart';
import 'package:ai_clinic/features/queue/presentation/pages/queue_page.dart';
import 'package:ai_clinic/features/queue/presentation/providers/queue_provider.dart';
import 'package:ai_clinic/features/queue/presentation/providers/queue_shift_provider.dart';
import 'package:ai_clinic/features/queue/presentation/widgets/queue_appointments_table.dart';
import 'package:ai_clinic/features/queue/presentation/widgets/queue_checked_in_panel.dart';
import 'package:ai_clinic/features/queue/presentation/widgets/queue_confirm_dialog.dart';
import 'package:ai_clinic/features/queue/presentation/widgets/queue_doctors_panel.dart';
import 'package:ai_clinic/features/queue/presentation/widgets/queue_flow_control_panel.dart';
import 'package:ai_clinic/features/queue/presentation/widgets/queue_kpi_carousel.dart';
import 'package:ai_clinic/features/queue/presentation/widgets/queue_row_actions.dart';
import 'package:ai_clinic/features/queue/presentation/widgets/queue_start_doctor_dialog.dart';
import 'package:ai_clinic/features/queue/presentation/widgets/queue_status_badge.dart';
import 'package:ai_clinic/features/queue/presentation/widgets/queue_toolbar.dart';

import '../../helpers/auth_test_support.dart';

void main() {
  final now = DateTime.utc(2026, 6, 4, 12);
  const emptyShiftLookup = AppointmentQueueShiftDoctorLookup.empty;

  Future<void> pumpShort(WidgetTester tester, [Duration duration = const Duration(milliseconds: 300)]) async {
    await tester.pump(duration);
  }

  Widget wrap(Widget child, {List overrides = const []}) {
    return ProviderScope(
      overrides: overrides.cast(),
      child: MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: child,
          ),
        ),
      ),
    );
  }

  group('QueueConfirmDialog', () {
    testWidgets('renders cancel variant and fires callbacks', (tester) async {
      var confirmed = false;
      var cancelled = false;

      await tester.pumpWidget(
        wrap(
          QueueConfirmDialog(
            open: true,
            kind: QueueConfirmKind.cancel,
            patientName: 'Jane Doe',
            onConfirm: () => confirmed = true,
            onCancel: () => cancelled = true,
          ),
        ),
      );
      await pumpShort(tester);

      expect(find.text('Cancel appointment?'), findsOneWidget);
      expect(find.text('Cancel appointment'), findsOneWidget);
      expect(find.text('Go back'), findsOneWidget);

      await tester.tap(find.text('Go back'));
      await pumpShort(tester);
      expect(cancelled, isTrue);

      await tester.pumpWidget(
        wrap(
          QueueConfirmDialog(
            open: true,
            kind: QueueConfirmKind.cancel,
            patientName: 'Jane Doe',
            onConfirm: () => confirmed = true,
            onCancel: () {},
          ),
        ),
      );
      await pumpShort(tester);

      await tester.tap(find.text('Cancel appointment'));
      await pumpShort(tester);
      expect(confirmed, isTrue);
    });

    testWidgets('renders no-show variant with expected actions', (tester) async {
      await tester.pumpWidget(
        wrap(
          QueueConfirmDialog(
            open: true,
            kind: QueueConfirmKind.noShow,
            patientName: 'Jane Doe',
            onConfirm: () {},
            onCancel: () {},
          ),
        ),
      );
      await pumpShort(tester);

      expect(find.text('Mark as no show?'), findsOneWidget);
      expect(find.text('Mark no show'), findsOneWidget);
      expect(find.text('Go back'), findsOneWidget);
    });
  });

  group('QueueStatusBadge', () {
    testWidgets('renders labels for major statuses', (tester) async {
      for (final status in [
        AppointmentStatus.scheduled,
        AppointmentStatus.confirmed,
        AppointmentStatus.checkedIn,
        AppointmentStatus.inProgress,
        AppointmentStatus.completed,
        AppointmentStatus.cancelled,
        AppointmentStatus.noShow,
      ]) {
        await tester.pumpWidget(wrap(QueueStatusBadge(status: status)));
        await tester.pump();

        final label = queueToolbarStatusLabels[status] ?? AppointmentQueueDisplay.scheduleBadgeLabel(status);
        expect(find.text(label), findsOneWidget);
      }
    });
  });

  group('QueueToolbar', () {
    testWidgets('search input fires onSearchChange', (tester) async {
      var search = '';

      await tester.binding.setSurfaceSize(const Size(900, 600));
      await tester.pumpWidget(
        wrap(
          QueueToolbar(
            search: search,
            onSearchChange: (value) => search = value,
            statusFilters: const {},
            onToggleStatus: (_) {},
            onClearFilters: () {},
          ),
        ),
      );
      await pumpShort(tester);

      expect(find.bySemanticsLabel('Search patients by name'), findsOneWidget);
      expect(find.bySemanticsLabel('Filter by status'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'Sam');
      await tester.pump();
      expect(search, 'Sam');
    });

    testWidgets('status filter trigger reflects active selections', (tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 600));
      await tester.pumpWidget(
        wrap(
          QueueToolbar(
            search: '',
            onSearchChange: (_) {},
            statusFilters: const {AppointmentStatus.scheduled, AppointmentStatus.confirmed},
            onToggleStatus: (_) {},
            onClearFilters: () {},
          ),
        ),
      );
      await pumpShort(tester);

      expect(find.bySemanticsLabel('Status filter, 2 selected'), findsOneWidget);
    });
  });

  group('QueueKpiCarousel', () {
    testWidgets('builds with sample stats and key KPI labels', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 400));
      await tester.pumpWidget(
        wrap(
          QueueKpiCarousel(
            stats: const AppointmentQueueStats(
              total: 12,
              completed: 4,
              noShow: 1,
              avgWaitMinutes: 18,
              avgVisitMinutes: 22,
            ),
            trends: const QueueKpiCarouselTrends(
              waiting: 3,
              checkedIn: 3,
              inProgress: 2,
              cancelled: 1,
              queueLength: 3,
            ),
          ),
        ),
      );
      await pumpShort(tester);

      expect(find.text('Total today'), findsOneWidget);
      expect(find.text('Waiting'), findsOneWidget);
      expect(find.text('Checked in'), findsOneWidget);
      expect(find.text('12'), findsOneWidget);
    });
  });

  group('QueueAppointmentsTable', () {
    testWidgets('builds rows with patient, status badge, and actions', (tester) async {
      final appointments = [
        item(patientName: 'Alice Patient', status: AppointmentStatus.scheduled),
      ];

      await tester.binding.setSurfaceSize(const Size(1200, 700));
      await tester.pumpWidget(
        wrap(
          QueueAppointmentsTable(
            appointments: appointments,
            siblingAppointments: appointments,
            shiftLookup: emptyShiftLookup,
            now: now,
            onTransition: (_, __, {doctorId}) {},
          ),
        ),
      );
      await pumpShort(tester);

      expect(find.text('Alice Patient'), findsOneWidget);
      expect(find.text('Scheduled'), findsOneWidget);
      expect(find.text('Actions'), findsWidgets);
    });

    testWidgets('shows empty state when no appointments', (tester) async {
      await tester.pumpWidget(
        wrap(
          QueueAppointmentsTable(
            appointments: const [],
            siblingAppointments: const [],
            shiftLookup: emptyShiftLookup,
            now: now,
            onTransition: (_, __, {doctorId}) {},
          ),
        ),
      );
      await pumpShort(tester);

      expect(find.text('No appointments match your filters'), findsOneWidget);
    });
  });

  group('QueueCheckedInPanel', () {
    testWidgets('shows empty state when no checked-in patients', (tester) async {
      await tester.pumpWidget(wrap(QueueCheckedInPanel(patients: const [], now: now)));
      await pumpShort(tester);

      expect(find.text('No patients currently waiting'), findsOneWidget);
      expect(find.text('Longest wait'), findsOneWidget);
    });

    testWidgets('shows checked-in patients and sort toggle', (tester) async {
      final patients = [
        item(
          id: 'w1',
          patientName: 'Waiting Pat',
          status: AppointmentStatus.checkedIn,
          checkedInAt: now.subtract(const Duration(minutes: 20)),
        ),
      ];

      await tester.pumpWidget(wrap(QueueCheckedInPanel(patients: patients, now: now)));
      await pumpShort(tester);

      expect(find.text('Waiting Pat'), findsOneWidget);
      expect(find.text('Next in order'), findsOneWidget);
      expect(find.text('Longest wait'), findsOneWidget);
    });
  });

  group('QueueDoctorsPanel', () {
    testWidgets('builds doctor names from doctors list', (tester) async {
      const doctors = [
        QueueShiftDoctor(id: 'd1', name: 'Dr Alpha'),
        QueueShiftDoctor(id: 'd2', name: 'Dr Beta'),
      ];

      await tester.pumpWidget(
        wrap(
          QueueDoctorsPanel(
            doctors: doctors,
            appointments: const [],
            now: now,
          ),
        ),
      );
      await pumpShort(tester);

      expect(find.text('Dr Alpha'), findsOneWidget);
      expect(find.text('Dr Beta'), findsOneWidget);
      expect(find.text('Doctors on shift'), findsOneWidget);
    });

    testWidgets('shows empty state when no doctors on shift', (tester) async {
      await tester.pumpWidget(
        wrap(
          QueueDoctorsPanel(
            doctors: const [],
            appointments: const [],
            now: now,
          ),
        ),
      );
      await pumpShort(tester);

      expect(find.text('No providers on shift'), findsOneWidget);
    });
  });

  group('QueueFlowControlPanel', () {
    testWidgets('switches between Waiting and Doctors tabs', (tester) async {
      final appointments = [
        item(
          id: 'w1',
          patientName: 'Checked In Pat',
          status: AppointmentStatus.checkedIn,
          checkedInAt: now.subtract(const Duration(minutes: 5)),
        ),
      ];

      await tester.binding.setSurfaceSize(const Size(500, 700));
      await tester.pumpWidget(
        wrap(
          QueueFlowControlPanel(appointments: appointments, now: now),
          overrides: [
            appointmentQueueShiftDoctorLookupProvider.overrideWith(
              (ref) async => emptyShiftLookup,
            ),
          ],
        ),
      );
      await pumpShort(tester);

      expect(find.text('Checked In Pat'), findsOneWidget);

      await tester.tap(find.textContaining('Doctors'));
      await pumpShort(tester, const Duration(milliseconds: 400));

      expect(find.text('No providers on shift'), findsOneWidget);

      await tester.tap(find.textContaining('Waiting'));
      await pumpShort(tester, const Duration(milliseconds: 400));

      expect(find.text('Checked In Pat'), findsOneWidget);
    });
  });

  group('QueueStartDoctorDialog', () {
    testWidgets('shows preferred callout and returns selected doctor on confirm', (tester) async {
      const options = [
        QueueStartDoctorOption(id: 'd1', name: 'Dr Alpha', isBusy: false, isPreferred: true),
        QueueStartDoctorOption(id: 'd2', name: 'Dr Beta', isBusy: false),
      ];

      String? selectedId;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Builder(
            builder: (context) {
              return Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () async {
                      selectedId = await QueueStartDoctorDialog.show(context, options: options);
                    },
                    child: const Text('Open'),
                  ),
                ),
              );
            },
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await pumpShort(tester);

      expect(find.text('Preferred provider'), findsOneWidget);
      expect(find.text('Dr Alpha'), findsWidgets);
      expect(find.text('Dr Beta'), findsOneWidget);

      await tester.tap(find.text('Start visit'));
      await pumpShort(tester);

      expect(selectedId, 'd1');
    });
  });

  group('QueueRowActions', () {
    testWidgets('shows actions menu for scheduled appointment', (tester) async {
      final appointment = item(status: AppointmentStatus.scheduled);

      expect(
        forwardStatusTargetFor(
          appointment,
          organizationTimezone: 'UTC',
          referenceUtc: now,
        ),
        AppointmentStatus.confirmed,
      );

      await tester.pumpWidget(
        wrap(
          QueueRowActions(
            appointment: appointment,
            siblingAppointments: [appointment],
            shiftLookup: emptyShiftLookup,
            organizationTimezone: 'UTC',
            referenceUtc: now,
            onTransition: (_, __, {doctorId}) {},
          ),
        ),
      );
      await pumpShort(tester);

      expect(find.bySemanticsLabel('Actions for Pat'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Actions for Pat'));
      await tester.pumpAndSettle();

      expect(find.bySemanticsLabel('Appointment actions'), findsOneWidget);
      expect(find.text('Confirm'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
    });
  });

  group('QueuePage', () {
    testWidgets('builds error state with overridden queue provider', (tester) async {
      final auth = AuthSessionState(
        status: AuthSessionStatus.authenticated,
        context: sampleAuthSessionContext(permissions: const {'appointments.read'}),
      );

      await tester.binding.setSurfaceSize(const Size(1280, 900));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authSessionProvider.overrideWith(() => _StaticAuthNotifier(auth)),
            appointmentQueueProvider.overrideWith(() => _StaticQueueController(
              const AppointmentQueueState(
                items: [],
                error: 'Select an active branch before viewing the queue.',
              ),
            )),
            appointmentQueueShiftDoctorLookupProvider.overrideWith(
              (ref) async => emptyShiftLookup,
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(body: QueuePage()),
          ),
        ),
      );
      await pumpShort(tester);

      expect(find.text('Unable to load queue'), findsOneWidget);
      expect(find.text('Select an active branch before viewing the queue.'), findsOneWidget);
    });
  });
}

class _StaticAuthNotifier extends TestAuthSessionNotifier {
  _StaticAuthNotifier(this._state);

  final AuthSessionState _state;

  @override
  AuthSessionState build() => _state;
}

class _StaticQueueController extends AppointmentQueueController {
  _StaticQueueController(this.initial);

  final AppointmentQueueState initial;

  @override
  AppointmentQueueState build() => initial;
}

AppointmentListItem item({
  String id = 'a1',
  String patientName = 'Pat',
  AppointmentStatus status = AppointmentStatus.scheduled,
  DateTime? checkedInAt,
}) {
  final start = DateTime.utc(2026, 6, 4, 10);
  return AppointmentListItem(
    id: id,
    patientId: 'p1',
    patientName: patientName,
    startTime: start,
    endTime: start.add(const Duration(minutes: 30)),
    type: AppointmentType.planned,
    status: status,
    checkedInAt: checkedInAt,
  );
}
