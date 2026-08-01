import 'package:ai_clinic/features/patients/domain/patient_visit_document.dart';
import 'package:ai_clinic/features/visits/domain/visit_attachment_file_type.dart';
import 'package:ai_clinic/features/visits/domain/visit_attachment_item.dart';
import 'package:flutter_test/flutter_test.dart';

VisitAttachmentItem _attachment({String id = 'att-1'}) {
  return VisitAttachmentItem(
    id: id,
    fileType: VisitAttachmentFileType.pdf,
    uploadedBy: 'user-1',
    sizeBytes: 1024,
    createdAt: DateTime.utc(2026, 1, 15),
    canDownload: true,
    canDelete: false,
  );
}

PatientVisitDocument _document({
  String visitId = 'v1',
  DateTime? visitDate,
  VisitAttachmentItem? attachment,
}) {
  return PatientVisitDocument(
    visitId: visitId,
    visitDate: visitDate ?? DateTime.utc(2026, 3, 10),
    attachment: attachment ?? _attachment(),
  );
}

void main() {
  group('PatientVisitDocument', () {
    test('trivial: constructs with visitId, visitDate, and attachment', () {
      final attachment = _attachment();
      final visitDate = DateTime.utc(2026, 5, 1);
      final document = PatientVisitDocument(
        visitId: 'visit-99',
        visitDate: visitDate,
        attachment: attachment,
      );

      expect(document.visitId, 'visit-99');
      expect(document.visitDate, visitDate);
      expect(document.attachment, attachment);
    });
  });

  group('PatientVisitDocument equality', () {
    test('trivial: equal instances share hashCode', () {
      final a = _document();
      final b = _document();

      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('edge case: differing visitId is unequal', () {
      expect(_document(visitId: 'v1') == _document(visitId: 'v2'), isFalse);
    });

    test('edge case: differing visitDate is unequal', () {
      expect(
        _document(visitDate: DateTime.utc(2026, 1, 1)) ==
            _document(visitDate: DateTime.utc(2026, 1, 2)),
        isFalse,
      );
    });

    test('edge case: differing attachment is unequal', () {
      expect(
        _document(attachment: _attachment(id: 'att-1')) ==
            _document(attachment: _attachment(id: 'att-2')),
        isFalse,
      );
    });
  });
}
