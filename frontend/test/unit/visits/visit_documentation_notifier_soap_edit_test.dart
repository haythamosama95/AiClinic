import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/auth/domain/permission_keys.dart';
import 'package:ai_clinic/features/visits/data/visit_repository.dart';
import 'package:ai_clinic/features/visits/presentation/providers/visit_documentation_notifier.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/auth_test_support.dart';
import '../../support/visit_rpc_test_client.dart';

void main() {
  const visitId = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee';
  const branchId = '44444444-4444-4444-8444-444444444444';

  late VisitRpcTestClient client;
  late ProviderContainer container;

  setUp(() {
    client = VisitRpcTestClient(
      rpcResults: {
        'get_specialty_form_schema': {
          'success': true,
          'data': {
            'schema_json': {'type': 'object', 'properties': {}},
          },
        },
      },
    );
    final authState = AuthSessionState(
      status: AuthSessionStatus.authenticated,
      context: sampleAuthSessionContext(
        permissions: {PermissionKeys.visitsEditSoap},
        activeBranchId: branchId,
        branchIds: [branchId],
      ),
    );

    container = ProviderContainer(
      overrides: [
        authSessionProvider.overrideWith(() => _PresetAuth(authState)),
        visitRepositoryProvider.overrideWithValue(VisitRepository(client)),
      ],
    );
  });

  tearDown(() {
    container.dispose();
  });

  group('enterSoapEditMode', () {
    test('switches from read-only back to editing after save', () async {
      final notifier = container.read(visitDocumentationProvider(visitId).notifier);
      await container.read(visitDocumentationProvider(visitId).future);

      notifier.updateSubjective('Saved note');
      await notifier.save();

      var state = container.read(visitDocumentationProvider(visitId)).value!;
      expect(state.soapEditMode, SoapEditMode.readOnly);

      notifier.enterSoapEditMode();
      state = container.read(visitDocumentationProvider(visitId)).value!;
      expect(state.soapEditMode, SoapEditMode.editing);
    });

    test('no-op when user cannot edit', () async {
      container.dispose();
      final authState = AuthSessionState(
        status: AuthSessionStatus.authenticated,
        context: sampleAuthSessionContext(
          permissions: {PermissionKeys.visitsCreate},
          activeBranchId: branchId,
          branchIds: [branchId],
        ),
      );
      container = ProviderContainer(
        overrides: [
          authSessionProvider.overrideWith(() => _PresetAuth(authState)),
          visitRepositoryProvider.overrideWithValue(VisitRepository(client)),
        ],
      );

      final notifier = container.read(visitDocumentationProvider(visitId).notifier);
      await container.read(visitDocumentationProvider(visitId).future);

      final before = container.read(visitDocumentationProvider(visitId)).value!;
      notifier.enterSoapEditMode();
      final after = container.read(visitDocumentationProvider(visitId)).value!;

      expect(after.soapEditMode, before.soapEditMode);
      expect(after.canEdit, isFalse);
    });
  });
}

class _PresetAuth extends AuthSessionNotifier {
  _PresetAuth(this._state);
  final AuthSessionState _state;

  @override
  AuthSessionState build() => _state;
}
