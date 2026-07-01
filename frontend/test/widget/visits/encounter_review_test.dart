import 'package:ai_clinic/features/visits/domain/treatment_plan_item.dart';
import 'package:ai_clinic/features/visits/domain/visit_attachment_file_type.dart';
import 'package:ai_clinic/features/visits/domain/visit_attachment_item.dart';
import 'package:ai_clinic/features/visits/domain/visit_investigation.dart';
import 'package:ai_clinic/features/visits/domain/visit_vital_sign.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/encounter_review.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'visit_encounter_test_support.dart';

VisitAttachmentItem _sampleAttachment({required String id, required String label, int sizeBytes = 1024}) {
  return VisitAttachmentItem(
    id: id,
    fileType: VisitAttachmentFileType.pdf,
    label: label,
    uploadedBy: 'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
    sizeBytes: sizeBytes,
    createdAt: DateTime.utc(2026, 5, 31),
    canDownload: true,
    canDelete: false,
  );
}

void main() {
  group('EncounterReview summary lists', () {
    testWidgets('shows bulleted list when a non-rich-text field has multiple items', (tester) async {
      final visit =
          sampleEncounterVisit(
            vitalSigns: const [
              VisitVitalSign(id: 'v1', name: 'BP', value: '120/80', unit: 'mmHg'),
              VisitVitalSign(id: 'v2', name: 'HR', value: '72', unit: 'bpm'),
            ],
          ).copyWith(
            treatmentPlans: const [
              TreatmentPlanItem(
                id: 'tp1',
                visitId: encounterTestVisitId,
                patientId: encounterTestPatientId,
                medicationName: 'Amoxicillin',
                dosage: '500 mg',
              ),
              TreatmentPlanItem(
                id: 'tp2',
                visitId: encounterTestVisitId,
                patientId: encounterTestPatientId,
                medicationName: 'Ibuprofen',
                dosage: '200 mg',
              ),
            ],
            investigations: const [
              VisitInvestigation(id: 'i1', name: 'CBC'),
              VisitInvestigation(id: 'i2', name: 'CRP'),
            ],
          );

      await pumpEncounterWidget(
        tester,
        docState: sampleEncounterDocState(visit: visit),
        size: const Size(1280, 1200),
        child: EncounterReview(visitId: encounterTestVisitId, visit: visit, canEdit: false),
      );

      expect(find.byKey(const Key('encounter_review')), findsOneWidget);
      expect(find.text('•'), findsNWidgets(6));
      expect(find.textContaining('Amoxicillin'), findsOneWidget);
      expect(find.textContaining('Ibuprofen'), findsOneWidget);
      expect(find.textContaining('CBC'), findsOneWidget);
      expect(find.textContaining('CRP'), findsOneWidget);
      expect(find.textContaining('BP: 120/80 mmHg'), findsOneWidget);
      expect(find.textContaining('HR: 72 bpm'), findsOneWidget);
    });

    testWidgets('shows plain text when a non-rich-text field has a single item', (tester) async {
      final visit = sampleEncounterVisit(
        vitalSigns: const [VisitVitalSign(id: 'v1', name: 'BP', value: '120/80', unit: 'mmHg')],
      );

      await pumpEncounterWidget(
        tester,
        docState: sampleEncounterDocState(visit: visit),
        size: const Size(1280, 1200),
        child: EncounterReview(visitId: encounterTestVisitId, visit: visit, canEdit: false),
      );

      expect(find.textContaining('BP: 120/80 mmHg'), findsOneWidget);
      expect(find.text('•'), findsNothing);
    });

    testWidgets('shows bulleted attachment list when multiple files are attached', (tester) async {
      final visit = sampleEncounterVisit().copyWith(
        attachments: [
          _sampleAttachment(id: 'a1', label: 'Lab results.pdf', sizeBytes: 1258291),
          _sampleAttachment(id: 'a2', label: 'X-ray.jpeg', sizeBytes: 2048),
        ],
      );

      await pumpEncounterWidget(
        tester,
        docState: sampleEncounterDocState(visit: visit),
        size: const Size(1280, 1200),
        child: EncounterReview(visitId: encounterTestVisitId, visit: visit, canEdit: false, onRefresh: () {}),
      );

      expect(find.text('•'), findsNWidgets(2));
      expect(find.textContaining('Lab results.pdf'), findsOneWidget);
      expect(find.textContaining('X-ray.jpeg'), findsOneWidget);
    });

    testWidgets('shows plain attachment text when only one file is attached', (tester) async {
      final visit = sampleEncounterVisit().copyWith(
        attachments: [_sampleAttachment(id: 'a1', label: 'Lab results.pdf', sizeBytes: 512)],
      );

      await pumpEncounterWidget(
        tester,
        docState: sampleEncounterDocState(visit: visit),
        size: const Size(1280, 1200),
        child: EncounterReview(visitId: encounterTestVisitId, visit: visit, canEdit: false, onRefresh: () {}),
      );

      expect(find.text('Lab results.pdf'), findsOneWidget);
      expect(find.text('•'), findsNothing);
    });
  });
}
