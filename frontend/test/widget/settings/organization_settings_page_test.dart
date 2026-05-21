import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/settings/data/organization_repository.dart';
import 'package:ai_clinic/features/settings/domain/organization_profile.dart';
import 'package:ai_clinic/features/settings/presentation/pages/organization_settings_page.dart';
import 'package:ai_clinic/features/settings/presentation/providers/organization_settings_notifier.dart';
import 'package:ai_clinic/shared/providers/auth_session_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:ai_clinic/testing/auth_test_support.dart';
import '../../support/settings_rpc_test_client.dart';

void main() {
  group('OrganizationSettingsPage', () {
    testWidgets('owner sees loaded organization fields', (tester) async {
      await tester.pumpWidget(_host(role: StaffRole.owner));
      await tester.pumpAndSettle();

      expect(find.text('Organization name'), findsOneWidget);
      expect(find.text('Test Clinic'), findsOneWidget);
      expect(find.text('Currency code'), findsOneWidget);
      expect(find.text('USD'), findsOneWidget);
      expect(find.text('Modify'), findsNWidgets(4));
      expect(find.byType(TextFormField), findsNothing);
      expect(find.text('Save organization settings'), findsOneWidget);
    });

    testWidgets('doctor sees permission denied message', (tester) async {
      await tester.pumpWidget(_host(role: StaffRole.doctor, permissionDenied: true));
      await tester.pumpAndSettle();

      expect(find.textContaining('owners and administrators'), findsOneWidget);
      expect(find.text('Save organization settings'), findsNothing);
    });

    testWidgets('stupid usage: saving whitespace-only name shows validation', (tester) async {
      await tester.pumpWidget(_host(role: StaffRole.owner));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Modify').first);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), '   ');
      await tester.tap(find.text('Save organization settings'));
      await tester.pumpAndSettle();

      expect(find.text('Organization name is required.'), findsOneWidget);
    });

    testWidgets('successful save shows confirmation snackbar', (tester) async {
      final client = SettingsRpcTestClient();
      await tester.pumpWidget(_host(role: StaffRole.owner, rpcClient: client));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Modify').first);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), 'Renamed Clinic');
      await tester.tap(find.text('Save organization settings'));
      await tester.pumpAndSettle();

      expect(find.text('Organization settings saved.'), findsOneWidget);
      expect(client.lastFunction, 'update_organization');
      expect(client.lastParams, containsPair('p_name', 'Renamed Clinic'));
    });

    testWidgets('advanced: RPC FORBIDDEN shows user-facing error', (tester) async {
      final client = SettingsRpcTestClient(
        rpcResults: {
          'update_organization': {'success': false, 'error_code': 'FORBIDDEN', 'error_message': 'Denied'},
        },
      );
      await tester.pumpWidget(_host(role: StaffRole.owner, rpcClient: client));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Save organization settings'));
      await tester.pumpAndSettle();

      expect(find.textContaining('do not have permission'), findsOneWidget);
    });

    testWidgets('corner case: subscription tier displayed read-only', (tester) async {
      await tester.pumpWidget(_host(role: StaffRole.administrator));
      await tester.pumpAndSettle();

      expect(find.text('Tier: pro'), findsOneWidget);
      expect(find.text('Subscription'), findsOneWidget);
    });

    testWidgets('unset logo, currency, and timezone show placeholder until Modify', (tester) async {
      await tester.pumpWidget(_host(role: StaffRole.owner, currencyCode: null, timezone: null));
      await tester.pumpAndSettle();

      expect(find.text('This value has not been set before.'), findsNWidgets(3));
      expect(find.text('USD'), findsNothing);
      expect(find.byKey(const ValueKey('org_settings_currency')), findsNothing);

      await tester.tap(find.text('Modify').at(2));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('org_settings_currency')), findsOneWidget);
    });

    testWidgets('Modify currency opens searchable dropdown and saves selection', (tester) async {
      final client = SettingsRpcTestClient();
      await tester.binding.setSurfaceSize(const Size(800, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(_host(role: StaffRole.owner, currencyCode: null, rpcClient: client));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Modify').at(2));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('org_settings_currency')));
      await tester.pump();
      await tester.enterText(find.byKey(const ValueKey('org_settings_currency')), 'EG');
      await tester.pump();
      await tester.pump();
      await tester.tap(find.widgetWithText(ListTile, 'EGP'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Save organization settings'));
      await tester.pumpAndSettle();

      expect(client.lastParams, containsPair('p_currency_code', 'EGP'));
    });

    testWidgets('Modify organization name opens editor', (tester) async {
      await tester.pumpWidget(_host(role: StaffRole.owner));
      await tester.pumpAndSettle();

      expect(find.byType(TextFormField), findsNothing);

      await tester.tap(find.text('Modify').first);
      await tester.pumpAndSettle();

      expect(find.byType(TextFormField), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'Test Clinic'), findsOneWidget);
    });

    testWidgets('unset logo URL shows placeholder until Modify', (tester) async {
      await tester.pumpWidget(_host(role: StaffRole.owner));
      await tester.pumpAndSettle();

      expect(find.text('Logo URL'), findsOneWidget);
      expect(find.text('This value has not been set before.'), findsOneWidget);

      await tester.tap(find.text('Modify').at(1));
      await tester.pumpAndSettle();

      expect(find.byType(TextFormField), findsOneWidget);
    });
  });
}

Widget _host({
  required StaffRole role,
  bool permissionDenied = false,
  SettingsRpcTestClient? rpcClient,
  String? currencyCode = 'USD',
  String? timezone = 'UTC',
}) {
  final fetchClient = OrganizationFetchTestClient({
    'id': '00000000-0000-4000-8000-000000000020',
    'name': 'Test Clinic',
    'currency_code': ?currencyCode,
    'timezone': ?timezone,
    'settings_json': {},
    'subscription_tier': 'pro',
  });

  final readWriteRepo = _ReadWriteOrganizationRepository(
    fetchClient: fetchClient,
    rpcClient: rpcClient ?? SettingsRpcTestClient(),
  );

  return ProviderScope(
    overrides: [
      authSessionProvider.overrideWith(
        () => _PresetAuthSessionNotifier(
          AuthSessionState(
            status: AuthSessionStatus.authenticated,
            context: sampleAuthSessionContext(
              role: role,
              permissions: role == StaffRole.owner || role == StaffRole.administrator
                  ? {'settings.manage_branches'}
                  : {'patients.view'},
            ),
          ),
        ),
      ),
      if (permissionDenied)
        organizationSettingsProvider.overrideWith(() => _DeniedOrganizationNotifier())
      else
        organizationRepositoryProvider.overrideWithValue(readWriteRepo),
    ],
    child: const MaterialApp(home: OrganizationSettingsPage()),
  );
}

class _PresetAuthSessionNotifier extends TestAuthSessionNotifier {
  _PresetAuthSessionNotifier(this.initial);

  final AuthSessionState initial;

  @override
  AuthSessionState build() => initial;
}

class _DeniedOrganizationNotifier extends OrganizationSettingsNotifier {
  @override
  Future<OrganizationSettingsUiState> build() async {
    return const OrganizationSettingsUiState(permissionDenied: true);
  }
}

class _ReadWriteOrganizationRepository extends OrganizationRepository {
  _ReadWriteOrganizationRepository({required SupabaseClient fetchClient, required SupabaseClient rpcClient})
    : _fetchClient = fetchClient,
      super(rpcClient);

  final SupabaseClient _fetchClient;

  @override
  Future<OrganizationProfile?> fetchProfile({required String organizationId}) {
    return OrganizationRepository(_fetchClient).fetchProfile(organizationId: organizationId);
  }
}
