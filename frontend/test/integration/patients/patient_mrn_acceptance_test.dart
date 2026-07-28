@Tags(['boundary', 'live'])
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_type.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/billing/data/invoice_repository.dart';
import 'package:ai_clinic/features/patients/domain/create_patient_input.dart';
import 'package:ai_clinic/features/patients/domain/patient_list_scope.dart';

import '../../boundary/harness/boundary_test_context.dart';
import '../../boundary/harness/manifest_scenario.dart';
import '../../boundary/harness/reset.dart';
import '../../boundary/harness/role_sessions.dart';

final _mrnPattern = RegExp(r'^MRN-\d{6,}$');

Future<void> _openBranchHours24x7(BoundaryTestContext ctx, String branchId) {
  return ctx.sql.execute('''
UPDATE public.branches
SET working_schedule = jsonb_build_object(
  'days',
  jsonb_build_array(
    jsonb_build_object('day', 'monday', 'is_working_day', true, 'open_time', '00:00', 'close_time', '23:59'),
    jsonb_build_object('day', 'tuesday', 'is_working_day', true, 'open_time', '00:00', 'close_time', '23:59'),
    jsonb_build_object('day', 'wednesday', 'is_working_day', true, 'open_time', '00:00', 'close_time', '23:59'),
    jsonb_build_object('day', 'thursday', 'is_working_day', true, 'open_time', '00:00', 'close_time', '23:59'),
    jsonb_build_object('day', 'friday', 'is_working_day', true, 'open_time', '00:00', 'close_time', '23:59'),
    jsonb_build_object('day', 'saturday', 'is_working_day', true, 'open_time', '00:00', 'close_time', '23:59'),
    jsonb_build_object('day', 'sunday', 'is_working_day', true, 'open_time', '00:00', 'close_time', '23:59')
  )
)
WHERE id = '$branchId'::uuid;
''');
}

DateTime _boundaryPlannedStartUtc({required int dayOffset, int hourOffset = 10}) {
  final now = DateTime.now().toUtc();
  final day = DateTime.utc(now.year, now.month, now.day).add(Duration(days: dayOffset));
  return day.add(Duration(hours: hourOffset));
}

/// Same calendar day — required for day-gated status transitions (checked_in, in_progress, …).
DateTime _boundarySameDayPlannedStartUtc({int hourOffset = 10}) =>
    _boundaryPlannedStartUtc(dayOffset: 0, hourOffset: hourOffset);

/// End-to-end MRN journey across patient create, list, detail, and invoice surfaces.
///
/// UI layers (toast, table column, identity chip) are covered by widget tests;
/// this integration test locks the repository contract against a live local stack.
void main() {
  late BoundaryTestContext ctx;

  setUpAll(() async {
    ctx = await BoundaryTestContext.create();
  });

  installBoundaryTestLifecycle(() => ctx);

  group('Patient MRN acceptance (016)', () {
    test('patients.mrn.createListDetailInvoice.success', () async {
      const ManifestScenario('patients.mrn.createListDetailInvoice.success');
      final clinic = await ctx.ensureClinic(label: 'mrn_accept');
      final doctor = await ctx.fixtures.createStaff(clinic: clinic, role: StaffRole.doctor);
      final sessions = RoleSessions(ctx, clinic);
      await sessions.signInAs(StaffRole.receptionist);

      // US1: create patient — server assigns MRN (toast/detail chip use this value).
      final created = await ctx.patients.createPatient(
        CreatePatientInput(
          activeBranchId: clinic.branchId,
          fullName: 'MRN Acceptance Patient',
          phone: clinic.phone('01'),
        ),
      );
      expect(created.mrn, matches(_mrnPattern));

      // US3: patients list/search payload includes MRN as first-column data source.
      final listPage = await ctx.patients.searchPatients(
        scope: PatientListScope.thisBranch,
        branchId: clinic.branchId,
        limit: 50,
        offset: 0,
      );
      final listRow = listPage.items.where((row) => row.id == created.patientId).singleOrNull;
      expect(listRow, isNotNull);
      expect(listRow!.mrn, created.mrn);

      // US4: patient detail payload includes MRN for identity chip.
      final detail = await ctx.patients.getPatient(created.patientId);
      expect(detail.mrn, created.mrn);

      // US5: invoice list shows patient MRN after billing from a completed visit.
      await _openBranchHours24x7(ctx, clinic.branchId);
      final start = _boundarySameDayPlannedStartUtc(hourOffset: 10);
      final appointment = await ctx.appointments.createAppointment(
        branchId: clinic.branchId,
        patientId: created.patientId,
        doctorId: doctor.staffMemberId,
        type: AppointmentType.planned,
        startTime: start,
        durationMinutes: 30,
      );

      await ctx.appointments.updateAppointmentStatus(
        appointmentId: appointment.appointmentId,
        newStatus: AppointmentStatus.confirmed,
      );
      await ctx.appointments.updateAppointmentStatus(
        appointmentId: appointment.appointmentId,
        newStatus: AppointmentStatus.checkedIn,
      );
      await ctx.appointments.updateAppointmentStatus(
        appointmentId: appointment.appointmentId,
        newStatus: AppointmentStatus.inProgress,
      );

      await sessions.signInAs(StaffRole.doctor);
      final visit = await ctx.visits.createVisit(appointmentId: appointment.appointmentId);
      final visitDetail = await ctx.visits.getVisit(visitId: visit.visitId);
      expect(visitDetail.documentation, isNotNull);
      await ctx.visits.saveVisitDocumentation(
        visitId: visit.visitId,
        expectedUpdatedAt: visitDetail.documentation!.updatedAt!,
        complaint: 'MRN acceptance visit.',
      );
      final completed = await ctx.visits.completeVisit(visitId: visit.visitId);
      expect(completed.visitStatus, 'completed');

      await sessions.signInAs(StaffRole.receptionist);
      final invoices = InvoiceRepository(ctx.client);
      final invoiceId = await invoices.createFromVisit(visitId: visit.visitId);
      expect(invoiceId, isNotEmpty);

      final invoicePage = await invoices.listPatientInvoices(patientId: created.patientId);
      final invoiceRow = invoicePage.items.where((row) => row.id == invoiceId).singleOrNull;
      expect(invoiceRow, isNotNull);
      expect(invoiceRow!.patientMrn, created.mrn);
    });
  });
}
