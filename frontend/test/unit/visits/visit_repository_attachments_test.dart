import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/visits/data/visit_repository.dart';
import 'package:ai_clinic/features/visits/domain/visit_attachment_file_type.dart';
import 'package:ai_clinic/features/visits/domain/visit_status.dart';

import '../../support/visit_rpc_test_client.dart';

const _visitId = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee';
const _patientId = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';
const _attachmentId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';

void main() {
  late VisitRpcTestClient client;
  late VisitRepository repository;

  setUp(() {
    client = VisitRpcTestClient();
    repository = VisitRepository(client);
  });

  group('VisitRepository.registerVisitAttachment', () {
    test('trivial: forwards required params to register_visit_attachment', () async {
      final id = await repository.registerVisitAttachment(
        visitId: _visitId,
        filePath: 'org/branch/visit/lab.pdf',
        fileType: 'pdf',
        sizeBytes: 2048,
      );

      expect(client.lastFunction, 'register_visit_attachment');
      expect(client.lastParams?['p_visit_id'], _visitId);
      expect(client.lastParams?['p_file_path'], 'org/branch/visit/lab.pdf');
      expect(client.lastParams?['p_file_type'], 'pdf');
      expect(client.lastParams?['p_size_bytes'], 2048);
      expect(client.lastParams?.containsKey('p_label'), isFalse);
      expect(id, _attachmentId);
    });

    test('advanced: forwards label when non-blank', () async {
      await repository.registerVisitAttachment(
        visitId: _visitId,
        filePath: '  path/to/file.pdf  ',
        fileType: '  pdf  ',
        sizeBytes: 100,
        label: '  Lab result  ',
      );

      expect(client.lastParams?['p_file_path'], 'path/to/file.pdf');
      expect(client.lastParams?['p_file_type'], 'pdf');
      expect(client.lastParams?['p_label'], 'Lab result');
    });

    test('advanced: omits label when blank', () async {
      await repository.registerVisitAttachment(
        visitId: _visitId,
        filePath: 'path.pdf',
        fileType: 'pdf',
        sizeBytes: 100,
        label: '   ',
      );

      expect(client.lastParams?.containsKey('p_label'), isFalse);
    });

    test('stupid usage: blank visit id, file path, or file type throws INVALID_INPUT', () async {
      expect(
        () => repository.registerVisitAttachment(visitId: '', filePath: 'p', fileType: 'pdf', sizeBytes: 1),
        throwsA(isA<RpcFailure>()),
      );
      expect(
        () => repository.registerVisitAttachment(visitId: _visitId, filePath: '  ', fileType: 'pdf', sizeBytes: 1),
        throwsA(isA<RpcFailure>()),
      );
      expect(
        () => repository.registerVisitAttachment(visitId: _visitId, filePath: 'p', fileType: '', sizeBytes: 1),
        throwsA(isA<RpcFailure>()),
      );
    });

    test('edge case: malformed success payload throws StateError', () async {
      client.rpcResults['register_visit_attachment'] = {'success': true, 'data': {}};

      expect(
        () => repository.registerVisitAttachment(
          visitId: _visitId,
          filePath: 'p.pdf',
          fileType: 'pdf',
          sizeBytes: 1,
        ),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('VisitRepository.getVisitAttachmentDownload', () {
    test('trivial: parses signed download result', () async {
      final download = await repository.getVisitAttachmentDownload(attachmentId: _attachmentId);

      expect(client.lastFunction, 'get_visit_attachment_download');
      expect(client.lastParams?['p_attachment_id'], _attachmentId);
      expect(download.signedUrl, 'https://example.test/download');
      expect(download.fileType, 'pdf');
      expect(download.filename, 'lab-result.pdf');
      expect(download.filePath, 'org-1/branch-1/visit-1/lab-result.pdf');
      expect(download.expiresAt, DateTime.parse('2026-05-31T12:00:00.000Z'));
    });

    test('advanced: empty file_path becomes null', () async {
      client.rpcResults['get_visit_attachment_download'] = {
        'success': true,
        'data': {
          'signed_url': 'https://example.test/x',
          'file_type': 'pdf',
          'filename': 'x.pdf',
          'file_path': '',
        },
      };

      final download = await repository.getVisitAttachmentDownload(attachmentId: _attachmentId);

      expect(download.filePath, isNull);
    });

    test('advanced: null expires_at is allowed', () async {
      client.rpcResults['get_visit_attachment_download'] = {
        'success': true,
        'data': {
          'signed_url': 'https://example.test/x',
          'file_type': 'jpeg',
          'filename': 'photo.jpg',
        },
      };

      final download = await repository.getVisitAttachmentDownload(attachmentId: _attachmentId);

      expect(download.expiresAt, isNull);
    });

    test('stupid usage: blank attachment id throws INVALID_INPUT', () async {
      expect(
        () => repository.getVisitAttachmentDownload(attachmentId: '  '),
        throwsA(isA<RpcFailure>().having((e) => e.code, 'code', 'INVALID_INPUT')),
      );
    });

    test('edge case: malformed success payload throws StateError', () async {
      client.rpcResults['get_visit_attachment_download'] = {
        'success': true,
        'data': {'signed_url': null},
      };

      expect(
        () => repository.getVisitAttachmentDownload(attachmentId: _attachmentId),
        throwsA(isA<StateError>()),
      );
    });

    test('invalid state: NOT_FOUND propagates from RPC', () async {
      client.rpcResults['get_visit_attachment_download'] = {
        'success': false,
        'error_code': 'NOT_FOUND',
        'error_message': 'Missing attachment',
      };

      expect(
        () => repository.getVisitAttachmentDownload(attachmentId: _attachmentId),
        throwsA(isA<RpcFailure>().having((e) => e.code, 'code', 'NOT_FOUND')),
      );
    });
  });

  group('VisitRepository.deleteVisitAttachment', () {
    test('trivial: forwards attachment id to delete_visit_attachment', () async {
      await repository.deleteVisitAttachment(attachmentId: _attachmentId);

      expect(client.lastFunction, 'delete_visit_attachment');
      expect(client.lastParams?['p_attachment_id'], _attachmentId);
    });

    test('stupid usage: blank attachment id throws INVALID_INPUT', () async {
      expect(
        () => repository.deleteVisitAttachment(attachmentId: ''),
        throwsA(isA<RpcFailure>()),
      );
      expect(client.lastFunction, isNull);
    });

    test('regression: FORBIDDEN propagates from RPC', () async {
      client.rpcResults['delete_visit_attachment'] = {
        'success': false,
        'error_code': 'FORBIDDEN',
        'error_message': 'Denied',
      };

      expect(
        () => repository.deleteVisitAttachment(attachmentId: _attachmentId),
        throwsA(isA<RpcFailure>().having((e) => e.code, 'code', 'FORBIDDEN')),
      );
    });
  });

  group('VisitRepository.listPatientVisitAttachments parsing', () {
    test('advanced: forwards default pagination params', () async {
      await repository.listPatientVisitAttachments(patientId: _patientId);

      expect(client.lastParams?['p_limit'], 100);
      expect(client.lastParams?['p_offset'], 0);
    });

    test('advanced: forwards custom limit and offset', () async {
      await repository.listPatientVisitAttachments(patientId: _patientId, limit: 25, offset: 50);

      expect(client.lastParams?['p_limit'], 25);
      expect(client.lastParams?['p_offset'], 50);
    });

    test('edge case: null items returns empty list', () async {
      client.rpcResults['list_patient_visit_attachments'] = {'success': true, 'data': {'items': null}};

      final rows = await repository.listPatientVisitAttachments(patientId: _patientId);

      expect(rows, isEmpty);
    });

    test('edge case: empty items returns empty list', () async {
      client.rpcResults['list_patient_visit_attachments'] = {'success': true, 'data': {'items': []}};

      final rows = await repository.listPatientVisitAttachments(patientId: _patientId);

      expect(rows, isEmpty);
    });

    test('edge case: malformed rows are skipped', () async {
      client.rpcResults['list_patient_visit_attachments'] = {
        'success': true,
        'data': {
          'items': [
            {'visit_id': '', 'visit_date': '2026-05-31', 'id': 'bad'},
            {
              'visit_id': _visitId,
              'visit_date': '2026-05-31',
              'id': _attachmentId,
              'file_type': 'pdf',
              'label': 'Valid',
              'uploaded_by': 'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
              'size_bytes': 512,
              'created_at': '2026-05-31T10:00:00.000Z',
              'can_download': true,
              'can_delete': true,
            },
          ],
        },
      };

      final rows = await repository.listPatientVisitAttachments(patientId: _patientId);

      expect(rows, hasLength(1));
      expect(rows.first.visitId, _visitId);
      expect(rows.first.attachment.id, _attachmentId);
      expect(rows.first.attachment.fileType, VisitAttachmentFileType.pdf);
      expect(rows.first.attachment.canDelete, isTrue);
    });

    test('edge case: non-list items key returns empty list', () async {
      client.rpcResults['list_patient_visit_attachments'] = {'success': true, 'data': {'items': 'not-a-list'}};

      final rows = await repository.listPatientVisitAttachments(patientId: _patientId);

      expect(rows, isEmpty);
    });
  });

  group('VisitRepository.listPatientVisits PatientVisitsPage parsing', () {
    test('edge case: empty items list parses successfully', () async {
      client.rpcResults['list_patient_visits'] = {
        'success': true,
        'data': {'items': [], 'total_count': 0, 'limit': 50, 'offset': 0},
      };

      final page = await repository.listPatientVisits(patientId: _patientId);

      expect(page.items, isEmpty);
      expect(page.totalCount, 0);
      expect(page.limit, 50);
      expect(page.offset, 0);
    });

    test('edge case: invalid visit rows are filtered out', () async {
      client.rpcResults['list_patient_visits'] = {
        'success': true,
        'data': {
          'items': [
            {'id': '', 'visit_date': '2026-05-31'},
            {
              'id': _visitId,
              'visit_date': '2026-05-31',
              'doctor_name': 'Dr Valid',
              'status': 'in_progress',
              'branch_name': 'Main',
            },
          ],
          'total_count': 2,
        },
      };

      final page = await repository.listPatientVisits(patientId: _patientId);

      expect(page.items, hasLength(1));
      expect(page.items.first.doctorName, 'Dr Valid');
      expect(page.items.first.status, VisitStatus.inProgress);
    });

    test('edge case: total_count falls back to items length when missing', () async {
      client.rpcResults['list_patient_visits'] = {
        'success': true,
        'data': {
          'items': [
            {
              'id': _visitId,
              'visit_date': '2026-05-31',
              'doctor_name': 'Dr Test',
              'status': 'completed',
              'branch_name': 'Main',
            },
          ],
        },
      };

      final page = await repository.listPatientVisits(patientId: _patientId);

      expect(page.totalCount, 1);
      expect(page.limit, 50);
      expect(page.offset, 0);
    });

    test('advanced: parses limit and offset from response', () async {
      client.rpcResults['list_patient_visits'] = {
        'success': true,
        'data': {
          'items': [],
          'total_count': 100,
          'limit': 10,
          'offset': 20,
        },
      };

      final page = await repository.listPatientVisits(patientId: _patientId, limit: 10, offset: 20);

      expect(page.limit, 10);
      expect(page.offset, 20);
      expect(page.totalCount, 100);
    });

    test('edge case: zero and negative pagination values are forwarded', () async {
      await repository.listPatientVisits(patientId: _patientId, limit: 0, offset: -5);

      expect(client.lastParams?['p_limit'], 0);
      expect(client.lastParams?['p_offset'], -5);
    });
  });

  group('PatientVisitAttachmentRow direct parsing', () {
    test('regression: fromRow requires visit id, date, and attachment fields', () {
      final row = PatientVisitAttachmentRow.fromRow({
        'visit_id': _visitId,
        'visit_date': '2026-05-31',
        'id': _attachmentId,
        'file_type': 'png',
        'uploaded_by': 'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
        'size_bytes': 256,
        'created_at': '2026-05-31T10:00:00.000Z',
        'can_download': 'true',
        'can_delete': 'false',
      });

      expect(row, isNotNull);
      expect(row!.attachment.fileType, VisitAttachmentFileType.png);
      expect(row.attachment.canDownload, isTrue);
      expect(row.attachment.canDelete, isFalse);
    });

    test('edge case: fromRow returns null for incomplete row', () {
      expect(
        PatientVisitAttachmentRow.fromRow({'visit_id': _visitId, 'visit_date': '2026-05-31'}),
        isNull,
      );
    });
  });
}
