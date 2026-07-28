import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/service_catalog/domain/eligible_service.dart';
import 'package:ai_clinic/features/service_catalog/presentation/providers/service_selector_notifier.dart';
import 'package:ai_clinic/core/money/organization_currency_provider.dart';
import 'package:ai_clinic/features/billing/presentation/providers/visit_billing_flow_notifier.dart';
import 'package:ai_clinic/features/billing/presentation/widgets/visit_billing/visit_service_selection_grid_view.dart';
import 'package:ai_clinic/features/billing/presentation/widgets/visit_billing/visit_service_selection_list_view.dart';
import 'package:ai_clinic/features/billing/presentation/widgets/visit_billing/visit_service_selection_sidebar.dart';

enum _ServiceSelectionView { grid, list }

/// Step 1 — catalog selection with sticky sidebar (web `ServiceSelectionStep`).
class VisitServiceSelectionStep extends ConsumerStatefulWidget {
  const VisitServiceSelectionStep({
    required this.visitId,
    required this.branchId,
    required this.onBack,
    required this.onContinue,
    super.key,
  });

  final String visitId;
  final String branchId;
  final VoidCallback onBack;
  final VoidCallback? onContinue;

  @override
  ConsumerState<VisitServiceSelectionStep> createState() =>
      _VisitServiceSelectionStepState();
}

class _VisitServiceSelectionStepState
    extends ConsumerState<VisitServiceSelectionStep> {
  final _searchController = TextEditingController();
  _ServiceSelectionView _view = _ServiceSelectionView.grid;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadCatalog(''));
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _loadCatalog(String query) {
    final branchId = widget.branchId.trim();
    if (branchId.isEmpty) {
      return;
    }
    ref.read(serviceSelectorProvider(branchId).notifier).search(query);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final elevation = context.appElevation;
    final billing = ref.watch(visitBillingFlowProvider(widget.visitId));
    final billingNotifier = ref.read(
      visitBillingFlowProvider(widget.visitId).notifier,
    );
    final branchId = widget.branchId.trim();
    final catalogAsync = branchId.isEmpty
        ? const AsyncValue<List<EligibleService>>.loading()
        : ref.watch(serviceSelectorProvider(branchId));

    final currency = ref.watch(organizationCurrencyProvider);
    final selectedIds = billing.selectedLines
        .map((line) => line.serviceId)
        .toSet();
    final subtotal = billing.totals.subtotal;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: SingleChildScrollView(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth >= 1024;

                final catalogCard = DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.surfaceRaised,
                    border: Border.all(color: colors.borderSubtle),
                    borderRadius: BorderRadius.circular(AppRadius.x2l),
                    boxShadow: elevation.shadows1,
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.x2l),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _ServiceSelectionHeader(
                          searchController: _searchController,
                          onSearchChanged: _loadCatalog,
                          viewToggle: AppSegmentedControl<String>(
                            ariaLabel: 'Catalog layout',
                            size: AppSegmentedControlSize.sm,
                            value: _view.name,
                            onChanged: (value) => setState(() {
                              _view = value == 'list'
                                  ? _ServiceSelectionView.list
                                  : _ServiceSelectionView.grid;
                            }),
                            options: const [
                              SegmentedOption(
                                value: 'grid',
                                label: Icon(Icons.grid_view_rounded, size: 15),
                              ),
                              SegmentedOption(
                                value: 'list',
                                label: Icon(Icons.view_list_rounded, size: 15),
                              ),
                            ],
                          ),
                        ),
                        catalogAsync.when(
                          loading: () => const Padding(
                            padding: EdgeInsets.all(AppSpacing.space6),
                            child: AppSkeleton(
                              variant: SkeletonVariant.rectangular,
                              height: 220,
                            ),
                          ),
                          error: (_, _) => _ServiceSelectionEmpty(
                            message:
                                'Could not load services. Try searching again.',
                          ),
                          data: (services) {
                            if (services.isEmpty) {
                              return _ServiceSelectionEmpty(
                                message: _searchController.text.trim().isEmpty
                                    ? 'No services in the catalog yet.'
                                    : 'No services match your search.',
                              );
                            }

                            if (_view == _ServiceSelectionView.grid) {
                              return VisitServiceSelectionGridView(
                                services: services,
                                selectedIds: selectedIds,
                                selectedLines: billing.selectedLines,
                                currency: currency,
                                onToggle: (service, selected) => billingNotifier
                                    .toggleService(service, selected: selected),
                                onQuantityChange:
                                    billingNotifier.updateQuantity,
                              );
                            }

                            return ConstrainedBox(
                              constraints: const BoxConstraints(maxHeight: 448),
                              child: VisitServiceSelectionListView(
                                services: services,
                                selectedIds: selectedIds,
                                selectedLines: billing.selectedLines,
                                currency: currency,
                                onToggle: (service, selected) => billingNotifier
                                    .toggleService(service, selected: selected),
                                onQuantityChange:
                                    billingNotifier.updateQuantity,
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                );

                final sidebar = VisitServiceSelectionSidebar(
                  selectedLines: billing.selectedLines,
                  subtotal: subtotal,
                  currency: currency,
                );

                if (isWide) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: catalogCard),
                      const SizedBox(width: AppSpacing.space6),
                      SizedBox(width: 288, child: sidebar),
                    ],
                  );
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    catalogCard,
                    const SizedBox(height: AppSpacing.space6),
                    sidebar,
                  ],
                );
              },
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.space6),
        _ServiceSelectionFooter(
          onBack: widget.onBack,
          onContinue: widget.onContinue,
        ),
      ],
    );
  }
}

class _ServiceSelectionHeader extends StatelessWidget {
  const _ServiceSelectionHeader({
    required this.searchController,
    required this.onSearchChanged,
    required this.viewToggle,
  });

  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;
  final Widget viewToggle;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceSunken.withValues(alpha: 0.5),
        border: Border(bottom: BorderSide(color: colors.borderSubtle)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.space5,
          AppSpacing.space4,
          AppSpacing.space5,
          AppSpacing.space4,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Step 1 of 2',
              style: AppTypography.overline(
                context,
              ).copyWith(color: colors.textTertiary),
            ),
            const SizedBox(height: AppSpacing.space1),
            Text(
              'Services performed',
              style: AppTypography.h2(
                context,
              ).copyWith(color: colors.textPrimary),
            ),
            const SizedBox(height: AppSpacing.space1),
            Text(
              'Select every procedure delivered during this visit.',
              style: AppTypography.bodySm(
                context,
              ).copyWith(color: colors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.space4),
            LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth >= 640;
                final search = AppSearchInput(
                  controller: searchController,
                  placeholder: 'Search services…',
                  showShortcutHint: false,
                  onChanged: onSearchChanged,
                );

                if (isWide) {
                  return Row(
                    children: [
                      Expanded(child: search),
                      const SizedBox(width: AppSpacing.space3),
                      viewToggle,
                    ],
                  );
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    search,
                    const SizedBox(height: AppSpacing.space3),
                    Align(alignment: Alignment.centerLeft, child: viewToggle),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _ServiceSelectionEmpty extends StatelessWidget {
  const _ServiceSelectionEmpty({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.space6,
        vertical: AppSpacing.space16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: colors.surfaceSunken,
              shape: BoxShape.circle,
            ),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.space3),
              child: Icon(
                Icons.search_rounded,
                size: 20,
                color: colors.iconMuted,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.space3),
          Text(
            message,
            style: AppTypography.bodySm(
              context,
            ).copyWith(color: colors.textSecondary),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _ServiceSelectionFooter extends StatelessWidget {
  const _ServiceSelectionFooter({
    required this.onBack,
    required this.onContinue,
  });

  final VoidCallback onBack;
  final VoidCallback? onContinue;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 640;
        final backButton = AppButton(
          variant: AppButtonVariant.secondary,
          onPressed: onBack,
          child: const Text('Back to review'),
        );
        final continueButton = AppButton(
          trailingIcon: const Icon(Icons.receipt_long_outlined, size: 16),
          onPressed: onContinue,
          child: const Text('Review invoice'),
        );

        if (isWide) {
          return Row(children: [backButton, const Spacer(), continueButton]);
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            continueButton,
            const SizedBox(height: AppSpacing.space3),
            backButton,
          ],
        );
      },
    );
  }
}
