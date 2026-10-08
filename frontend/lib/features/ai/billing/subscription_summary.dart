import 'package:ai_clinic/core/contract_versions.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/ai/billing/abo_client.dart';
import 'package:ai_clinic/features/ai/availability/ai_availability.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Injectable RPC callable for unit tests.
typedef SubscriptionSummaryRpcInvoke = Future<dynamic> Function(
  String functionName,
  Map<String, dynamic> params,
);

/// Loaded subscription summary from `get_ai_billing_status` and `GET /v1/subscription`.
class SubscriptionSummaryData {
  const SubscriptionSummaryData({
    required this.planDisplayName,
    required this.startsAt,
    required this.endsAt,
    required this.graceEndsAt,
    required this.allowance,
    required this.used,
    required this.queuedCount,
    required this.heldCount,
    required this.subscriptionRef,
    required this.showEndedReversed,
  });

  final String? planDisplayName;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final DateTime? graceEndsAt;
  final int? allowance;
  final int? used;
  final int? queuedCount;
  final int? heldCount;
  final String? subscriptionRef;
  final bool showEndedReversed;
}

/// Shows plan, dates, allowance, counts, subscription reference, and status notices.
class SubscriptionSummary extends StatefulWidget {
  const SubscriptionSummary({
    super.key,
    required this.client,
    this.supabaseClient,
    this.rpc,
  });

  final AboClient client;
  final SupabaseClient? supabaseClient;
  final SubscriptionSummaryRpcInvoke? rpc;

  @override
  State<SubscriptionSummary> createState() => _SubscriptionSummaryState();
}

class _SubscriptionSummaryState extends State<SubscriptionSummary> {
  static const _rpcName = 'get_ai_billing_status';

  var _loading = true;
  SubscriptionSummaryData? _summary;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _fetchBillingStatus(),
        widget.client.getSubscription(),
      ]);
      final billingStatus = results[0] as Map<String, dynamic>;
      // Subscription read completes before render; null snapshot still shows summary (T014).
      final _ = results[1] as SubscriptionResponse;
      if (!mounted) {
        return;
      }
      setState(() {
        _summary = _parseSummary(billingStatus);
        _loading = false;
      });
    } on AboContractVersionUnsupportedException {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = const ContractVersionUnsupportedException();
        _loading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  Future<Map<String, dynamic>> _fetchBillingStatus() async {
    final raw = await _callRpc(_rpcName, {'p_contract_version': backendRpc});
    final result = RpcResult.fromDynamic(raw);
    if (!result.success) {
      if (result.errorCode == 'CONTRACT_VERSION_UNSUPPORTED') {
        throw const ContractVersionUnsupportedException();
      }
      throw RpcFailure(result);
    }
    final data = result.data;
    if (data == null) {
      throw StateError('get_ai_billing_status returned no data');
    }
    return data;
  }

  Future<dynamic> _callRpc(String functionName, Map<String, dynamic> params) {
    final rpc = widget.rpc;
    if (rpc != null) {
      return rpc(functionName, params);
    }
    final client = widget.supabaseClient ?? Supabase.instance.client;
    return client.rpc(functionName, params: params);
  }

  SubscriptionSummaryData _parseSummary(Map<String, dynamic> data) {
    final notices = (data['notices'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    final showEndedReversed = notices.any((entry) => entry['code']?.toString() == 'ended_reversed');
    return SubscriptionSummaryData(
      planDisplayName: _nullableString(data['plan_display_name']),
      startsAt: _nullableDateTime(data['starts_at']),
      endsAt: _nullableDateTime(data['ends_at']),
      graceEndsAt: _nullableDateTime(data['grace_ends_at']),
      allowance: _nullableInt(data['allowance']),
      used: _nullableInt(data['used']),
      queuedCount: _nullableInt(data['queued_count']),
      heldCount: _nullableInt(data['held_count']),
      subscriptionRef: _nullableString(data['subscription_ref']),
      showEndedReversed: showEndedReversed,
    );
  }

  String? _nullableString(Object? value) {
    if (value == null) {
      return null;
    }
    final text = value.toString();
    return text.isEmpty ? null : text;
  }

  int? _nullableInt(Object? value) {
    if (value == null) {
      return null;
    }
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value.toString());
  }

  DateTime? _nullableDateTime(Object? value) {
    if (value == null) {
      return null;
    }
    if (value is DateTime) {
      return value.toUtc();
    }
    if (value is String && value.isNotEmpty) {
      return DateTime.tryParse(value)?.toUtc();
    }
    return null;
  }

  String? _formatDateTime(DateTime? value) {
    if (value == null) {
      return null;
    }
    return value.toUtc().toIso8601String();
  }

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(
      key: const Key('billing_subscription_summary'),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: _buildBody(context),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Text('$_error');
    }
    final summary = _summary;
    if (summary == null) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Subscription', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 16),
        if (summary.planDisplayName != null) Text(summary.planDisplayName!),
        if (_formatDateTime(summary.startsAt) case final startsAt?) Text(startsAt),
        if (_formatDateTime(summary.endsAt) case final endsAt?) Text(endsAt),
        if (_formatDateTime(summary.graceEndsAt) case final graceEndsAt?) Text(graceEndsAt),
        if (summary.allowance != null) Text('${summary.allowance}'),
        if (summary.used != null) Text('${summary.used}'),
        if (summary.queuedCount != null) Text('${summary.queuedCount}'),
        if (summary.heldCount != null) Text('${summary.heldCount}'),
        if (summary.subscriptionRef != null) Text(summary.subscriptionRef!),
        const SizedBox(height: 12),
        const Text('Contact support'),
        if (summary.subscriptionRef != null) ...[
          const SizedBox(height: 4),
          Text(summary.subscriptionRef!),
        ],
        if (summary.showEndedReversed) ...[
          const SizedBox(height: 12),
          const Text('ended_reversed'),
        ],
      ],
    );
  }
}
