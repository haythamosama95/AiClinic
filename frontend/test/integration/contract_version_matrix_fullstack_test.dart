@Tags(['fullstack'])
library;

// ignore_for_file: depend_on_referenced_packages

import 'dart:convert';
import 'dart:io';

import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/app/router.dart';
import 'package:ai_clinic/core/config/supabase_config.dart';
import 'package:ai_clinic/core/contract_versions.dart';
import 'package:ai_clinic/core/ui/theme/app_theme.dart';
import 'package:ai_clinic/features/ai/degraded/ai_degraded_view.dart';
import 'package:ai_clinic/features/ai/presentation/pages/ai_page.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;

import '../boundary/harness/boundary_test_context.dart';
import '../boundary/harness/live_supabase_harness.dart';
import '../boundary/harness/role_sessions.dart';
import '../helpers/auth_test_support.dart';
import '../widget/ai/ai_surface_test_harness.dart';

const kAdministratorBillingPath = '/ai/administrator-billing';
const _appUpdateCopy = 'Update the app to use AI';
const _billingHost = 'billing.vendor.test';

final _aboUrl = Platform.environment['ABO_URL'] ?? 'http://127.0.0.1:8788';
final _platformUrl = Platform.environment['PLATFORM_URL'] ?? 'http://127.0.0.1:8787';

var _hfsStackReady = false;

/// Fullstack contract-version matrix tests call live Supabase, ABO, and platform HTTP.
class _FullstackContractVersionTestBinding extends AutomatedTestWidgetsFlutterBinding {
  @override
  bool get overrideHttpClient => false;
}

void main() {
  _FullstackContractVersionTestBinding();

  late BoundaryTestContext ctx;

  setUpAll(() async {
    _hfsStackReady = await _probeDesktopWindowStackReady();
    if (_hfsStackReady) {
      await LiveSupabaseHarness.ensureReady();
    }
  });

  setUp(() async {
    if (!_hfsStackReady) {
      return;
    }
    ctx = await BoundaryTestContext.create();
    await ctx.resetInstallation();
  });

  group('E2E-P7.3-06', () {
    testWidgets('E2E-P7.3-06', (tester) async {
      if (!_hfsStackReady) {
        fail(
          'H-FS desktop-window stack unavailable (ABO at $_aboUrl, platform at $_platformUrl). '
          'Run p7-3-06-prepare.mjs before this test.',
        );
      }

      final clinic = await ctx.ensureClinic(label: 'p73_desktop_window');
      final installationId = _deterministicUuid('b73', clinic.suffix);
      await _seedActiveCoverage(
        ctx: ctx,
        orgId: clinic.organizationId,
        installationId: installationId,
      );

      final sessions = RoleSessions(ctx, clinic);
      await sessions.signInAs(StaffRole.administrator);

      final aboProbe = await http.get(
        Uri.parse('$_aboUrl/v1/offers'),
        headers: {
          'Host': _billingHost,
          'Abo-Contract-Version': '$aboClinic',
        },
      );
      expect(aboProbe.statusCode, 400, reason: 'desktop Abo-Contract-Version should be below the worker minimum');
      final aboBody = _decodeJsonMap(aboProbe.body);
      expect(aboBody['code'], 'contract_version_unsupported');

      final rpcProbe = await LiveSupabaseHarness.client.rpc(
        'get_ai_status',
        params: {'p_contract_version': backendRpc},
      );
      final rpcMap = Map<String, dynamic>.from(rpcProbe as Map);
      expect(rpcMap['success'], isFalse);
      expect(rpcMap['error_code'], 'CONTRACT_VERSION_UNSUPPORTED');

      final platformProbe = await http.get(
        Uri.parse('$_platformUrl/v1/capabilities'),
        headers: {'Aip-Contract-Version': '$platformClinic'},
      );
      expect(platformProbe.statusCode, 400, reason: 'desktop platform clinic version should be below the worker minimum');
      final platformBody = _decodeJsonMap(platformProbe.body);
      expect(platformBody['code'], 'contract_version_unsupported');

      await _pumpAdministratorBillingRoute(tester, router: _billingRouter());
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byKey(kAiDegradedAppUpdateKey), findsOneWidget);
      expect(find.text(_appUpdateCopy), findsOneWidget);

      final composition = buildLiveVisitSummaryComposition(
        client: LiveSupabaseHarness.client,
        visitId: testVisitId,
        staffIsAdministrator: true,
        reachabilityPort: FakePlatformReachabilityPort(reachable: true),
        autoInvoke: false,
      );
      await _pumpAiPage(tester, composition: composition);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byKey(kAiDegradedAppUpdateKey), findsOneWidget);
      expect(find.text(_appUpdateCopy), findsOneWidget);

      await _pumpAdministratorBillingRoute(tester, router: _billingRouter());
      await _advanceBillingToCheckout(tester);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byKey(kAiDegradedAppUpdateKey), findsOneWidget);
      expect(find.text(_appUpdateCopy), findsOneWidget);
    });
  });
}

GoRouter _billingRouter() {
  final container = ProviderContainer(
    overrides: [
      supabaseClientProvider.overrideWithValue(LiveSupabaseHarness.client),
      authSessionProvider.overrideWith(
        () => MutableAuthSessionNotifier(
          AuthSessionState(
            status: AuthSessionStatus.authenticated,
            context: sampleAuthSessionContext(role: StaffRole.administrator),
          ),
        ),
      ),
    ],
  );
  return container.read(appRouterProvider);
}

Future<void> _pumpAdministratorBillingRoute(
  WidgetTester tester, {
  required GoRouter router,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        supabaseClientProvider.overrideWithValue(LiveSupabaseHarness.client),
        authSessionProvider.overrideWith(
          () => MutableAuthSessionNotifier(
            AuthSessionState(
              status: AuthSessionStatus.authenticated,
              context: sampleAuthSessionContext(role: StaffRole.administrator),
            ),
          ),
        ),
      ],
      child: MaterialApp.router(
        theme: AppTheme.light(),
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
  router.go(kAdministratorBillingPath);
  await tester.pumpAndSettle();
}

Future<void> _pumpAiPage(
  WidgetTester tester, {
  required LiveVisitSummaryComposition composition,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        supabaseClientProvider.overrideWithValue(LiveSupabaseHarness.client),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: liveVisitSummaryHostBody(visitId: testVisitId, composition: composition),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _advanceBillingToCheckout(WidgetTester tester) async {
  final acceptTerms = find.byKey(const Key('billing_accept_terms'));
  if (acceptTerms.evaluate().isNotEmpty) {
    await tester.tap(acceptTerms);
    await tester.pumpAndSettle();
  }
  final continueButton = find.byKey(const Key('billing_continue'));
  if (continueButton.evaluate().isNotEmpty) {
    await tester.tap(continueButton);
    await tester.pumpAndSettle();
  }
  final saveContact = find.byKey(const Key('billing_contact_save'));
  if (saveContact.evaluate().isNotEmpty) {
    await tester.enterText(find.byKey(const Key('billing_contact_name')), 'Test Clinic');
    await tester.enterText(find.byKey(const Key('billing_contact_email')), 'billing@clinic.test');
    await tester.enterText(find.byKey(const Key('billing_contact_phone')), '+201000000000');
    await tester.tap(saveContact);
    await tester.pumpAndSettle();
  }
}

Future<bool> _probeDesktopWindowStackReady() async {
  try {
    final aboResponse = await http
        .get(
          Uri.parse('$_aboUrl/v1/offers'),
          headers: {
            'Host': _billingHost,
            'Abo-Contract-Version': '$aboClinic',
          },
        )
        .timeout(const Duration(seconds: 3));
    if (aboResponse.statusCode != 400) {
      return false;
    }
    final aboBody = _decodeJsonMap(aboResponse.body);
    if (aboBody['code'] != 'contract_version_unsupported') {
      return false;
    }

    final platformResponse = await http
        .get(
          Uri.parse('$_platformUrl/v1/capabilities'),
          headers: {'Aip-Contract-Version': '$platformClinic'},
        )
        .timeout(const Duration(seconds: 3));
    if (platformResponse.statusCode != 400) {
      return false;
    }
    final platformBody = _decodeJsonMap(platformResponse.body);
    return platformBody['code'] == 'contract_version_unsupported';
  } on Exception {
    return false;
  }
}

Map<String, dynamic> _decodeJsonMap(String body) {
  return Map<String, dynamic>.from(jsonDecode(body) as Map);
}

String _deterministicUuid(String prefix, String label) {
  final hash = '$prefix$label'.hashCode.abs();
  final p1 = hash.toRadixString(16).padLeft(8, '0').substring(0, 8);
  final p2 = (hash >> 4).toRadixString(16).padLeft(4, '0').substring(0, 4);
  final p3 = (hash >> 8).toRadixString(16).padLeft(3, '0').substring(0, 3);
  final p4 = (hash >> 12).toRadixString(16).padLeft(3, '0').substring(0, 3);
  final p5 = hash.toRadixString(16).padLeft(12, '0').substring(0, 12);
  return '$p1-$p2-4$p3-8$p4-$p5';
}

Future<void> _seedActiveCoverage({
  required BoundaryTestContext ctx,
  required String orgId,
  required String installationId,
}) async {
  await ctx.sql.execute('''
DELETE FROM ai_internal.clinic_ai_coverage WHERE organization_id = '$orgId'::uuid;

INSERT INTO ai_internal.membership (user_id, organization_id, role)
SELECT sm.auth_user_id, '$orgId'::uuid, sm.role
FROM public.staff_members sm
JOIN public.staff_branch_assignments sba
  ON sba.staff_member_id = sm.id
  AND sba.is_deleted = false
JOIN public.branches b
  ON b.id = sba.branch_id
  AND b.organization_id = '$orgId'::uuid
  AND b.is_deleted = false
WHERE sm.is_deleted = false
  AND sm.is_active = true
ON CONFLICT (user_id, organization_id) DO NOTHING;

INSERT INTO ai_internal.clinic_ai_coverage (
  organization_id,
  installation_id,
  binding_epoch,
  clinic_seq,
  state,
  reason,
  term_ref,
  plan_display_name,
  starts_at,
  ends_at,
  grace_ends_at,
  allowance,
  used,
  band,
  queued_count,
  held_count,
  suspended,
  event_at,
  applied_at
) VALUES (
  '$orgId'::uuid,
  '$installationId'::uuid,
  1,
  1,
  'active',
  NULL,
  'TERM-P73',
  'P7.3 Test Plan',
  now() - interval '30 days',
  now() + interval '30 days',
  now() + interval '37 days',
  10000,
  0,
  'ok',
  0,
  0,
  false,
  timestamp '2020-06-15 12:00:00+00',
  timestamp '2021-03-20 08:00:00+00'
);

UPDATE ai_internal.feed_state
SET last_success_at = now()
WHERE singleton;
''');
}
