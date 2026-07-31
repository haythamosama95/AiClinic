// Test-only harness for appointment detail and booking widget tests.
// ignore_for_file: depend_on_referenced_packages

import 'dart:async';

import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/auth/permission_service.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/appointments/data/appointment_repository.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_detail.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_list_item.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_queue_shift_doctors.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_settings.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status_update_result.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_type.dart';
import 'package:ai_clinic/features/appointments/domain/create_appointment_result.dart';
import 'package:ai_clinic/features/appointments/presentation/navigation/appointment_detail_route_extra.dart';
import 'package:ai_clinic/features/appointments/presentation/pages/appointment_detail_page.dart';
import 'package:ai_clinic/features/appointments/presentation/providers/appointment_calendar_provider.dart';
import 'package:ai_clinic/features/appointments/presentation/providers/appointment_detail_provider.dart';
import 'package:ai_clinic/features/appointments/presentation/providers/appointment_detail_shift_provider.dart';
import 'package:ai_clinic/features/appointments/presentation/providers/appointment_detail_siblings_provider.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/appointment_booking_sheet.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/billing/data/invoice_repository.dart';
import 'package:ai_clinic/features/billing/domain/invoice_detail.dart';
import 'package:ai_clinic/features/billing/domain/invoice_list_item.dart';
import 'package:ai_clinic/features/billing/domain/invoice_status.dart';
import 'package:ai_clinic/features/billing/domain/money.dart';
import 'package:ai_clinic/features/clinic-management/domain/branch_list_item.dart';
import 'package:ai_clinic/features/clinic-management/domain/branch_working_schedule.dart';
import 'package:ai_clinic/features/clinic-management/domain/staff_list_item.dart';
import 'package:ai_clinic/features/patients/data/patient_repository.dart';
import 'package:ai_clinic/features/shifts/domain/shift_list_item.dart';
import 'package:ai_clinic/features/shifts/domain/shift_status.dart';
import 'package:ai_clinic/features/visits/data/visit_repository.dart';
import 'package:ai_clinic/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../helpers/auth_test_support.dart';
import '../../helpers/patient_test_support.dart';
import '../../helpers/role_permission_seed.dart';
import '../../support/appointment_calendar_test_support.dart';
import '../../support/appointment_rpc_test_client.dart';

const detailTestAppointmentId = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const detailTestPatientId = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';
const detailTestVisitId = 'vvvvvvvv-vvvv-4vvv-8vvv-vvvvvvvvvvvv';
const detailTestInvoiceId = 'iiiiiiii-iiii-4iii-8iii-iiiiiiiiiiii';

/// Fixed "today" for booking tests (Monday, mid-morning local).
final detailHarnessFixedNow = DateTime(2026, 6, 15, 10, 0);

AppointmentDetail buildAppointmentDetail({
  String id = detailTestAppointmentId,
  String patientId = detailTestPatientId,
  String patientName = 'Test Patient',
  String branchId = calendarTestBranchAId,
  AppointmentStatus status = AppointmentStatus.scheduled,
  String? doctorId = calendarTestDoctorAId,
  String? doctorName = 'Dr. Ada',
  DateTime? startTime,
  int durationMinutes = 30,
  String? notes,
  String? cancelReason,
  int? queueNumber,
}) {
  final start = startTime ?? DateTime(2026, 6, 15, 10, 0);
  final end = start.add(Duration(minutes: durationMinutes));
  final now = DateTime.utc(2026, 6, 14, 8);
  return AppointmentDetail(
    id: id,
    branchId: branchId,
    patientId: patientId,
    patientName: patientName,
    doctorId: doctorId,
    doctorName: doctorName,
    startTime: start.toUtc(),
    endTime: end.toUtc(),
    type: AppointmentType.planned,
    status: status,
    queueNumber: queueNumber,
    notes: notes,
    cancelReason: cancelReason,
    createdAt: now,
    updatedAt: now,
    createdByDisplay: 'Reception',
  );
}

AppointmentListItem buildAppointmentListItem({
  String id = detailTestAppointmentId,
  String patientId = detailTestPatientId,
  String patientName = 'Test Patient',
  AppointmentStatus status = AppointmentStatus.scheduled,
  String? doctorId = calendarTestDoctorAId,
  String? doctorName = 'Dr. Ada',
  DateTime? startTime,
}) {
  final start = startTime ?? DateTime(2026, 6, 15, 10, 0);
  return AppointmentListItem(
    id: id,
    patientId: patientId,
    patientName: patientName,
    doctorId: doctorId,
    doctorName: doctorName,
    startTime: start.toUtc(),
    endTime: start.add(const Duration(minutes: 30)).toUtc(),
    type: AppointmentType.planned,
    status: status,
  );
}

List<BranchListItem> buildTestBranches() {
  return [
    BranchListItem(
      id: calendarTestBranchAId,
      name: 'Main',
      code: 'M1',
      isActive: true,
      workingSchedule: BranchWorkingSchedule.defaultSchedule(),
    ),
    BranchListItem(
      id: calendarTestBranchBId,
      name: 'North',
      code: 'N1',
      isActive: true,
      workingSchedule: BranchWorkingSchedule.defaultSchedule(),
    ),
  ];
}

List<StaffListItem> buildTestDoctors() {
  return [
    StaffListItem(
      id: calendarTestDoctorAId,
      fullName: 'Dr. Ada',
      role: StaffRole.doctor,
      isActive: true,
      branches: [StaffBranchLabel(id: calendarTestBranchAId, name: 'Main')],
    ),
    StaffListItem(
      id: calendarTestDoctorBId,
      fullName: 'Dr. Ben',
      role: StaffRole.doctor,
      isActive: true,
      branches: [StaffBranchLabel(id: calendarTestBranchBId, name: 'North')],
    ),
  ];
}

AppointmentQueueShiftDoctorLookup buildShiftLookup({
  DateTime? shiftDate,
  List<StaffListItem> doctors = const [],
}) {
  final resolvedShiftDate = shiftDate ?? DateTime(2026, 6, 15);
  final doctorList = doctors.isEmpty ? buildTestDoctors() : doctors;
  return AppointmentQueueShiftDoctorLookup.fromShiftsAndDoctors(
    organizationTimezone: 'UTC',
    shifts: [
      ShiftListItem(
        id: 'shift-1',
        branchId: calendarTestBranchAId,
        shiftDate: resolvedShiftDate,
        startTime: '06:00',
        endTime: '23:59',
        status: ShiftStatus.active,
        isUnassigned: false,
        assigneeNames: doctorList.map((d) => d.fullName).toList(),
        assigneeCount: doctorList.length,
      ),
    ],
    doctors: doctorList,
  );
}

AppointmentSettings defaultHarnessSettings() {
  return AppointmentSettings(
    defaultDurationMinutes: 30,
    minDurationMinutes: 5,
    maxDurationMinutes: 240,
    workingSchedule: BranchWorkingSchedule.defaultSchedule(),
  );
}

/// Every weekday uses the same open/close window (including Sunday).
BranchWorkingSchedule buildHarnessUniformSchedule({
  required String openTime,
  required String closeTime,
}) {
  return BranchWorkingSchedule(
    BranchWeekday.values
        .map(
          (day) => BranchWorkingDayHours(
            day: day,
            isWorkingDay: true,
            openTime: openTime,
            closeTime: closeTime,
          ),
        )
        .toList(growable: false),
  );
}

class HarnessAppointmentRepository extends AppointmentRepository {
  HarnessAppointmentRepository({AppointmentRpcTestClient? client})
      : super(client ?? AppointmentRpcTestClient());

  AppointmentSettings settings = defaultHarnessSettings();
  AppointmentDetail? detailOverride;
  List<AppointmentListItem> listAppointmentsResult = const [];
  RpcFailure? getAppointmentFailure;
  RpcFailure? getSettingsFailure;
  RpcFailure? createFailure;
  RpcFailure? updateFailure;
  RpcFailure? statusUpdateFailure;
  RpcFailure? cancelFailure;
  RpcFailure? noShowFailure;

  int getAppointmentCallCount = 0;
  int getSettingsCallCount = 0;
  int createCallCount = 0;
  int updateCallCount = 0;
  int statusUpdateCallCount = 0;
  int cancelCallCount = 0;
  int noShowCallCount = 0;
  AppointmentStatus? lastStatusUpdate;

  bool delaySettingsLoad = false;
  int failGetAppointmentTimes = 0;
  Completer<CreateAppointmentResult>? createAppointmentCompleter;

  @override
  Future<AppointmentDetail> getAppointment({required String appointmentId}) async {
    getAppointmentCallCount++;
    if (failGetAppointmentTimes > 0 && getAppointmentCallCount <= failGetAppointmentTimes) {
      throw StateError('Network blew up');
    }
    if (getAppointmentFailure != null) {
      throw getAppointmentFailure!;
    }
    if (detailOverride != null) {
      return detailOverride!;
    }
    return super.getAppointment(appointmentId: appointmentId);
  }

  @override
  Future<AppointmentSettings> getSettings({required String branchId}) async {
    getSettingsCallCount++;
    if (delaySettingsLoad) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    if (getSettingsFailure != null) {
      throw getSettingsFailure!;
    }
    return settings;
  }

  @override
  Future<List<AppointmentListItem>> listAppointments({
    required String branchId,
    required DateTime from,
    required DateTime to,
    String? doctorId,
    List<AppointmentStatus>? statuses,
    String? patientId,
  }) async {
    return listAppointmentsResult;
  }

  @override
  Future<CreateAppointmentResult> createAppointment({
    required String branchId,
    required String patientId,
    String? doctorId,
    required AppointmentType type,
    DateTime? startTime,
    int? durationMinutes,
    DateTime? endTime,
    String? notes,
  }) async {
    createCallCount++;
    if (createFailure != null) {
      throw createFailure!;
    }
    if (createAppointmentCompleter != null) {
      return createAppointmentCompleter!.future;
    }
    final resolvedStart = startTime ?? DateTime.utc(2026, 6, 15, 10);
    final resolvedDuration = durationMinutes ?? 30;
    return CreateAppointmentResult(
      appointmentId: 'new-appointment-id',
      startTime: resolvedStart,
      endTime: endTime ?? resolvedStart.add(Duration(minutes: resolvedDuration)),
      status: AppointmentStatus.scheduled,
      type: type,
    );
  }

  @override
  Future<CreateAppointmentResult> updateAppointment({
    required String appointmentId,
    required String patientId,
    String? doctorId,
    String? branchId,
    required DateTime startTime,
    int? durationMinutes,
    DateTime? endTime,
    String? notes,
  }) async {
    updateCallCount++;
    if (updateFailure != null) {
      throw updateFailure!;
    }
    final resolvedDuration = durationMinutes ?? 30;
    return CreateAppointmentResult(
      appointmentId: appointmentId,
      startTime: startTime,
      endTime: endTime ?? startTime.add(Duration(minutes: resolvedDuration)),
      status: AppointmentStatus.scheduled,
      type: AppointmentType.planned,
    );
  }

  @override
  Future<AppointmentStatusUpdateResult> updateAppointmentStatus({
    required String appointmentId,
    required AppointmentStatus newStatus,
  }) async {
    statusUpdateCallCount++;
    lastStatusUpdate = newStatus;
    if (statusUpdateFailure != null) {
      throw statusUpdateFailure!;
    }
    return AppointmentStatusUpdateResult(
      status: newStatus,
      updatedAt: DateTime.utc(2026, 6, 15, 12),
    );
  }

  @override
  Future<AppointmentStatus> cancelAppointment({
    required String appointmentId,
    String? reason,
  }) async {
    cancelCallCount++;
    if (cancelFailure != null) {
      throw cancelFailure!;
    }
    return AppointmentStatus.cancelled;
  }

  @override
  Future<AppointmentStatus> markAppointmentNoShow({required String appointmentId}) async {
    noShowCallCount++;
    if (noShowFailure != null) {
      throw noShowFailure!;
    }
    return AppointmentStatus.noShow;
  }
}

class HarnessVisitRepository extends VisitRepository {
  HarnessVisitRepository() : super(AppointmentRpcTestClient());

  VisitByAppointmentResult visitByAppointment =
      VisitByAppointmentResult(visitId: detailTestVisitId, status: 'open');
  RpcFailure? visitByAppointmentFailure;
  RpcFailure? createVisitFailure;
  int getVisitByAppointmentCallCount = 0;
  int createVisitCallCount = 0;

  @override
  Future<VisitByAppointmentResult> getVisitByAppointment({
    required String appointmentId,
  }) async {
    getVisitByAppointmentCallCount++;
    if (visitByAppointmentFailure != null) {
      throw visitByAppointmentFailure!;
    }
    return visitByAppointment;
  }

  @override
  Future<CreateVisitResult> createVisit({
    required String appointmentId,
    String? doctorId,
  }) async {
    createVisitCallCount++;
    if (createVisitFailure != null) {
      throw createVisitFailure!;
    }
    return CreateVisitResult(
      visitId: detailTestVisitId,
      appointmentId: appointmentId,
      status: 'open',
      visitDate: DateTime.utc(2026, 6, 15),
    );
  }
}

class HarnessInvoiceRepository extends InvoiceRepository {
  HarnessInvoiceRepository() : super(AppointmentRpcTestClient());

  InvoiceListItem? listItem;
  InvoiceDetail? detail;
  RpcFailure? findForVisitFailure;

  @override
  Future<InvoiceListItem?> findForVisit({required String visitId}) async {
    if (findForVisitFailure != null) {
      throw findForVisitFailure!;
    }
    return listItem;
  }

  @override
  Future<InvoiceDetail> getDetail({required String invoiceId}) async {
    return detail ?? _defaultDetail(invoiceId);
  }

  InvoiceDetail _defaultDetail(String invoiceId) {
    return InvoiceDetail(
      id: invoiceId,
      invoiceNumber: 'INV-000001',
      status: InvoiceStatus.issued,
      branchId: calendarTestBranchAId,
      patientId: detailTestPatientId,
      visitId: detailTestVisitId,
      subtotal: Money.parse('100.00'),
      discountAmount: Money.zero,
      insuranceCoveredAmount: Money.zero,
      currency: 'USD',
      balance: Money.parse('100.00'),
      createdAt: DateTime.utc(2026, 6, 15),
      updatedAt: DateTime.utc(2026, 6, 15),
      items: const [],
      payments: const [],
      patientDisplayName: 'Test Patient',
    );
  }
}

InvoiceListItem buildHarnessInvoiceListItem() {
  return InvoiceListItem(
    id: detailTestInvoiceId,
    status: InvoiceStatus.issued,
    subtotal: Money.parse('100.00'),
    discountAmount: Money.zero,
    insuranceCoveredAmount: Money.zero,
    paidAmount: Money.zero,
    balance: Money.parse('100.00'),
    createdAt: DateTime.utc(2026, 6, 15),
    currency: 'USD',
    invoiceNumber: 'INV-000001',
  );
}

AuthSessionState harnessAuthSession({Set<String>? permissions, StaffRole role = StaffRole.administrator}) {
  return AuthSessionState(
    status: AuthSessionStatus.authenticated,
    context: sampleAuthSessionContext(
      role: role,
      permissions: permissions ?? RolePermissionSeed.administrator,
    ),
  );
}

List<Override> harnessDetailProviderOverrides({
  required HarnessAppointmentRepository appointmentRepo,
  AuthSessionState? auth,
  HarnessVisitRepository? visitRepo,
  HarnessInvoiceRepository? invoiceRepo,
  FakePatientRepository? patientRepo,
  AppointmentDetail? detail,
  List<AppointmentListItem>? siblings,
  AppointmentQueueShiftDoctorLookup? shiftLookup,
  List<BranchListItem>? branches,
  List<StaffListItem>? doctors,
  String appointmentId = detailTestAppointmentId,
  bool loadingDetail = false,
  Object? detailError,
}) {
  final resolvedDetail = detail ?? buildAppointmentDetail();
  final siblingsQuery = AppointmentDetailSiblingsQuery(
    branchId: resolvedDetail.branchId,
    startTime: resolvedDetail.startTime,
  );
  final shiftQuery = AppointmentDetailShiftQuery(
    branchId: resolvedDetail.branchId,
    appointmentStart: resolvedDetail.startTime,
  );

  appointmentRepo.detailOverride = resolvedDetail;

  return [
    authSessionProvider.overrideWith(
      () => MutableAuthSessionNotifier(auth ?? harnessAuthSession()),
    ),
    appointmentRepositoryProvider.overrideWith((ref) => appointmentRepo),
    if (visitRepo != null)
      visitRepositoryProvider.overrideWith((ref) => visitRepo),
    if (invoiceRepo != null)
      invoiceRepositoryProvider.overrideWith((ref) => invoiceRepo),
    if (patientRepo != null)
      patientRepositoryProvider.overrideWith((ref) => patientRepo),
    permissionServiceProvider.overrideWith(
      (ref) => PermissionService(ref.watch(authSessionProvider).context),
    ),
    appointmentCalendarBranchesProvider.overrideWith(
      (ref) async => branches ?? buildTestBranches(),
    ),
    appointmentCalendarDoctorsProvider.overrideWith(
      (ref) async => doctors ?? buildTestDoctors(),
    ),
    if (loadingDetail)
      appointmentDetailProvider(appointmentId).overrideWithValue(
        const AsyncLoading<AppointmentDetail>(),
      )
    else if (detailError != null)
      appointmentDetailProvider(appointmentId).overrideWith((ref) async => throw detailError),
    appointmentDetailSiblingsProvider(siblingsQuery).overrideWith(
      (ref) async => siblings ?? const [],
    ),
    appointmentDetailShiftLookupProvider(shiftQuery).overrideWith(
      (ref) async => shiftLookup ?? AppointmentQueueShiftDoctorLookup.empty,
    ),
  ];
}

Widget harnessMaterialApp({
  Widget? child,
  GoRouter? router,
}) {
  if (router != null) {
    return MaterialApp.router(
      theme: AppTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: router,
    );
  }
  return MaterialApp(
    theme: AppTheme.light(),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: AppToastHost(child: child ?? const SizedBox.shrink()),
  );
}

/// Calendar ↔ detail stack for [_goBack] navigation tests.
GoRouter buildDetailBackNavigationRouter({
  required String appointmentId,
  required Widget detailPage,
  String initialLocation = AppRoutes.appointmentsCalendar,
}) {
  return buildDetailTestRouter(
    appointmentId: appointmentId,
    detailPage: detailPage,
    initialLocation: initialLocation,
  );
}

GoRouter buildDetailTestRouter({
  required String appointmentId,
  required Widget detailPage,
  String initialLocation = AppRoutes.appointmentsCalendar,
}) {
  return GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(
        path: AppRoutes.appointmentsCalendar,
        builder: (context, state) => Scaffold(
          body: Center(
            child: Text('Calendar stub', key: const Key('calendar_stub')),
          ),
        ),
      ),
      GoRoute(
        path: '/appointments/:appointmentId',
        builder: (context, state) => detailPage,
      ),
      GoRoute(
        path: '/patients/:patientId',
        builder: (context, state) => Scaffold(
          body: Text(
            'Patient ${state.pathParameters['patientId']}',
            key: Key('patient_stub_${state.pathParameters['patientId']}'),
          ),
        ),
      ),
      GoRoute(
        path: '/visits/:visitId/document',
        builder: (context, state) => Scaffold(
          body: Text(
            'Visit ${state.pathParameters['visitId']}',
            key: Key('visit_stub_${state.pathParameters['visitId']}'),
          ),
        ),
      ),
    ],
  );
}

Future<void> pumpAppointmentDetail(
  WidgetTester tester, {
  required String appointmentId,
  List<Override> overrides = const [],
  AppointmentDetailRouteExtra? extra,
  GoRouter? router,
  Size surfaceSize = const Size(1280, 900),
}) async {
  await tester.binding.setSurfaceSize(surfaceSize);
  tester.binding.platformDispatcher.textScaleFactorTestValue = 1.0;
  addTearDown(() {
    tester.binding.platformDispatcher.clearTextScaleFactorTestValue();
    tester.binding.setSurfaceSize(null);
  });

  final page = AppointmentDetailPage(appointmentId: appointmentId, extra: extra);

  if (router != null) {
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides,
        child: harnessMaterialApp(router: router),
      ),
    );
  } else {
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides,
        child: harnessMaterialApp(
          child: Scaffold(body: page),
        ),
      ),
    );
  }

  await tester.pump();
}

Future<void> pumpBookingSheetHost(
  WidgetTester tester, {
  required List<Override> overrides,
  required HarnessAppointmentRepository appointmentRepo,
  AppointmentDetail? existingAppointment,
  String branchId = calendarTestBranchAId,
  DateTime? slotStart,
  DateTime? slotEnd,
  BranchWorkingSchedule? schedule,
  String? initialDoctorId,
  List<StaffListItem>? doctors,
  String? branchName = 'Main',
  Duration settleAfterOpen = const Duration(milliseconds: 300),
}) async {
  await tester.binding.setSurfaceSize(const Size(1280, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final start = slotStart ?? detailHarnessFixedNow;
  final end = slotEnd ?? start.add(const Duration(minutes: 30));
  final resolvedSchedule = schedule ?? BranchWorkingSchedule.defaultSchedule();
  final doctorList = doctors ?? buildTestDoctors();

  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: harnessMaterialApp(
        child: Scaffold(
          body: Builder(
            builder: (context) {
              return Center(
                child: AppButton(
                  key: const Key('open_booking_sheet'),
                  onPressed: () {
                    AppointmentBookingSheet.show(
                      context,
                      branchId: branchId,
                      schedule: resolvedSchedule,
                      slotStart: start,
                      slotEnd: end,
                      initialDoctorId: initialDoctorId,
                      doctors: doctorList,
                      existingAppointment: existingAppointment,
                      branchName: branchName,
                    );
                  },
                  child: const Text('Open booking'),
                ),
              );
            },
          ),
        ),
      ),
    ),
  );

  await tester.tap(find.byKey(const Key('open_booking_sheet')));
  await tester.pump();
  if (settleAfterOpen > Duration.zero) {
    await tester.pump(settleAfterOpen);
  }
}

Future<void> tapAppSelectOption(
  WidgetTester tester,
  Key selectKey,
  String optionLabel,
) async {
  final select = find.descendant(
    of: find.byKey(selectKey),
    matching: find.byType(AppSelect),
  );
  await tester.tap(select);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  await tester.tap(find.text(optionLabel).last);
  await tester.pump();
}

Future<void> tapDisabledActionForToast(
  WidgetTester tester,
  Key buttonKey,
) async {
  final finder = find.byKey(buttonKey);
  await tester.tap(finder);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

Future<void> selectPatientAndAdvanceToStep2(
  WidgetTester tester, {
  String patientSearch = 'Booking',
  String patientName = 'Booking Patient',
}) async {
  final searchField = find.descendant(
    of: find.bySemanticsIdentifier('patient_picker_search'),
    matching: find.byType(TextField),
  );
  await tester.tap(searchField);
  await tester.pump();
  await tester.enterText(searchField, patientSearch);
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pump();
  await tester.tap(find.text(patientName).last);
  await tester.pump();
  await tester.tap(find.byKey(const Key('appointment_booking_choose_time')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 100));
    if (find.bySemanticsLabel('Available time slots').evaluate().isNotEmpty) {
      break;
    }
  }
}

Future<void> enterBookingNotes(WidgetTester tester, String text) async {
  final notesField = find.descendant(
    of: find.bySemanticsLabel('Notes (optional)'),
    matching: find.byType(TextField),
  );
  await tester.tap(notesField);
  await tester.pump();
  await tester.enterText(notesField, text);
  await tester.pump(const Duration(milliseconds: 50));
}

Future<void> tapBookingDialogBackdrop(WidgetTester tester) async {
  await tester.tapAt(const Offset(5, 5));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}
