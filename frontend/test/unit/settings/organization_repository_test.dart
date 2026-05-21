import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/settings/data/organization_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../support/settings_rpc_test_client.dart';

void main() {
  group('OrganizationRepository', () {
    late SettingsRpcTestClient client;
    late OrganizationRepository repository;

    setUp(() {
      client = SettingsRpcTestClient();
      repository = OrganizationRepository(client);
    });

    test('fetchProfile parses organization row', () async {
      final fetchClient = OrganizationFetchTestClient({
        'id': '11111111-1111-4111-8111-111111111111',
        'name': 'Test Clinic',
        'currency_code': 'USD',
        'timezone': 'UTC',
        'settings_json': {},
      });
      final profile = await OrganizationRepository(
        fetchClient,
      ).fetchProfile(organizationId: '11111111-1111-4111-8111-111111111111');
      expect(profile?.name, 'Test Clinic');
      expect(profile?.currencyCode, 'USD');
    });

    test('fetchProfile returns null when row missing', () async {
      final profile = await OrganizationRepository(
        OrganizationFetchTestClient(null),
      ).fetchProfile(organizationId: 'missing');
      expect(profile, isNull);
    });

    test('updateOrganization sends trimmed contract parameters', () async {
      final id = await repository.updateOrganization(
        const UpdateOrganizationInput(
          name: '  Updated Clinic  ',
          logoUrl: ' https://logo ',
          currencyCode: ' EGP ',
          timezone: ' Africa/Cairo ',
          settingsJson: {'locale': 'ar'},
        ),
      );

      expect(id, '11111111-1111-4111-8111-111111111111');
      expect(client.lastFunction, 'update_organization');
      expect(client.lastParams, containsPair('p_name', 'Updated Clinic'));
      expect(client.lastParams, containsPair('p_logo_url', 'https://logo'));
      expect(client.lastParams, containsPair('p_currency_code', 'EGP'));
      expect(client.lastParams, containsPair('p_timezone', 'Africa/Cairo'));
      expect(client.lastParams?['p_settings_json'], {'locale': 'ar'});
    });

    test('stupid usage: whitespace-only name throws INVALID_INPUT before RPC', () async {
      expect(
        () => repository.updateOrganization(const UpdateOrganizationInput(name: '   ')),
        throwsA(isA<RpcFailure>().having((e) => e.code, 'code', 'INVALID_INPUT')),
      );
      expect(client.lastFunction, isNull);
    });

    test('advanced: RPC failure surfaces RpcFailure code', () async {
      client.rpcResults['update_organization'] = {
        'success': false,
        'error_code': 'FORBIDDEN',
        'error_message': 'Denied',
      };

      expect(
        () => repository.updateOrganization(const UpdateOrganizationInput(name: 'X')),
        throwsA(isA<RpcFailure>().having((e) => e.code, 'code', 'FORBIDDEN')),
      );
    });

    test('advanced: RPC_NOT_APPLIED when update_organization missing', () async {
      final client = SettingsRpcTestClient(
        rpcException: const PostgrestException(
          message: 'Could not find the function public.update_organization',
          code: 'PGRST202',
        ),
      );

      expect(
        () => OrganizationRepository(client).updateOrganization(const UpdateOrganizationInput(name: 'X')),
        throwsA(isA<RpcFailure>().having((e) => e.code, 'code', 'RPC_NOT_APPLIED')),
      );
    });

    test('corner case: success without organization_id throws StateError', () async {
      client.rpcResults['update_organization'] = {'success': true, 'data': {}};
      expect(() => repository.updateOrganization(const UpdateOrganizationInput(name: 'X')), throwsA(isA<StateError>()));
    });
  });
}
