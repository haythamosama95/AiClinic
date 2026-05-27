import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

/// Builds a minimal JWT-shaped access token for boundary tests of claim parsing.
String minimalAccessToken(Map<String, dynamic> claims) {
  final header = base64Url.encode(utf8.encode('{"alg":"none","typ":"JWT"}'));
  final payload = base64Url.encode(utf8.encode(jsonEncode(claims)));
  return '$header.$payload.sig';
}

/// [Session] with arbitrary claim payload (no live GoTrue required).
Session sessionWithClaims(Map<String, dynamic> claims) {
  final sub = claims['sub']?.toString() ?? '00000000-0000-0000-0000-000000000099';
  final token = minimalAccessToken(claims);
  return Session(
    accessToken: token,
    refreshToken: 'fake-refresh',
    tokenType: 'bearer',
    user: User(
      id: sub,
      appMetadata: const {},
      userMetadata: const {},
      aud: 'authenticated',
      createdAt: DateTime.now().toUtc().toIso8601String(),
    ),
  );
}
