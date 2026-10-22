import 'package:ai_clinic/features/ai/billing/abo_client.dart';
import 'package:ai_clinic/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

/// Shows payment history from `GET /v1/payments` in response order.
class PaymentHistory extends StatefulWidget {
  const PaymentHistory({super.key, required this.client, this.generation = 0});

  final AboClient client;

  /// R7-UI2: the parent's billing-read generation. A change resets the list and cursor and restarts
  /// at the first page.
  final int generation;

  @override
  State<PaymentHistory> createState() => _PaymentHistoryState();
}

class _PaymentHistoryState extends State<PaymentHistory> {
  /// True only until the first load finishes. Later reloads keep the previous rows visible.
  var _loading = true;

  /// True while a reload is in flight (review F4): a small indicator, not a spinner.
  var _refreshing = false;
  var _loadingNextPage = false;
  List<PaymentRecord> _payments = const [];
  String _nextCursor = '';
  var _hasMore = false;
  var _hasLoaded = false;
  Object? _error;

  /// Every first-page or next-page request takes a sequence number. A reply whose number is no
  /// longer current (a reset or a newer request happened meanwhile) is discarded, so an old
  /// in-flight page never appends to the restarted list.
  var _requestSeq = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant PaymentHistory oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.generation != widget.generation) {
      _load();
    }
  }

  Future<void> _load() async {
    final seq = ++_requestSeq;
    final generation = widget.generation;
    // R7-UI2 step 2: the cursor and next-page state reset now, so no stale next page can append.
    // The old rows stay visible until the first page of the new read replaces them (review F4).
    setState(() {
      _loading = !_hasLoaded;
      _refreshing = _hasLoaded;
      _loadingNextPage = false;
      _error = null;
      _nextCursor = '';
      _hasMore = false;
    });
    try {
      final response = await widget.client.getPayments();
      if (!mounted || seq != _requestSeq || generation != widget.generation) {
        return;
      }
      setState(() {
        _payments = response.payments;
        _nextCursor = response.nextCursor;
        _hasMore = response.hasMore;
        _loading = false;
        _refreshing = false;
        _hasLoaded = true;
      });
    } catch (error) {
      if (!mounted || seq != _requestSeq || generation != widget.generation) {
        return;
      }
      setState(() {
        _error = error;
        _payments = const [];
        _loading = false;
        _refreshing = false;
      });
    }
  }

  Future<void> _loadNextPage() async {
    if (!_hasMore || _loadingNextPage) {
      return;
    }
    final seq = ++_requestSeq;
    final generation = widget.generation;
    final cursor = _nextCursor;
    setState(() {
      _loadingNextPage = true;
      _error = null;
    });
    try {
      final response = await widget.client.getPayments(cursor: cursor);
      if (!mounted || seq != _requestSeq || generation != widget.generation) {
        return;
      }
      setState(() {
        _payments = [..._payments, ...response.payments];
        _nextCursor = response.nextCursor;
        _hasMore = response.hasMore;
        _loadingNextPage = false;
      });
    } catch (error) {
      if (!mounted || seq != _requestSeq || generation != widget.generation) {
        return;
      }
      setState(() {
        _error = error;
        _loadingNextPage = false;
      });
    }
  }

  String _formatDateTime(BuildContext context, DateTime value) {
    final local = value.toLocal();
    final materialLocalizations = MaterialLocalizations.of(context);
    return '${materialLocalizations.formatMediumDate(local)} · '
        '${materialLocalizations.formatTimeOfDay(TimeOfDay.fromDateTime(local))}';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return KeyedSubtree(
      key: const Key('billing_payment_history'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
        child: _buildBody(context, l10n),
      ),
    );
  }

  Widget _buildBody(BuildContext context, AppLocalizations l10n) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return _HistoryMessage(
        icon: Icons.cloud_off_outlined,
        text: l10n.aiBillingPaymentHistoryUnavailable,
        action: TextButton.icon(
          onPressed: _load,
          icon: const Icon(Icons.refresh),
          label: Text(l10n.retry),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l10n.aiBillingPaymentHistory, style: textTheme.titleMedium),
        if (_refreshing) ...[
          const SizedBox(height: 8),
          const LinearProgressIndicator(
            key: Key('billing_payment_history_refreshing'),
            minHeight: 2,
          ),
        ],
        const SizedBox(height: 10),
        if (_payments.isEmpty)
          _HistoryMessage(
            icon: Icons.receipt_long_outlined,
            text: l10n.aiBillingNoPaymentsDescription,
            title: l10n.aiBillingNoPayments,
          ),
        for (final payment in _payments) ...[
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            color: colors.surfaceContainerLow,
            child: ListTile(
              leading: Icon(Icons.receipt_long_outlined, color: colors.primary),
              title: Text(payment.planDisplayName),
              subtitle: Text(
                '${_formatDateTime(context, payment.paidAt)} · ${payment.reference}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: Text(
                '${payment.amountMinor} ${payment.currency}',
                style: textTheme.labelLarge,
              ),
            ),
          ),
        ],
        if (_hasMore) ...[
          const SizedBox(height: 8),
          TextButton(
            key: const Key('billing_payment_history_next'),
            onPressed: _loadingNextPage ? null : _loadNextPage,
            child: _loadingNextPage
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(l10n.aiBillingPaymentsLoadMore),
          ),
        ],
      ],
    );
  }
}

class _HistoryMessage extends StatelessWidget {
  const _HistoryMessage({
    required this.icon,
    required this.text,
    this.title,
    this.action,
  });

  final IconData icon;
  final String text;
  final String? title;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(icon, color: colors.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != null) Text(title!, style: textTheme.titleSmall),
                Text(
                  text,
                  style: textTheme.bodyMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          ?action,
        ],
      ),
    );
  }
}
