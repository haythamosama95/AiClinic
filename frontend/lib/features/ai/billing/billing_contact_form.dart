import 'package:ai_clinic/core/ui/components/app_button.dart';
import 'package:ai_clinic/features/ai/billing/abo_client.dart';
import 'package:ai_clinic/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

/// Reads and saves the clinic billing contact before checkout.
class BillingContactForm extends StatefulWidget {
  const BillingContactForm({
    super.key,
    required this.client,
    required this.onSaved,
    this.onContractVersionUnsupported,
  });

  final AboClient client;
  final ValueChanged<BillingContact> onSaved;
  final VoidCallback? onContractVersionUnsupported;

  @override
  State<BillingContactForm> createState() => _BillingContactFormState();
}

class _BillingContactFormState extends State<BillingContactForm> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();

  var _loading = true;
  var _saving = false;
  Object? _error;
  String? _saveRequestId;

  @override
  void initState() {
    super.initState();
    _loadContact();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _loadContact() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await widget.client.getBillingContact();
      if (!mounted) {
        return;
      }
      switch (result) {
        case BillingContactFound(:final contact):
          _nameController.text = contact.name;
          _emailController.text = contact.email;
          _phoneController.text = contact.phone;
        case BillingContactMissing():
          _nameController.clear();
          _emailController.clear();
          _phoneController.clear();
      }
      setState(() => _loading = false);
    } on AboContractVersionUnsupportedException {
      if (!mounted) {
        return;
      }
      widget.onContractVersionUnsupported?.call();
      setState(() => _loading = false);
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

  Future<void> _saveContact() async {
    _saveRequestId ??= _newClientRequestId('billing-contact');
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final contact = await widget.client.putBillingContact(
        clientRequestId: _saveRequestId!,
        name: _nameController.text.trim(),
        email: _emailController.text.trim(),
        phone: _phoneController.text.trim(),
      );
      if (!mounted) {
        return;
      }
      setState(() => _saving = false);
      widget.onSaved(contact);
    } on AboBillingContactRequiredException {
      if (!mounted) {
        return;
      }
      final l10n = AppLocalizations.of(context)!;
      setState(() {
        _error = l10n.aiBillingErrorBillingContactRequired;
        _saving = false;
      });
    } on AboContractVersionUnsupportedException {
      if (!mounted) {
        return;
      }
      widget.onContractVersionUnsupported?.call();
      setState(() => _saving = false);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error;
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return KeyedSubtree(
      key: const Key('billing_contact_form'),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.aiBillingContactTitle, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 24),
            if (_loading)
              const Expanded(child: Center(child: CircularProgressIndicator()))
            else ...[
              TextField(
                key: const Key('billing_contact_name'),
                controller: _nameController,
                decoration: InputDecoration(labelText: l10n.aiBillingContactName),
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 16),
              TextField(
                key: const Key('billing_contact_email'),
                controller: _emailController,
                decoration: InputDecoration(labelText: l10n.aiBillingContactEmail),
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 16),
              TextField(
                key: const Key('billing_contact_phone'),
                controller: _phoneController,
                decoration: InputDecoration(labelText: l10n.aiBillingContactPhone),
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.done,
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  '$_error',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
            const Spacer(),
            AppButton(
              key: const Key('billing_contact_save'),
              loading: _saving,
              disabled: _loading || _saving,
              onPressed: _loading || _saving ? null : _saveContact,
              child: Text(l10n.aiBillingContactSave),
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
