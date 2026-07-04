import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/auth/auth_route_guard.dart';
import 'package:ai_clinic/core/ui/ui.dart';
import 'package:ai_clinic/features/billing/domain/insurance_provider.dart';
import 'package:ai_clinic/features/billing/presentation/providers/insurance_providers_notifier.dart';
import 'package:ai_clinic/features/billing/presentation/widgets/insurance_provider_form_dialog.dart';

/// Insurance provider catalog management (V1-6 US4).
class InsuranceProvidersPage extends ConsumerWidget {
  const InsuranceProvidersPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!AuthRouteGuard.canAccessInsuranceProviders(ref.watch(authSessionProvider))) {
      return const AppEmptyState(
        variant: AppEmptyStateVariant.noAccess,
        title: 'Insurance providers',
        description: 'You do not have permission to manage insurance providers.',
      );
    }

    final listAsync = ref.watch(insuranceProvidersProvider);

    return listAsync.when(
      skipLoadingOnReload: true,
      loading: () => _buildShell(
        context,
        table: const Center(child: AppSpinner()),
      ),
      error: (error, _) => _buildShell(
        context,
        table: AppErrorState(
          message: error.toString(),
          onRetry: () => ref.read(insuranceProvidersProvider.notifier).reload(),
        ),
      ),
      data: (providers) => _buildShell(
        context,
        table: providers.isEmpty
            ? AppEmptyState(
                key: const Key('insurance_providers_empty'),
                variant: AppEmptyStateVariant.firstRun,
                title: 'No insurance providers yet',
                description: 'Create one to use on invoices.',
                actionLabel: 'New provider',
                onAction: () => _editProvider(context, ref, null),
              )
            : _ProvidersTable(
                providers: providers,
                onEdit: (provider) => _editProvider(context, ref, provider),
                onDeactivate: (provider) => _deactivateProvider(context, ref, provider),
              ),
        headerActions: AppButton(
          key: const Key('insurance_provider_add_button'),
          label: 'New provider',
          leadingIcon: LucideIcons.plus,
          onPressed: () => _editProvider(context, ref, null),
        ),
      ),
    );
  }

  Widget _buildShell(
    BuildContext context, {
    required Widget table,
    Widget? headerActions,
  }) {
    return ListIndexPattern(
      title: 'Insurance providers',
      description: 'Manage the catalog used when recording insurance coverage on invoices.',
      headerActions: headerActions,
      table: table,
      page: 1,
      pageCount: 1,
      onPageChanged: (_) {},
      paginationLabel: 'Insurance providers',
    );
  }

  Future<void> _editProvider(
    BuildContext context,
    WidgetRef ref,
    InsuranceProvider? provider,
  ) async {
    final saved = await showInsuranceProviderFormDialog(context: context, ref: ref, provider: provider);
    if (saved) {
      ref.showAppToast(
        message: provider == null ? 'Insurance provider created.' : 'Insurance provider updated.',
        variant: AppToastVariant.success,
      );
    }
  }

  Future<void> _deactivateProvider(
    BuildContext context,
    WidgetRef ref,
    InsuranceProvider provider,
  ) async {
    final confirmed = await showAppConfirmationDialog(
      context,
      title: 'Deactivate insurance provider?',
      message:
          '${provider.name} will be hidden from invoice selectors but remain on historical invoices.',
      confirmLabel: 'Deactivate',
      destructive: true,
    );
    if (!confirmed) {
      return;
    }

    await ref.read(insuranceProvidersProvider.notifier).deactivate(provider.id);
    ref.showAppToast(message: 'Insurance provider deactivated.', variant: AppToastVariant.success);
  }
}

class _ProvidersTable extends StatelessWidget {
  const _ProvidersTable({
    required this.providers,
    required this.onEdit,
    required this.onDeactivate,
  });

  final List<InsuranceProvider> providers;
  final ValueChanged<InsuranceProvider> onEdit;
  final ValueChanged<InsuranceProvider> onDeactivate;

  @override
  Widget build(BuildContext context) {
    return AppTable<InsuranceProvider>(
      columns: [
        AppTableColumn(
          id: 'name',
          header: 'Name',
          cellBuilder: (context, provider) => Text(
            provider.name,
            style: context.typography.bodyStrong,
          ),
        ),
        AppTableColumn(
          id: 'contact',
          header: 'Contact',
          cellBuilder: (context, provider) => Text(provider.contactInfo ?? '—'),
        ),
        AppTableColumn(
          id: 'status',
          header: 'Status',
          width: 120,
          cellBuilder: (context, provider) => AppBadge(
            color: provider.isActive ? AppBadgeColor.success : AppBadgeColor.neutral,
            child: Text(provider.isActive ? 'Active' : 'Inactive'),
          ),
        ),
        AppTableColumn(
          id: 'actions',
          header: 'Actions',
          width: 160,
          align: AppTableColumnAlign.end,
          cellBuilder: (context, provider) => Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              AppButton(
                label: 'Edit',
                size: AppButtonSize.sm,
                variant: AppButtonVariant.ghost,
                onPressed: () => onEdit(provider),
              ),
              if (provider.isActive) ...[
                const SizedBox(width: AppSpacing.s1),
                AppButton(
                  key: Key('insurance_provider_deactivate_${provider.id}'),
                  label: 'Deactivate',
                  size: AppButtonSize.sm,
                  variant: AppButtonVariant.ghost,
                  onPressed: () => onDeactivate(provider),
                ),
              ],
            ],
          ),
        ),
      ],
      rowId: (provider) => provider.id,
      data: providers,
      semanticLabel: 'Insurance providers',
      onRowTap: onEdit,
    );
  }
}
