import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:ai_clinic/core/config/supabase_config.dart';
import 'package:ai_clinic/core/rpc/app_rpc_invoker.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/settings/data/settings_rpc_repository.dart';
import 'package:ai_clinic/features/settings/domain/organization_profile.dart';
import 'package:ai_clinic/features/settings/domain/repositories/organization_repository.dart';
import 'package:ai_clinic/features/settings/domain/update_organization_input.dart';

/// Organization profile reads (RLS) and updates (RPC).
class OrganizationRepositoryImpl with AppRpcInvoker, SettingsRpcInvoker implements OrganizationRepository {
  OrganizationRepositoryImpl(this._client);

  final SupabaseClient _client;

  @override
  SupabaseClient get settingsRpcClient => _client;

  @override
  Future<OrganizationProfile?> fetchProfile({required String organizationId}) async {
    final row = await _client
        .from('organizations')
        .select(
          'id, name, logo_url, currency_code, timezone, settings_json, '
          'subscription_tier, subscription_valid_until',
        )
        .eq('id', organizationId)
        .eq('is_deleted', false)
        .maybeSingle();

    if (row == null) {
      return null;
    }

    return OrganizationProfile.fromRow(Map<String, dynamic>.from(row));
  }

  @override
  Future<String> updateOrganization(UpdateOrganizationInput input) async {
    final name = OrganizationProfile.normalizeName(input.name);
    if (name == null) {
      throw RpcFailure(
        const RpcResult(success: false, errorCode: 'INVALID_INPUT', errorMessage: 'Organization name is required.'),
      );
    }

    final result = await invokeSettingsRpc('update_organization', {
      'p_name': name,
      if (input.logoUrl != null) 'p_logo_url': input.logoUrl!.trim(),
      if (input.currencyCode != null) 'p_currency_code': OrganizationProfile.normalizeCurrencyCode(input.currencyCode),
      if (input.timezone != null) 'p_timezone': OrganizationProfile.normalizeTimezone(input.timezone),
      if (input.settingsJson != null) 'p_settings_json': input.settingsJson,
    });

    final organizationId = result.data?['organization_id']?.toString();
    if (organizationId == null || organizationId.isEmpty) {
      throw StateError('Organization was updated but no organization_id was returned.');
    }

    return organizationId;
  }
}

final organizationRepositoryProvider = Provider<OrganizationRepository>((ref) {
  return OrganizationRepositoryImpl(ref.watch(supabaseClientProvider));
});
