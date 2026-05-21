import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/auth/data/bootstrap_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('bootstrapRpcFailureFromPostgrest', () {
    test('maps safe-delete PostgREST error to RESET_SAFE_DELETE', () {
      final failure = bootstrapRpcFailureFromPostgrest(
        const PostgrestException(message: 'DELETE requires a WHERE clause', code: '21000'),
        'dev_reset_clinic_installation',
      );

      expect(failure, isNotNull);
      expect(failure!.code, 'RESET_SAFE_DELETE');
      expect(failure.message, contains('20260521150000'));
    });

    test('maps missing function PostgREST error to RESET_NOT_APPLIED', () {
      final failure = bootstrapRpcFailureFromPostgrest(
        const PostgrestException(
          message: 'Could not find the function public.dev_reset_clinic_installation',
          code: 'PGRST202',
        ),
        'dev_reset_clinic_installation',
      );

      expect(failure, isNotNull);
      expect(failure!.code, 'RESET_NOT_APPLIED');
    });

    test('returns null for unrelated PostgREST errors', () {
      final failure = bootstrapRpcFailureFromPostgrest(
        const PostgrestException(message: 'permission denied', code: '42501'),
        'dev_reset_clinic_installation',
      );

      expect(failure, isNull);
    });
  });
}
