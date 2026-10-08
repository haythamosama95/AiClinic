import 'dart:async';

import 'package:ai_clinic/core/contract_versions.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/core/ui/components/app_button.dart';
import 'package:ai_clinic/features/ai/billing/abo_client.dart';
import 'package:ai_clinic/features/ai/degraded/ai_degraded_mode.dart';
import 'package:ai_clinic/features/ai/degraded/ai_degraded_view.dart';
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
    this.initialCheckout,
    this.supabaseClient,
    this.onTermsNotAccepted,
    this.onBillingContactRequired,
    this.onContractVersionUnsupported,
  });

  final AboClient client;
  final BillingOffer? offer;
  final int? termsVersion;
  final String? checkoutId;
  final String? reference;
  final CheckoutRead? initialCheckout;
  final SupabaseClient? supabaseClient;
  final VoidCallback? onTermsNotAccepted;
  final VoidCallback? onBillingContactRequired;
  final VoidCallback? onContractVersionUnsupported;

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
  var _showAppUpdate = false;
  Timer? _pollTimer;
  String? _errorMessage;
  String? _checkoutRequestId;
  int? _displayPriceMinor;
  int? _offerVersionOverride;
  String? _resolvedCheckoutId;

  BillingOffer? get _offer => widget.offer;

  int? get _termsVersion => widget.termsVersion;

  String? get _checkoutId => _resolvedCheckoutId ?? widget.checkoutId ?? _createdCheckout?.checkoutId;

  String? get _reference =>
      widget.reference ?? _createdCheckout?.reference ?? _checkoutRead?.reference;

  @override
  void initState() {
    super.initState();
    if (widget.initialCheckout != null) {
      _checkoutRead = widget.initialCheckout;
      _displayPriceMinor = widget.initialCheckout!.offer.chargedPriceMinor;
      _syncPolling(widget.initialCheckout!.shownState);
    } else if (widget.checkoutId != null) {
      unawaited(_refreshCheckout());
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _refreshCheckout() async {
    try {
      final read = await _readCheckoutState();
      if (!mounted || read == null) {
        return;
      }
      _applyCheckoutRead(read);
    } on AboContractVersionUnsupportedException {
      if (!mounted) {
        return;
      }
      _showContractVersionUnsupported();
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _errorMessage = '$error');
    }
  }

  Future<CheckoutRead?> _readCheckoutState() async {
    final checkoutId = _checkoutId;
    if (checkoutId != null) {
      return widget.client.getCheckout(checkoutId);
    }

    final reference = _reference;
    if (reference == null) {
      return null;
    }

    final open = await widget.client.listOpenCheckouts();
    for (final checkout in open.checkouts) {
      if (checkout.reference == reference) {
        return checkout;
      }
    }
    return null;
  }

  void _applyCheckoutRead(CheckoutRead read) {
    setState(() {
      _checkoutRead = read;
      _displayPriceMinor = read.offer.chargedPriceMinor;
      _errorMessage = null;
    });
    _syncPolling(read.shownState);
    if (read.shownState == CheckoutShownState.active) {
      unawaited(_requestAiStatusRefreshOnce());
    }
  }

  void _syncPolling(CheckoutShownState state) {
    final shouldPoll = state == CheckoutShownState.waiting ||
        state == CheckoutShownState.paid ||
        state == CheckoutShownState.failed;
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

  void _showContractVersionUnsupported() {
    widget.onContractVersionUnsupported?.call();
    setState(() => _showAppUpdate = true);
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

    final offer = _offer;
    final termsVersion = _termsVersion;
    if (offer == null || termsVersion == null) {
      return;
    }

    _checkoutRequestId ??= _newClientRequestId('billing-checkout');
    setState(() {
      _submitting = true;
      _errorMessage = null;
    });

    try {
      final created = await widget.client.createCheckout(
        clientRequestId: _checkoutRequestId!,
        offerId: offer.offerId,
        offerVersion: _offerVersionOverride ?? offer.version,
        termsVersion: termsVersion,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _createdCheckout = created;
        _resolvedCheckoutId = created.checkoutId;
        _displayPriceMinor = offer.priceMinor;
        _submitting = false;
      });

      if (created.starts == CheckoutStarts.afterCurrent) {
        setState(() => _pendingLaunch = true);
        return;
      }

      await _launchPayment();
    } on AboOfferUnavailableException {
      await _handleOfferUnavailable(offer);
    } on AboBillingContactRequiredException {
      if (!mounted) {
        return;
      }
      setState(() => _submitting = false);
      widget.onBillingContactRequired?.call();
    } on AboTermsNotAcceptedException {
      if (!mounted) {
        return;
      }
      setState(() => _submitting = false);
      widget.onTermsNotAccepted?.call();
    } on AboProviderUnavailableException catch (error) {
      if (!mounted) {
        return;
      }
      final l10n = AppLocalizations.of(context)!;
      setState(() {
        _resolvedCheckoutId = error.checkoutId ?? _resolvedCheckoutId;
        _errorMessage = l10n.aiBillingErrorProviderUnavailable;
        _submitting = false;
      });
    } on AboRateLimitedException {
      if (!mounted) {
        return;
      }
      final l10n = AppLocalizations.of(context)!;
      setState(() {
        _errorMessage = l10n.aiBillingErrorRateLimited;
        _submitting = false;
      });
    } on AboContractVersionUnsupportedException {
      if (!mounted) {
        return;
      }
      setState(() => _submitting = false);
      _showContractVersionUnsupported();
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = '$error';
        _submitting = false;
      });
    }
  }

  Future<void> _handleOfferUnavailable(BillingOffer offer) async {
    final l10n = AppLocalizations.of(context)!;
    try {
      final offers = await widget.client.getOffers();
      if (!mounted) {
        return;
      }
      BillingOffer? updated;
      for (final entry in offers.offers) {
        if (entry.offerId == offer.offerId) {
          updated = entry;
          break;
        }
      }
      updated ??= offers.offers.isNotEmpty ? offers.offers.first : null;
      setState(() {
        _errorMessage = l10n.aiBillingErrorOfferUnavailable;
        _displayPriceMinor = updated?.priceMinor ?? offer.priceMinor;
        _offerVersionOverride = updated?.version ?? offer.version;
        _submitting = false;
      });
    } on AboContractVersionUnsupportedException {
      if (!mounted) {
        return;
      }
      setState(() => _submitting = false);
      _showContractVersionUnsupported();
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = l10n.aiBillingErrorOfferUnavailable;
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
      setState(() => _errorMessage = 'Could not open payment page');
      return;
    }

    if (!mounted) {
      return;
    }
    final offer = _offer;
    setState(() {
      _pendingLaunch = false;
      _launched = true;
      _checkoutRead = CheckoutRead(
        contractVersion: _createdCheckout!.contractVersion,
        reference: _createdCheckout!.reference,
        shownState: CheckoutShownState.waiting,
        offer: CheckoutOfferSummary(
          offerId: offer?.offerId ?? _checkoutRead?.offer.offerId ?? '',
          version: _offerVersionOverride ?? offer?.version ?? _checkoutRead?.offer.version ?? 0,
          termUnit: offer?.termUnit ?? _checkoutRead?.offer.termUnit ?? '',
          termCount: offer?.termCount ?? _checkoutRead?.offer.termCount ?? 0,
          chargedPriceMinor: _displayPriceMinor ?? offer?.priceMinor ?? _checkoutRead?.offer.chargedPriceMinor ?? 0,
          currency: offer?.currency ?? _checkoutRead?.offer.currency ?? '',
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
    if (_showAppUpdate) {
      return const AiDegradedView(mode: AiDegradedMode.appUpdate);
    }

    final l10n = AppLocalizations.of(context)!;
    final shownState = _checkoutRead?.shownState;
    final showQueuedTerm =
        _pendingLaunch && _createdCheckout?.starts == CheckoutStarts.afterCurrent;
    final currency = _offer?.currency ?? _checkoutRead?.offer.currency ?? '';

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
              Text('$_displayPriceMinor $currency'),
            ],
            if (showQueuedTerm) ...[
              const SizedBox(height: 16),
              Text(l10n.aiBillingStartsAfterCurrentTerm),
            ],
            if (shownState != null) ...[
              const SizedBox(height: 16),
              Text(_shownStateLabel(l10n, shownState)),
            ],
            if (_errorMessage != null) ...[
              const SizedBox(height: 12),
              Text(
                _errorMessage!,
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
