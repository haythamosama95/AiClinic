import 'dart:typed_data';

import 'package:ai_clinic/features/visits/data/visit_attachment_service.dart';
import 'package:ai_clinic/features/visits/domain/patient_safety.dart';
import 'package:ai_clinic/features/visits/domain/treatment_plan_item.dart';
import 'package:ai_clinic/features/visits/domain/visit_attachment_file_type.dart';
import 'package:ai_clinic/features/visits/domain/visit_attachment_item.dart';
import 'package:ai_clinic/features/visits/domain/visit_detail.dart';
import 'package:ai_clinic/features/visits/domain/visit_encounter_draft.dart';
import 'package:ai_clinic/features/visits/domain/visit_investigation.dart';
import 'package:ai_clinic/features/visits/domain/visit_status.dart';
import 'package:ai_clinic/features/visits/domain/visit_vital_sign.dart';
import 'package:flutter_test/flutter_test.dart';

const _visitId = 'visit-1';
const _patientId = 'patient-1';

VisitDetail _baseVisit({
  List<VisitVitalSign> vitalSigns = const [],
  List<VisitInvestigation> investigations = const [],
  List<TreatmentPlanItem> treatmentPlans = const [],
  List<VisitAttachmentItem> attachments = const [],
  List<VisitInvestigation> pendingInvestigations = const [],
}) {
  return VisitDetail(
    id: _visitId,
    branchId: 'branch-1',
    appointmentId: 'appt-1',
    patientId: _patientId,
    doctorId: 'doctor-1',
    doctorName: 'Dr. Test',
    visitDate: DateTime.utc(2026, 5, 31),
    status: VisitStatus.inProgress,
    vitalSigns: vitalSigns,
    investigations: investigations,
    treatmentPlans: treatmentPlans,
    attachments: attachments,
    pendingInvestigations: pendingInvestigations,
  );
}

PendingVisitAttachment _pendingAttachment({
  String id = 'draft:att-1',
  Uint8List? bytes,
}) {
  return PendingVisitAttachment(
    id: id,
    pick: VisitAttachmentPickInput(filename: 'report.pdf', bytes: bytes ?? Uint8List.fromList([1, 2, 3])),
    label: 'Lab report',
    fileType: VisitAttachmentFileType.pdf,
    uploadedBy: 'staff-1',
    uploadedByName: 'Lab Tech',
  );
}

void main() {
  group('visitDraftIdPrefix / isVisitDraftId / newVisitDraftId', () {
    test('trivial: recognizes draft-prefixed ids', () {
      expect(isVisitDraftId('draft:abc'), isTrue);
      expect(isVisitDraftId('real-id'), isFalse);
      expect('draft:xyz'.startsWith(visitDraftIdPrefix), isTrue);
    });

    test('advanced: newVisitDraftId returns unique draft-prefixed ids', () {
      final first = newVisitDraftId();
      final second = newVisitDraftId();
      expect(first, startsWith(visitDraftIdPrefix));
      expect(second, startsWith(visitDraftIdPrefix));
      expect(first, isNot(equals(second)));
    });
  });

  group('PendingVisitAttachment.toDisplayItem', () {
    test('trivial: maps staged attachment to display item', () {
      final bytes = Uint8List.fromList([10, 20, 30]);
      final pending = _pendingAttachment(bytes: bytes);
      final display = pending.toDisplayItem();

      expect(display.id, pending.id);
      expect(display.fileType, VisitAttachmentFileType.pdf);
      expect(display.label, 'Lab report');
      expect(display.uploadedBy, 'staff-1');
      expect(display.uploadedByName, 'Lab Tech');
      expect(display.sizeBytes, bytes.length);
      expect(display.canDownload, isTrue);
      expect(display.canDelete, isTrue);
      expect(display.createdAt.isUtc, isTrue);
    });
  });

  group('PatientSafetyDraft.isEmpty', () {
    test('trivial: empty draft reports isEmpty', () {
      expect(const PatientSafetyDraft().isEmpty, isTrue);
    });

    test('edge case: any staged mutation makes draft non-empty', () {
      expect(
        const PatientSafetyDraft(archivedAllergyIds: {'a-1'}).isEmpty,
        isFalse,
      );
      expect(
        const PatientSafetyDraft(
          allergyUpdates: {'a-1': PatientAllergy(id: 'a-1', substance: 'Latex')},
        ).isEmpty,
        isFalse,
      );
    });
  });

  group('PatientSafetyDraft.applyTo', () {
    final base = PatientSafetyContext(
      allergies: const [PatientAllergy(id: 'a-1', substance: 'Penicillin', reaction: 'Rash')],
      currentMedications: const [PatientMedication(id: 'm-1', name: 'Aspirin')],
      chronicConditions: const [PatientChronicCondition(id: 'c-1', name: 'Asthma')],
      lastVitals: PatientSafetyLastVitals.fromRow({
        'items': [
          {'name': 'HR', 'value': '72'},
        ],
      }),
    );

    test('trivial: appends pending allergies, medications, and conditions', () {
      const draft = PatientSafetyDraft(
        pendingAllergies: [PatientAllergy(id: 'draft:a-2', substance: 'Latex')],
        pendingMedications: [PatientMedication(id: 'draft:m-2', name: 'Ibuprofen')],
        pendingConditions: [PatientChronicCondition(id: 'draft:c-2', name: 'Diabetes')],
      );

      final merged = draft.applyTo(base);
      expect(merged.allergies.map((a) => a.id), ['a-1', 'draft:a-2']);
      expect(merged.currentMedications.map((m) => m.id), ['m-1', 'draft:m-2']);
      expect(merged.chronicConditions.map((c) => c.id), ['c-1', 'draft:c-2']);
      expect(merged.lastVitals, same(base.lastVitals));
    });

    test('advanced: updates replace existing records by id', () {
      const draft = PatientSafetyDraft(
        allergyUpdates: {
          'a-1': PatientAllergy(id: 'a-1', substance: 'Penicillin', reaction: 'Anaphylaxis'),
        },
        medicationUpdates: {
          'm-1': PatientMedication(id: 'm-1', name: 'Aspirin', note: '81mg'),
        },
        conditionUpdates: {
          'c-1': PatientChronicCondition(id: 'c-1', name: 'Asthma', note: 'Mild'),
        },
      );

      final merged = draft.applyTo(base);
      expect(merged.allergies.single.reaction, 'Anaphylaxis');
      expect(merged.currentMedications.single.note, '81mg');
      expect(merged.chronicConditions.single.note, 'Mild');
    });

    test('edge case: archived ids remove base records before appending pending', () {
      const draft = PatientSafetyDraft(
        archivedAllergyIds: {'a-1'},
        archivedMedicationIds: {'m-1'},
        archivedConditionIds: {'c-1'},
        pendingAllergies: [PatientAllergy(id: 'draft:a-3', substance: 'Shellfish')],
      );

      final merged = draft.applyTo(base);
      expect(merged.allergies.map((a) => a.id), ['draft:a-3']);
      expect(merged.currentMedications, isEmpty);
      expect(merged.chronicConditions, isEmpty);
    });

    test('regression: archive wins over update for same id', () {
      const draft = PatientSafetyDraft(
        archivedAllergyIds: {'a-1'},
        allergyUpdates: {
          'a-1': PatientAllergy(id: 'a-1', substance: 'Penicillin', reaction: 'Updated'),
        },
      );

      final merged = draft.applyTo(base);
      expect(merged.allergies, isEmpty);
    });

    test('edge case: duplicate pending ids are all appended', () {
      const draft = PatientSafetyDraft(
        pendingAllergies: [
          PatientAllergy(id: 'draft:dup', substance: 'A'),
          PatientAllergy(id: 'draft:dup', substance: 'B'),
        ],
      );

      final merged = draft.applyTo(const PatientSafetyContext());
      expect(merged.allergies, hasLength(2));
    });
  });

  group('PatientSafetyDraft copyWith extension', () {
    test('trivial: no-arg copyWith returns equivalent draft', () {
      const original = PatientSafetyDraft(
        pendingAllergies: [PatientAllergy(id: 'draft:a-1', substance: 'Latex')],
      );
      final copied = original.copyWith();
      expect(copied.pendingAllergies, original.pendingAllergies);
      expect(copied.archivedAllergyIds, original.archivedAllergyIds);
    });

    test('advanced: overrides individual fields independently', () {
      const original = PatientSafetyDraft(
        archivedAllergyIds: {'a-1'},
        pendingMedications: [PatientMedication(id: 'm-1', name: 'Drug')],
      );
      final copied = original.copyWith(archivedAllergyIds: {'a-2'});
      expect(copied.archivedAllergyIds, {'a-2'});
      expect(copied.pendingMedications, original.pendingMedications);
    });
  });

  group('VisitEncounterDraft.isEmpty', () {
    test('trivial: default draft is empty', () {
      expect(const VisitEncounterDraft().isEmpty, isTrue);
    });

    test('edge case: nested patient safety draft makes encounter draft non-empty', () {
      expect(
        const VisitEncounterDraft(
          patientSafety: PatientSafetyDraft(archivedAllergyIds: {'a-1'}),
        ).isEmpty,
        isFalse,
      );
    });
  });

  group('VisitEncounterDraft.applyTo — vital signs', () {
    test('trivial: appends pending vital signs after updated base', () {
      const draft = VisitEncounterDraft(
        pendingVitalSigns: [VisitVitalSign(id: 'draft:v-2', name: 'HR', value: '80')],
      );
      final visit = _baseVisit(
        vitalSigns: const [VisitVitalSign(id: 'v-1', name: 'BP', value: '120/80')],
      );

      final merged = draft.applyTo(visit);
      expect(merged.vitalSigns.map((v) => v.id), ['v-1', 'draft:v-2']);
    });

    test('advanced: vital sign updates replace base entry', () {
      const draft = VisitEncounterDraft(
        vitalSignUpdates: {
          'v-1': VisitVitalSign(id: 'v-1', name: 'BP', value: '130/85', unit: 'mmHg'),
        },
      );
      final visit = _baseVisit(
        vitalSigns: const [VisitVitalSign(id: 'v-1', name: 'BP', value: '120/80')],
      );

      expect(draft.applyTo(visit).vitalSigns.single.value, '130/85');
    });

    test('edge case: archived vital signs are removed', () {
      const draft = VisitEncounterDraft(archivedVitalSignIds: {'v-1'});
      final visit = _baseVisit(
        vitalSigns: const [VisitVitalSign(id: 'v-1', name: 'BP', value: '120/80')],
      );
      expect(draft.applyTo(visit).vitalSigns, isEmpty);
    });
  });

  group('VisitEncounterDraft.applyTo — investigations', () {
    test('trivial: appends pending investigations and applies staged results to pending list', () {
      const pending = VisitInvestigation(id: 'p-1', name: 'CBC', orderedVisitId: 'prior');
      const draft = VisitEncounterDraft(
        pendingInvestigations: [VisitInvestigation(id: 'draft:i-1', name: 'X-Ray')],
        investigationResults: {'p-1': 'Normal'},
      );
      final visit = _baseVisit(
        investigations: const [VisitInvestigation(id: 'i-1', name: 'UA')],
        pendingInvestigations: [pending],
      );

      final merged = draft.applyTo(visit);
      expect(merged.investigations.map((i) => i.id), ['i-1', 'draft:i-1']);
      expect(merged.pendingInvestigations.single.result, 'Normal');
      expect(merged.pendingInvestigations.single.resultRecordedAt, isNotNull);
    });

    test('advanced: investigation updates replace base investigations', () {
      const draft = VisitEncounterDraft(
        investigationUpdates: {
          'i-1': VisitInvestigation(id: 'i-1', name: 'CBC', note: 'STAT'),
        },
      );
      final visit = _baseVisit(
        investigations: const [VisitInvestigation(id: 'i-1', name: 'CBC')],
      );

      expect(draft.applyTo(visit).investigations.single.note, 'STAT');
    });

    test('edge case: archived investigations removed from both lists', () {
      const draft = VisitEncounterDraft(archivedInvestigationIds: {'i-1', 'p-1'});
      final visit = _baseVisit(
        investigations: const [VisitInvestigation(id: 'i-1', name: 'CBC')],
        pendingInvestigations: const [VisitInvestigation(id: 'p-1', name: 'MRI', orderedVisitId: 'prior')],
      );

      final merged = draft.applyTo(visit);
      expect(merged.investigations, isEmpty);
      expect(merged.pendingInvestigations, isEmpty);
    });
  });

  group('VisitEncounterDraft.applyTo — treatment plans', () {
    test('trivial: appends pending treatment plans', () {
      const draft = VisitEncounterDraft(
        pendingTreatmentPlans: [
          TreatmentPlanItem(
            id: 'draft:tp-1',
            visitId: _visitId,
            patientId: _patientId,
            medicationName: 'Ibuprofen',
          ),
        ],
      );
      final visit = _baseVisit(
        treatmentPlans: const [
          TreatmentPlanItem(
            id: 'tp-1',
            visitId: _visitId,
            patientId: _patientId,
            medicationName: 'Aspirin',
          ),
        ],
      );

      expect(draft.applyTo(visit).treatmentPlans, hasLength(2));
    });

    test('advanced: treatment plan updates and archives work like other collections', () {
      const draft = VisitEncounterDraft(
        treatmentPlanUpdates: {
          'tp-1': TreatmentPlanItem(
            id: 'tp-1',
            visitId: _visitId,
            patientId: _patientId,
            medicationName: 'Aspirin',
            dosage: '81mg',
          ),
        },
        archivedTreatmentPlanIds: {'tp-2'},
      );
      final visit = _baseVisit(
        treatmentPlans: const [
          TreatmentPlanItem(id: 'tp-1', visitId: _visitId, patientId: _patientId, medicationName: 'Aspirin'),
          TreatmentPlanItem(id: 'tp-2', visitId: _visitId, patientId: _patientId, medicationName: 'Metformin'),
        ],
      );

      final merged = draft.applyTo(visit);
      expect(merged.treatmentPlans.single.dosage, '81mg');
    });
  });

  group('VisitEncounterDraft.applyTo — attachments', () {
    test('trivial: keeps base attachments and appends pending display items', () {
      final draft = VisitEncounterDraft(pendingAttachments: [_pendingAttachment()]);
      final visit = _baseVisit(
        attachments: [
          VisitAttachmentItem(
            id: 'att-1',
            fileType: VisitAttachmentFileType.jpeg,
            uploadedBy: 'staff-1',
            sizeBytes: 100,
            createdAt: DateTime.utc(2026, 5, 31),
            canDownload: true,
            canDelete: false,
          ),
        ],
      );

      final merged = draft.applyTo(visit);
      expect(merged.attachments, hasLength(2));
      expect(merged.attachments.last.id, 'draft:att-1');
      expect(merged.attachments.last.sizeBytes, 3);
    });

    test('edge case: deleted attachment ids are removed from base list', () {
      const draft = VisitEncounterDraft(deletedAttachmentIds: {'att-1'});
      final visit = _baseVisit(
        attachments: [
          VisitAttachmentItem(
            id: 'att-1',
            fileType: VisitAttachmentFileType.png,
            uploadedBy: 'staff-1',
            sizeBytes: 50,
            createdAt: DateTime.utc(2026, 5, 31),
            canDownload: true,
            canDelete: true,
          ),
        ],
      );

      expect(draft.applyTo(visit).attachments, isEmpty);
    });
  });

  group('VisitEncounterDraft.applyTo — patient safety staging', () {
    test('regression: patientSafety draft is not merged onto VisitDetail by applyTo', () {
      const draft = VisitEncounterDraft(
        patientSafety: PatientSafetyDraft(
          pendingAllergies: [PatientAllergy(id: 'draft:a-1', substance: 'Latex')],
        ),
      );
      final visit = _baseVisit();
      expect(draft.applyTo(visit), equals(visit));
      expect(draft.patientSafety.pendingAllergies, hasLength(1));
    });
  });

  group('VisitEncounterDraft.pendingAttachmentById / pendingAttachmentBytes', () {
    test('trivial: resolves staged attachment bytes by id', () {
      final bytes = Uint8List.fromList([7, 8, 9]);
      final draft = VisitEncounterDraft(
        pendingAttachments: [_pendingAttachment(id: 'draft:att-x', bytes: bytes)],
      );

      expect(draft.pendingAttachmentById('draft:att-x')?.id, 'draft:att-x');
      expect(draft.pendingAttachmentBytes('draft:att-x'), bytes);
      expect(draft.pendingAttachmentById('missing'), isNull);
      expect(draft.pendingAttachmentBytes('missing'), isNull);
    });
  });

  group('VisitEncounterDraft.copyWith', () {
    test('trivial: no-arg copyWith preserves all fields', () {
      final original = VisitEncounterDraft(
        pendingVitalSigns: const [VisitVitalSign(id: 'draft:v-1', name: 'HR', value: '70')],
        deletedAttachmentIds: {'att-1'},
      );
      final copied = original.copyWith();
      expect(copied.pendingVitalSigns, original.pendingVitalSigns);
      expect(copied.deletedAttachmentIds, original.deletedAttachmentIds);
      expect(copied.patientSafety, original.patientSafety);
    });

    test('advanced: overrides individual collections without clearing others', () {
      const original = VisitEncounterDraft(
        archivedVitalSignIds: {'v-1'},
        investigationResults: {'i-1': 'Positive'},
      );
      final copied = original.copyWith(investigationResults: {'i-2': 'Negative'});
      expect(copied.archivedVitalSignIds, original.archivedVitalSignIds);
      expect(copied.investigationResults, {'i-2': 'Negative'});
    });

    test('stupid usage: null params do not clear fields because copyWith uses ??', () {
      const original = VisitEncounterDraft(
        archivedInvestigationIds: {'i-1'},
      );
      final copied = original.copyWith(archivedInvestigationIds: null);
      expect(copied.archivedInvestigationIds, original.archivedInvestigationIds);
    });
  });
}
