import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/auth/domain/permission_keys.dart';
import 'package:ai_clinic/features/billing/data/billing_settings_repository.dart';
import 'package:ai_clinic/features/settings/presentation/widgets/billing_settings_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/auth_test_support.dart';
import '../../support/billing_rpc_test_client.dart';

void main() {
  group('BillingSettingsSection', () {
    testWidgets('owner sees an editable partial-payments toggle', (tester) async {
      final client = BillingRpcTestClient();
      await tester.pumpWidget(_host(role: StaffRole.owner, client: client));
      await tester.pumpAndSettle();

      expect(find.text('Billing'), findsOneWidget);
      final toggle = tester.widget<SwitchListTile>(find.byType(SwitchListTile));
      expect(toggle.onChanged, isNotNull);

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();

      expect(client.rpcLog.where((name) => name == 'update_billing_settings').length, 1);
      expect(client.allowPartialPayments, isTrue);
    });

    testWidgets('admin sees an editable partial-payments toggle', (tester) async {
      final client = BillingRpcTestClient();
      await tester.pumpWidget(_host(role: StaffRole.administrator, client: client));
      await tester.pumpAndSettle();

      expect(find.text('Billing'), findsOneWidget);
      expect(find.text('Allow partial payments'), findsOneWidget);
      expect(find.byKey(const Key('billing_allow_partial_payments_toggle')), findsOneWidget);

      final toggle = tester.widget<SwitchListTile>(find.byType(SwitchListTile));
      expect(toggle.onChanged, isNotNull);
      expect(toggle.value, isFalse);

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();

      expect(client.rpcLog.where((name) => name == 'update_billing_settings').length, 1);
      expect(client.allowPartialPayments, isTrue);
      expect(find.text('Billing settings saved.'), findsOneWidget);
    });

    testWidgets('receptionist sees read-only toggle', (tester) async {
      await tester.pumpWidget(_host(role: StaffRole.receptionist));
      await tester.pumpAndSettle();

      expect(find.text('Allow partial payments'), findsOneWidget);
      final toggle = tester.widget<SwitchListTile>(find.byType(SwitchListTile));
      expect(toggle.onChanged, isNull);
      expect(find.textContaining('owners and administrators'), findsOneWidget);
    });

    testWidgets('doctor does not see billing section', (tester) async {
      await tester.pumpWidget(_host(role: StaffRole.doctor));
      await tester.pumpAndSettle();

      expect(find.text('Billing'), findsNothing);
      expect(find.text('Allow partial payments'), findsNothing);
    });

    testWidgets('lab staff does not see billing section', (tester) async {
      await tester.pumpWidget(_host(role: StaffRole.labStaff));
      await tester.pumpAndSettle();

      expect(find.text('Billing'), findsNothing);
      expect(find.text('Allow partial payments'), findsNothing);
    });
  });
}

Widget _host({required StaffRole role, BillingRpcTestClient? client}) {
  final rpcClient = client ?? BillingRpcTestClient();

  return ProviderScope(
    overrides: [
      authSessionProvider.overrideWith(
        () => _PresetAuthSessionNotifier(
          AuthSessionState(
            status: AuthSessionStatus.authenticated,
            context: sampleAuthSessionContext(role: role, permissions: RolePermissionSeed.forRole(role)),
          ),
        ),
      ),
      billingSettingsRepositoryProvider.overrideWith((ref) => BillingSettingsRepository(rpcClient)),
    ],
    child: const MaterialApp(home: Scaffold(body: BillingSettingsSection())),
  );
}

class _PresetAuthSessionNotifier extends TestAuthSessionNotifier {
  _PresetAuthSessionNotifier(this.initial);

  final AuthSessionState initial;

  @override
  AuthSessionState build() => initial;
}
