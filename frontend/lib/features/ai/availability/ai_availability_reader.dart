import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'ai_availability.dart';

/// Production reader for `public.get_ai_availability()` — never probes the platform
/// to discover enrollment (FR-009).
class SupabaseAiAvailabilityReader implements AiAvailabilityReader {
  SupabaseAiAvailabilityReader({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  @override
  Future<AiAvailability> read() async {
    final raw = await _client.rpc('get_ai_availability');
    if (raw is Map<String, dynamic>) {
      return AiAvailability.fromJson(raw);
    }
    if (raw is String) {
      return AiAvailability.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    }
    return AiAvailability.nonEnrolled;
  }
}

/// HTTP reachability check for enrolled installations (A1 `/health`).
class HttpPlatformReachabilityPort implements PlatformReachabilityPort {
  HttpPlatformReachabilityPort({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  @override
  Future<bool> isReachable(String platformBaseUrl) async {
    final base = platformBaseUrl.endsWith('/')
        ? platformBaseUrl.substring(0, platformBaseUrl.length - 1)
        : platformBaseUrl;
    try {
      final response = await _client
          .get(Uri.parse('$base/health'))
          .timeout(const Duration(seconds: 5));
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (_) {
      return false;
    }
  }
}
