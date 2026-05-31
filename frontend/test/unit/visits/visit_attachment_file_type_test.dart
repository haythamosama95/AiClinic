import 'package:ai_clinic/features/visits/domain/visit_attachment_file_type.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('VisitAttachmentFileType', () {
    test('tryParse accepts all wire values', () {
      expect(VisitAttachmentFileType.tryParse('pdf'), VisitAttachmentFileType.pdf);
      expect(VisitAttachmentFileType.tryParse('docx'), VisitAttachmentFileType.docx);
      expect(VisitAttachmentFileType.tryParse('jpeg'), VisitAttachmentFileType.jpeg);
      expect(VisitAttachmentFileType.tryParse('png'), VisitAttachmentFileType.png);
    });

    test('rejects disallowed types', () {
      expect(VisitAttachmentFileType.tryParse('exe'), isNull);
      expect(VisitAttachmentFileType.tryParse('gif'), isNull);
      expect(VisitAttachmentFileType.tryParse(''), isNull);
    });

    test('wireValue round-trips', () {
      for (final type in VisitAttachmentFileType.values) {
        expect(VisitAttachmentFileType.tryParse(type.wireValue), type);
      }
    });
  });
}
