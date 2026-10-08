@Tags(['fullstack'])
library;

// ignore_for_file: depend_on_referenced_packages

import 'dart:convert';
import 'dart:io';

import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/app/router.dart';
import 'package:ai_clinic/core/ai/ports.dart';
import 'package:ai_clinic/core/ai/sse_events.dart';
import 'package:ai_clinic/core/ai/taxonomy.dart';
import 'package:ai_clinic/core/config/supabase_config.dart';
import 'package:ai_clinic/core/contract_versions.dart';
import 'package:ai_clinic/core/ui/theme/app_theme.dart';
import 'package:ai_clinic/features/ai/billing/abo_client.dart';
import 'package:ai_clinic/features/ai/degraded/ai_degraded_view.dart';
import 'package:ai_clinic/features/ai/presentation/pages/ai_page.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/clinic-management/domain/branch_working_schedule.dart';
import 'package:ai_clinic/features/clinic-management/domain/create_branch_input.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import '../boundary/harness/boundary_test_context.dart';
import '../boundary/harness/fixture_factory.dart';
import '../boundary/harness/live_supabase_harness.dart' hide markTestSkipped;
import '../boundary/harness/role_sessions.dart';
import '../helpers/auth_test_support.dart';
import '../widget/ai/ai_surface_test_harness.dart';

/// Route path T012 registers on [AppRoutes] and [router.dart].
const kAdministratorBillingPath = '/ai/administrator-billing';

final _aboUrl = Platform.environment['ABO_URL'] ?? 'http://127.0.0.1:8788';
var _hfsStackReady = false;
const _billingHost = 'billing.vendor.test';
const _paymobHmacSecret = 'paymob-hmac-unconfigured';

const _billingOffersKey = Key('billing_offers_screen');
const _billingContactKey = Key('billing_contact_form');
const _billingCheckoutKey = Key('billing_checkout_screen');

const _queuedTermText = 'starts after the current term';
const _appUpdateCopy = 'Update the app to use AI';
const _unsupportedAboContractVersion = aboClinic + 1;

/// Fullstack billing tests call live Supabase and ABO over real HTTP.
class _FullstackBillingTestBinding extends AutomatedTestWidgetsFlutterBinding {
  @override
  bool get overrideHttpClient => false;
}

const _paymobHmacFields = <String>[
  'amount_cents',
  'created_at',
  'currency',
  'error_occured',
  'has_parent_transaction',
  'id',
  'integration_id',
  'is_3d_secure',
  'is_auth',
  'is_capture',
  'is_refunded',
  'is_standalone_payment',
  'is_voided',
  'order.id',
  'owner',
  'pending',
  'source_data.pan',
  'source_data.sub_type',
  'source_data.type',
  'success',
];

void main() {
  _FullstackBillingTestBinding();

  late BoundaryTestContext ctx;
  late RecordingUrlLauncher urlLauncher;

  setUpAll(() async {
    _hfsStackReady = await _probeHfsReady();
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
    urlLauncher = RecordingUrlLauncher();
    UrlLauncherPlatform.instance = urlLauncher;
  });

  group('E2E-P6.3-01', () {
    testWidgets('E2E-P6.3-01', (tester) async {
      if (!_hfsStackReady) {
        fail(
          'H-FS stack unavailable (ABO at $_aboUrl). Start the H-FS stack before running fullstack billing tests.',
        );
      }

      final clinic = await ctx.ensureClinic(label: 'p63_purchase');
      final installationId = _deterministicUuid('b63', clinic.suffix);
      await _seedEndsSoonCoverage(
        ctx: ctx,
        orgId: clinic.organizationId,
        installationId: installationId,
      );

      final sessions = RoleSessions(ctx, clinic);
      await sessions.signInAs(StaffRole.administrator);

      final composition = buildLiveVisitSummaryComposition(
        client: LiveSupabaseHarness.client,
        visitId: testVisitId,
        staffIsAdministrator: true,
        reachabilityPort: FakePlatformReachabilityPort(reachable: false),
      );

      await _pumpAdministratorShell(
        tester,
        router: _billingRouter(),
        composition: composition,
        boundedPumping: true,
      );

      await tester.tap(find.byKey(const Key('ai_notice_renew')));
      await _pumpUntilFound(
        tester,
        find.byKey(_billingOffersKey),
        reason: 'renew should open the offers screen',
      );

      await _acceptTermsAndContinue(tester, boundedPumping: true);
      await _pumpUntilFound(
        tester,
        find.byKey(_billingContactKey),
        reason: 'offers should advance to the contact form',
      );

      await _fillAndSaveBillingContact(tester, boundedPumping: true);
      await _pumpUntilFound(
        tester,
        find.byKey(_billingCheckoutKey),
        reason: 'contact save should advance to checkout',
      );

      await _submitCheckout(tester);

      expect(urlLauncher.launchedUrls, isNotEmpty, reason: 'checkout should record redirect_url via UrlLauncherPlatform');
      expect(urlLauncher.didOpenBrowser, isFalse, reason: 'UrlLauncherPlatform records redirect_url and does not open a browser');

      final redirectUrl = urlLauncher.launchedUrls.last;
      await _replayPaymobFixture('success.json', redirectUrl: redirectUrl);

      await _pumpUntilCheckoutShownState(tester, 'Active');
      expect(find.text('Active'), findsOneWidget);

      expect(
        await _readStatusRefreshRequestedAt(clinic.organizationId),
        isNotNull,
        reason: 'Active should call request_ai_status_refresh once',
      );

      final status = await LiveSupabaseHarness.client.rpc(
        'get_ai_status',
        params: {'p_contract_version': backendRpc},
      );
      final statusMap = Map<String, dynamic>.from(status as Map);
      expect(statusMap['success'], isTrue);
      final data = Map<String, dynamic>.from(statusMap['data'] as Map);
      expect(data['available'], isTrue);
      expect(data['state'], 'active');

      await _expectAiRequestSucceeds(composition);
    });
  });

  group('E2E-P6.3-02', () {
    testWidgets('E2E-P6.3-02', (tester) async {
      final clinic = await ctx.ensureClinic(label: 'p63_resume');
      final secondBranchId = await _createSecondBranch(ctx, clinic);
      final installationId = _deterministicUuid('b632', clinic.suffix);
      await _seedEndsSoonCoverage(
        ctx: ctx,
        orgId: clinic.organizationId,
        installationId: installationId,
      );

      final sessions = RoleSessions(ctx, clinic);
      await sessions.signInAs(StaffRole.administrator);

      final firstSession = _BillingDesktopSession(
        tester: tester,
        branchId: clinic.branchId,
        organizationId: clinic.organizationId,
        urlLauncher: urlLauncher,
      );

      await firstSession.openBillingFromRenew();
      await firstSession.completeOffersAndContact();
      await firstSession.submitCheckout();
      final checkoutReference = firstSession.openCheckoutReference;
      expect(checkoutReference, isNotNull);

      await firstSession.dispose();
      expect(find.byKey(_billingCheckoutKey), findsNothing);

      final secondSession = _BillingDesktopSession(
        tester: tester,
        branchId: secondBranchId,
        organizationId: clinic.organizationId,
        urlLauncher: urlLauncher,
      );
      await secondSession.openBillingRouteDirectly();

      expect(
        find.textContaining(checkoutReference!),
        findsOneWidget,
        reason: 'second desktop should resume the open checkout by reference from GET /v1/checkouts?open=1',
      );

      await _replayPaymobFixture('success.json', redirectUrl: urlLauncher.launchedUrls.last);
      await _pumpUntilCheckoutShownState(tester, 'Active');
      expect(find.text('Active'), findsOneWidget);

      final statusOnOpen = await LiveSupabaseHarness.client.rpc(
        'get_ai_status',
        params: {'p_contract_version': backendRpc},
      );
      final statusMap = Map<String, dynamic>.from(statusOnOpen as Map);
      expect(statusMap['success'], isTrue);
      final data = Map<String, dynamic>.from(statusMap['data'] as Map);
      expect(data['state'], 'active', reason: 'get_ai_status should be active on open');
    });
  });

  group('E2E-P6.3-03', () {
    testWidgets('E2E-P6.3-03', (tester) async {
      final clinic = await ctx.ensureClinic(label: 'p63_queued');
      final installationId = _deterministicUuid('b633', clinic.suffix);
      await _seedActiveCoverage(
        ctx: ctx,
        orgId: clinic.organizationId,
        installationId: installationId,
      );

      final sessions = RoleSessions(ctx, clinic);
      await sessions.signInAs(StaffRole.administrator);

      final composition = buildLiveVisitSummaryComposition(
        client: LiveSupabaseHarness.client,
        visitId: testVisitId,
        staffIsAdministrator: true,
        reachabilityPort: FakePlatformReachabilityPort(reachable: false),
      );

      await _pumpAdministratorShell(
        tester,
        router: _billingRouter(),
        composition: composition,
      );

      await tester.tap(find.byKey(const Key('ai_notice_renew')));
      await tester.pumpAndSettle();

      await _acceptTermsAndContinue(tester);
      await _fillAndSaveBillingContact(tester);

      expect(find.byKey(_billingCheckoutKey), findsOneWidget);
      await _submitCheckout(tester);

      expect(
        find.text(_queuedTermText),
        findsOneWidget,
        reason: 'active clinic should see queued-term sentence before launchUrl',
      );
      expect(urlLauncher.launchedUrls, isEmpty, reason: 'launchUrl should not run before the queued-term sentence is shown');
    });
  });

  group('E2E-P6.3-04', () {
    testWidgets('E2E-P6.3-04', (tester) async {
      final clinic = await ctx.ensureClinic(label: 'p63_price');
      final installationId = _deterministicUuid('b634', clinic.suffix);
      await _seedEndsSoonCoverage(
        ctx: ctx,
        orgId: clinic.organizationId,
        installationId: installationId,
      );

      final sessions = RoleSessions(ctx, clinic);
      await sessions.signInAs(StaffRole.administrator);

      final composition = buildLiveVisitSummaryComposition(
        client: LiveSupabaseHarness.client,
        visitId: testVisitId,
        staffIsAdministrator: true,
        reachabilityPort: FakePlatformReachabilityPort(reachable: false),
      );

      await _pumpAdministratorShell(
        tester,
        router: _billingRouter(),
        composition: composition,
      );

      await tester.tap(find.byKey(const Key('ai_notice_renew')));
      await tester.pumpAndSettle();
      await _acceptTermsAndContinue(tester);
      await _fillAndSaveBillingContact(tester);

      final heldPriceMinor = await _readCurrentSellablePriceMinor();
      await _bumpSellableOfferVersion();
      final newPriceMinor = heldPriceMinor + 100;

      await _submitCheckout(tester);

      expect(find.textContaining('$newPriceMinor'), findsOneWidget, reason: 'offer_unavailable should show the new price before launch');
      expect(urlLauncher.launchedUrls, isEmpty, reason: 'checkout should not launch until the new price is shown');
    });
  });

  group('E2E-P6.3-05', () {
    testWidgets('E2E-P6.3-05', (tester) async {
      final clinic = await ctx.ensureClinic(label: 'p63_decline');
      final installationId = _deterministicUuid('b635', clinic.suffix);
      await _seedEndsSoonCoverage(
        ctx: ctx,
        orgId: clinic.organizationId,
        installationId: installationId,
      );

      final sessions = RoleSessions(ctx, clinic);
      await sessions.signInAs(StaffRole.administrator);

      final composition = buildLiveVisitSummaryComposition(
        client: LiveSupabaseHarness.client,
        visitId: testVisitId,
        staffIsAdministrator: true,
        reachabilityPort: FakePlatformReachabilityPort(reachable: false),
      );

      await _pumpAdministratorShell(
        tester,
        router: _billingRouter(),
        composition: composition,
      );

      await tester.tap(find.byKey(const Key('ai_notice_renew')));
      await tester.pumpAndSettle();
      await _acceptTermsAndContinue(tester);
      await _fillAndSaveBillingContact(tester);
      await _submitCheckout(tester);

      final redirectUrl = urlLauncher.launchedUrls.last;
      await _replayPaymobFixture('decline.json', redirectUrl: redirectUrl);
      await _pumpUntilCheckoutShownState(tester, 'Failed');
      expect(find.text('Failed'), findsOneWidget, reason: 'decline should leave the checkout page on Failed');

      await _replayPaymobFixture('success.json', redirectUrl: redirectUrl);
      await _pumpUntilCheckoutShownState(tester, 'Active');
      expect(find.text('Active'), findsOneWidget, reason: 'later success on the same page should show Active');
      expect(find.byKey(_billingCheckoutKey), findsOneWidget, reason: 'Failed should stay on the same checkout page');
    });
  });

  group('E2E-P6.3-06', () {
    testWidgets('E2E-P6.3-06', (tester) async {
      final clinic = await ctx.ensureClinic(label: 'p63_staff_gate');
      final installationId = _deterministicUuid('b636', clinic.suffix);
      await _seedEndsSoonCoverage(
        ctx: ctx,
        orgId: clinic.organizationId,
        installationId: installationId,
      );

      final sessions = RoleSessions(ctx, clinic);
      await sessions.signInAs(StaffRole.doctor);

      final recordingClient = _RecordingSessionSupabaseClient(LiveSupabaseHarness.client);
      final composition = buildLiveVisitSummaryComposition(
        client: recordingClient,
        visitId: testVisitId,
        staffIsAdministrator: false,
        reachabilityPort: FakePlatformReachabilityPort(reachable: false),
        autoInvoke: false,
      );

      await _pumpStaffShell(
        tester,
        router: _billingRouter(role: StaffRole.doctor),
        composition: composition,
        role: StaffRole.doctor,
      );

      expect(find.byKey(const Key('ai_notice_renew')), findsNothing, reason: 'staff should not see the renew control');
      expect(find.byKey(kAiDegradedRenewOrBuyKey), findsNothing, reason: 'staff should not see the renew or buy control');

      final degradedComposition = buildLiveVisitSummaryComposition(
        client: recordingClient,
        visitId: testVisitId,
        staffIsAdministrator: false,
        reachabilityPort: FakePlatformReachabilityPort(reachable: true),
        submitPortOverride: _WireDenialSubmitPort(wireCode: 'coverage_lapsed'),
        autoInvoke: true,
      );

      await _pumpStaffShell(
        tester,
        router: _billingRouter(role: StaffRole.doctor),
        composition: degradedComposition,
        role: StaffRole.doctor,
      );

      expect(find.byKey(kAiDegradedRenewOrBuyKey), findsNothing, reason: 'staff degraded state should not offer renew or buy');
      expect(
        recordingClient.rpcCalls.where((call) => call == 'issue_billing_token'),
        isEmpty,
        reason: 'staff session should never call issue_billing_token',
      );
    });
  });

  group('E2E-P6.3-07', () {
    testWidgets('E2E-P6.3-07', (tester) async {
      final clinic = await ctx.ensureClinic(label: 'p63_contract');
      final installationId = _deterministicUuid('b637', clinic.suffix);
      await _seedEndsSoonCoverage(
        ctx: ctx,
        orgId: clinic.organizationId,
        installationId: installationId,
      );

      final sessions = RoleSessions(ctx, clinic);
      await sessions.signInAs(StaffRole.administrator);

      final tokenResponse = await LiveSupabaseHarness.client.rpc(
        'issue_billing_token',
        params: {'p_contract_version': backendRpc},
      );
      final tokenMap = Map<String, dynamic>.from(tokenResponse as Map);
      final data = Map<String, dynamic>.from(tokenMap['data'] as Map);
      final billingToken = data['token'] as String;

      final unsupportedProbe = await http.get(
        Uri.parse('$_aboUrl/v1/offers'),
        headers: {
          'Authorization': 'Bearer $billingToken',
          'Host': _billingHost,
          'Abo-Contract-Version': '$_unsupportedAboContractVersion',
        },
      );
      expect(unsupportedProbe.statusCode, 400, reason: 'unsupported Abo-Contract-Version should be refused before auth');
      final unsupportedBody = jsonDecode(unsupportedProbe.body) as Map<String, dynamic>;
      expect(unsupportedBody['code'], 'contract_version_unsupported');

      debugAboContractVersionOverride = _unsupportedAboContractVersion;
      try {
        await _pumpAdministratorBillingRoute(tester, router: _billingRouter());
      } finally {
        debugAboContractVersionOverride = null;
      }

      expect(find.byType(AlertDialog), findsNothing, reason: 'contract_version_unsupported should not open a dialog');
      expect(find.byKey(kAiDegradedAppUpdateKey), findsOneWidget, reason: 'billing screens should show the inline app-update state');
      expect(find.text(_appUpdateCopy), findsOneWidget);
    });
  });
}

GoRouter _billingRouter({
  StaffRole role = StaffRole.administrator,
  List<String>? branchIds,
  String? activeBranchId,
}) {
  final container = ProviderContainer(
    overrides: [
      supabaseClientProvider.overrideWithValue(LiveSupabaseHarness.client),
      authSessionProvider.overrideWith(
        () => MutableAuthSessionNotifier(
          AuthSessionState(
            status: AuthSessionStatus.authenticated,
            context: sampleAuthSessionContext(
              role: role,
              branchIds: branchIds ?? const ['00000000-0000-4000-8000-000000000001'],
              activeBranchId: activeBranchId,
            ),
          ),
        ),
      ),
    ],
  );
  return container.read(appRouterProvider);
}

Future<void> _pumpAdministratorShell(
  WidgetTester tester, {
  required GoRouter router,
  required LiveVisitSummaryComposition composition,
  bool boundedPumping = false,
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
  if (boundedPumping) {
    await _pumpBillingFrames(tester);
  } else {
    await tester.pumpAndSettle();
  }
  router.go(AppRoutes.ai);
  if (boundedPumping) {
    await _pumpBillingFrames(tester);
  } else {
    await tester.pumpAndSettle();
  }
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
  if (boundedPumping) {
    await _pumpUntilFound(
      tester,
      find.byKey(const Key('ai_notice_renew')),
      reason: 'administrator shell should show the renew control',
    );
  } else {
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ai_notice_renew')), findsOneWidget);
  }
}

Future<void> _pumpStaffShell(
  WidgetTester tester, {
  required GoRouter router,
  required LiveVisitSummaryComposition composition,
  required StaffRole role,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        supabaseClientProvider.overrideWithValue(LiveSupabaseHarness.client),
        authSessionProvider.overrideWith(
          () => MutableAuthSessionNotifier(
            AuthSessionState(
              status: AuthSessionStatus.authenticated,
              context: sampleAuthSessionContext(role: role),
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
  router.go(AppRoutes.ai);
  await tester.pumpAndSettle();
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

Future<void> _acceptTermsAndContinue(WidgetTester tester, {bool boundedPumping = false}) async {
  final acceptTerms = find.byKey(const Key('billing_accept_terms'));
  if (acceptTerms.evaluate().isNotEmpty) {
    await tester.tap(acceptTerms);
    if (boundedPumping) {
      await _pumpBillingFrames(tester);
    } else {
      await tester.pumpAndSettle();
    }
  }
  final continueButton = find.byKey(const Key('billing_continue'));
  if (continueButton.evaluate().isNotEmpty) {
    await tester.tap(continueButton);
    if (boundedPumping) {
      await _pumpBillingFrames(tester);
    } else {
      await tester.pumpAndSettle();
    }
  }
}

Future<void> _fillAndSaveBillingContact(WidgetTester tester, {bool boundedPumping = false}) async {
  await tester.enterText(find.byKey(const Key('billing_contact_name')), 'P6.3 Administrator');
  await tester.enterText(find.byKey(const Key('billing_contact_email')), 'p63-admin@clinic.test');
  await tester.enterText(find.byKey(const Key('billing_contact_phone')), '+201001234567');
  await tester.tap(find.byKey(const Key('billing_contact_save')));
  if (boundedPumping) {
    await _pumpBillingFrames(tester);
  } else {
    await tester.pumpAndSettle();
  }
}

Future<void> _submitCheckout(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('billing_checkout_submit')));
  // Checkout polling uses Timer.periodic; pumpAndSettle would wait until timeout.
  await _pumpBillingFrames(tester, iterations: 60);
}

Future<void> _pumpUntilCheckoutShownState(WidgetTester tester, String shownState, {int maxSeconds = 30}) async {
  for (var i = 0; i < maxSeconds; i++) {
    await tester.pump(const Duration(seconds: 1));
    if (find.text(shownState).evaluate().isNotEmpty) {
      return;
    }
  }
  fail('Timed out waiting for checkout shown_state $shownState');
}

Future<void> _expectAiRequestSucceeds(LiveVisitSummaryComposition composition) async {
  final session = await composition.dependencies.sdk.invoke(
    const CapabilityInvokeInput(
      capabilityId: 'clinic.visit_summary',
      capabilityVersion: '1',
      intent: 'generate',
      context: {'visit_id': testVisitId, 'complaint': 'Headache for two days.'},
    ),
  );
  final terminal = await session.terminal;
  expect(terminal, isA<CompletedTerminal>(), reason: 'an AI request should succeed after billing completes');
}

Future<bool> _probeHfsReady() async {
  try {
    final response = await http
        .get(
          Uri.parse('$_aboUrl/v1/offers'),
          headers: {'Host': _billingHost},
        )
        .timeout(const Duration(seconds: 3));
    return response.statusCode < 500;
  } on Exception {
    return false;
  }
}

Future<void> _pumpBillingFrames(
  WidgetTester tester, {
  int iterations = 10,
  Duration step = const Duration(milliseconds: 100),
}) async {
  for (var i = 0; i < iterations; i++) {
    await tester.pump(step);
  }
}

Future<void> _pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  String? reason,
  int maxIterations = 120,
  Duration step = const Duration(milliseconds: 500),
}) async {
  for (var i = 0; i < maxIterations; i++) {
    await tester.pump(step);
    if (finder.evaluate().isNotEmpty) {
      return;
    }
  }
  fail(reason ?? 'Timed out waiting for $finder');
}

Future<void> _replayPaymobFixture(String fixtureName, {required String redirectUrl}) async {
  final repoRoot = File('pubspec.yaml').existsSync() ? Directory.current.parent.path : Directory.current.path;
  final fixturePath = '$repoRoot/abo/test/fixtures/paymob/$fixtureName';
  final fixture = jsonDecode(File(fixturePath).readAsStringSync()) as Map<String, dynamic>;
  final obj = Map<String, dynamic>.from(fixture['obj'] as Map);
  final body = jsonEncode({'type': fixture['type'], 'obj': obj});
  final hmac = _signPaymobObj(obj);
  final response = await http.post(
    Uri.parse('$_aboUrl/notify/paymob?hmac=${Uri.encodeComponent(hmac)}'),
    headers: {
      'Host': _billingHost,
      'content-type': 'application/json',
      'cf-connecting-ip': '203.0.113.10',
    },
    body: body,
  );
  expect(response.statusCode, 200, reason: 'paymob fixture $fixtureName should be accepted by the running stack');
}

String _signPaymobObj(Map<String, dynamic> obj) {
  final concatenated = _paymobHmacFields.map((field) => _paymobFieldValue(obj, field)).join();
  final digest = Hmac(sha512, utf8.encode(_paymobHmacSecret)).convert(utf8.encode(concatenated));
  return digest.toString();
}

String _paymobFieldValue(Map<String, dynamic> obj, String field) {
  if (field == 'order.id') {
    return '${(obj['order'] as Map)['id']}';
  }
  if (field.startsWith('source_data.')) {
    final key = field.split('.').last;
    return '${(obj['source_data'] as Map)[key]}';
  }
  final raw = obj[field];
  if (raw is bool) {
    return raw ? 'true' : 'false';
  }
  return '$raw';
}

Future<String> _createSecondBranch(BoundaryTestContext ctx, BoundaryClinicFixture clinic) async {
  await ctx.signInAdminForClinic(clinic);
  final branchId = await ctx.branches.createBranch(
    CreateBranchInput(
      name: 'Second ${clinic.suffix}',
      workingSchedule: BranchWorkingSchedule.defaultSchedule(),
      code: 'P63${clinic.suffix.hashCode.abs() % 999}',
    ),
  );
  await ctx.signOut();
  return branchId;
}

Future<int> _readCurrentSellablePriceMinor() async {
  final token = await LiveSupabaseHarness.client.rpc(
    'issue_billing_token',
    params: {'p_contract_version': backendRpc},
  );
  final tokenMap = Map<String, dynamic>.from(token as Map);
  final data = Map<String, dynamic>.from(tokenMap['data'] as Map);
  final billingToken = data['token'] as String;
  final response = await http.get(
    Uri.parse('$_aboUrl/v1/offers'),
    headers: {
      'Authorization': 'Bearer $billingToken',
      'Host': _billingHost,
      'Abo-Contract-Version': '$aboClinic',
    },
  );
  expect(response.statusCode, 200);
  final body = jsonDecode(response.body) as Map<String, dynamic>;
  final offers = (body['offers'] as List).cast<Map<String, dynamic>>();
  expect(offers, isNotEmpty);
  return offers.first['price_minor'] as int;
}

Future<void> _bumpSellableOfferVersion() async {
  final repoRoot = File('pubspec.yaml').existsSync() ? Directory.current.parent.path : Directory.current.path;
  final aboPersist = '$repoRoot/e2e/fullstack/.wrangler/abo';
  final dbPath = '$aboPersist/v3/d1/miniflare-D1DatabaseObject';
  final dbDir = Directory(dbPath);
  if (!dbDir.existsSync()) {
    return;
  }
  final files = dbDir
      .listSync()
      .whereType<File>()
      .where((file) => file.path.endsWith('.sqlite'))
      .toList();
  if (files.isEmpty) {
    return;
  }
  final dbFile = files.first.path;
  await Process.run(
    'sqlite3',
    [
      dbFile,
      '''
INSERT INTO offer_version (
  offer_id, version, plan_id, plan_version, term_unit, term_count,
  price_minor, currency, allowance_credits, grace_days, grace_cap_rule,
  copy, terms_version, published_by, assertion_sha256, contract_version
)
SELECT
  offer_id, version + 1, plan_id, plan_version, term_unit, term_count,
  price_minor + 100, currency, allowance_credits, grace_days, grace_cap_rule,
  copy, terms_version, published_by, assertion_sha256, contract_version
FROM offer_version
WHERE offer_id = (SELECT offer_id FROM offer LIMIT 1)
ORDER BY version DESC
LIMIT 1;

INSERT INTO offer_event (
  offer_id, kind, version, actor, at, contract_version
)
SELECT
  offer_id, 'published', version, 'fixture', datetime('now'), contract_version
FROM offer_version
WHERE offer_id = (SELECT offer_id FROM offer LIMIT 1)
ORDER BY version DESC
LIMIT 1;
''',
    ],
  );
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
  'TERM-P63',
  'P6.3 Test Plan',
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

Future<void> _seedEndsSoonCoverage({
  required BoundaryTestContext ctx,
  required String orgId,
  required String installationId,
}) async {
  await _seedActiveCoverage(ctx: ctx, orgId: orgId, installationId: installationId);
  await ctx.sql.execute('''
UPDATE ai_internal.clinic_ai_coverage
SET ends_at = now() + interval '3 days',
    grace_ends_at = now() + interval '10 days'
WHERE organization_id = '$orgId'::uuid;
''');
}

class _RecordingSessionSupabaseClient extends Fake implements SupabaseClient {
  _RecordingSessionSupabaseClient(this._inner);

  final SupabaseClient _inner;
  final List<String> rpcCalls = [];

  @override
  GoTrueClient get auth => _inner.auth;

  @override
  PostgrestClient get rest => _inner.rest;

  @override
  PostgrestFilterBuilder<T> rpc<T>(String fn, {Map<String, dynamic>? params, dynamic get = false}) {
    rpcCalls.add(fn);
    return _inner.rpc<T>(fn, params: params, get: get);
  }
}

class _WireDenialSubmitPort implements HttpsSubmitPort {
  _WireDenialSubmitPort({required this.wireCode});

  final String wireCode;

  @override
  Future<SseConnection> submit({
    required CapabilityInvokeInput input,
    required SubmitRequestHeaders headers,
  }) async {
    throw PlatformHttpException(
      code: classifyTaxonomyCode(wireCode),
      wireCode: wireCode,
      requestReference: 'req-$wireCode',
      traceId: 'trace-$wireCode',
    );
  }
}

class RecordingUrlLauncher extends UrlLauncherPlatform {
  final List<String> launchedUrls = [];
  var didOpenBrowser = false;

  @override
  LinkDelegate? get linkDelegate => null;

  @override
  Future<bool> canLaunch(String url) async => true;

  @override
  Future<bool> launch(
    String url, {
    required bool useSafariVC,
    required bool useWebView,
    required bool enableJavaScript,
    required bool enableDomStorage,
    required bool universalLinksOnly,
    required Map<String, String> headers,
    String? webOnlyWindowName,
  }) async {
    launchedUrls.add(url);
    return true;
  }

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    launchedUrls.add(url);
    return true;
  }
}

Future<String?> _readStatusRefreshRequestedAt(String orgId) async {
  final result = await Process.run(
    'psql',
    [
      '-h',
      '127.0.0.1',
      '-p',
      '54322',
      '-U',
      'postgres',
      '-d',
      'postgres',
      '-t',
      '-A',
      '-c',
      "SELECT requested_at::text FROM ai_internal.status_refresh WHERE organization_id = '$orgId'::uuid",
    ],
    environment: {'PGPASSWORD': Platform.environment['POSTGRES_PASSWORD'] ?? 'postgres'},
  );
  if (result.exitCode != 0) {
    return null;
  }
  final value = '${result.stdout}'.trim();
  return value.isEmpty ? null : value;
}

class _BillingDesktopSession {
  _BillingDesktopSession({
    required this.tester,
    required this.branchId,
    required this.organizationId,
    required this.urlLauncher,
  }) : _router = _billingRouter(
         branchIds: [branchId],
         activeBranchId: branchId,
       );

  final WidgetTester tester;
  final String branchId;
  final String organizationId;
  final RecordingUrlLauncher urlLauncher;
  final GoRouter _router;

  String? openCheckoutReference;

  Future<void> _pumpShell() async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          supabaseClientProvider.overrideWithValue(LiveSupabaseHarness.client),
          authSessionProvider.overrideWith(
            () => MutableAuthSessionNotifier(
              AuthSessionState(
                status: AuthSessionStatus.authenticated,
                context: sampleAuthSessionContext(
                  role: StaffRole.administrator,
                  branchIds: [branchId],
                  activeBranchId: branchId,
                ),
              ),
            ),
          ),
        ],
        child: MaterialApp.router(
          theme: AppTheme.light(),
          routerConfig: _router,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openBillingFromRenew() async {
    final composition = buildLiveVisitSummaryComposition(
      client: LiveSupabaseHarness.client,
      visitId: testVisitId,
      staffIsAdministrator: true,
      reachabilityPort: FakePlatformReachabilityPort(reachable: false),
    );
    await _pumpAdministratorShell(tester, router: _router, composition: composition);
    await tester.tap(find.byKey(const Key('ai_notice_renew')));
    await tester.pumpAndSettle();
  }

  Future<void> openBillingRouteDirectly() async {
    await _pumpShell();
    _router.go(kAdministratorBillingPath);
    await tester.pumpAndSettle();
  }

  Future<void> completeOffersAndContact() async {
    await _acceptTermsAndContinue(tester);
    await _fillAndSaveBillingContact(tester);
  }

  Future<void> submitCheckout() async {
    await _submitCheckout(tester);
    final referenceFinder = find.byKey(const Key('billing_checkout_reference'));
    await _pumpUntilFound(
      tester,
      referenceFinder,
      reason: 'checkout should show reference after POST /v1/checkouts',
    );
    openCheckoutReference = tester.widget<Text>(referenceFinder).data;
  }

  Future<void> dispose() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  }
}
