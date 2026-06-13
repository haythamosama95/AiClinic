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

/// Upcoming appointments for a patient (filtered from `list_appointments`).
final patientUpcomingAppointmentsProvider = FutureProvider.autoDispose
    .family<List<AppointmentListItem>, PatientDetailHistoryQuery>((ref, query) async {
      final now = clock.now().toUtc();
      final items = await ref
          .read(appointmentRepositoryProvider)
          .listAppointments(
            branchId: query.branchId,
            from: now,
            to: now.add(const Duration(days: 365)),
            statuses: const [
              AppointmentStatus.scheduled,
              AppointmentStatus.confirmed,
              AppointmentStatus.checkedIn,
              AppointmentStatus.inProgress,
            ],
          );

      final upcoming = items.where((item) => item.patientId == query.patientId).toList()
        ..sort((a, b) => a.startTime.compareTo(b.startTime));
      return upcoming;
    });

/// Visit attachments aggregated from the patient's past visits (`get_visit` per visit).
final patientVisitDocumentsProvider = FutureProvider.autoDispose.family<List<PatientVisitDocument>, String>((
  ref,
  patientId,
) async {
  final visits = await ref.watch(patientPastVisitsProvider(patientId).future);
  if (visits.isEmpty) {
    return const [];
  }

  final repository = ref.read(visitRepositoryProvider);
  final documents = <PatientVisitDocument>[];

  await Future.wait(
    visits.map((visit) async {
      try {
        final detail = await repository.getVisit(visitId: visit.id);
        for (final attachment in detail.attachments) {
          documents.add(PatientVisitDocument(visitId: visit.id, visitDate: visit.visitDate, attachment: attachment));
        }
      } on Object {
        // Skip visits the current user cannot access in full.
      }
    }),
  );

  documents.sort((a, b) => b.attachment.createdAt.compareTo(a.attachment.createdAt));
  return documents;
});
