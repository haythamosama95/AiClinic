import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/features/visits/domain/visit_detail.dart';
import 'package:ai_clinic/features/visits/domain/visit_status.dart';
import 'package:ai_clinic/features/visits/presentation/providers/visit_documentation_notifier.dart';

void main() {
  group('VisitDocumentationState.isEditable', () {
    VisitDetail visit({required VisitStatus status}) {
      return VisitDetail.fromRow({
        'id': 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',
        'branch_id': '44444444-4444-4444-8444-444444444444',
        'appointment_id': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
        'patient_id': 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
        'doctor_id': 'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
        'doctor_name': 'Dr Test',
        'visit_date': '2026-05-31',
        'status': status.wireValue,
      })!;
    }

    test('is editable when user has visits.edit_soap on in-progress visit', () {
      final state = VisitDocumentationState.fromVisit(visit(status: VisitStatus.inProgress), canEdit: true);
      expect(state.isEditable, isTrue);
    });

    test('is editable when user has visits.edit_soap on completed visit', () {
      final state = VisitDocumentationState.fromVisit(visit(status: VisitStatus.completed), canEdit: true);
      expect(state.isEditable, isTrue);
    });

    test('is not editable without visits.edit_soap even when visit in progress', () {
      final state = VisitDocumentationState.fromVisit(visit(status: VisitStatus.inProgress), canEdit: false);
      expect(state.isEditable, isFalse);
    });

    test('is not editable without visits.edit_soap on completed visit', () {
      final state = VisitDocumentationState.fromVisit(visit(status: VisitStatus.completed), canEdit: false);
      expect(state.isEditable, isFalse);
    });
  });

  group('VisitDocumentationState.needsSaveBeforeLeaving', () {
    VisitDetail visit() {
      return VisitDetail.fromRow({
        'id': 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',
        'branch_id': '44444444-4444-4444-8444-444444444444',
        'appointment_id': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
        'patient_id': 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
        'doctor_id': 'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
        'doctor_name': 'Dr Test',
        'visit_date': '2026-05-31',
        'status': 'completed',
      })!;
    }

    test('is true for a fresh editable load', () {
      final state = VisitDocumentationState.fromVisit(visit(), canEdit: true);
      expect(state.needsSaveBeforeLeaving, isTrue);
    });

    test('is false after a successful save', () {
      final state = VisitDocumentationState.fromVisit(
        visit(),
        canEdit: true,
      ).copyWith(saveStatus: SoapSaveStatus.saved, soapEditMode: SoapEditMode.readOnly);
      expect(state.needsSaveBeforeLeaving, isFalse);
    });
  });
}
