import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:ai_clinic/core/config/supabase_config.dart' show supabaseClientProvider;
import 'package:ai_clinic/core/rpc/app_rpc_invoker.dart';
import 'package:ai_clinic/features/billing/domain/billing_settings.dart';

/// Organization billing settings RPC wrappers (V1-6).
class BillingSettingsRepository with AppRpcInvoker {
  BillingSettingsRepository(this._client);

  final SupabaseClient _client;

  @override
  SupabaseClient get rpcClient => _client;

  @override
  String get migrationHint => '20260605180000_billing.sql';

  @override
  String get rpcLogDomain => 'billing.settings';

  Future<BillingSettings> get() async {
    final result = await invokeRpc('get_billing_settings', null);
    final settings = BillingSettings.fromRow(result.data ?? const {});
    if (settings == null) {
      throw StateError('Get billing settings returned an unexpected shape.');
    }
    return settings;
  }

  Future<void> update({required bool allowPartialPayments}) async {
    await invokeRpc('update_billing_settings', {'p_allow_partial_payments': allowPartialPayments});
  }
}

final billingSettingsRepositoryProvider = Provider<BillingSettingsRepository>((ref) {
  return BillingSettingsRepository(ref.watch(supabaseClientProvider));
});
