import 'package:ai_clinic/features/visits/domain/visit_attachment_file_type.dart';
import 'package:ai_clinic/features/visits/domain/visit_attachment_item.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('VisitAttachmentItem.fromRow', () {
    test('parses valid attachment row', () {
      final item = VisitAttachmentItem.fromRow({
        'id': 'att-1',
        'file_type': 'pdf',
        'label': 'Lab report',
        'uploaded_by': 'staff-1',
        'uploaded_by_name': 'Lab Tech',
        'size_bytes': 12345,
        'created_at': '2026-05-31T12:00:00Z',
        'can_download': true,
      });

      expect(item, isNotNull);
      expect(item!.fileType, VisitAttachmentFileType.pdf);
      expect(item.label, 'Lab report');
      expect(item.canDownload, isTrue);
      expect(item.sizeBytes, 12345);
    });

    test('parses can_download from string', () {
      final item = VisitAttachmentItem.fromRow({
        'id': 'att-1',
        'file_type': 'jpeg',
        'uploaded_by': 'staff-1',
        'size_bytes': 100,
        'created_at': '2026-05-31T12:00:00Z',
        'can_download': 'false',
      });
      expect(item!.canDownload, isFalse);
    });

    test('returns null for invalid file type', () {
      expect(
        VisitAttachmentItem.fromRow({
          'id': 'att-1',
          'file_type': 'exe',
          'uploaded_by': 'staff-1',
          'size_bytes': 100,
          'created_at': '2026-05-31T12:00:00Z',
        }),
        isNull,
      );
    });

    test('returns null when size_bytes missing', () {
      expect(
        VisitAttachmentItem.fromRow({
          'id': 'att-1',
          'file_type': 'png',
          'uploaded_by': 'staff-1',
          'created_at': '2026-05-31T12:00:00Z',
        }),
        isNull,
      );
    });

    test('supports all allowed file types', () {
      for (final type in VisitAttachmentFileType.values) {
        final item = VisitAttachmentItem.fromRow({
          'id': 'att-1',
          'file_type': type.wireValue,
          'uploaded_by': 'staff-1',
          'size_bytes': 1,
          'created_at': '2026-05-31T12:00:00Z',
        });
        expect(item?.fileType, type);
      }
    });
  });
}
