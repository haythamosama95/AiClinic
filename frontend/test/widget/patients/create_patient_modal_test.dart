import 'package:ai_clinic/core/ui/theme/app_theme.dart';
import 'package:ai_clinic/core/ui/theme/forui_app_scope.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/patients/data/patient_repository.dart';
import 'package:ai_clinic/features/patients/domain/patient_gender.dart';
import 'package:ai_clinic/features/patients/presentation/widgets/create_patient_modal.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../helpers/auth_test_support.dart';
import '../../support/fake_postgrest_rpc.dart';
import '../../support/patient_rpc_test_client.dart';

Future<void> _pumpModal(WidgetTester tester, Widget widget) async {
  await tester.binding.setSurfaceSize(const Size(900, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(widget);
  await tester.pumpAndSettle();

  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

Future<void> _tapRegister(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(const Key('patient_register_submit')));
  await tester.tap(find.byKey(const Key('patient_register_submit')));
  await tester.pumpAndSettle();
}

Future<void> _selectGender(WidgetTester tester, String label) async {
  await tester.tap(find.widgetWithText(AppSelect<PatientGender>, 'Gender *'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

void main() {
  group('CreatePatientModal', () {
    testWidgets('shows form fields and register button over blurred backdrop', (tester) async {
      await _pumpModal(tester, _host());

      expect(find.text('Register patient'), findsWidgets);
      expect(find.text('Full name *'), findsOneWidget);
      expect(find.text('Mobile number *'), findsOneWidget);
      expect(find.text('Gender *'), findsOneWidget);
      expect(find.text('Marital status'), findsOneWidget);
      expect(find.byType(BackdropFilter), findsOneWidget);
    });

    testWidgets('empty name blocked on submit', (tester) async {
      await _pumpModal(tester, _host());

      await _tapRegister(tester);

      expect(find.text('Full name is required.'), findsOneWidget);
    });

    testWidgets('empty mobile blocked on submit', (tester) async {
      await _pumpModal(tester, _host());

      await tester.enterText(find.widgetWithText(AppTextField, 'Full name *'), 'New Patient');
      await _tapRegister(tester);

      expect(find.text('Mobile number is required.'), findsOneWidget);
    });

    testWidgets('empty gender blocked on submit', (tester) async {
      await _pumpModal(tester, _host());

      await tester.enterText(find.widgetWithText(AppTextField, 'Full name *'), 'New Patient');
      await tester.enterText(find.widgetWithText(AppTextField, 'Mobile number *'), '201005551234');
      await _tapRegister(tester);

      expect(find.text('Gender is required.'), findsOneWidget);
    });

    testWidgets('successful register closes modal with patient id', (tester) async {
      String? createdPatientId;

      await tester.binding.setSurfaceSize(const Size(900, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_host(onCreated: (id) => createdPatientId = id));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(AppTextField, 'Full name *'), 'New Patient');
      await tester.enterText(find.widgetWithText(AppTextField, 'Mobile number *'), '201005551234');
      await _selectGender(tester, 'Male');
      await _tapRegister(tester);

      expect(createdPatientId, '33333333-3333-4333-8333-333333333333');
      expect(find.text('Patient registered successfully.'), findsOneWidget);
      expect(find.text('Register patient'), findsNothing);
    });

    testWidgets('DUPLICATE_WARNING shows dialog then retries with acknowledge', (tester) async {
      final client = _DuplicateThenSuccessClient();

      await _pumpModal(tester, _host(rpcClient: client));

      await tester.enterText(find.widgetWithText(AppTextField, 'Full name *'), 'Dup Patient');
      await tester.enterText(find.widgetWithText(AppTextField, 'Mobile number *'), '201000000001');
      await _selectGender(tester, 'Male');
      await _tapRegister(tester);

      expect(find.text('Similar patients found'), findsOneWidget);
      expect(find.text('Existing'), findsOneWidget);

      await tester.tap(find.text('Continue anyway'));
      await tester.pumpAndSettle();

      expect(client.createCallCount, 2);
      expect(client.lastParams?['p_acknowledge_duplicate'], true);
    });

    testWidgets('permission denied without patients.create', (tester) async {
      await _pumpModal(tester, _host(permissions: const {'patients.view'}));

      expect(find.text('You do not have permission to register patients.'), findsOneWidget);
      expect(find.byKey(const Key('patient_register_submit')), findsNothing);
    });

    testWidgets('close dismisses modal', (tester) async {
      await _pumpModal(tester, _host());

      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();

      expect(find.text('Register patient'), findsNothing);
      expect(find.text('Open'), findsOneWidget);
    });

    testWidgets('duplicate dialog Go back does not call RPC again', (tester) async {
      final client = _DuplicateThenSuccessClient();

      await _pumpModal(tester, _host(rpcClient: client));

      await tester.enterText(find.widgetWithText(AppTextField, 'Full name *'), 'Dup Patient');
      await tester.enterText(find.widgetWithText(AppTextField, 'Mobile number *'), '201000000001');
      await _selectGender(tester, 'Male');
      await _tapRegister(tester);

      await tester.tap(find.text('Go back'));
      await tester.pumpAndSettle();

      expect(client.createCallCount, 1);
    });
  });
}

class _DuplicateThenSuccessClient extends PatientRpcTestClient {
  int createCallCount = 0;

  @override
  PostgrestFilterBuilder<T> rpc<T>(String fn, {Map<String, dynamic>? params, dynamic get = false}) {
    if (fn == 'create_patient') {
      createCallCount++;
      if (createCallCount == 1) {
        lastFunction = fn;
        lastParams = params == null ? null : Map<String, dynamic>.from(params);
        return FakePostgrestRpc({
              'success': false,
              'error_code': 'DUPLICATE_WARNING',
              'error_message': 'Similar patients found',
              'data': {
                'candidates': [
                  {'id': '22222222-2222-4222-8222-222222222222', 'full_name': 'Existing', 'branch_name': 'Main'},
                ],
              },
            })
            as PostgrestFilterBuilder<T>;
      }
    }
    return super.rpc(fn, params: params, get: get);
  }
}

Widget _host({
  PatientRpcTestClient? rpcClient,
  Set<String> permissions = const {'patients.view', 'patients.create'},
  void Function(String patientId)? onCreated,
}) {
  final client = rpcClient ?? PatientRpcTestClient();

  return ProviderScope(
    overrides: [
      authSessionProvider.overrideWith(
        () => _PresetAuthSessionNotifier(
          AuthSessionState(
            status: AuthSessionStatus.authenticated,
            context: sampleAuthSessionContext(permissions: permissions),
          ),
        ),
      ),
      patientRepositoryProvider.overrideWith((ref) => PatientRepositoryImpl(client)),
    ],
    child: MaterialApp(
      theme: AppTheme.light(),
      builder: (context, child) => ForuiAppScope(child: child ?? const SizedBox.shrink()),
      home: Builder(
        builder: (context) {
          return Scaffold(
            body: Center(
              child: AppButton(
                label: 'Open',
                onPressed: () async {
                  final patientId = await CreatePatientModal.show(context);
                  if (patientId != null) {
                    onCreated?.call(patientId);
                  }
                },
              ),
            ),
          );
        },
      ),
    ),
  );
}

class _PresetAuthSessionNotifier extends TestAuthSessionNotifier {
  _PresetAuthSessionNotifier(this.initial);

  final AuthSessionState initial;

  @override
  AuthSessionState build() => initial;
}
