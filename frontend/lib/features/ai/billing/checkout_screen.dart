import 'dart:async';

import 'package:ai_clinic/core/contract_versions.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/core/ui/components/app_button.dart';
import 'package:ai_clinic/features/ai/billing/abo_client.dart';
import 'package:ai_clinic/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

/// Checkout progress, queued-term notice, polling, and Active refresh.
class CheckoutScreen extends StatefulWidget {
  const CheckoutScreen({
    super.key,
    required this.client,
    this.offer,
    this.termsVersion,
    this.checkoutId,
    this.reference,
    this.supabaseClient,
  });

  final AboClient client;
  final BillingOffer? offer;
  final int? termsVersion;
  final String? checkoutId;
  final String? reference;
  final SupabaseClient? supabaseClient;

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  CheckoutCreateResponse? _createdCheckout;
  CheckoutRead? _checkoutRead;
  var _submitting = false;
  var _pendingLaunch = false;
  var _launched = false;
  var _refreshRequested = false;
  Timer? _pollTimer;
  Object? _error;
  String? _checkoutRequestId;
  int? _displayPriceMinor;

  String? get _checkoutId => widget.checkoutId ?? _createdCheckout?.checkoutId;

  String? get _reference => widget.reference ?? _createdCheckout?.reference ?? _checkoutRead?.reference;

  @override
  void initState() {
    super.initState();
    if (widget.checkoutId != null) {
      _refreshCheckout();
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _refreshCheckout() async {
    final checkoutId = _checkoutId;
    if (checkoutId == null) {
      return;
    }
    try {
      final read = await widget.client.getCheckout(checkoutId);
      if (!mounted) {
        return;
      }
      _applyCheckoutRead(read);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _error = error);
    }
  }

  void _applyCheckoutRead(CheckoutRead read) {
    setState(() {
      _checkoutRead = read;
      _displayPriceMinor = read.offer.chargedPriceMinor;
      _error = null;
    });
    _syncPolling(read.shownState);
    if (read.shownState == CheckoutShownState.active) {
      unawaited(_requestAiStatusRefreshOnce());
    }
  }

  void _syncPolling(CheckoutShownState state) {
    final shouldPoll = state == CheckoutShownState.waiting || state == CheckoutShownState.paid;
    if (shouldPoll) {
      _startPolling();
    } else {
      _pollTimer?.cancel();
      _pollTimer = null;
    }
  }

  void _startPolling() {
    if (_pollTimer != null) {
      return;
    }
    _pollTimer = Timer.periodic(const Duration(seconds: 1), (_) => _refreshCheckout());
  }

  Future<void> _submitCheckout() async {
    if (_pendingLaunch) {
      await _launchPayment();
      return;
    }

    final checkoutId = _checkoutId;
    if (checkoutId != null) {
      if (!_launched && _createdCheckout != null) {
        await _launchPayment();
      }
      return;
    }

    final offer = widget.offer;
    final termsVersion = widget.termsVersion;
    if (offer == null || termsVersion == null) {
      return;
    }

    _checkoutRequestId ??= _newClientRequestId('billing-checkout');
    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final created = await widget.client.createCheckout(
        clientRequestId: _checkoutRequestId!,
        offerId: offer.offerId,
        offerVersion: offer.version,
        termsVersion: termsVersion,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _createdCheckout = created;
        _displayPriceMinor = offer.priceMinor;
        _submitting = false;
      });

      if (created.starts == CheckoutStarts.afterCurrent) {
        setState(() => _pendingLaunch = true);
        return;
      }

      await _launchPayment();
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error;
        _submitting = false;
      });
    }
  }

  Future<void> _launchPayment() async {
    final redirectUrl = _createdCheckout?.redirectUrl;
    if (redirectUrl == null || redirectUrl.isEmpty) {
      return;
    }

    final launched = await launchUrl(
      Uri.parse(redirectUrl),
      mode: LaunchMode.externalApplication,
    );
    if (!launched) {
      if (!mounted) {
        return;
      }
      setState(() => _error = StateError('Could not open payment page'));
      return;
    }

    if (!mounted) {
      return;
    }
    setState(() {
      _pendingLaunch = false;
      _launched = true;
      _checkoutRead = CheckoutRead(
        contractVersion: _createdCheckout!.contractVersion,
        reference: _createdCheckout!.reference,
        shownState: CheckoutShownState.waiting,
        offer: CheckoutOfferSummary(
          offerId: widget.offer!.offerId,
          version: widget.offer!.version,
          termUnit: widget.offer!.termUnit,
          termCount: widget.offer!.termCount,
          chargedPriceMinor: _displayPriceMinor ?? widget.offer!.priceMinor,
          currency: widget.offer!.currency,
        ),
        updatedAt: DateTime.now().toUtc(),
      );
    });
    _startPolling();
    await _refreshCheckout();
  }

  Future<void> _requestAiStatusRefreshOnce() async {
    if (_refreshRequested) {
      return;
    }
    _refreshRequested = true;
    final client = widget.supabaseClient ?? Supabase.instance.client;
    final raw = await client.rpc(
      'request_ai_status_refresh',
      params: {'p_contract_version': backendRpc},
    );
    final result = RpcResult.fromDynamic(raw);
    if (!result.success) {
      throw RpcFailure(result);
    }
  }

  String _shownStateLabel(AppLocalizations l10n, CheckoutShownState state) {
    return switch (state) {
      CheckoutShownState.waiting => l10n.aiBillingCheckoutWaiting,
      CheckoutShownState.failed => l10n.aiBillingCheckoutFailed,
      CheckoutShownState.paid => l10n.aiBillingCheckoutPaid,
      CheckoutShownState.active => l10n.aiBillingCheckoutActive,
      CheckoutShownState.abandoned => l10n.aiBillingCheckoutAbandoned,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final shownState = _checkoutRead?.shownState;
    final showQueuedTerm =
        _pendingLaunch && _createdCheckout?.starts == CheckoutStarts.afterCurrent;

    return KeyedSubtree(
      key: const Key('billing_checkout_screen'),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.aiBillingCheckoutTitle, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 16),
            if (_reference != null)
              Text(
                _reference!,
                key: const Key('billing_checkout_reference'),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            if (_displayPriceMinor != null) ...[
              const SizedBox(height: 8),
              Text('$_displayPriceMinor ${widget.offer?.currency ?? _checkoutRead?.offer.currency ?? ''}'),
            ],
            if (showQueuedTerm) ...[
              const SizedBox(height: 16),
              Text(l10n.aiBillingStartsAfterCurrentTerm),
            ],
            if (shownState != null) ...[
              const SizedBox(height: 16),
              Text(_shownStateLabel(l10n, shownState)),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                '$_error',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const Spacer(),
            AppButton(
              key: const Key('billing_checkout_submit'),
              loading: _submitting,
              disabled: _submitting,
              onPressed: _submitting ? null : () => unawaited(_submitCheckout()),
              child: Text(l10n.aiBillingCheckoutSubmit),
            ),
          ],
        ),
      ),
    );
  }
}

String _newClientRequestId(String prefix) {
  return '$prefix-${DateTime.now().microsecondsSinceEpoch}';
}
