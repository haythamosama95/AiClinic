import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:ai_clinic/core/config/supabase_config.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/settings/data/settings_rpc_repository.dart';
import 'package:ai_clinic/features/settings/domain/organization_profile.dart';

/// Input for steady-state [update_organization] RPC.
class UpdateOrganizationInput {
  const UpdateOrganizationInput({
    required this.name,
    this.logoUrl,
    this.currencyCode,
    this.timezone,
    this.settingsJson,
  });

  final String name;
  final String? logoUrl;
  final String? currencyCode;
  final String? timezone;
  final Map<String, dynamic>? settingsJson;
}

/// Organization profile reads (RLS) and updates (RPC).
class OrganizationRepository with SettingsRpcInvoker {
  OrganizationRepository(this._client);

  final SupabaseClient _client;

  @override
  SupabaseClient get settingsRpcClient => _client;

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
  return OrganizationRepository(ref.watch(supabaseClientProvider));
});
