import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:ai_clinic/core/config/deployment_profile.dart';
import 'package:ai_clinic/core/config/supabase_config.dart';

/// Probes and initializes a live local Supabase stack for boundary tests.
class LiveSupabaseHarness {
  LiveSupabaseHarness._();

  static bool? _available;
  static SupabaseConfig? _config;

  static bool get isAvailable => _available ?? false;

  static SupabaseConfig get config {
    final value = _config;
    if (value == null) {
      throw StateError('LiveSupabaseHarness.ensureReady() was not called.');
    }
    return value;
  }

  static SupabaseClient get client => Supabase.instance.client;

  /// Loads deployment profile, probes health, initializes Supabase (once per process).
  static Future<void> ensureReady() async {
    if (_available == true && SupabaseBootstrap.isReady) {
      return;
    }

    WidgetsFlutterBinding.ensureInitialized();

    final profile = await _loadProfile();
    final config = SupabaseConfig.fromDeploymentProfile(profile);

    final authOk = await _probe(config.authHealthUrl);
    final restOk = await _probe(config.restProbeUrl);
    if (!authOk || !restOk) {
      _available = false;
      markTestSkipped(
        'Local Supabase unavailable at ${config.url} '
        '(auth=$authOk rest=$restOk). Start backend/local docker compose and apply migrations.',
      );
    }

    await SupabaseBootstrap.ensureInitialized(config);
    _config = config;
    _available = true;
    await _assertStaffClaimsAfterBootstrapSignIn();
  }

  static Future<void> _assertStaffClaimsAfterBootstrapSignIn() async {
    try {
      await client.auth.signInWithPassword(email: 'admin', password: 'admin');
      final session = client.auth.currentSession;
      if (session == null) {
        markTestSkipped('Bootstrap admin sign-in failed; check auth seed.');
      }
      final claims = decodeAccessTokenClaims(session!.accessToken);
      if (claims['staff_member_id'] == null) {
        markTestSkipped(
          'JWT missing staff_member_id. Enable GoTrue custom_access_token hook on local auth '
          '(pg-functions://postgres/public/get_custom_claims).',
        );
      }
      await client.auth.signOut();
    } on AuthException catch (error) {
      markTestSkipped('Bootstrap admin sign-in failed: ${error.message}');
    }
  }

  static Future<bool> _probe(Uri url) async {
    try {
      final response = await http.get(url).timeout(const Duration(seconds: 5));
      return response.statusCode >= 200 && response.statusCode < 500;
    } on Exception {
      return false;
    }
  }

  static Future<DeploymentProfile> _loadProfile() async {
    final path = Platform.environment['AICLINIC_DEPLOYMENT_PROFILE_PATH'] ?? 'deployment-profile.json';
    final file = File(path);
    if (!await file.exists()) {
      markTestSkipped('Missing deployment profile at $path');
    }
    final contents = await file.readAsString();
    return DeploymentProfile.fromJsonString(contents, sourcePath: file.path);
  }
}

void markTestSkipped(String message) {
  throw Skip(message);
}
