import 'package:ai_clinic/features/visits/domain/visit_detail.dart';
import 'package:ai_clinic/features/visits/domain/visit_status.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_submitted_confirmation_data.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

VisitDetail _sampleVisit({String id = 'abcd1234-5678-4abc-8def-abcdef123456', DateTime? visitDate}) {
  return VisitDetail(
    id: id,
    branchId: 'branch-1',
    appointmentId: 'appt-1',
    patientId: 'patient-1',
    doctorId: 'doctor-1',
    doctorName: 'Dr. Smith',
    visitDate: visitDate ?? DateTime.utc(2026, 5, 31),
    status: VisitStatus.completed,
  );
}

void main() {
  group('VisitConfirmationKind', () {
    test('trivial: completed kind uses finalize copy', () {
      expect(VisitConfirmationKind.completed.title, 'Visit completed');
      expect(VisitConfirmationKind.completed.bodyLine('Jane'), 'The visit for Jane is on file.');
      expect(VisitConfirmationKind.completed.filingBadgeLabel, 'Filed');
      expect(VisitConfirmationKind.completed.footerNote, 'Record locked · available in patient chart');
    });

    test('trivial: edited kind uses update copy', () {
      expect(VisitConfirmationKind.edited.title, 'Changes saved');
      expect(VisitConfirmationKind.edited.bodyLine('Jane'), 'The visit for Jane has been updated.');
      expect(VisitConfirmationKind.edited.filingBadgeLabel, 'Updated');
      expect(VisitConfirmationKind.edited.footerNote, 'Record updated · available in patient chart');
    });
  });

  group('formatVisitFilingReference', () {
    test('trivial: builds ENC reference from visit date and id prefix', () {
      final visit = _sampleVisit();
      final local = visit.visitDate.toLocal();
      final datePart = DateFormat('yyyy-MMdd').format(local);
      final compactId = visit.id.replaceAll('-', '');
      final suffix = compactId.substring(0, 4).toUpperCase();

      expect(formatVisitFilingReference(visit), 'ENC-$datePart-$suffix');
    });

    test('edge case: short id uses entire compact id as suffix', () {
      final visit = _sampleVisit(id: 'ab');
      expect(formatVisitFilingReference(visit), 'ENC-${DateFormat('yyyy-MMdd').format(visit.visitDate.toLocal())}-AB');
    });

    test('advanced: strips hyphens before taking suffix', () {
      final visit = _sampleVisit(id: 'zz-yy-xx-ww-vv');
      expect(formatVisitFilingReference(visit).endsWith('-ZZYY'), isTrue);
    });
  });

  group('VisitSubmittedConfirmationData', () {
    test('trivial: displayTimestamp prefers actionAt over visitDate', () {
      final visitDate = DateTime.utc(2026, 5, 31);
      final actionAt = DateTime.utc(2026, 6, 1, 10);
      final data = VisitSubmittedConfirmationData(
        patientName: 'Jane',
        doctorName: 'Dr. Smith',
        visitDate: visitDate,
        appointmentStart: DateTime.utc(2026, 5, 31, 9),
        appointmentEnd: DateTime.utc(2026, 5, 31, 9, 30),
        filingReference: 'ENC-2026-0531-ABCD',
        branchName: 'Main',
        actionAt: actionAt,
      );
      expect(data.displayTimestamp, actionAt);
    });

    test('edge case: displayTimestamp falls back to visitDate when actionAt null', () {
      final visitDate = DateTime.utc(2026, 5, 31);
      final data = VisitSubmittedConfirmationData(
        patientName: 'Jane',
        doctorName: 'Dr. Smith',
        visitDate: visitDate,
        appointmentStart: DateTime.utc(2026, 5, 31, 9),
        appointmentEnd: DateTime.utc(2026, 5, 31, 9, 30),
        filingReference: 'ENC-2026-0531-ABCD',
        branchName: 'Main',
      );
      expect(data.displayTimestamp, visitDate);
    });

    test('advanced: fromVisit maps visit fields and filing reference', () {
      final visit = _sampleVisit();
      final start = DateTime.utc(2026, 5, 31, 9);
      final end = DateTime.utc(2026, 5, 31, 9, 30);
      final data = VisitSubmittedConfirmationData.fromVisit(
        visit: visit,
        patientName: 'Jane Doe',
        branchName: 'Downtown',
        appointmentStart: start,
        appointmentEnd: end,
        kind: VisitConfirmationKind.edited,
        actionAt: DateTime.utc(2026, 6, 1),
      );

      expect(data.patientName, 'Jane Doe');
      expect(data.doctorName, visit.doctorName);
      expect(data.visitDate, visit.visitDate);
      expect(data.filingReference, formatVisitFilingReference(visit));
      expect(data.branchName, 'Downtown');
      expect(data.kind, VisitConfirmationKind.edited);
      expect(data.invoicePreview, isNull);
      expect(data.persistedInvoice, isNull);
    });
  });
}
