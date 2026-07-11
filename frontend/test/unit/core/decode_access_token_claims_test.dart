import 'dart:convert';

import 'package:ai_clinic/core/config/supabase_config.dart';
import 'package:flutter_test/flutter_test.dart';

String _fakeJwt(Map<String, dynamic> payload) {
  final header = base64Url.encode(utf8.encode('{"alg":"none"}'));
  final body = base64Url.encode(utf8.encode(jsonEncode(payload)));
  return '$header.$body.signature';
}

void main() {
  group('decodeAccessTokenClaims', () {
    test('returns invalid result for malformed token', () {
      expect(decodeAccessTokenClaims('not-a-jwt'), isA<AccessTokenClaimsInvalid>());
      expect(decodeAccessTokenClaims('only.two'), isA<AccessTokenClaimsInvalid>());
    });

    test('decodes staff claims from payload', () {
      final result = decodeAccessTokenClaims(
        _fakeJwt({
          'staff_member_id': 'b0000000-0000-4000-8000-000000000001',
          'staff_role': 'administrator',
          'setup_required': true,
          'branch_ids': 'a,b',
        }),
      );

      expect(result, isA<AccessTokenClaimsSuccess>());
      final claims = result.claims;
      expect(claims['staff_member_id'], 'b0000000-0000-4000-8000-000000000001');
      expect(claims['staff_role'], 'administrator');
      expect(claims['setup_required'], true);
      expect(claims['branch_ids'], 'a,b');
    });

    test('returns expired result when exp is in the past', () {
      final result = decodeAccessTokenClaims(
        _fakeJwt({
          'exp': DateTime.now().toUtc().subtract(const Duration(minutes: 5)).millisecondsSinceEpoch ~/ 1000,
          'staff_member_id': 'b0000000-0000-4000-8000-000000000001',
        }),
      );

      expect(result, isA<AccessTokenClaimsExpired>());
      expect(result.claims, isEmpty);
    });

    test('returns invalid result when payload is not a JSON object', () {
      final header = base64Url.encode(utf8.encode('{}'));
      final body = base64Url.encode(utf8.encode('"string"'));
      expect(decodeAccessTokenClaims('$header.$body.sig'), isA<AccessTokenClaimsInvalid>());
    });
  });
}
