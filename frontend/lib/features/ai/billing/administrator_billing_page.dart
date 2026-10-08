import 'dart:async';

import 'package:ai_clinic/features/ai/billing/abo_client.dart';
import 'package:ai_clinic/features/ai/billing/billing_contact_form.dart';
import 'package:ai_clinic/features/ai/billing/billing_token_client.dart';
import 'package:ai_clinic/features/ai/billing/checkout_screen.dart';
import 'package:ai_clinic/features/ai/billing/offers_screen.dart';
import 'package:ai_clinic/features/ai/degraded/ai_degraded_mode.dart';
import 'package:ai_clinic/features/ai/degraded/ai_degraded_view.dart';
import 'package:ai_clinic/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum _BillingStep { loading, offers, contact, checkout, appUpdate }

/// Administrator billing flow: resume open checkouts or offers → contact → checkout.
class AdministratorBillingPage extends StatefulWidget {
  const AdministratorBillingPage({super.key, this.supabaseClient});

  final SupabaseClient? supabaseClient;

  @override
  State<AdministratorBillingPage> createState() => _AdministratorBillingPageState();
}

class _AdministratorBillingPageState extends State<AdministratorBillingPage> {
  late final BillingTokenClient _tokenClient;
  late final AboClient _aboClient;

  _BillingStep _step = _BillingStep.loading;
  BillingOffersSelection? _selection;
  CheckoutRead? _resumedCheckout;
  Object? _loadError;

  @override
  void initState() {
    super.initState();
    _tokenClient = BillingTokenClient(client: widget.supabaseClient);
    _aboClient = AboClient(tokenClient: _tokenClient);
    unawaited(_bootstrap());
  }

  @override
  void dispose() {
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

  void _onBillingContactRequired() {
    setState(() => _step = _BillingStep.contact);
  }

  void _onContractVersionUnsupported() {
    setState(() => _step = _BillingStep.appUpdate);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.aiBillingOffersTitle)),
      body: switch (_step) {
        _BillingStep.loading => const Center(child: CircularProgressIndicator()),
        _BillingStep.appUpdate => const AiDegradedView(mode: AiDegradedMode.appUpdate),
        _BillingStep.offers => OffersScreen(
            client: _aboClient,
            onContinue: _onOffersContinue,
            onContractVersionUnsupported: _onContractVersionUnsupported,
            loadError: _loadError,
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
            supabaseClient: widget.supabaseClient,
            onTermsNotAccepted: _onTermsNotAccepted,
            onBillingContactRequired: _onBillingContactRequired,
            onContractVersionUnsupported: _onContractVersionUnsupported,
          ),
      },
    );
  }
}
