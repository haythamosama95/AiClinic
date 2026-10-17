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
        _selectedOffer = response.offers.isNotEmpty
            ? response.offers.first
            : null;
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
      BillingOffersSelection(offer: offer, termsVersion: offer.terms.version),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final locale = Localizations.localeOf(context).languageCode;

    return KeyedSubtree(
      key: const Key('billing_offers_screen'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 18),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              _OffersMessage(
                icon: Icons.cloud_off_outlined,
                title: l10n.aiBillingOffersUnavailable,
                description: l10n.aiBillingOffersUnavailableDescription,
                action: TextButton.icon(
                  onPressed: _loadOffers,
                  icon: const Icon(Icons.refresh),
                  label: Text(l10n.retry),
                ),
              )
            else if (_response?.offers.isEmpty ?? true)
              _OffersMessage(
                icon: Icons.auto_awesome_outlined,
                title: l10n.aiBillingOffersEmptyTitle,
                description: l10n.aiBillingOffersEmpty,
                action: TextButton.icon(
                  onPressed: _loadOffers,
                  icon: const Icon(Icons.refresh),
                  label: Text(l10n.aiBillingRefreshPlans),
                ),
              )
            else
              ListView(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  for (final offer
                      in _response?.offers ?? const <BillingOffer>[])
                    _OfferCard(
                      offer: offer,
                      locale: locale,
                      selected: _selectedOffer?.offerId == offer.offerId,
                      onSelected: () => setState(() => _selectedOffer = offer),
                    ),
                  if (_selectedOffer != null) ...[
                    const SizedBox(height: 24),
                    Text(
                      l10n.aiBillingTermsTitle,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(_selectedOffer!.terms.text),
                    const SizedBox(height: 16),
                    CheckboxListTile(
                      key: const Key('billing_accept_terms'),
                      value: _termsAccepted,
                      onChanged: (value) =>
                          setState(() => _termsAccepted = value ?? false),
                      title: Text(l10n.aiBillingAcceptTerms),
                      controlAffinity: ListTileControlAffinity.leading,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ],
                ],
              ),
            if ((_response?.offers.isNotEmpty ?? false) && !_loading) ...[
              const SizedBox(height: 16),
              AppButton(
                key: const Key('billing_continue'),
                onPressed: _termsAccepted && _selectedOffer != null
                    ? _handleContinue
                    : null,
                disabled: !_termsAccepted || _selectedOffer == null,
                child: Text(l10n.aiBillingContinue),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _OffersMessage extends StatelessWidget {
  const _OffersMessage({
    required this.icon,
    required this.title,
    required this.description,
    required this.action,
  });

  final IconData icon;
  final String title;
  final String description;
  final Widget action;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: colors.primary),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: textTheme.titleSmall),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: textTheme.bodyMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 6),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: action,
                ),
              ],
            ),
          ),
        ],
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
              RadioGroup<String>(
                groupValue: selected ? offer.offerId : null,
                onChanged: (_) => onSelected(),
                child: Radio<String>(value: offer.offerId),
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
