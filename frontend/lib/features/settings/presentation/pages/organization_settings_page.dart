import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/core/widgets/app_modifiable_form_field.dart';
import 'package:ai_clinic/core/widgets/app_modifiable_searchable_dropdown_field.dart';
import 'package:ai_clinic/features/auth/domain/bootstrap_field_options.dart';
import 'package:ai_clinic/features/settings/domain/organization_profile.dart';
import 'package:ai_clinic/features/settings/presentation/providers/organization_settings_notifier.dart';

/// Organization profile settings for owner and administrator roles (US1).
class OrganizationSettingsPage extends ConsumerStatefulWidget {
  const OrganizationSettingsPage({super.key});

  @override
  ConsumerState<OrganizationSettingsPage> createState() => _OrganizationSettingsPageState();
}

class _OrganizationSettingsPageState extends ConsumerState<OrganizationSettingsPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _logoUrlController = TextEditingController();
  final _currencyController = TextEditingController();
  final _timezoneController = TextEditingController();
  OrganizationProfile? _lastSyncedProfile;

  @override
  void dispose() {
    _nameController.dispose();
    _logoUrlController.dispose();
    _currencyController.dispose();
    _timezoneController.dispose();
    super.dispose();
  }

  void _syncControllers(OrganizationSettingsUiState ui) {
    final profile = ui.profile;
    if (profile == null || profile == _lastSyncedProfile) {
      return;
    }
    _nameController.text = profile.name;
    _logoUrlController.text = profile.logoUrl ?? '';
    _currencyController.text = profile.currencyCode ?? '';
    _timezoneController.text = profile.timezone ?? '';
    _lastSyncedProfile = profile;
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    await ref
        .read(organizationSettingsProvider.notifier)
        .save(
          name: _nameController.text,
          logoUrl: _logoUrlController.text,
          currencyCode: OrganizationProfile.normalizeCurrencyCode(_currencyController.text),
          timezone: OrganizationProfile.normalizeTimezone(_timezoneController.text),
        );
  }

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(organizationSettingsProvider);

    ref.listen<AsyncValue<OrganizationSettingsUiState>>(organizationSettingsProvider, (previous, next) {
      final value = next.value;
      if (value?.saveMessage != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value!.saveMessage!)));
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Organization'),
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.go(AppRoutes.settings)),
      ),
      body: settingsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Failed to load organization: $error')),
        data: (ui) {
          if (ui.permissionDenied) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Only clinic owners and administrators can view or change organization settings.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          _syncControllers(ui);
          final profile = ui.profile!;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (ui.errorMessage != null) ...[
                    Text(ui.errorMessage!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                    const SizedBox(height: 16),
                  ],
                  AppModifiableFormField(
                    label: 'Organization name',
                    currentValue: profile.name,
                    controller: _nameController,
                    enabled: !ui.isSaving,
                    validator: (value) =>
                        ui.fieldErrors['name'] ??
                        (value == null || value.trim().isEmpty ? 'Organization name is required.' : null),
                  ),
                  const SizedBox(height: 16),
                  AppModifiableFormField(
                    label: 'Logo URL',
                    currentValue: profile.logoUrl,
                    controller: _logoUrlController,
                    enabled: !ui.isSaving,
                    hint: 'https://…',
                    keyboardType: TextInputType.url,
                  ),
                  const SizedBox(height: 16),
                  AppModifiableSearchableDropdownField(
                    fieldKey: const ValueKey('org_settings_currency'),
                    label: 'Currency code',
                    infoTooltip: 'ISO 4217 code for billing and receipts (e.g. EGP, USD). Type to filter the list.',
                    currentValue: profile.currencyCode,
                    controller: _currencyController,
                    enabled: !ui.isSaving,
                    hint: 'Type to search (e.g. EGP)',
                    options: BootstrapCurrencyOptions.codes,
                    filterOptions: BootstrapCurrencyOptions.filter,
                    validator: (value) {
                      if (value != null && value.trim().isNotEmpty && !BootstrapCurrencyOptions.isValid(value)) {
                        return 'Select a currency code from the list';
                      }
                      return ui.fieldErrors['currencyCode'];
                    },
                  ),
                  const SizedBox(height: 16),
                  AppModifiableSearchableDropdownField(
                    fieldKey: const ValueKey('org_settings_timezone'),
                    label: 'Timezone',
                    infoTooltip:
                        'IANA timezone for appointments and daily reports (e.g. Africa/Cairo). Type to filter.',
                    currentValue: profile.timezone,
                    controller: _timezoneController,
                    enabled: !ui.isSaving,
                    hint: 'Type to search (e.g. Africa/Cairo)',
                    options: BootstrapTimezoneOptions.zones,
                    filterOptions: BootstrapTimezoneOptions.filter,
                    validator: (value) {
                      if (value != null && value.trim().isNotEmpty && !BootstrapTimezoneOptions.isValid(value)) {
                        return 'Select a timezone from the list';
                      }
                      return ui.fieldErrors['timezone'];
                    },
                  ),
                  const SizedBox(height: 24),
                  Text('Subscription', style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 8),
                  Text('Tier: ${profile.subscriptionTier ?? '—'}'),
                  Text('Valid until: ${profile.subscriptionValidUntil?.toLocal().toString().split(' ').first ?? '—'}'),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: ui.isSaving ? null : _save,
                    child: ui.isSaving
                        ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Save organization settings'),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
