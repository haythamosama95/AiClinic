import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/billing/data/billing_settings_repository.dart';
import 'package:ai_clinic/features/billing/domain/billing_settings.dart';
import 'package:ai_clinic/features/billing/presentation/providers/billing_settings_notifier.dart';
import 'package:ai_clinic/features/clinic-management/presentation/components/clinic_settings_tab.dart';

import '../../support/billing_rpc_test_client.dart';
import 'clinic_management_widget_test_harness.dart';

void main() {
  testWidgets('ClinicSettingsTab shows loading spinner while settings load', (tester) async {
    await pumpClinicMgmtWidget(
      tester,
      overrides: [
        authSessionProvider.overrideWith(() => PresetAuthSessionNotifier(clinicMgmtAdminAuth())),
        billingSettingsProvider.overrideWith(() => LoadingBillingSettingsNotifier()),
      ],
      child: const ClinicSettingsTab(),
    );
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Clinic settings'), findsNothing);
  });

  testWidgets('ClinicSettingsTab shows error empty state when load fails', (tester) async {
    await pumpClinicMgmtWidget(
      tester,
      overrides: [
        authSessionProvider.overrideWith(() => PresetAuthSessionNotifier(clinicMgmtAdminAuth())),
        billingSettingsProvider.overrideWith(() => ErrorBillingSettingsNotifier()),
      ],
      child: const ClinicSettingsTab(),
    );
    await settleClinicMgmtWidget(tester);

    expect(find.text('Something went wrong'), findsOneWidget);
    expect(find.text('Allow partial payments'), findsNothing);
  });

  testWidgets('ClinicSettingsTab toggles allow partial payments and calls update', (tester) async {
    final client = BillingRpcTestClient()..allowPartialPayments = false;

    await pumpClinicMgmtWidget(
      tester,
      overrides: [
        authSessionProvider.overrideWith(() => PresetAuthSessionNotifier(clinicMgmtAdminAuth())),
        billingSettingsRepositoryProvider.overrideWithValue(BillingSettingsRepository(client)),
      ],
      child: const ClinicSettingsTab(),
    );
    await settleClinicMgmtWidget(tester);

    expect(find.text('Allow partial payments'), findsOneWidget);
    expect(find.byType(AppSwitch), findsOneWidget);

    await tester.tap(find.byType(AppSwitch));
    await settleClinicMgmtWidget(tester);

    expect(client.rpcLog, contains('update_billing_settings'));
    expect(client.allowPartialPayments, isTrue);
  });
}
