import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/auth/domain/permission_keys.dart';
import 'package:ai_clinic/features/billing/data/insurance_provider_repository.dart';
import 'package:ai_clinic/features/billing/presentation/pages/insurance_providers_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/auth_test_support.dart';
import '../../support/billing_rpc_test_client.dart';

void main() {
  group('InsuranceProvidersPage', () {
    testWidgets('owner can create and deactivate providers', (tester) async {
      final client = BillingRpcTestClient();
      client.insuranceProviders.clear();

      await tester.pumpWidget(_host(role: StaffRole.owner, client: client));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('insurance_providers_empty')), findsOneWidget);

      await tester.tap(find.byKey(const Key('insurance_provider_add_fab')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('insurance_provider_name_field')), 'Global Health');
      await tester.enterText(find.byKey(const Key('insurance_provider_contact_field')), 'support@global.test');
      await tester.tap(find.byKey(const Key('insurance_provider_save_button')));
      await tester.pumpAndSettle();

      expect(client.rpcLog.where((name) => name == 'insurance_provider_upsert').length, 1);
      expect(find.text('Global Health'), findsOneWidget);

      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Deactivate'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('insurance_provider_deactivate_confirm')));
      await tester.pumpAndSettle();

      expect(client.rpcLog.where((name) => name == 'insurance_provider_deactivate').length, 1);
      expect(find.textContaining('Inactive'), findsOneWidget);
    });

    testWidgets('receptionist sees access denied view', (tester) async {
      await tester.pumpWidget(_host(role: StaffRole.receptionist));
      await tester.pumpAndSettle();

      expect(find.text('You do not have permission to manage insurance providers.'), findsOneWidget);
      expect(find.byKey(const Key('insurance_provider_add_fab')), findsNothing);
    });
  });
}

Widget _host({required StaffRole role, BillingRpcTestClient? client}) {
  final rpcClient = client ?? BillingRpcTestClient();

  return ProviderScope(
    overrides: [
      authSessionProvider.overrideWith(
        () => _PresetAuth(
          AuthSessionState(
            status: AuthSessionStatus.authenticated,
            context: sampleAuthSessionContext(role: role, permissions: RolePermissionSeed.forRole(role)),
          ),
        ),
      ),
      insuranceProviderRepositoryProvider.overrideWith((ref) => InsuranceProviderRepository(rpcClient)),
    ],
    child: const MaterialApp(home: InsuranceProvidersPage()),
  );
}

class _PresetAuth extends TestAuthSessionNotifier {
  _PresetAuth(this.initial);

  final AuthSessionState initial;

  @override
  AuthSessionState build() => initial;
}
