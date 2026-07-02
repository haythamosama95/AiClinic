import 'dart:typed_data';

import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/ui/theme/app_theme.dart';
import 'package:ai_clinic/core/ui/theme/forui_app_scope.dart';
import 'package:ai_clinic/features/auth/domain/permission_keys.dart';
import 'package:ai_clinic/features/visits/data/visit_attachment_service.dart';
import 'package:ai_clinic/features/visits/data/visit_repository.dart';
import 'package:ai_clinic/features/visits/domain/visit_attachment_file_type.dart';
import 'package:ai_clinic/features/visits/domain/visit_attachment_item.dart';
import 'package:ai_clinic/features/visits/domain/visit_encounter_draft.dart';
import 'package:ai_clinic/features/visits/domain/visit_status.dart';
import 'package:ai_clinic/features/visits/presentation/providers/visit_documentation_notifier.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_attachment_list.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_page_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../helpers/auth_test_support.dart';
import '../../support/visit_rpc_test_client.dart';
import 'visit_encounter_test_support.dart';

const _testOrgId = '00000000-0000-4000-8000-000000000020';
const _testStaffId = '00000000-0000-4000-8000-000000000010';
const _persistedAttachmentId = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';

VisitAttachmentPickInput _samplePick({Uint8List? bytes}) {
  return VisitAttachmentPickInput(
    filename: 'lab-result.pdf',
    bytes: bytes ?? Uint8List.fromList([0x25, 0x50, 0x44, 0x46]),
  );
}

class _RecordingStorageBucket extends Fake implements StorageFileApi {
  final List<({String path, Uint8List bytes})> uploads = [];

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

class _SeededVisitDocumentationNotifier extends VisitDocumentationNotifier {
  _SeededVisitDocumentationNotifier(this._state) : super(encounterTestVisitId);

  final VisitDocumentationState _state;

  @override
  Future<VisitDocumentationState> build() async => _state;
}

class _PresetAuthSessionNotifier extends TestAuthSessionNotifier {
  _PresetAuthSessionNotifier(this.initial);

  final AuthSessionState initial;

  @override
  AuthSessionState build() => initial;
}

List<Override> _deferredAttachmentOverrides({
  required _DeferredAttachmentRpcClient client,
  required _RecordingStorageBucket bucket,
  required VisitDocumentationState seedState,
}) {
  return [
    authSessionProvider.overrideWith(
      () => _PresetAuthSessionNotifier(
        AuthSessionState(
          status: AuthSessionStatus.authenticated,
          context: sampleAuthSessionContext(
            branchIds: [encounterTestBranchId],
            activeBranchId: encounterTestBranchId,
            permissions: {PermissionKeys.visitsEditSoap, PermissionKeys.visitsUploadAttachment},
          ),
        ),
      ),
    ),
    visitRepositoryProvider.overrideWith((ref) => VisitRepository(client)),
    visitAttachmentServiceProvider.overrideWith(
      (ref) => VisitAttachmentService(_AttachmentStorageTestClient(bucket), VisitRepository(client)),
    ),
    visitDocumentationProvider(encounterTestVisitId).overrideWith(() => _SeededVisitDocumentationNotifier(seedState)),
  ];
}

/// Tracks attachment RPCs and returns consistent [get_visit] payloads after flush/complete.
class _DeferredAttachmentRpcClient extends VisitRpcTestClient {
  final List<Map<String, dynamic>> persistedAttachments = [];
  var _visitCompleted = false;
  var _nextAttachmentSeq = 0;

  Map<String, dynamic> _visitPayload(String visitId) {
    return {
      'id': visitId,
      'branch_id': encounterTestBranchId,
      'appointment_id': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      'patient_id': encounterTestPatientId,
      'doctor_id': 'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
      'doctor_name': 'Dr Test',
      'visit_date': '2026-05-31',
      'status': _visitCompleted ? 'completed' : 'in_progress',
      'updated_at': '2026-05-31T10:00:00.000Z',
      'documentation': {
        'complaint': null,
        'history': null,
        'examination': null,
        'diagnosis': null,
        'plan': null,
        'updated_at': '2026-05-31T10:00:00.000Z',
      },
      if (persistedAttachments.isNotEmpty) 'attachments': persistedAttachments,
    };
  }

  @override
  PostgrestFilterBuilder<T> rpc<T>(String fn, {Map<String, dynamic>? params, dynamic get = false}) {
    if (fn == 'get_visit') {
      final visitId = params?['p_visit_id']?.toString() ?? encounterTestVisitId;
      rpcResults['get_visit'] = {'success': true, 'data': _visitPayload(visitId)};
    }
    if (fn == 'complete_visit') {
      _visitCompleted = true;
    }
    if (fn == 'register_visit_attachment') {
      _nextAttachmentSeq++;
      final attachmentId = 'aaaaaaaa-aaaa-4aaa-8aaa-${_nextAttachmentSeq.toString().padLeft(12, '0')}';
      persistedAttachments.add({
        'id': attachmentId,
        'file_type': params?['p_file_type'],
        'label': params?['p_label'],
        'uploaded_by': _testStaffId,
        'size_bytes': params?['p_size_bytes'],
        'created_at': '2026-05-31T10:00:00.000Z',
        'can_download': true,
        'can_delete': true,
      });
      rpcResults['register_visit_attachment'] = {
        'success': true,
        'data': {'attachment_id': attachmentId},
      };
    }
    if (fn == 'delete_visit_attachment') {
      final attachmentId = params?['p_attachment_id']?.toString();
      persistedAttachments.removeWhere((item) => item['id'] == attachmentId);
      rpcResults['delete_visit_attachment'] = {
        'success': true,
        'data': {'attachment_id': attachmentId},
      };
    }
    return super.rpc(fn, params: params, get: get);
  }
}

class _DeferredAttachmentHarness extends ConsumerWidget {
  const _DeferredAttachmentHarness({required this.pick, required this.label});

  final VisitAttachmentPickInput pick;
  final String label;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final attachments =
        ref.watch(visitDocumentationProvider(encounterTestVisitId)).value?.effectiveVisit.attachments ??
        const <VisitAttachmentItem>[];

    return VisitAttachmentList(
      visitId: encounterTestVisitId,
      branchId: encounterTestBranchId,
      attachments: attachments,
      canUpload: true,
      deferPersistence: true,
      sectionTitle: 'Attachments',
      sectionKind: VisitPanelKind.attachment,
      pickAttachment: () async => pick,
      promptAttachmentLabel: (_) async => label,
      onChanged: () {},
    );
  }
}

Future<ProviderContainer> _pumpDeferredAttachmentHarness(
  WidgetTester tester, {
  required _DeferredAttachmentRpcClient client,
  required _RecordingStorageBucket bucket,
  required Widget child,
  VisitDocumentationState? seedState,
}) async {
  final container = ProviderContainer(
    overrides: _deferredAttachmentOverrides(
      client: client,
      bucket: bucket,
      seedState: seedState ?? sampleEncounterDocState(),
    ),
  );
  addTearDown(container.dispose);

  await tester.binding.setSurfaceSize(const Size(900, 700));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.light(),
        builder: (context, appChild) => ForuiAppScope(child: appChild ?? const SizedBox.shrink()),
        home: Scaffold(body: SingleChildScrollView(child: child)),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  group('INT-002 — Staged attachment uploads on submit', () {
    late _DeferredAttachmentRpcClient client;
    late _RecordingStorageBucket bucket;

    ProviderContainer createContainer({VisitDocumentationState? seedState}) {
      return ProviderContainer(
        overrides: _deferredAttachmentOverrides(
          client: client,
          bucket: bucket,
          seedState: seedState ?? sampleEncounterDocState(),
        ),
      );
    }

    setUp(() {
      client = _DeferredAttachmentRpcClient();
      bucket = _RecordingStorageBucket();
    });

    test('stageAttachment holds bytes in draft without RPC upload', () async {
      final container = createContainer();
      addTearDown(container.dispose);

      await container.read(visitDocumentationProvider(encounterTestVisitId).future);
      final notifier = container.read(visitDocumentationProvider(encounterTestVisitId).notifier);
      final pick = _samplePick();

      notifier.stageAttachment(
        pick: pick,
        label: 'Lab results',
        uploadedBy: _testStaffId,
        uploadedByName: 'Test Staff',
      );

      final state = container.read(visitDocumentationProvider(encounterTestVisitId)).requireValue;
      expect(state.hasPendingEncounterDraft, isTrue);
      expect(state.encounterDraft.pendingAttachments, hasLength(1));
      expect(state.encounterDraft.pendingAttachments.first.label, 'Lab results');
      expect(state.encounterDraft.pendingAttachments.first.pick.bytes, pick.bytes);
      expect(state.effectiveVisit.attachments, hasLength(1));
      expect(isVisitDraftId(state.effectiveVisit.attachments.first.id), isTrue);
      expect(client.rpcLog, isNot(contains('register_visit_attachment')));
      expect(bucket.uploads, isEmpty);
    });

    test('stageAttachment ignores unsupported file types', () async {
      final container = createContainer();
      addTearDown(container.dispose);

      await container.read(visitDocumentationProvider(encounterTestVisitId).future);
      final notifier = container.read(visitDocumentationProvider(encounterTestVisitId).notifier);

      notifier.stageAttachment(
        pick: VisitAttachmentPickInput(filename: 'notes.txt', bytes: Uint8List.fromList([1, 2, 3])),
        label: 'Notes',
        uploadedBy: _testStaffId,
      );

      final state = container.read(visitDocumentationProvider(encounterTestVisitId)).requireValue;
      expect(state.encounterDraft.pendingAttachments, isEmpty);
      expect(state.hasPendingEncounterDraft, isFalse);
    });

    testWidgets('deferPersistence pick stages attachment in notifier without upload RPC', (tester) async {
      final pick = _samplePick(bytes: Uint8List.fromList([9, 8, 7, 6]));
      final container = await _pumpDeferredAttachmentHarness(
        tester,
        client: client,
        bucket: bucket,
        child: _DeferredAttachmentHarness(pick: pick, label: 'Deferred lab'),
      );

      await container.read(visitDocumentationProvider(encounterTestVisitId).future);
      await tester.tap(find.byKey(const Key('visit_attachment_upload_button')));
      await tester.pumpAndSettle();

      final state = container.read(visitDocumentationProvider(encounterTestVisitId)).requireValue;
      expect(state.encounterDraft.pendingAttachments, hasLength(1));
      expect(state.encounterDraft.pendingAttachments.first.label, 'Deferred lab');
      expect(find.text('Deferred lab'), findsOneWidget);
      expect(client.rpcLog, isNot(contains('register_visit_attachment')));
      expect(bucket.uploads, isEmpty);
    });

    test('pending draft bytes are readable before flush', () async {
      final pick = _samplePick(bytes: Uint8List.fromList([1, 2, 3, 4, 5]));
      final container = createContainer();
      addTearDown(container.dispose);

      await container.read(visitDocumentationProvider(encounterTestVisitId).future);
      final notifier = container.read(visitDocumentationProvider(encounterTestVisitId).notifier);
      notifier.stageAttachment(pick: pick, label: 'Lab results', uploadedBy: _testStaffId);

      final draftId = container
          .read(visitDocumentationProvider(encounterTestVisitId))
          .requireValue
          .encounterDraft
          .pendingAttachments
          .single
          .id;
      final bytes = container
          .read(visitDocumentationProvider(encounterTestVisitId))
          .requireValue
          .encounterDraft
          .pendingAttachmentBytes(draftId);

      expect(bytes, pick.bytes);
    });

    test('stageDeleteAttachment removes pending draft without upload RPC', () async {
      final container = createContainer();
      addTearDown(container.dispose);

      await container.read(visitDocumentationProvider(encounterTestVisitId).future);
      final notifier = container.read(visitDocumentationProvider(encounterTestVisitId).notifier);
      notifier.stageAttachment(pick: _samplePick(), label: 'Lab results', uploadedBy: _testStaffId);

      final draftId = container
          .read(visitDocumentationProvider(encounterTestVisitId))
          .requireValue
          .encounterDraft
          .pendingAttachments
          .single
          .id;
      notifier.stageDeleteAttachment(draftId);

      final state = container.read(visitDocumentationProvider(encounterTestVisitId)).requireValue;
      expect(state.encounterDraft.pendingAttachments, isEmpty);
      expect(state.effectiveVisit.attachments, isEmpty);
      expect(client.rpcLog, isNot(contains('register_visit_attachment')));
      expect(client.rpcLog, isNot(contains('delete_visit_attachment')));
    });

    test('saveAll flushes staged attachment with correct metadata', () async {
      final pick = _samplePick(bytes: Uint8List.fromList([11, 22, 33]));
      final container = createContainer();
      addTearDown(container.dispose);

      await container.read(visitDocumentationProvider(encounterTestVisitId).future);
      final notifier = container.read(visitDocumentationProvider(encounterTestVisitId).notifier);
      notifier.stageAttachment(pick: pick, label: 'Lab results', uploadedBy: _testStaffId);

      final saved = await notifier.saveAll();

      expect(saved, isTrue);
      expect(client.rpcLog, contains('register_visit_attachment'));
      expect(bucket.uploads, hasLength(1));
      expect(bucket.uploads.single.bytes, pick.bytes);
      expect(bucket.uploads.single.path, startsWith('$_testOrgId/$encounterTestBranchId/$encounterTestVisitId/'));

      final params = client.paramsForFunction('register_visit_attachment')!;
      expect(params['p_visit_id'], encounterTestVisitId);
      expect(params['p_label'], 'Lab results');
      expect(params['p_file_type'], VisitAttachmentFileType.pdf.wireValue);
      expect(params['p_size_bytes'], pick.bytes.length);

      final state = container.read(visitDocumentationProvider(encounterTestVisitId)).requireValue;
      expect(state.encounterDraft.pendingAttachments, isEmpty);
      expect(state.hasPendingEncounterDraft, isFalse);
    });

    test('saveAll defers persisted attachment delete until flush', () async {
      client.persistedAttachments.add({
        'id': _persistedAttachmentId,
        'file_type': VisitAttachmentFileType.pdf.wireValue,
        'label': 'Old scan',
        'uploaded_by': _testStaffId,
        'size_bytes': 512,
        'created_at': '2026-05-31T00:00:00.000Z',
        'can_download': true,
        'can_delete': true,
      });
      final visit = sampleEncounterVisit().copyWith(
        attachments: [
          VisitAttachmentItem(
            id: _persistedAttachmentId,
            fileType: VisitAttachmentFileType.pdf,
            label: 'Old scan',
            uploadedBy: _testStaffId,
            sizeBytes: 512,
            createdAt: DateTime.utc(2026, 5, 31),
            canDownload: true,
            canDelete: true,
          ),
        ],
      );
      final container = createContainer(seedState: sampleEncounterDocState(visit: visit));
      addTearDown(container.dispose);

      await container.read(visitDocumentationProvider(encounterTestVisitId).future);
      final notifier = container.read(visitDocumentationProvider(encounterTestVisitId).notifier);
      notifier.stageDeleteAttachment(_persistedAttachmentId);

      expect(client.rpcLog, isNot(contains('delete_visit_attachment')));

      final saved = await notifier.saveAll();
      expect(saved, isTrue);
      expect(client.rpcLog, contains('delete_visit_attachment'));
      expect(client.paramsForFunction('delete_visit_attachment')?['p_attachment_id'], _persistedAttachmentId);
    });

    test('completeVisit uploads staged attachment before completing visit', () async {
      final pick = _samplePick(bytes: Uint8List.fromList([5, 4, 3, 2, 1]));
      final container = createContainer();
      addTearDown(container.dispose);

      await container.read(visitDocumentationProvider(encounterTestVisitId).future);
      final notifier = container.read(visitDocumentationProvider(encounterTestVisitId).notifier);
      notifier.stageAttachment(pick: pick, label: 'Submit lab', uploadedBy: _testStaffId);

      await notifier.completeVisit();

      final registerIndex = client.rpcLog.indexOf('register_visit_attachment');
      final completeIndex = client.rpcLog.indexOf('complete_visit');
      expect(registerIndex, greaterThanOrEqualTo(0));
      expect(completeIndex, greaterThan(registerIndex));
      expect(bucket.uploads.single.bytes, pick.bytes);
      expect(client.paramsForFunction('register_visit_attachment')?['p_label'], 'Submit lab');

      final state = container.read(visitDocumentationProvider(encounterTestVisitId)).requireValue;
      expect(state.encounterDraft.pendingAttachments, isEmpty);
      expect(state.visit.status, VisitStatus.completed);
      expect(state.workspaceEditMode, WorkspaceEditMode.viewing);
    });
  });
}
