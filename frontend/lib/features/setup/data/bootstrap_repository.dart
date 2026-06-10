import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:ai_clinic/core/config/supabase_config.dart';
import 'package:ai_clinic/core/logging/app_log.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/setup/domain/bootstrap_organization_input.dart';
import 'package:ai_clinic/features/setup/domain/bootstrap_branch_input.dart';
import 'package:ai_clinic/features/setup/domain/repositories/bootstrap_repository.dart';

/// Maps bootstrap RPC PostgREST failures to [RpcFailure], or returns null to rethrow.
RpcFailure? bootstrapRpcFailureFromPostgrest(PostgrestException error, String functionName) {
  if (error.code == 'PGRST202' || error.message.contains('Could not find the function')) {
    return RpcFailure(
      RpcResult(
        success: false,
        errorCode: 'RESET_NOT_APPLIED',
        errorMessage:
            'Database function "$functionName" is missing. Run backend migrations '
            '(20260521140000_dev_reset_clinic_installation.sql) and restart Supabase.',
      ),
    );
  }

  if (error.message.contains('DELETE requires a WHERE clause')) {
    return RpcFailure(
      RpcResult(
        success: false,
        errorCode: 'RESET_SAFE_DELETE',
        errorMessage:
            'Clinic reset failed because the database function needs a migration update. '
            'Apply 20260521150000_fix_dev_reset_safe_delete_where.sql and try again.',
      ),
    );
  }

  if (functionName == 'dev_reset_clinic_installation' &&
      (error.code == '23503' || error.message.contains('violates foreign key constraint'))) {
    return RpcFailure(
      RpcResult(
        success: false,
        errorCode: 'RESET_DEPENDENCY_BLOCKED',
        errorMessage:
            'Clinic reset could not remove branches or organization data because related records still exist '
            '(for example patients or billing settings). Apply migration 20260605190000_dev_reset_delete_billing.sql, restart Supabase, and try again.',
      ),
    );
  }

  return null;
}

/// Calls bootstrap RPCs (`bootstrap_create_organization`, `bootstrap_create_branch`).
class BootstrapRepositoryImpl implements BootstrapRepository {
  BootstrapRepositoryImpl(this._client);

  final SupabaseClient _client;

  @override
  Future<String> createOrganization(BootstrapOrganizationInput input) async {
    final result = await _invoke('bootstrap_create_organization', {
      'p_name': input.name.trim(),
      'p_settings_json': input.settingsJson,
      if (input.logoUrl != null) 'p_logo_url': input.logoUrl!.trim(),
      if (input.currencyCode != null) 'p_currency_code': input.currencyCode!.trim(),
      if (input.timezone != null) 'p_timezone': input.timezone!.trim(),
    });

    final organizationId = result.data?['organization_id']?.toString();
    if (organizationId == null || organizationId.isEmpty) {
      throw StateError('Organization was created but no organization_id was returned.');
    }

    return organizationId;
  }

  /// Removes all organizations/branches (bootstrap admin only). For local development.
  @override
  Future<RpcResult> resetInstallationForDevelopment() async {
    return _invoke('dev_reset_clinic_installation', null, allowEmptyParams: true);
  }

  @override
  Future<String> createBranch(BootstrapBranchInput input) async {
    final result = await _invoke('bootstrap_create_branch', {
      'p_organization_id': input.organizationId,
      'p_name': input.name.trim(),
      if (input.address != null) 'p_address': input.address!.trim(),
      if (input.phone != null) 'p_phone': input.phone!.trim(),
      if (input.code != null) 'p_code': input.code!.trim(),
      if (input.mapsUrl != null) 'p_maps_url': input.mapsUrl!.trim(),
    });

    final branchId = result.data?['branch_id']?.toString();
    if (branchId == null || branchId.isEmpty) {
      throw StateError('Branch was created but no branch_id was returned.');
    }

    return branchId;
  }

  Future<RpcResult> _invoke(String functionName, Map<String, dynamic>? params, {bool allowEmptyParams = false}) async {
    AppLog.fine('bootstrap.rpc.invoke fn=$functionName params=${params?.keys.join(',') ?? 'none'}');

    try {
      final dynamic raw;
      if (params == null || (params.isEmpty && allowEmptyParams)) {
        raw = await _client.rpc(functionName);
      } else {
        raw = await _client.rpc(functionName, params: params);
      }

      AppLog.fine('bootstrap.rpc.response fn=$functionName type=${raw.runtimeType}');

      final result = RpcResult.fromDynamic(raw);
      if (!result.success) {
        AppLog.warning(
          'bootstrap.rpc.rejected fn=$functionName code=${result.errorCode} '
          'message=${result.errorMessage}',
        );
        throw RpcFailure(result);
      }

      AppLog.fine('bootstrap.rpc.ok fn=$functionName data_keys=${result.data?.keys.join(',') ?? 'none'}');
      return result;
    } on PostgrestException catch (error) {
      AppLog.warning(
        'bootstrap.rpc.postgrest_error fn=$functionName code=${error.code} '
        'message=${error.message} details=${error.details}',
      );
      final mapped = bootstrapRpcFailureFromPostgrest(error, functionName);
      if (mapped != null) {
        throw mapped;
      }
      rethrow;
    } catch (error) {
      AppLog.warning('bootstrap.rpc.error fn=$functionName reason=${error.runtimeType} detail=$error');
      rethrow;
    }
  }
}

final bootstrapRepositoryProvider = Provider<BootstrapRepository>((ref) {
  return BootstrapRepositoryImpl(ref.watch(supabaseClientProvider));
});
