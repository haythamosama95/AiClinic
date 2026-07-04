import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/auth/auth_route_guard.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/core/ui/theme/semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/spacing_tokens.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/billing/application/billing_rpc_messages.dart';
import 'package:ai_clinic/features/billing/domain/insurance_provider.dart';
import 'package:ai_clinic/features/billing/presentation/providers/insurance_providers_notifier.dart';

/// Organization insurance provider catalog management (V1-6 US4).
class InsuranceProvidersPage extends ConsumerWidget {
  const InsuranceProvidersPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authSessionProvider);
    if (!AuthRouteGuard.canAccessInsuranceProviders(auth)) {
      return const Scaffold(body: Center(child: Text('You do not have permission to manage insurance providers.')));
    }

    final providersAsync = ref.watch(insuranceProvidersProvider);

    return Scaffold(
      backgroundColor: context.semanticColors.background,
      body: Padding(
        padding: const EdgeInsets.all(SpacingTokens.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                AppIconButton(icon: const Icon(Icons.arrow_back), tooltip: 'Back', onPressed: () => context.pop()),
                const SizedBox(width: SpacingTokens.sm),
                Expanded(
                  child: Text(
                    'Insurance providers',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                AppButton(
                  label: 'Add provider',
                  icon: const Icon(Icons.add, size: 18),
                  expand: false,
                  onPressed: () => _openEditor(context, ref),
                ),
              ],
            ),
            const SizedBox(height: SpacingTokens.lg),
            Expanded(
              child: providersAsync.when(
                loading: () => const Center(child: AppCircularProgress()),
                error: (error, _) => Center(child: Text('Unable to load providers: $error')),
                data: (providers) => _ProvidersList(
                  providers: providers,
                  onEdit: (provider) => _openEditor(context, ref, provider: provider),
                  onDeactivate: (provider) => _deactivate(context, ref, provider),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openEditor(BuildContext context, WidgetRef ref, {InsuranceProvider? provider}) async {
    await AppDialog.show<void>(
      context: context,
      title: provider == null ? 'Add insurance provider' : 'Edit insurance provider',
      bodyBuilder: (dialogContext) => _ProviderEditorBody(
        provider: provider,
        onSave: (name, contactInfo) async {
          try {
            await ref
                .read(insuranceProvidersProvider.notifier)
                .upsert(id: provider?.id, name: name, contactInfo: contactInfo);
            if (dialogContext.mounted) Navigator.of(dialogContext).pop();
            if (context.mounted) {
              AppToast.success(context, message: provider == null ? 'Provider added.' : 'Provider updated.');
            }
          } on RpcFailure catch (error) {
            if (context.mounted) AppToast.error(context, message: billingMessageForRpc(error));
          }
        },
      ),
    );
  }

  Future<void> _deactivate(BuildContext context, WidgetRef ref, InsuranceProvider provider) async {
    await AppDialog.showConfirmation(
      context: context,
      title: 'Deactivate provider',
      message: '${provider.name} will be hidden from invoice selectors. Historical invoices keep the link.',
      confirmLabel: 'Deactivate',
      destructive: true,
      onConfirm: () async {
        try {
          await ref.read(insuranceProvidersProvider.notifier).deactivate(provider.id);
          if (context.mounted) AppToast.success(context, message: 'Provider deactivated.');
        } on RpcFailure catch (error) {
          if (context.mounted) AppToast.error(context, message: billingMessageForRpc(error));
        }
      },
    );
  }
}

class _ProvidersList extends StatelessWidget {
  const _ProvidersList({required this.providers, required this.onEdit, required this.onDeactivate});

  final List<InsuranceProvider> providers;
  final ValueChanged<InsuranceProvider> onEdit;
  final ValueChanged<InsuranceProvider> onDeactivate;

  @override
  Widget build(BuildContext context) {
    final colors = context.semanticColors;

    if (providers.isEmpty) {
      return Center(
        child: Text(
          'No insurance providers yet. Add one to use during invoice creation.',
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: colors.mutedForeground),
          textAlign: TextAlign.center,
        ),
      );
    }

    return ListView.separated(
      itemCount: providers.length,
      separatorBuilder: (_, _) => const SizedBox(height: SpacingTokens.sm),
      itemBuilder: (context, index) {
        final provider = providers[index];
        return Material(
          color: colors.card,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(color: colors.border),
          ),
          clipBehavior: Clip.antiAlias,
          child: ListTile(
            title: Text(provider.name),
            subtitle: provider.contactInfo == null ? null : Text(provider.contactInfo!),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppBadge(
                  label: provider.isActive ? 'Active' : 'Inactive',
                  variant: provider.isActive ? AppBadgeVariant.primary : AppBadgeVariant.muted,
                ),
                AppIconButton(
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  tooltip: 'Edit',
                  onPressed: () => onEdit(provider),
                ),
                if (provider.isActive)
                  AppIconButton(
                    icon: Icon(Icons.block_outlined, size: 18, color: colors.destructive),
                    tooltip: 'Deactivate',
                    onPressed: () => onDeactivate(provider),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ProviderEditorBody extends StatefulWidget {
  const _ProviderEditorBody({required this.provider, required this.onSave});

  final InsuranceProvider? provider;
  final Future<void> Function(String name, String? contactInfo) onSave;

  @override
  State<_ProviderEditorBody> createState() => _ProviderEditorBodyState();
}

class _ProviderEditorBodyState extends State<_ProviderEditorBody> {
  late final TextEditingController _nameController;
  late final TextEditingController _contactController;
  var _isSaving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.provider?.name ?? '');
    _contactController = TextEditingController(text: widget.provider?.contactInfo ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _contactController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    setState(() => _isSaving = true);
    try {
      final contact = _contactController.text.trim();
      await widget.onSave(name, contact.isEmpty ? null : contact);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppTextField(controller: _nameController, label: 'Name'),
        const SizedBox(height: SpacingTokens.md),
        AppTextField(controller: _contactController, label: 'Contact info (optional)'),
        const SizedBox(height: SpacingTokens.lg),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            AppButton(
              label: 'Cancel',
              variant: AppButtonVariant.outline,
              expand: false,
              onPressed: () => Navigator.of(context).pop(),
            ),
            const SizedBox(width: SpacingTokens.sm),
            AppButton(label: 'Save', expand: false, isLoading: _isSaving, onPressed: _save),
          ],
        ),
      ],
    );
  }
}
