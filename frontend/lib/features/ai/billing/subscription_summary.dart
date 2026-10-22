import 'package:ai_clinic/core/contract_version_guard.dart';
import 'package:ai_clinic/core/contract_versions.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/ai/billing/abo_client.dart';
import 'package:ai_clinic/features/ai/availability/ai_availability.dart';
import 'package:ai_clinic/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Injectable RPC callable for unit tests.
typedef SubscriptionSummaryRpcInvoke =
    Future<dynamic> Function(String functionName, Map<String, dynamic> params);

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
    this.generation = 0,
    this.onLoaded,
  });

  final AboClient client;
  final SupabaseClient? supabaseClient;
  final SubscriptionSummaryRpcInvoke? rpc;

  /// R7-UI2: the parent's billing-read generation. A change reloads the summary; results from an
  /// earlier generation are ignored.
  final int generation;

  /// Called after each successful load that is still current.
  final ValueChanged<SubscriptionSummaryData>? onLoaded;

  @override
  State<SubscriptionSummary> createState() => _SubscriptionSummaryState();
}

class _SubscriptionSummaryState extends State<SubscriptionSummary> {
  static const _rpcName = 'get_ai_billing_status';

  /// True only until the first successful or failed load. Later reloads keep [_summary] on screen.
  var _loading = true;

  /// True while a reload is in flight (review F4): a small indicator, not a full spinner.
  var _refreshing = false;
  SubscriptionSummaryData? _summary;
  Object? _error;
  var _requestSeq = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant SubscriptionSummary oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.generation != widget.generation) {
      _load();
    }
  }

  Future<void> _load() async {
    final seq = ++_requestSeq;
    final generation = widget.generation;
    setState(() {
      _loading = _summary == null;
      _refreshing = true;
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
      if (!mounted || seq != _requestSeq || generation != widget.generation) {
        return;
      }
      final summary = _parseSummary(billingStatus);
      setState(() {
        _summary = summary;
        _loading = false;
        _refreshing = false;
      });
      widget.onLoaded?.call(summary);
    } on AboContractVersionUnsupportedException {
      if (!mounted || seq != _requestSeq || generation != widget.generation) {
        return;
      }
      setState(() {
        _error = const ContractVersionUnsupportedException();
        _loading = false;
        _refreshing = false;
      });
    } catch (error) {
      if (!mounted || seq != _requestSeq || generation != widget.generation) {
        return;
      }
      setState(() {
        _error = error;
        _loading = false;
        _refreshing = false;
      });
    }
  }

  Future<Map<String, dynamic>> _fetchBillingStatus() async {
    final raw = await _callRpc(_rpcName, {'p_contract_version': backendRpc});
    final result = RpcResult.fromDynamic(raw);
    // R2-C3: validate the echoed version before any business cast.
    requireEchoedRpcContractVersion(result, sent: backendRpc, current: backendRpc);
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
    final notices =
        (data['notices'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    final showEndedReversed = notices.any(
      (entry) => entry['code']?.toString() == 'ended_reversed',
    );
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

  String? _formatDateTime(BuildContext context, DateTime? value) {
    if (value == null) {
      return null;
    }
    return MaterialLocalizations.of(context).formatMediumDate(value.toLocal());
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
    final l10n = AppLocalizations.of(context)!;
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return _BillingPanel(
        child: Row(
          children: [
            const Icon(Icons.wifi_off_outlined),
            const SizedBox(width: 12),
            Expanded(child: Text(l10n.aiBillingStatusUnavailable)),
            TextButton(onPressed: _load, child: Text(l10n.retry)),
          ],
        ),
      );
    }
    final summary = _summary;
    if (summary == null) {
      return const SizedBox.shrink();
    }
    final hasPlan = summary.planDisplayName != null;
    final endsAt = _formatDateTime(context, summary.endsAt);
    final startsAt = _formatDateTime(context, summary.startsAt);
    final graceEndsAt = _formatDateTime(context, summary.graceEndsAt);
    final textTheme = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_refreshing) ...[
          const LinearProgressIndicator(
            key: Key('billing_summary_refreshing'),
            minHeight: 2,
          ),
          const SizedBox(height: 8),
        ],
        Text(l10n.aiBillingCurrentCoverage, style: textTheme.titleMedium),
        const SizedBox(height: 10),
        _BillingPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    hasPlan ? Icons.verified_outlined : Icons.info_outline,
                    color: hasPlan ? colors.primary : colors.onSurfaceVariant,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          hasPlan
                              ? summary.planDisplayName!
                              : l10n.aiBillingNoActivePlan,
                          style: textTheme.titleSmall,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          hasPlan
                              ? l10n.aiBillingPlanActiveDescription
                              : l10n.aiBillingNoActivePlanDescription,
                          style: textTheme.bodyMedium?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (hasPlan && startsAt != null) ...[
                const SizedBox(height: 16),
                _BillingDetail(label: l10n.aiBillingStarted, value: startsAt),
              ],
              if (hasPlan && endsAt != null) ...[
                const SizedBox(height: 10),
                _BillingDetail(
                  label: l10n.aiBillingRenewsOrEnds,
                  value: endsAt,
                ),
              ],
              if (hasPlan && graceEndsAt != null) ...[
                const SizedBox(height: 10),
                _BillingDetail(
                  label: l10n.aiBillingGraceEnds,
                  value: graceEndsAt,
                ),
              ],
              if (hasPlan && summary.allowance != null) ...[
                const SizedBox(height: 10),
                _BillingDetail(
                  label: l10n.aiBillingCreditsIncluded,
                  value: '${summary.allowance}',
                ),
              ],
              if (hasPlan && summary.used != null) ...[
                const SizedBox(height: 10),
                _BillingDetail(
                  label: l10n.aiBillingCreditsUsed,
                  value: '${summary.used}',
                ),
              ],
              if (summary.subscriptionRef case final reference?) ...[
                const SizedBox(height: 16),
                Divider(height: 1, color: colors.outlineVariant),
                const SizedBox(height: 12),
                Text(
                  l10n.aiBillingSupportReference,
                  style: textTheme.labelMedium,
                ),
                const SizedBox(height: 3),
                SelectableText(
                  reference,
                  style: textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  l10n.aiBillingSupportReferenceDescription,
                  style: textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
              if (summary.showEndedReversed) ...[
                const SizedBox(height: 12),
                Text(
                  l10n.aiBillingEndedReversed,
                  style: textTheme.bodyMedium?.copyWith(color: colors.error),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _BillingPanel extends StatelessWidget {
  const _BillingPanel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.outlineVariant),
      ),
      padding: const EdgeInsets.all(18),
      child: child,
    );
  }
}

class _BillingDetail extends StatelessWidget {
  const _BillingDetail({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      children: [
        Text(label, style: Theme.of(context).textTheme.labelMedium),
        const Spacer(),
        Text(
          value,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
        ),
      ],
    );
  }
}
