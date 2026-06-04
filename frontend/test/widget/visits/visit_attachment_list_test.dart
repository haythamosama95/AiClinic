import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/auth/domain/permission_keys.dart';
import 'package:ai_clinic/features/visits/data/visit_attachment_service.dart';
import 'package:ai_clinic/features/visits/data/visit_repository.dart'
    show VisitAttachmentDownloadResult, VisitRepository;
import 'package:ai_clinic/features/visits/domain/visit_attachment_file_type.dart';
import 'package:ai_clinic/features/visits/domain/visit_attachment_item.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_attachment_list.dart';

import '../../helpers/auth_test_support.dart';
import '../../support/visit_rpc_test_client.dart';

class _TestVisitAttachmentService extends VisitAttachmentService {
  _TestVisitAttachmentService({required this.onUpload, required VisitRepository repository})
    : super(_NoStorageClient(), repository);

  final Future<String> Function({
    required String organizationId,
    required String branchId,
    required String visitId,
    required VisitAttachmentPickInput pick,
    String? label,
  })
  onUpload;

  @override
  Future<String> uploadAndRegister({
    required String organizationId,
    required String branchId,
    required String visitId,
    required VisitAttachmentPickInput pick,
    String? label,
  }) {
    VisitAttachmentService.validatePick(pick);
    return onUpload(organizationId: organizationId, branchId: branchId, visitId: visitId, pick: pick, label: label);
  }
}

class _NoStorageClient extends Fake implements SupabaseClient {}

void main() {
  late VisitRpcTestClient testClient;
  var uploadCount = 0;
  var shouldFailUpload = false;
  Object? uploadError;

  setUp(() {
    testClient = VisitRpcTestClient();
    uploadCount = 0;
    shouldFailUpload = false;
    uploadError = null;
  });

  Widget buildWidget({
    List<VisitAttachmentItem> attachments = const [],
    bool canUpload = true,
    Future<VisitAttachmentPickInput?> Function()? pickAttachment,
    Future<Uint8List> Function(VisitAttachmentDownloadResult download)? fetchDownloadBytes,
    Future<bool> Function(String filename, Uint8List bytes)? saveDownloadedAttachment,
  }) {
    final authState = AuthSessionState(
      status: AuthSessionStatus.authenticated,
      context: sampleAuthSessionContext(
        permissions: {PermissionKeys.visitsEditSoap},
        branchIds: const ['branch-1'],
        activeBranchId: 'branch-1',
      ),
    );

    final attachmentService = _TestVisitAttachmentService(
      repository: VisitRepository(testClient),
      onUpload:
          ({
            required String organizationId,
            required String branchId,
            required String visitId,
            required VisitAttachmentPickInput pick,
            String? label,
          }) async {
            uploadCount++;
            await Future<void>.delayed(const Duration(milliseconds: 50));
            if (shouldFailUpload) {
              throw uploadError ??
                  RpcFailure(const RpcResult(success: false, errorCode: 'INVALID_FILE_TYPE', errorMessage: 'bad type'));
            }
            return 'new-attachment-id';
          },
    );

    return ProviderScope(
      overrides: [
        authSessionProvider.overrideWith(() => _PresetAuth(authState)),
        visitAttachmentServiceProvider.overrideWithValue(attachmentService),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: VisitAttachmentList(
              visitId: 'visit-1',
              branchId: 'branch-1',
              attachments: attachments,
              canUpload: canUpload,
              onChanged: () {},
              pickAttachment:
                  pickAttachment ??
                  () async => VisitAttachmentPickInput(filename: 'lab.pdf', bytes: Uint8List.fromList([1, 2, 3])),
              fetchDownloadBytes: fetchDownloadBytes ?? (_) async => Uint8List.fromList([4, 5, 6]),
              saveDownloadedAttachment:
                  saveDownloadedAttachment ??
                  (filename, bytes) async {
                    expect(filename, 'lab-result.pdf');
                    expect(bytes, Uint8List.fromList([4, 5, 6]));
                    return true;
                  },
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('shows empty state when no attachments', (tester) async {
    await tester.pumpWidget(buildWidget());
    expect(find.byKey(const Key('visit_attachment_empty')), findsOneWidget);
  });

  testWidgets('hides upload button when canUpload is false', (tester) async {
    await tester.pumpWidget(buildWidget(canUpload: false));
    expect(find.byKey(const Key('visit_attachment_upload_button')), findsNothing);
  });

  testWidgets('shows upload progress while uploading', (tester) async {
    await tester.pumpWidget(buildWidget());
    await tester.tap(find.byKey(const Key('visit_attachment_upload_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
    expect(find.byKey(const Key('visit_attachment_upload_progress')), findsOneWidget);
    await tester.pumpAndSettle();
    expect(uploadCount, 1);
  });

  testWidgets('shows friendly message after storage permission failure', (tester) async {
    shouldFailUpload = true;
    uploadError = const StorageException('new row violates row level security policy');
    await tester.pumpWidget(buildWidget());
    await tester.tap(find.byKey(const Key('visit_attachment_upload_button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('visit_attachment_error')), findsOneWidget);
    expect(find.textContaining('StorageException'), findsNothing);
    expect(find.textContaining('permission'), findsOneWidget);
  });

  testWidgets('shows RPC error after failed upload', (tester) async {
    shouldFailUpload = true;
    await tester.pumpWidget(buildWidget());
    await tester.tap(find.byKey(const Key('visit_attachment_upload_button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('visit_attachment_error')), findsOneWidget);
    expect(find.textContaining('PDF'), findsOneWidget);
  });

  testWidgets('shows client validation error for disallowed file type', (tester) async {
    await tester.pumpWidget(
      buildWidget(
        pickAttachment: () async =>
            VisitAttachmentPickInput(filename: 'report.exe', bytes: Uint8List.fromList([1, 2, 3])),
      ),
    );
    await tester.tap(find.byKey(const Key('visit_attachment_upload_button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('visit_attachment_error')), findsOneWidget);
    expect(find.textContaining('PDF'), findsOneWidget);
    expect(uploadCount, 0);
  });

  testWidgets('lists attachments and shows download when allowed', (tester) async {
    final attachments = [
      VisitAttachmentItem(
        id: 'att-1',
        fileType: VisitAttachmentFileType.pdf,
        label: 'Lab result',
        uploadedBy: 'staff-1',
        uploadedByName: 'Lab Tech',
        sizeBytes: 2048,
        createdAt: DateTime.utc(2026, 5, 31, 10),
        canDownload: true,
      ),
    ];
    await tester.pumpWidget(buildWidget(attachments: attachments));
    expect(find.byKey(const Key('visit_attachment_row_att-1')), findsOneWidget);
    expect(find.text('Lab result'), findsOneWidget);
    expect(find.byKey(const Key('visit_attachment_download_att-1')), findsOneWidget);
  });

  testWidgets('download test hook receives filePath from authorized download metadata', (tester) async {
    testClient.rpcResults['get_visit_attachment_download'] = {
      'success': true,
      'data': {
        'signed_url': 'https://example.com/signed',
        'file_type': 'pdf',
        'filename': 'lab-result.pdf',
        'expires_at': '2026-06-01T12:00:00.000Z',
        'file_path': 'org/branch/visit/lab.pdf',
      },
    };

    VisitAttachmentDownloadResult? captured;
    final attachments = [
      VisitAttachmentItem(
        id: 'att-1',
        fileType: VisitAttachmentFileType.pdf,
        uploadedBy: 'staff-1',
        sizeBytes: 2048,
        createdAt: DateTime.utc(2026, 5, 31, 10),
        canDownload: true,
      ),
    ];
    await tester.pumpWidget(
      buildWidget(
        attachments: attachments,
        fetchDownloadBytes: (download) async {
          captured = download;
          return Uint8List.fromList([4, 5, 6]);
        },
        saveDownloadedAttachment: (_, __) async => true,
      ),
    );
    await tester.tap(find.byKey(const Key('visit_attachment_download_att-1')));
    await tester.pumpAndSettle();

    expect(captured, isNotNull);
    expect(captured!.filePath, 'org/branch/visit/lab.pdf');
    expect(captured!.signedUrl, 'https://example.com/signed');
  });

  testWidgets('download prompts to save file with attachment filename', (tester) async {
    var saveCalled = false;
    final attachments = [
      VisitAttachmentItem(
        id: 'att-1',
        fileType: VisitAttachmentFileType.pdf,
        label: 'Lab result',
        uploadedBy: 'staff-1',
        sizeBytes: 2048,
        createdAt: DateTime.utc(2026, 5, 31, 10),
        canDownload: true,
      ),
    ];
    await tester.pumpWidget(
      buildWidget(
        attachments: attachments,
        saveDownloadedAttachment: (filename, bytes) async {
          saveCalled = true;
          expect(filename, 'lab-result.pdf');
          expect(bytes, Uint8List.fromList([4, 5, 6]));
          return true;
        },
      ),
    );
    await tester.tap(find.byKey(const Key('visit_attachment_download_att-1')));
    await tester.pump();
    await tester.pumpAndSettle();
    expect(saveCalled, isTrue);
    expect(find.byKey(const Key('visit_attachment_error')), findsNothing);
  });

  testWidgets('download byte fetch failure shows download error not upload', (tester) async {
    final attachments = [
      VisitAttachmentItem(
        id: 'att-1',
        fileType: VisitAttachmentFileType.pdf,
        uploadedBy: 'staff-1',
        sizeBytes: 2048,
        createdAt: DateTime.utc(2026, 5, 31, 10),
        canDownload: true,
      ),
    ];
    await tester.pumpWidget(
      buildWidget(
        attachments: attachments,
        fetchDownloadBytes: (_) async => throw StateError('Could not download the file (404)'),
      ),
    );
    await tester.tap(find.byKey(const Key('visit_attachment_download_att-1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('visit_attachment_error')), findsOneWidget);
    expect(find.textContaining('download'), findsOneWidget);
    expect(find.textContaining('upload'), findsNothing);
  });

  testWidgets('hides download when canDownload is false', (tester) async {
    final attachments = [
      VisitAttachmentItem(
        id: 'att-2',
        fileType: VisitAttachmentFileType.png,
        uploadedBy: 'staff-2',
        sizeBytes: 512,
        createdAt: DateTime.utc(2026, 5, 31, 11),
        canDownload: false,
      ),
    ];
    await tester.pumpWidget(buildWidget(attachments: attachments));
    expect(find.byKey(const Key('visit_attachment_download_att-2')), findsNothing);
  });
}

class _PresetAuth extends AuthSessionNotifier {
  _PresetAuth(this._state);
  final AuthSessionState _state;

  @override
  AuthSessionState build() => _state;
}
