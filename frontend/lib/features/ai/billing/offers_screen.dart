import 'package:ai_clinic/core/ui/components/app_button.dart';
import 'package:ai_clinic/features/ai/billing/abo_client.dart';
import 'package:ai_clinic/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

/// Selected offer and accepted terms passed to the billing-contact step.
class BillingOffersSelection {
  const BillingOffersSelection({
    required this.offer,
    required this.termsVersion,
  });

  final BillingOffer offer;
  final int termsVersion;
}

/// Shows sellable offers, terms text, and terms acceptance before checkout.
class OffersScreen extends StatefulWidget {
  const OffersScreen({
    super.key,
    required this.client,
    required this.onContinue,
    this.onContractVersionUnsupported,
    this.loadError,
  });

  final AboClient client;
  final ValueChanged<BillingOffersSelection> onContinue;
  final VoidCallback? onContractVersionUnsupported;
  final Object? loadError;

  @override
  State<OffersScreen> createState() => _OffersScreenState();
}

class _OffersScreenState extends State<OffersScreen> {
  BillingOffersResponse? _response;
  BillingOffer? _selectedOffer;
  var _termsAccepted = false;
  var _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    if (widget.loadError != null) {
      _error = widget.loadError;
      _loading = false;
    } else {
      _loadOffers();
    }
  }

  Future<void> _loadOffers() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await widget.client.getOffers();
      if (!mounted) {
        return;
      }
      setState(() {
        _response = response;
        _selectedOffer = response.offers.isNotEmpty ? response.offers.first : null;
        _loading = false;
      });
    } on AboContractVersionUnsupportedException {
      if (!mounted) {
        return;
      }
      widget.onContractVersionUnsupported?.call();
      setState(() => _loading = false);
    } on AboTermsNotAcceptedException {
      if (!mounted) {
        return;
      }
      setState(() {
        _termsAccepted = false;
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

  void _handleContinue() {
    final offer = _selectedOffer;
    if (offer == null || !_termsAccepted) {
      return;
    }
    widget.onContinue(
      BillingOffersSelection(
        offer: offer,
        termsVersion: offer.terms.version,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final locale = Localizations.localeOf(context).languageCode;

    return KeyedSubtree(
      key: const Key('billing_offers_screen'),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.aiBillingOffersTitle, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(l10n.aiBillingOffersDescription),
            const SizedBox(height: 24),
            if (_loading)
              const Expanded(child: Center(child: CircularProgressIndicator()))
            else if (_error != null)
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('$_error'),
                      const SizedBox(height: 12),
                      AppButton(onPressed: _loadOffers, child: Text(l10n.retry)),
                    ],
                  ),
                ),
              )
            else
              Expanded(
                child: ListView(
                  children: [
                    for (final offer in _response?.offers ?? const <BillingOffer>[])
                      _OfferCard(
                        offer: offer,
                        locale: locale,
                        selected: _selectedOffer?.offerId == offer.offerId,
                        onSelected: () => setState(() => _selectedOffer = offer),
                      ),
                    if (_selectedOffer != null) ...[
                      const SizedBox(height: 24),
                      Text(l10n.aiBillingTermsTitle, style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 8),
                      Text(_selectedOffer!.terms.text),
                      const SizedBox(height: 16),
                      CheckboxListTile(
                        key: const Key('billing_accept_terms'),
                        value: _termsAccepted,
                        onChanged: (value) => setState(() => _termsAccepted = value ?? false),
                        title: Text(l10n.aiBillingAcceptTerms),
                        controlAffinity: ListTileControlAffinity.leading,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ],
                  ],
                ),
              ),
            const SizedBox(height: 16),
            AppButton(
              key: const Key('billing_continue'),
              onPressed: _termsAccepted && _selectedOffer != null ? _handleContinue : null,
              disabled: !_termsAccepted || _selectedOffer == null || _loading,
              child: Text(l10n.aiBillingContinue),
            ),
          ],
        ),
      ),
    );
  }
}

class _OfferCard extends StatelessWidget {
  const _OfferCard({
    required this.offer,
    required this.locale,
    required this.selected,
    required this.onSelected,
  });

  final BillingOffer offer;
  final String locale;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    final copy = offer.copy.locale(locale) ?? offer.copy.locale('en');
    final title = copy?.name ?? offer.planDisplayName;
    final summary = copy?.summary ?? offer.planDisplayName;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onSelected,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Radio<String>(
                value: offer.offerId,
                groupValue: selected ? offer.offerId : null,
                onChanged: (_) => onSelected(),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(summary),
                    const SizedBox(height: 8),
                    Text('${offer.priceMinor} ${offer.currency}'),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
