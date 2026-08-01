import 'dart:typed_data';

<<<<<<< HEAD
=======
import 'package:flutter/material.dart';
>>>>>>> master
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/core/ui/components/app_file_dropzone.dart';
import 'package:ai_clinic/features/visits/domain/visit_attachment_file_type.dart';
import 'package:ai_clinic/features/visits/data/visit_attachment_service.dart';
import 'package:ai_clinic/features/visits/domain/visit_attachment_item.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_attachments_editor.dart';

<<<<<<< HEAD
import '../../support/visit_encounter_test_support.dart';
=======
>>>>>>> master
import 'visit_widget_test_harness.dart';

Future<void> _pumpEditor(
  WidgetTester tester, {
  required List<VisitAttachmentItem> attachments,
  bool canEdit = true,
  void Function({
    required VisitAttachmentPickInput pick,
    required String label,
    required String uploadedBy,
    String? uploadedByName,
  })?
  onStage,
  void Function(String attachmentId)? onDelete,
}) async {
  await pumpVisitsSurface(
    tester,
<<<<<<< HEAD
    child: VisitAttachmentsEditor(
      attachments: attachments,
      uploadedBy: encounterTestDoctorId,
      uploadedByName: 'Dr Test',
      canEdit: canEdit,
      onStage: onStage ??
          ({
            required pick,
            required label,
            required uploadedBy,
            uploadedByName,
          }) {},
      onDelete: onDelete ?? (_) {},
=======
    child: SingleChildScrollView(
      child: VisitAttachmentsEditor(
        attachments: attachments,
        uploadedBy: encounterTestDoctorId,
        uploadedByName: 'Dr Test',
        canEdit: canEdit,
        onStage: onStage ??
            ({
              required pick,
              required label,
              required uploadedBy,
              uploadedByName,
            }) {},
        onDelete: onDelete ?? (_) {},
      ),
>>>>>>> master
    ),
  );
  await pumpVisitsFrames(tester);
}

void main() {
  group('VisitAttachmentsEditor', () {
    group('trivial:', () {
      testWidgets('renders AppFileDropzone and helper copy', (tester) async {
        await _pumpEditor(tester, attachments: const []);

        expect(find.byType(AppFileDropzone), findsOneWidget);
        expect(find.text('Drop files here'), findsOneWidget);
        expect(find.text('PDF, DOCX, JPG, PNG up to 25 MB each.'), findsOneWidget);
      });

      testWidgets('attachment rows show label and formatted size', (tester) async {
        final attachments = [
          buildVisitAttachmentItem(label: 'Lab PDF', sizeBytes: 1024),
          buildVisitAttachmentItem(
            id: 'att-2',
            label: 'Scan.png',
            fileType: VisitAttachmentFileType.png,
            sizeBytes: 2048,
          ),
        ];

        await _pumpEditor(tester, attachments: attachments);

        expect(find.text('Lab PDF'), findsOneWidget);
        expect(find.text('1.0 KB'), findsOneWidget);
        expect(find.text('Scan.png'), findsOneWidget);
        expect(find.text('2.0 KB'), findsOneWidget);
      });

      testWidgets('delete on a row invokes delete callback with correct id', (tester) async {
        String? deletedId;
        final attachment = buildVisitAttachmentItem(id: 'att-delete-me', label: 'Lab PDF');

        await _pumpEditor(
          tester,
          attachments: [attachment],
          onDelete: (id) => deletedId = id,
        );

        final removeButton = find.bySemanticsLabel('Remove Lab PDF');
        await tester.ensureVisible(removeButton);
        await tester.tap(removeButton);
        await pumpVisitsFrames(tester);

        expect(deletedId, 'att-delete-me');
      });
    });

    group('advanced:', () {
      testWidgets('read-only mode disables dropzone browse affordance', (tester) async {
        await _pumpEditor(tester, attachments: const [], canEdit: false);

        expect(find.byType(AppFileDropzone), findsOneWidget);
        expect(find.text('Browse files'), findsOneWidget);

        await tester.tap(find.text('Browse files'));
        await pumpVisitsFrames(tester);

        // Dropzone browse is a no-op when disabled; no upload rows appear.
        expect(find.text('Uploaded files'), findsNothing);
      });

      testWidgets('canDelete false hides row delete control', (tester) async {
        final attachment = buildVisitAttachmentItem(label: 'Locked PDF', canDelete: false);

        await _pumpEditor(tester, attachments: [attachment]);

        expect(find.text('Locked PDF'), findsOneWidget);
        expect(find.bySemanticsLabel('Remove Locked PDF'), findsNothing);
      });

      testWidgets('read-only with deletable row still hides delete control', (tester) async {
        final attachment = buildVisitAttachmentItem(label: 'Lab PDF', canDelete: true);

        await _pumpEditor(tester, attachments: [attachment], canEdit: false);

        expect(find.bySemanticsLabel('Remove Lab PDF'), findsNothing);
      });
    });

    group('edge case:', () {
      testWidgets('null label falls back to attachment id', (tester) async {
        final attachment = buildVisitAttachmentItem(
          id: 'fallback-id',
          label: null,
        );

        await _pumpEditor(tester, attachments: [attachment]);

        expect(find.text('fallback-id'), findsOneWidget);
      });

      testWidgets('many attachments render one row each', (tester) async {
        final attachments = List.generate(
          20,
          (index) => buildVisitAttachmentItem(
            id: 'att-$index',
            label: 'File $index.pdf',
          ),
        );

        await _pumpEditor(tester, attachments: attachments);

        expect(find.text('File 0.pdf'), findsOneWidget);
<<<<<<< HEAD
        expect(find.text('File 19.pdf'), findsOneWidget);
        expect(find.text('Remove File 0.pdf'), findsOneWidget);
        expect(find.text('Remove File 19.pdf'), findsOneWidget);
=======
        await tester.scrollUntilVisible(find.text('File 19.pdf'), 100);
        await pumpVisitsFrames(tester);
        expect(find.text('File 19.pdf'), findsOneWidget);
        expect(find.bySemanticsLabel('Remove File 0.pdf'), findsOneWidget);
        await tester.scrollUntilVisible(
          find.bySemanticsLabel('Remove File 19.pdf'),
          100,
        );
        await pumpVisitsFrames(tester);
        expect(find.bySemanticsLabel('Remove File 19.pdf'), findsOneWidget);
>>>>>>> master
      });

      testWidgets('very long filename does not throw', (tester) async {
        final longLabel = '${'A' * 200}.pdf';

        await _pumpEditor(
          tester,
          attachments: [
            buildVisitAttachmentItem(label: longLabel),
          ],
        );

        expect(find.textContaining('AAAA'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    });

    group('regression:', () {
      test('VisitAttachmentService.validatePick exposes expected user-facing messages', () {
        expect(
          () => VisitAttachmentService.validatePick(
            buildVisitAttachmentPickInput(filename: 'empty.pdf', bytes: Uint8List(0)),
          ),
          throwsA(
            isA<VisitAttachmentValidationException>().having(
              (e) => e.message,
              'message',
              'The selected file is empty.',
            ),
          ),
        );

        expect(
          () => VisitAttachmentService.validatePick(
            buildVisitAttachmentPickInput(filename: 'bad.exe'),
          ),
          throwsA(
            isA<VisitAttachmentValidationException>().having(
              (e) => e.message,
              'message',
              'Only PDF, Word (DOCX), JPEG, and PNG files are allowed.',
            ),
          ),
        );
      });
    });
  });
}
