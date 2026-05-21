import 'package:ai_clinic/features/settings/data/settings_rpc_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('settingsRpcFailureFromPostgrest', () {
    test('maps missing RPC to RPC_NOT_APPLIED with migration hint', () {
      final failure = settingsRpcFailureFromPostgrest(
        const PostgrestException(message: 'Could not find the function public.update_organization', code: 'PGRST202'),
        'update_organization',
      );

      expect(failure, isNotNull);
      expect(failure!.code, 'RPC_NOT_APPLIED');
      expect(failure.message, contains('20260522100000'));
    });

    test('returns null for unrelated PostgREST errors', () {
      final failure = settingsRpcFailureFromPostgrest(
        const PostgrestException(message: 'permission denied', code: '42501'),
        'update_organization',
      );
      expect(failure, isNull);
    });
  });
}
