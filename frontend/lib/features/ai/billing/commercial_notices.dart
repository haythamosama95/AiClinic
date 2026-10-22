import 'package:ai_clinic/features/ai/billing/abo_client.dart';
import 'package:ai_clinic/features/ai/availability/ai_availability.dart';
import 'package:ai_clinic/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

/// Shows commercial notice codes from `GET /v1/subscription` as localized administrator text.
///
/// R7-UI2: [generation] reloads the notices when the parent's billing read changes; results from an
/// earlier generation are ignored. R7-UI3: wire codes are never printed, unknown codes get the
/// neutral status-unavailable text.
class CommercialNotices extends StatefulWidget {
  const CommercialNotices({
    super.key,
    required this.client,
    this.generation = 0,
  });

  final AboClient client;
  final int generation;

  @override
  State<CommercialNotices> createState() => _CommercialNoticesState();
}

class _CommercialNoticesState extends State<CommercialNotices> {
  var _loading = true;
  List<String> _notices = const [];
  Object? _error;
  var _requestSeq = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant CommercialNotices oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.generation != widget.generation) {
      _load();
    }
  }

  Future<void> _load() async {
    final seq = ++_requestSeq;
    final generation = widget.generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final subscription = await widget.client.getSubscription();
      if (!mounted || seq != _requestSeq || generation != widget.generation) {
        return;
      }
      setState(() {
        _notices = subscription.notices;
        _loading = false;
      });
    } on AboContractVersionUnsupportedException {
      if (!mounted || seq != _requestSeq || generation != widget.generation) {
        return;
      }
      setState(() {
        _error = const ContractVersionUnsupportedException();
        _loading = false;
      });
    } catch (error) {
      if (!mounted || seq != _requestSeq || generation != widget.generation) {
        return;
      }
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(
      key: const Key('billing_commercial_notices'),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: _buildBody(context),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Row(
        children: [
          Expanded(child: Text('$_error')),
          TextButton(
            key: const Key('billing_commercial_notices_retry'),
            onPressed: _load,
            child: Text(l10n.retry),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final notice in _notices) Text(_noticeText(l10n, notice)),
      ],
    );
  }
}

/// R7-UI3: maps the five ABO commercial codes (04 §2.2) to distinct administrator explanations.
String _noticeText(AppLocalizations l10n, String code) {
  return switch (code) {
    'duplicate_payment' => l10n.aiBillingNoticeDuplicatePayment,
    'late_payment_honoured' => l10n.aiBillingNoticeLatePaymentHonoured,
    'payment_withheld' => l10n.aiBillingNoticePaymentWithheld,
    'reversal_recorded' => l10n.aiBillingNoticeReversalRecorded,
    'terms_held' => l10n.aiBillingNoticeTermsHeld,
    _ => l10n.aiNoticeUnavailable,
  };
}
