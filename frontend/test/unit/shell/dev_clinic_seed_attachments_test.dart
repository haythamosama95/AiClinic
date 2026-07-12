import 'package:ai_clinic/app/shell/dev/dev_clinic_seed_attachments.dart';
import 'package:ai_clinic/features/visits/domain/visit_attachment_file_type.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DevClinicSeedAttachments', () {
    test('covers every file type with and without labels', () {
      final combos = <String>{};
      const seedKeysForSingleCombos = [8, 1, 2, 3, 4, 5, 6, 15];
      for (final seedKey in seedKeysForSingleCombos) {
        final seed = DevClinicSeedAttachments.attachmentsFor(
          seedKey: seedKey,
          branchCode: 'DTWN',
          patientIndex: 1,
        ).single;
        combos.add('${seed.fileType.wireValue}:${seed.label != null}');
        expect(
          seed.filename,
          endsWith(switch (seed.fileType) {
            VisitAttachmentFileType.pdf => '.pdf',
            VisitAttachmentFileType.docx => '.docx',
            VisitAttachmentFileType.jpeg => '.jpg',
            VisitAttachmentFileType.png => '.png',
          }),
        );
        expect(DevClinicSeedAttachments.dummyBytesFor(seed.fileType), isNotEmpty);
      }

      expect(combos.length, DevClinicSeedAttachments.singleAttachmentCombos);
      for (final fileType in VisitAttachmentFileType.values) {
        expect(combos, contains('${fileType.wireValue}:true'));
        expect(combos, contains('${fileType.wireValue}:false'));
      }
    });

    test('includes visits without documents and visits with multiple documents', () {
      expect(DevClinicSeedAttachments.shouldSeedAttachments(10), isFalse);
      expect(DevClinicSeedAttachments.shouldSeedMultipleAttachments(7), isTrue);
      expect(DevClinicSeedAttachments.attachmentsFor(seedKey: 7, branchCode: 'UPTN', patientIndex: 2), hasLength(2));
    });
  });
}
