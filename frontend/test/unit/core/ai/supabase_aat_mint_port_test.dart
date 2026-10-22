import 'dart:convert';

import 'package:ai_clinic/core/ai/supabase_aat_mint_port.dart';
import 'package:ai_clinic/features/ai/availability/ai_availability.dart';
import 'package:flutter_test/flutter_test.dart';

String _jws(Map<String, Object?> payload) {
  String b64(String s) => base64Url.encode(utf8.encode(s)).replaceAll('=', '');
  return '${b64('{"alg":"HS256","typ":"JWT"}')}.${b64(jsonEncode(payload))}.c2ln';
}

SupabaseAatMintPort _portReturning(String token) =>
    SupabaseAatMintPort.withRpc(rpc: (functionName, params) async => token);

void main() {
  group('SupabaseAatMintPort ver claim', () {
    test('R2-C3: AI token with ver 2 is accepted by the mint port', () async {
      final token = _jws({'ver': '2', 'sub': 'x'});
      expect(await _portReturning(token).mint(), token);
    });

    test('R2-C3: AI token with a mismatched ver is rejected as contract version unsupported', () async {
      final port = _portReturning(_jws({'ver': '1'}));
      await expectLater(port.mint(), throwsA(isA<ContractVersionUnsupportedException>()));
    });

    test('R2-C3: AI token without a ver claim is rejected as contract version unsupported', () async {
      final port = _portReturning(_jws({'sub': 'x'}));
      await expectLater(port.mint(), throwsA(isA<ContractVersionUnsupportedException>()));
    });

    test('R2-C3: malformed AI token is rejected as contract version unsupported', () async {
      for (final malformed in [
        'not-a-jwt',
        'a.b',
        'a.b.c.d',
        'aGVsbG8.!!!.c2ln',
        'aGVsbG8.bm90LWpzb24.c2ln',
        '${base64Url.encode(utf8.encode('[2]'))}.${base64Url.encode(utf8.encode('[2]'))}.c2ln',
      ]) {
        await expectLater(
          _portReturning(malformed).mint(),
          throwsA(isA<ContractVersionUnsupportedException>()),
          reason: 'token: $malformed',
        );
      }
    });
  });
}
