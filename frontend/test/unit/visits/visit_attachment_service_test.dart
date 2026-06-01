import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:storage_client/storage_client.dart' show FileObject;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/visits/data/visit_attachment_service.dart';
import 'package:ai_clinic/features/visits/data/visit_repository.dart';
import 'package:ai_clinic/features/visits/domain/visit_attachment_file_type.dart';

import '../../support/visit_rpc_test_client.dart';

class _RecordingStorageBucket extends Fake implements StorageFileApi {
  final List<({String path, Uint8List bytes})> uploads = [];
  final List<String> removed = [];

  @override
  Future<String> uploadBinary(
    String path,
    Uint8List data, {
    FileOptions fileOptions = const FileOptions(),
    int? retryAttempts,
    StorageRetryController? retryController,
  }) async {
    uploads.add((path: path, bytes: data));
    return path;
  }

  @override
  Future<List<FileObject>> remove(List<String> paths) async {
    removed.addAll(paths);
    return [];
  }
}

class _AttachmentStorageTestClient extends Fake implements SupabaseClient {
  _AttachmentStorageTestClient(this.bucket);

  final _RecordingStorageBucket bucket;

  @override
  SupabaseStorageClient get storage => _FakeStorageClient(bucket);
}

class _FakeStorageClient extends Fake implements SupabaseStorageClient {
  _FakeStorageClient(this.bucket);

  final _RecordingStorageBucket bucket;

  @override
  StorageFileApi from(String id) {
    if (id != VisitAttachmentService.bucketName) {
      throw StateError('Unexpected bucket: $id');
    }
    return bucket;
  }
}

void main() {
  group('VisitAttachmentService validation', () {
    test('inferFileTypeFromFilename accepts allowed extensions', () {
      expect(VisitAttachmentService.inferFileTypeFromFilename('report.PDF'), VisitAttachmentFileType.pdf);
      expect(VisitAttachmentService.inferFileTypeFromFilename('notes.docx'), VisitAttachmentFileType.docx);
      expect(VisitAttachmentService.inferFileTypeFromFilename('scan.JPG'), VisitAttachmentFileType.jpeg);
      expect(VisitAttachmentService.inferFileTypeFromFilename('x.png'), VisitAttachmentFileType.png);
    });

    test('inferFileTypeFromFilename rejects unsupported extensions', () {
      expect(VisitAttachmentService.inferFileTypeFromFilename('virus.exe'), isNull);
      expect(VisitAttachmentService.inferFileTypeFromFilename('noext'), isNull);
    });

    test('validatePick rejects empty bytes', () {
      expect(
        () => VisitAttachmentService.validatePick(VisitAttachmentPickInput(filename: 'a.pdf', bytes: Uint8List(0))),
        throwsA(isA<VisitAttachmentValidationException>().having((e) => e.errorCode, 'errorCode', 'INVALID_INPUT')),
      );
    });

    test('validatePick rejects oversize files', () {
      expect(
        () => VisitAttachmentService.validatePick(
          VisitAttachmentPickInput(filename: 'big.pdf', bytes: Uint8List(VisitAttachmentService.maxBytes + 1)),
        ),
        throwsA(isA<VisitAttachmentValidationException>().having((e) => e.errorCode, 'errorCode', 'FILE_TOO_LARGE')),
      );
    });

    test('validatePick rejects disallowed file types', () {
      expect(
        () => VisitAttachmentService.validatePick(
          VisitAttachmentPickInput(filename: 'notes.txt', bytes: Uint8List.fromList([1, 2, 3])),
        ),
        throwsA(isA<VisitAttachmentValidationException>().having((e) => e.errorCode, 'errorCode', 'INVALID_FILE_TYPE')),
      );
    });

    test('contentTypeFor maps file types', () {
      expect(VisitAttachmentService.contentTypeFor(VisitAttachmentFileType.pdf), 'application/pdf');
      expect(VisitAttachmentService.contentTypeFor(VisitAttachmentFileType.png), 'image/png');
    });
  });

  group('VisitAttachmentService paths', () {
    late VisitAttachmentService service;

    setUp(() {
      service = VisitAttachmentService(
        _AttachmentStorageTestClient(_RecordingStorageBucket()),
        VisitRepository(VisitRpcTestClient()),
      );
    });

    test('buildStoragePath uses org/branch/visit prefix and sanitizes filename', () {
      final path = service.buildStoragePath(
        organizationId: 'org-1',
        branchId: 'branch-1',
        visitId: 'visit-1',
        originalFilename: 'lab report (1).pdf',
        uniqueId: '11111111-1111-4111-8111-111111111111',
      );
      expect(path, 'org-1/branch-1/visit-1/11111111-1111-4111-8111-111111111111_lab_report_1_.pdf');
    });
  });

  group('VisitAttachmentService RPC delegation', () {
    late VisitRpcTestClient testClient;
    late VisitAttachmentService service;

    setUp(() {
      testClient = VisitRpcTestClient();
      service = VisitAttachmentService(
        _AttachmentStorageTestClient(_RecordingStorageBucket()),
        VisitRepository(testClient),
      );
    });

    test('registerVisitAttachment invokes RPC', () async {
      final id = await service.registerVisitAttachment(
        visitId: 'visit-1',
        filePath: 'org/branch/visit/file.pdf',
        fileType: VisitAttachmentFileType.pdf,
        sizeBytes: 100,
        label: 'Lab',
      );
      expect(id, isNotEmpty);
      expect(testClient.rpcLog.last, 'register_visit_attachment');
      final params = testClient.paramsForFunction('register_visit_attachment')!;
      expect(params['p_visit_id'], 'visit-1');
      expect(params['p_file_type'], 'pdf');
      expect(params['p_size_bytes'], 100);
      expect(params['p_label'], 'Lab');
    });

    test('getVisitAttachmentDownload returns signed URL', () async {
      final download = await service.getVisitAttachmentDownload(attachmentId: 'att-1');
      expect(download.signedUrl, 'https://example.test/download');
      expect(download.filename, 'lab-result.pdf');
    });
  });

  group('uploadAndRegister', () {
    late VisitRpcTestClient testClient;
    late _RecordingStorageBucket bucket;
    late VisitAttachmentService service;

    setUp(() {
      testClient = VisitRpcTestClient();
      bucket = _RecordingStorageBucket();
      service = VisitAttachmentService(_AttachmentStorageTestClient(bucket), VisitRepository(testClient));
    });

    test('uploads then registers attachment metadata', () async {
      final id = await service.uploadAndRegister(
        organizationId: 'org-1',
        branchId: 'branch-1',
        visitId: 'visit-1',
        pick: VisitAttachmentPickInput(filename: 'result.pdf', bytes: Uint8List.fromList([1, 2, 3])),
      );
      expect(id, isNotEmpty);
      expect(bucket.uploads, hasLength(1));
      expect(bucket.uploads.first.bytes, Uint8List.fromList([1, 2, 3]));
      expect(testClient.rpcLog, contains('register_visit_attachment'));
    });

    test('removes storage object when register fails', () async {
      testClient.rpcResults['register_visit_attachment'] = {
        'success': false,
        'error_code': 'FORBIDDEN',
        'error_message': 'denied',
      };

      await expectLater(
        service.uploadAndRegister(
          organizationId: 'org-1',
          branchId: 'branch-1',
          visitId: 'visit-1',
          pick: VisitAttachmentPickInput(filename: 'result.pdf', bytes: Uint8List.fromList([1, 2, 3])),
        ),
        throwsA(isA<RpcFailure>()),
      );
      expect(bucket.uploads, hasLength(1));
      expect(bucket.removed, hasLength(1));
    });
  });
}
