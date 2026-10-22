import 'dart:async';

import 'package:ai_clinic/core/contract_version_guard.dart';
import 'package:ai_clinic/core/contract_versions.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/core/ui/components/app_page_header.dart';
import 'package:ai_clinic/features/ai/billing/abo_client.dart';
import 'package:ai_clinic/features/ai/billing/billing_contact_form.dart';
import 'package:ai_clinic/features/ai/billing/billing_token_client.dart';
import 'package:ai_clinic/features/ai/billing/checkout_screen.dart';
import 'package:ai_clinic/features/ai/billing/commercial_notices.dart';
import 'package:ai_clinic/features/ai/billing/offers_screen.dart';
import 'package:ai_clinic/features/ai/billing/payment_history.dart';
import 'package:ai_clinic/features/ai/billing/subscription_summary.dart';
import 'package:ai_clinic/features/ai/degraded/ai_degraded_mode.dart';
import 'package:ai_clinic/features/ai/degraded/ai_degraded_view.dart';
import 'package:ai_clinic/features/ai/availability/ai_availability.dart';
import 'package:ai_clinic/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum _BillingStep { loading, offers, contact, checkout, appUpdate }

/// R7-UI2: projection catch-up after a checkout reaches Active.
enum _ProjectionStatus { idle, pending, pullFailed, caughtUp }

/// R7-UI2 step 3: at most four rereads, 30 seconds apart, so the last one lands within two minutes.
const _projectionRereadInterval = Duration(seconds: 30);
const _projectionMaxRereads = 4;

/// Administrator billing flow: resume open checkouts or offers → contact → checkout.
///
/// R7-UI2: owns one billing-read generation. Every sibling read (subscription summary, commercial
/// notices, payment history) reloads when the generation changes. The checkout reports state changes
/// here; Paid and Active bump the generation, and Active also starts the backend projection pull.
class AdministratorBillingPage extends StatefulWidget {
  const AdministratorBillingPage({
    super.key,
    this.supabaseClient,
    @visibleForTesting this.rpc,
    @visibleForTesting this.tokenClient,
    @visibleForTesting this.aboClient,
  });

  final SupabaseClient? supabaseClient;

  /// Test seams: injected RPC callable and clients. Production leaves them null.
  final SubscriptionSummaryRpcInvoke? rpc;
  final BillingTokenClient? tokenClient;
  final AboClient? aboClient;

  @override
  State<AdministratorBillingPage> createState() =>
      _AdministratorBillingPageState();
}

class _AdministratorBillingPageState extends State<AdministratorBillingPage> {
  late final BillingTokenClient _tokenClient;
  late final AboClient _aboClient;

  _BillingStep _step = _BillingStep.loading;
  BillingOffersSelection? _selection;
  CheckoutRead? _resumedCheckout;
  Object? _loadError;

  /// Shared billing-read generation for the sibling reads.
  int _billingGeneration = 0;

  /// Generation issued by the latest bounded reread. Only a summary read at this generation may
  /// confirm the projection, because it was issued after the pull request succeeded.
  int _chainGeneration = -1;
  var _projectionStatus = _ProjectionStatus.idle;
  var _projectionEpoch = 0;
  var _projectionRereads = 0;
  String? _projectionReference;
  Timer? _projectionTimer;

  @override
  void initState() {
    super.initState();
    _tokenClient = widget.tokenClient ?? BillingTokenClient(client: widget.supabaseClient);
    _aboClient = widget.aboClient ?? AboClient(tokenClient: _tokenClient);
    unawaited(_bootstrap());
  }

  @override
  void dispose() {
    _projectionTimer?.cancel();
    _tokenClient.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    try {
      await _tokenClient.ensureToken();
      final open = await _aboClient.listOpenCheckouts();
      if (!mounted) {
        return;
      }
      if (open.checkouts.isNotEmpty) {
        setState(() {
          _resumedCheckout = open.checkouts.first;
          _step = _BillingStep.checkout;
        });
        return;
      }
      setState(() => _step = _BillingStep.offers);
    } on AboContractVersionUnsupportedException {
      if (!mounted) {
        return;
      }
      setState(() => _step = _BillingStep.appUpdate);
    } on ContractVersionUnsupportedException {
      if (!mounted) {
        return;
      }
      setState(() => _step = _BillingStep.appUpdate);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loadError = error;
        _step = _BillingStep.offers;
      });
    }
  }

  void _onOffersContinue(BillingOffersSelection selection) {
    setState(() {
      _selection = selection;
      _resumedCheckout = null;
      _step = _BillingStep.contact;
    });
  }

  void _onContactSaved(BillingContact contact) {
    setState(() {
      _resumedCheckout = null;
      _step = _BillingStep.checkout;
    });
  }

  void _onTermsNotAccepted() {
    setState(() {
      _selection = null;
      _resumedCheckout = null;
      _step = _BillingStep.offers;
    });
  }

  void _onOfferUnavailable() {
    setState(() {
      _selection = null;
      _resumedCheckout = null;
      _step = _BillingStep.offers;
    });
  }

  void _onBillingContactRequired() {
    setState(() => _step = _BillingStep.contact);
  }

  void _onContractVersionUnsupported() {
    setState(() => _step = _BillingStep.appUpdate);
  }

  void _bumpBillingGeneration() {
    if (!mounted) {
      return;
    }
    setState(() => _billingGeneration++);
  }

  /// R7-UI2 step 1: a checkout read changed state. Paid and Active refresh the siblings immediately.
  /// This never creates a checkout or changes the checkout's idempotency key.
  void _onCheckoutStateChanged(CheckoutRead read) {
    final state = read.shownState;
    if (state == CheckoutShownState.paid || state == CheckoutShownState.active) {
      _bumpBillingGeneration();
    }
    if (state == CheckoutShownState.active) {
      unawaited(_startProjectionCatchUp(read.reference));
    }
  }

  /// R7-UI2 step 3: requests the backend pull, then rereads at most four times. A new call replaces
  /// any earlier catch-up through the epoch.
  Future<void> _startProjectionCatchUp(String reference) async {
    final epoch = ++_projectionEpoch;
    _projectionTimer?.cancel();
    _projectionTimer = null;
    _projectionReference = reference;
    _projectionRereads = 0;
    _chainGeneration = -1;
    if (mounted) {
      setState(() => _projectionStatus = _ProjectionStatus.pending);
    }
    final requested = await _requestAiStatusPull();
    if (!mounted || epoch != _projectionEpoch) {
      return;
    }
    if (!requested) {
      setState(() => _projectionStatus = _ProjectionStatus.pullFailed);
      return;
    }
    _scheduleProjectionReread(epoch, reference, _billingGeneration);
  }

  void _scheduleProjectionReread(int epoch, String reference, int generation) {
    if (_projectionRereads >= _projectionMaxRereads) {
      // Still pending: the status message stays and manual refresh remains available.
      return;
    }
    _projectionTimer = Timer(_projectionRereadInterval, () {
      _projectionTimer = null;
      // Reject a retry whose epoch, identity or billing-read generation no longer matches.
      if (!mounted ||
          epoch != _projectionEpoch ||
          reference != _projectionReference ||
          generation != _billingGeneration) {
        return;
      }
      _projectionRereads++;
      setState(() {
        _billingGeneration++;
        _chainGeneration = _billingGeneration;
      });
      _scheduleProjectionReread(epoch, reference, _billingGeneration);
    });
  }

  /// Returns false when the pull could not be requested or the reply is not a success.
  Future<bool> _requestAiStatusPull() async {
    try {
      final raw = await _callRpc('request_ai_status_refresh', {'p_contract_version': backendRpc});
      final result = RpcResult.fromDynamic(raw);
      // R2-C3: an unversioned or mismatched refresh reply never counts as success.
      requireEchoedRpcContractVersion(result, sent: backendRpc, current: backendRpc);
      return result.success;
    } catch (_) {
      return false;
    }
  }

  Future<dynamic> _callRpc(String functionName, Map<String, dynamic> params) {
    final rpc = widget.rpc;
    if (rpc != null) {
      return rpc(functionName, params);
    }
    final client = widget.supabaseClient ?? Supabase.instance.client;
    return client.rpc(functionName, params: params);
  }

  /// Confirms the projection only for a summary read issued after the pull (see [_chainGeneration]).
  void _onSubscriptionLoaded(SubscriptionSummaryData data) {
    if (_projectionStatus != _ProjectionStatus.pending) {
      return;
    }
    if (_chainGeneration != _billingGeneration || data.planDisplayName == null) {
      return;
    }
    _projectionTimer?.cancel();
    _projectionTimer = null;
    setState(() => _projectionStatus = _ProjectionStatus.caughtUp);
  }

  /// Manual refresh: re-reads every sibling. A pending or failed pull is requested again.
  void _onRefreshBilling() {
    final reference = _projectionReference;
    if (reference != null &&
        (_projectionStatus == _ProjectionStatus.pending ||
            _projectionStatus == _ProjectionStatus.pullFailed)) {
      unawaited(_startProjectionCatchUp(reference));
    }
    _bumpBillingGeneration();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppPageHeader(
          title: l10n.aiBillingOffersTitle,
          description: l10n.aiBillingOffersDescription,
        ),
        const SizedBox(height: 20),
        if (_step == _BillingStep.appUpdate)
          const AiDegradedView(mode: AiDegradedMode.appUpdate)
        else ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton.icon(
                key: const Key('billing_refresh'),
                onPressed: _onRefreshBilling,
                icon: const Icon(Icons.refresh),
                label: Text(l10n.aiBillingRefresh),
              ),
            ),
          ),
          if (_projectionStatus == _ProjectionStatus.pending)
            _ProjectionNotice(
              key: const Key('billing_projection_pending'),
              text: l10n.aiBillingProjectionPending,
            ),
          if (_projectionStatus == _ProjectionStatus.pullFailed)
            _ProjectionNotice(
              key: const Key('billing_projection_pull_failed'),
              text: l10n.aiBillingProjectionPullFailed,
              isError: true,
            ),
          SubscriptionSummary(
            client: _aboClient,
            supabaseClient: widget.supabaseClient,
            rpc: widget.rpc,
            generation: _billingGeneration,
            onLoaded: _onSubscriptionLoaded,
          ),
          CommercialNotices(
            client: _aboClient,
            generation: _billingGeneration,
          ),
          switch (_step) {
            _BillingStep.loading => const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
            _BillingStep.offers => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 22, 24, 0),
                  child: Text(
                    l10n.aiBillingAvailablePlans,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                OffersScreen(
                  key: ValueKey(_step),
                  client: _aboClient,
                  onContinue: _onOffersContinue,
                  onContractVersionUnsupported: _onContractVersionUnsupported,
                  loadError: _loadError,
                ),
              ],
            ),
            _BillingStep.contact => BillingContactForm(
              client: _aboClient,
              onSaved: _onContactSaved,
              onContractVersionUnsupported: _onContractVersionUnsupported,
            ),
            _BillingStep.checkout => CheckoutScreen(
              client: _aboClient,
              offer: _selection?.offer,
              termsVersion: _selection?.termsVersion,
              initialCheckout: _resumedCheckout,
              reference: _resumedCheckout?.reference,
              onCheckoutStateChanged: _onCheckoutStateChanged,
              onTermsNotAccepted: _onTermsNotAccepted,
              onOfferUnavailable: _onOfferUnavailable,
              onBillingContactRequired: _onBillingContactRequired,
              onContractVersionUnsupported: _onContractVersionUnsupported,
            ),
            _ => const SizedBox.shrink(),
          },
          PaymentHistory(
            client: _aboClient,
            generation: _billingGeneration,
          ),
        ],
      ],
    );
  }
}

class _ProjectionNotice extends StatelessWidget {
  const _ProjectionNotice({super.key, required this.text, this.isError = false});

  final String text;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: isError ? colors.error : colors.onSurfaceVariant,
        ),
      ),
    );
  }
}
