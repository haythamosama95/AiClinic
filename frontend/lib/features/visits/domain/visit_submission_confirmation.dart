import 'package:intl/intl.dart';

import 'package:ai_clinic/features/visits/domain/visit_detail.dart';

/// Whether the confirmation celebrates a first-time finalize or a post-submit edit.
enum VisitConfirmationKind {
  completed,
  edited;

  String get title => switch (this) {
    VisitConfirmationKind.completed => 'Visit completed',
    VisitConfirmationKind.edited => 'Changes saved',
  };

  String bodyLine(String patientName) => switch (this) {
    VisitConfirmationKind.completed => 'The visit for $patientName is on file.',
    VisitConfirmationKind.edited => 'The visit for $patientName has been updated.',
  };

  String get filingBadgeLabel => switch (this) {
    VisitConfirmationKind.completed => 'Filed',
    VisitConfirmationKind.edited => 'Updated',
  };

  String get footerNote => switch (this) {
    VisitConfirmationKind.completed => 'Record locked · available in patient chart',
    VisitConfirmationKind.edited => 'Record updated · available in patient chart',
  };
}

/// Display data for the post-finalize visit confirmation card.
class VisitSubmissionConfirmation {
  const VisitSubmissionConfirmation({
    required this.patientName,
    required this.doctorName,
    required this.visitDate,
    required this.appointmentStart,
    required this.appointmentEnd,
    required this.filingReference,
    required this.branchName,
    required this.appointmentId,
    this.kind = VisitConfirmationKind.completed,
    this.actionAt,
  });

  final String patientName;
  final String doctorName;
  final DateTime visitDate;
  final DateTime appointmentStart;
  final DateTime appointmentEnd;
  final String filingReference;
  final String branchName;
  final String appointmentId;
  final VisitConfirmationKind kind;
  final DateTime? actionAt;

  DateTime get displayTimestamp => actionAt ?? visitDate;

  static VisitSubmissionConfirmation fromVisit({
    required VisitDetail visit,
    required String patientName,
    required String branchName,
    required DateTime appointmentStart,
    required DateTime appointmentEnd,
    VisitConfirmationKind kind = VisitConfirmationKind.completed,
    DateTime? actionAt,
  }) {
    return VisitSubmissionConfirmation(
      patientName: patientName,
      doctorName: visit.doctorName,
      visitDate: visit.visitDate,
      appointmentStart: appointmentStart,
      appointmentEnd: appointmentEnd,
      filingReference: formatVisitFilingReference(visit),
      branchName: branchName,
      appointmentId: visit.appointmentId,
      kind: kind,
      actionAt: actionAt,
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
