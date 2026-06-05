import 'package:ai_clinic/features/auth/data/bootstrap_repository.dart';
import 'package:ai_clinic/features/auth/domain/bootstrap_branch_input.dart';
import 'package:ai_clinic/features/auth/domain/bootstrap_organization_input.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../support/fake_postgrest_rpc.dart';

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

    test('maps patient FK violation on dev reset to RESET_DEPENDENCY_BLOCKED', () {
      final failure = bootstrapRpcFailureFromPostgrest(
        const PostgrestException(
          message:
              'update or delete on table "branches" violates foreign key constraint "patients_branch_id_fkey" on table "patients"',
          code: '23503',
        ),
        'dev_reset_clinic_installation',
      );

      expect(failure, isNotNull);
      expect(failure!.code, 'RESET_DEPENDENCY_BLOCKED');
      expect(failure.message, contains('20260605190000'));
    });

    test('returns null for unrelated PostgREST errors', () {
      final failure = bootstrapRpcFailureFromPostgrest(
        const PostgrestException(message: 'permission denied', code: '42501'),
        'dev_reset_clinic_installation',
      );

      expect(failure, isNull);
    });
  });

  group('BootstrapRepository RPC contract', () {
    late RpcCaptureSupabaseClient client;
    late BootstrapRepositoryImpl repository;

    setUp(() {
      client = RpcCaptureSupabaseClient();
      repository = BootstrapRepositoryImpl(client);
    });

    test('createOrganization sends contract parameter names and trims strings', () async {
      await repository.createOrganization(
        const BootstrapOrganizationInput(
          name: '  Test Clinic  ',
          logoUrl: ' https://logo ',
          currencyCode: ' USD ',
          timezone: ' Africa/Cairo ',
        ),
      );

      expect(client.lastFunction, 'bootstrap_create_organization');
      expect(client.lastParams, containsPair('p_name', 'Test Clinic'));
      expect(client.lastParams, containsPair('p_logo_url', 'https://logo'));
      expect(client.lastParams, containsPair('p_currency_code', 'USD'));
      expect(client.lastParams, containsPair('p_timezone', 'Africa/Cairo'));
    });

    test('createBranch sends parameters in migration order (address before code)', () async {
      await repository.createBranch(
        const BootstrapBranchInput(
          organizationId: '11111111-1111-4111-8111-111111111111',
          name: ' Main ',
          code: ' M1 ',
          address: ' 1 St ',
          phone: ' 555 ',
          mapsUrl: ' https://maps ',
        ),
      );

      expect(client.lastFunction, 'bootstrap_create_branch');
      final keys = client.lastParams!.keys.toList();
      expect(keys.indexOf('p_address'), lessThan(keys.indexOf('p_code')));
      expect(client.lastParams, containsPair('p_organization_id', '11111111-1111-4111-8111-111111111111'));
      expect(client.lastParams, containsPair('p_name', 'Main'));
      expect(client.lastParams, containsPair('p_maps_url', 'https://maps'));
    });

    test('createBranch omits optional null fields', () async {
      await repository.createBranch(
        const BootstrapBranchInput(organizationId: '11111111-1111-4111-8111-111111111111', name: 'Branch'),
      );

      expect(client.lastParams, isNot(contains('p_code')));
      expect(client.lastParams, isNot(contains('p_address')));
      expect(client.lastParams, isNot(contains('p_phone')));
      expect(client.lastParams, isNot(contains('p_maps_url')));
    });
  });
}
