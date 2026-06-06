import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/navigation/app_navigator.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/features/billing/domain/insurance_provider.dart';
import 'package:ai_clinic/features/billing/presentation/providers/insurance_providers_notifier.dart';
import 'package:ai_clinic/features/billing/presentation/widgets/billing_access_denied_view.dart';

/// Insurance provider catalog management (V1-6 US4).
class InsuranceProvidersPage extends ConsumerStatefulWidget {
  const InsuranceProvidersPage({super.key});

  @override
  ConsumerState<InsuranceProvidersPage> createState() => _InsuranceProvidersPageState();
}

class _InsuranceProvidersPageState extends ConsumerState<InsuranceProvidersPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final current = ref.read(insuranceProvidersProvider);
      if (!current.isLoading) {
        ref.read(insuranceProvidersProvider.notifier).reload();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final permissions = ref.watch(permissionServiceProvider);
    final canManage = permissions.canManageInsurance();

    if (!canManage) {
      return const BillingAccessDeniedView(
        title: 'Insurance providers',
        message: 'You do not have permission to manage insurance providers.',
      );
    }

    final listAsync = ref.watch(insuranceProvidersProvider);

    ref.listen(insuranceProvidersProvider, (previous, next) {
      final message = next.value?.successMessage ?? next.value?.errorMessage;
      if (message != null && message != (previous?.value?.successMessage ?? previous?.value?.errorMessage)) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
        ref.read(insuranceProvidersProvider.notifier).clearMessages();
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Insurance providers'),
        leading: IconButton(
          tooltip: 'Go back',
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.nav.goHome(),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('insurance_provider_add_fab'),
        onPressed: () => _showProviderDialog(context),
        icon: const Icon(Icons.add),
        label: const Text('New provider'),
      ),
      body: listAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Failed to load providers: $error')),
        data: (ui) => ui.providers.isEmpty
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    key: Key('insurance_providers_empty'),
                    'No insurance providers yet. Create one to use on invoices.',
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            : ListView.builder(
                itemCount: ui.providers.length,
                itemBuilder: (context, index) {
                  final provider = ui.providers[index];
                  return _InsuranceProviderTile(
                    provider: provider,
                    isBusy: ui.isBusy && ui.busyProviderId == provider.id,
                    onEdit: () => _showProviderDialog(context, provider: provider),
                    onDeactivate: provider.isActive ? () => _confirmDeactivate(context, provider) : null,
                  );
                },
              ),
      ),
    );
  }

  Future<void> _showProviderDialog(BuildContext context, {InsuranceProvider? provider}) async {
    final nameController = TextEditingController(text: provider?.name ?? '');
    final contactController = TextEditingController(text: provider?.contactInfo ?? '');

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(provider == null ? 'New insurance provider' : 'Edit insurance provider'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const Key('insurance_provider_name_field'),
              controller: nameController,
              decoration: const InputDecoration(labelText: 'Name', border: OutlineInputBorder()),
              autofocus: true,
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('insurance_provider_contact_field'),
              controller: contactController,
              decoration: const InputDecoration(labelText: 'Contact info (optional)', border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          FilledButton(
            key: const Key('insurance_provider_save_button'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (saved != true || !mounted) {
      return;
    }

    await ref
        .read(insuranceProvidersProvider.notifier)
        .upsertProvider(id: provider?.id, name: nameController.text, contactInfo: contactController.text);
  }

  Future<void> _confirmDeactivate(BuildContext context, InsuranceProvider provider) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Deactivate insurance provider?'),
        content: Text('${provider.name} will be hidden from invoice selectors but remain on historical invoices.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          FilledButton(
            key: const Key('insurance_provider_deactivate_confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Deactivate'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await ref.read(insuranceProvidersProvider.notifier).deactivateProvider(provider.id);
    }
  }
}

class _InsuranceProviderTile extends StatelessWidget {
  const _InsuranceProviderTile({required this.provider, required this.isBusy, required this.onEdit, this.onDeactivate});

  final InsuranceProvider provider;
  final bool isBusy;
  final VoidCallback onEdit;
  final VoidCallback? onDeactivate;

  @override
  Widget build(BuildContext context) {
    final subtitleParts = <String>[
      provider.isActive ? 'Active' : 'Inactive',
      if (provider.contactInfo != null && provider.contactInfo!.isNotEmpty) provider.contactInfo!,
    ];

    return ListTile(
      key: Key('insurance_provider_tile_${provider.id}'),
      title: Text(provider.name),
      subtitle: Text(subtitleParts.join(' · ')),
      trailing: isBusy
          ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
          : PopupMenuButton<String>(
              onSelected: (value) {
                switch (value) {
                  case 'edit':
                    onEdit();
                  case 'deactivate':
                    onDeactivate?.call();
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(value: 'edit', child: Text('Edit')),
                if (onDeactivate != null) const PopupMenuItem(value: 'deactivate', child: Text('Deactivate')),
              ],
            ),
      onTap: onEdit,
    );
  }
}
