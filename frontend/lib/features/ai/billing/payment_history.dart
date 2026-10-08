import 'package:ai_clinic/features/ai/billing/abo_client.dart';
import 'package:flutter/material.dart';

/// Shows payment history from `GET /v1/payments` in response order.
class PaymentHistory extends StatefulWidget {
  const PaymentHistory({
    super.key,
    required this.client,
  });

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

  String _formatDateTime(DateTime value) {
    return value.toUtc().toIso8601String();
  }

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(
      key: const Key('billing_payment_history'),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Payment history', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 16),
        for (final payment in _payments) ...[
          Text(payment.reference),
          Text(_formatDateTime(payment.paidAt)),
          Text('${payment.amountMinor}'),
          Text(payment.currency),
          Text(payment.planDisplayName),
          Text('${payment.offerVersion}'),
          Text(payment.termUnit),
          Text('${payment.termCount}'),
          Text(payment.classification.wireValue),
          for (final reversal in payment.reversals) ...[
            Text(reversal.reference),
            Text('${reversal.amountMinor}'),
            Text(reversal.kind.wireValue),
            Text('${reversal.isFull}'),
          ],
          const SizedBox(height: 12),
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
                : const Text('Next page'),
          ),
        ],
      ],
    );
  }
}
