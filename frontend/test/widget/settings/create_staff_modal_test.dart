import 'package:ai_clinic/core/ui/theme/app_theme.dart';
import 'package:ai_clinic/core/ui/theme/forui_app_scope.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/setup/data/provisioning_repository.dart';
import 'package:ai_clinic/features/setup/domain/branch_summary.dart';
import 'package:ai_clinic/features/setup/presentation/providers/staff_assignable_branches_provider.dart';
import 'package:ai_clinic/features/settings/presentation/widgets/create_staff_modal.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../helpers/auth_test_support.dart';
import '../../support/fake_postgrest_rpc.dart';

void main() {
  Future<void> selectMainClinicBranch(WidgetTester tester) async {
    await tester.tap(find.text('Select branches'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Main Clinic'));
    await tester.pumpAndSettle();
  }

  group('CreateStaffModal', () {
    Future<void> pumpModal(WidgetTester tester, {RpcCaptureSupabaseClient? rpcClient}) async {
      final client = rpcClient ?? RpcCaptureSupabaseClient();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authSessionProvider.overrideWith(
              () => _PresetAuthSessionNotifier(
                AuthSessionState(
                  status: AuthSessionStatus.authenticated,
                  context: sampleAuthSessionContext(
                    role: StaffRole.administrator,
                    permissions: {'settings.manage_staff'},
                  ),
                ),
              ),
            ),
            provisioningRepositoryProvider.overrideWithValue(ProvisioningRepositoryImpl(client)),
            staffAssignableBranchesProvider.overrideWith(
              (ref) async => const [BranchSummary(id: '00000000-0000-4000-8000-000000000201', name: 'Main Clinic')],
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            builder: (context, child) => ForuiAppScope(child: child ?? const SizedBox.shrink()),
            home: const Scaffold(body: CreateStaffModal()),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('shows staff create form fields', (tester) async {
      await pumpModal(tester);

      expect(find.text('New staff member'), findsOneWidget);
      expect(find.text('Create staff account'), findsOneWidget);
      expect(find.widgetWithText(AppTextField, 'Username *'), findsOneWidget);
      expect(find.widgetWithText(AppTextField, 'Full name *'), findsOneWidget);
      expect(find.widgetWithText(AppTextField, 'Initial password *'), findsOneWidget);
      expect(find.widgetWithText(AppTextField, 'Phone number *'), findsOneWidget);
    });

    testWidgets('create without branch selection shows snackbar', (tester) async {
      await pumpModal(tester);

      await tester.enterText(find.widgetWithText(AppTextField, 'Full name *'), 'New Receptionist');
      await tester.enterText(find.widgetWithText(AppTextField, 'Phone number *'), '201000000000');
      await tester.enterText(find.widgetWithText(AppTextField, 'Username *'), 'newrecep');
      await tester.enterText(find.widgetWithText(AppTextField, 'Initial password *'), 'Secret12');

      await tester.tap(find.widgetWithText(AppButton, 'Create staff account'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Select at least one branch'), findsOneWidget);
    });

    testWidgets('close button dismisses modal', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authSessionProvider.overrideWith(
              () => _PresetAuthSessionNotifier(
                AuthSessionState(
                  status: AuthSessionStatus.authenticated,
                  context: sampleAuthSessionContext(
                    role: StaffRole.administrator,
                    permissions: {'settings.manage_staff'},
                  ),
                ),
              ),
            ),
            provisioningRepositoryProvider.overrideWithValue(ProvisioningRepositoryImpl(RpcCaptureSupabaseClient())),
            staffAssignableBranchesProvider.overrideWith(
              (ref) async => const [BranchSummary(id: '00000000-0000-4000-8000-000000000201', name: 'Main Clinic')],
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            builder: (context, child) => ForuiAppScope(child: child ?? const SizedBox.shrink()),
            home: Builder(
              builder: (context) {
                return Scaffold(
                  body: Center(
                    child: AppButton(label: 'Open', onPressed: () => CreateStaffModal.show(context)),
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('New staff member'), findsOneWidget);

      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();

      expect(find.text('New staff member'), findsNothing);
    });

    testWidgets('successful create closes modal and shows credentials dialog', (tester) async {
      final rpcClient = RpcCaptureSupabaseClient();
      await pumpModal(tester, rpcClient: rpcClient);

      await selectMainClinicBranch(tester);

      await tester.tap(find.text('Select a role'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Receptionist').last);
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(AppTextField, 'Full name *'), 'New Receptionist');
      await tester.enterText(find.widgetWithText(AppTextField, 'Phone number *'), '201000000000');
      await tester.enterText(find.widgetWithText(AppTextField, 'Username *'), 'newrecep');
      await tester.enterText(find.widgetWithText(AppTextField, 'Initial password *'), 'Secret12');

      await tester.tap(find.widgetWithText(AppButton, 'Create staff account'));
      await tester.pumpAndSettle();

      expect(rpcClient.lastFunction, 'create_staff_account');
      expect(find.text('Staff account created'), findsOneWidget);
      expect(find.textContaining('Username: newrecep'), findsOneWidget);
      expect(find.textContaining('Password: Secret12'), findsOneWidget);

      await tester.tap(find.widgetWithText(AppButton, 'Done'));
      await tester.pumpAndSettle();

      expect(find.text('New staff member'), findsNothing);
    });

    testWidgets('dismiss scrim cancels without create', (tester) async {
      final rpcClient = RpcCaptureSupabaseClient();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authSessionProvider.overrideWith(
              () => _PresetAuthSessionNotifier(
                AuthSessionState(
                  status: AuthSessionStatus.authenticated,
                  context: sampleAuthSessionContext(
                    role: StaffRole.administrator,
                    permissions: {'settings.manage_staff'},
                  ),
                ),
              ),
            ),
            provisioningRepositoryProvider.overrideWithValue(ProvisioningRepositoryImpl(rpcClient)),
            staffAssignableBranchesProvider.overrideWith(
              (ref) async => const [BranchSummary(id: '00000000-0000-4000-8000-000000000201', name: 'Main Clinic')],
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            builder: (context, child) => ForuiAppScope(child: child ?? const SizedBox.shrink()),
            home: Builder(
              builder: (context) {
                return Scaffold(
                  body: Center(
                    child: AppButton(label: 'Open', onPressed: () => CreateStaffModal.show(context)),
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      expect(find.text('New staff member'), findsNothing);
      expect(rpcClient.lastFunction, isNull);
    });

    testWidgets('provisioning error shown inline', (tester) async {
      final rpcClient = _ErrorProvisioningClient();
      await pumpModal(tester, rpcClient: rpcClient);

      await selectMainClinicBranch(tester);
      await tester.tap(find.text('Select a role'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Receptionist').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(AppTextField, 'Full name *'), 'Dup User');
      await tester.enterText(find.widgetWithText(AppTextField, 'Phone number *'), '201000000000');
      await tester.enterText(find.widgetWithText(AppTextField, 'Username *'), 'dupuser');
      await tester.enterText(find.widgetWithText(AppTextField, 'Initial password *'), 'Secret12');
      await tester.tap(find.widgetWithText(AppButton, 'Create staff account'));
      await tester.pumpAndSettle();

      expect(find.textContaining('already exists'), findsOneWidget);
    });

    testWidgets('create staff modal clears provisioning error on open', (tester) async {
      final rpcClient = _ErrorProvisioningClient();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authSessionProvider.overrideWith(
              () => _PresetAuthSessionNotifier(
                AuthSessionState(
                  status: AuthSessionStatus.authenticated,
                  context: sampleAuthSessionContext(
                    role: StaffRole.administrator,
                    permissions: {'settings.manage_staff'},
                  ),
                ),
              ),
            ),
            provisioningRepositoryProvider.overrideWithValue(ProvisioningRepositoryImpl(rpcClient)),
            staffAssignableBranchesProvider.overrideWith(
              (ref) async => const [BranchSummary(id: '00000000-0000-4000-8000-000000000201', name: 'Main Clinic')],
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            builder: (context, child) => ForuiAppScope(child: child ?? const SizedBox.shrink()),
            home: Builder(
              builder: (context) {
                return Scaffold(
                  body: Center(
                    child: AppButton(label: 'Open', onPressed: () => CreateStaffModal.show(context)),
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await selectMainClinicBranch(tester);
      await tester.tap(find.text('Select a role'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Receptionist').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(AppTextField, 'Username *'), 'dupuser');
      await tester.enterText(find.widgetWithText(AppTextField, 'Full name *'), 'Dup');
      await tester.enterText(find.widgetWithText(AppTextField, 'Phone number *'), '201000000000');
      await tester.enterText(find.widgetWithText(AppTextField, 'Initial password *'), 'Secret12');
      await tester.tap(find.widgetWithText(AppButton, 'Create staff account'));
      await tester.pumpAndSettle();
      expect(find.byType(AppAlert), findsOneWidget);

      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.byType(AppAlert), findsNothing);
    });

    testWidgets('doctor without manage_staff cannot create staff', (tester) async {
      final rpcClient = RpcCaptureSupabaseClient();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authSessionProvider.overrideWith(
              () => _PresetAuthSessionNotifier(
                AuthSessionState(
                  status: AuthSessionStatus.authenticated,
                  context: sampleAuthSessionContext(role: StaffRole.doctor, permissions: {'patients.view'}),
                ),
              ),
            ),
            provisioningRepositoryProvider.overrideWithValue(ProvisioningRepositoryImpl(rpcClient)),
            staffAssignableBranchesProvider.overrideWith(
              (ref) async => const [BranchSummary(id: '00000000-0000-4000-8000-000000000201', name: 'Main Clinic')],
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            builder: (context, child) => ForuiAppScope(child: child ?? const SizedBox.shrink()),
            home: const Scaffold(body: CreateStaffModal()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await selectMainClinicBranch(tester);
      await tester.enterText(find.widgetWithText(AppTextField, 'Full name *'), 'Blocked');
      await tester.enterText(find.widgetWithText(AppTextField, 'Phone number *'), '201000000000');
      await tester.enterText(find.widgetWithText(AppTextField, 'Username *'), 'blocked');
      await tester.enterText(find.widgetWithText(AppTextField, 'Initial password *'), 'Secret12');
      final createButton = find.widgetWithText(AppButton, 'Create staff account');
      await tester.ensureVisible(createButton);
      await tester.tap(createButton);
      await tester.pumpAndSettle();

      expect(rpcClient.lastFunction, isNull);
    });
  });
}

class _ErrorProvisioningClient extends RpcCaptureSupabaseClient {
  @override
  PostgrestFilterBuilder<T> rpc<T>(String fn, {Map<String, dynamic>? params, dynamic get = false}) {
    if (fn == 'create_staff_account') {
      return FakePostgrestRpc({
            'success': false,
            'error_code': 'USERNAME_EXISTS',
            'error_message': 'That username is already taken.',
          })
          as PostgrestFilterBuilder<T>;
    }
    return super.rpc<T>(fn, params: params, get: get);
  }
}

class _PresetAuthSessionNotifier extends TestAuthSessionNotifier {
  _PresetAuthSessionNotifier(this.initial);

  final AuthSessionState initial;

  @override
  AuthSessionState build() => initial;
}
