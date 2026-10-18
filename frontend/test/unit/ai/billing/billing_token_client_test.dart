import 'package:ai_clinic/features/ai/billing/billing_token_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('R3-M1 BillingTokenClient', () {
    test('rotates before the local token use budget is exhausted', () async {
      var mintCount = 0;
      final client = BillingTokenClient.withRpc(rpc: (_, __) async {
        mintCount++;
        return {
          'success': true,
          'data': {
            'token': 'token-$mintCount',
            'abo_base_url': 'https://abo.example',
            'expires_at': DateTime.now().toUtc().add(const Duration(hours: 1)).toIso8601String(),
          },
        };
      });

      for (var i = 0; i < BillingTokenClient.maxLocalTokenUses + 1; i++) {
        await client.reserveRequestToken();
      }

      expect(mintCount, 2);
      client.dispose();
    });
  });
}
