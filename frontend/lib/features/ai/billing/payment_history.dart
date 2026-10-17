import 'package:ai_clinic/features/ai/billing/abo_client.dart';
import 'package:ai_clinic/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

/// Shows payment history from `GET /v1/payments` in response order.
class PaymentHistory extends StatefulWidget {
  const PaymentHistory({super.key, required this.client});

  final AboClient client;

  @override
  State<PaymentHistory> createState() => _PaymentHistoryState();
}

class _PaymentHistoryState extends State<PaymentHistory> {
  var _loading = true;
  var _loadingNextPage = false;
  List<PaymentRecord> _payments = const [];
  String _nextCursor = '';
  var _hasMore = false;
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
      final response = await widget.client.getPayments();
      if (!mounted) {
        return;
      }
      setState(() {
        _payments = response.payments;
        _nextCursor = response.nextCursor;
        _hasMore = response.hasMore;
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

  Future<void> _loadNextPage() async {
    if (!_hasMore || _loadingNextPage) {
      return;
    }
    setState(() {
      _loadingNextPage = true;
      _error = null;
    });
    try {
      final response = await widget.client.getPayments(cursor: _nextCursor);
      if (!mounted) {
        return;
      }
      setState(() {
        _payments = [..._payments, ...response.payments];
        _nextCursor = response.nextCursor;
        _hasMore = response.hasMore;
        _loadingNextPage = false;
      });
    } catch (error) {
      if (!mounted) {
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
