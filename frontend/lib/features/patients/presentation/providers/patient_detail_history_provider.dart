import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/features/appointments/data/appointment_repository.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_list_item.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';
import 'package:ai_clinic/features/patients/domain/patient_visit_document.dart';
import 'package:ai_clinic/features/visits/data/visit_repository.dart';
import 'package:ai_clinic/features/visits/domain/visit_list_item.dart';

/// Past vs upcoming tab on the patient detail timeline.
enum PatientDetailHistoryTab { past, upcoming }

class PatientDetailHistoryTabNotifier extends Notifier<PatientDetailHistoryTab> {
  PatientDetailHistoryTabNotifier(this.patientId);

  final String patientId;

  @override
  PatientDetailHistoryTab build() => PatientDetailHistoryTab.past;

  void select(PatientDetailHistoryTab tab) => state = tab;
}

/// Selected timeline tab for a patient detail page (survives provider reloads).
final patientDetailHistoryTabProvider =
    NotifierProvider.family<PatientDetailHistoryTabNotifier, PatientDetailHistoryTab, String>(
      PatientDetailHistoryTabNotifier.new,
      isAutoDispose: true,
    );

/// Branch + patient pair for loading upcoming appointments on the detail page.
@immutable
class PatientDetailHistoryQuery {
  const PatientDetailHistoryQuery({required this.patientId, required this.branchId});

  final String patientId;
  final String branchId;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is PatientDetailHistoryQuery &&
            runtimeType == other.runtimeType &&
            patientId == other.patientId &&
            branchId == other.branchId;
  }

  @override
  int get hashCode => Object.hash(patientId, branchId);
}

/// Past visits for a patient (`list_patient_visits`).
final patientPastVisitsProvider = FutureProvider.autoDispose.family<List<VisitListItem>, String>((
  ref,
  patientId,
) async {
  final page = await ref.read(visitRepositoryProvider).listPatientVisits(patientId: patientId, limit: 100);
  final visits = [...page.items]..sort((a, b) => b.visitDate.compareTo(a.visitDate));
  return visits;
});

/// Upcoming appointments for a patient (`list_appointments` with `p_patient_id`).
final patientUpcomingAppointmentsProvider = FutureProvider.autoDispose
    .family<List<AppointmentListItem>, PatientDetailHistoryQuery>((ref, query) async {
      final now = clock.now().toUtc();
      final items = await ref
          .read(appointmentRepositoryProvider)
          .listAppointments(
            branchId: query.branchId,
            from: now,
            to: now.add(const Duration(days: 365)),
            patientId: query.patientId,
            statuses: const [
              AppointmentStatus.scheduled,
              AppointmentStatus.confirmed,
              AppointmentStatus.checkedIn,
              AppointmentStatus.inProgress,
            ],
          );

      return [...items]..sort((a, b) => a.startTime.compareTo(b.startTime));
    });

/// Visit attachments for a patient (`list_patient_visit_attachments`).
final patientVisitDocumentsProvider = FutureProvider.autoDispose.family<List<PatientVisitDocument>, String>((
  ref,
  patientId,
) async {
  final rows = await ref.read(visitRepositoryProvider).listPatientVisitAttachments(patientId: patientId);
  return [
    for (final row in rows)
      PatientVisitDocument(visitId: row.visitId, visitDate: row.visitDate, attachment: row.attachment),
  ];
});
