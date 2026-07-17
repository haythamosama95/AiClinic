import 'package:intl/intl.dart';

import 'package:ai_clinic/features/visits/domain/visit_detail.dart';

/// Display data for the post-finalize visit confirmation card.
class VisitSubmittedConfirmationData {
  const VisitSubmittedConfirmationData({
    required this.patientName,
    required this.doctorName,
    required this.visitDate,
    required this.appointmentStart,
    required this.appointmentEnd,
    required this.filingReference,
    required this.branchName,
  });

  final String patientName;
  final String doctorName;
  final DateTime visitDate;
  final DateTime appointmentStart;
  final DateTime appointmentEnd;
  final String filingReference;
  final String branchName;

  static VisitSubmittedConfirmationData fromVisit({
    required VisitDetail visit,
    required String patientName,
    required String branchName,
    required DateTime appointmentStart,
    required DateTime appointmentEnd,
  }) {
    return VisitSubmittedConfirmationData(
      patientName: patientName,
      doctorName: visit.doctorName,
      visitDate: visit.visitDate,
      appointmentStart: appointmentStart,
      appointmentEnd: appointmentEnd,
      filingReference: formatVisitFilingReference(visit),
      branchName: branchName,
    );
  }
}

/// Human-readable filing reference derived from visit metadata.
String formatVisitFilingReference(VisitDetail visit) {
  final local = visit.visitDate.toLocal();
  final datePart = DateFormat('yyyy-MMdd').format(local);
  final compactId = visit.id.replaceAll('-', '');
  final suffix = compactId.length >= 4 ? compactId.substring(0, 4).toUpperCase() : compactId.toUpperCase();
  return 'ENC-$datePart-$suffix';
}
