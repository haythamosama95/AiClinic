import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/navigation/app_navigator.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/ui/components/app_empty_state.dart';
import 'package:ai_clinic/core/ui/components/app_page_header.dart';
import 'package:ai_clinic/core/ui/components/app_pagination.dart';
import 'package:ai_clinic/core/ui/motion/app_motion.dart';
import 'package:ai_clinic/core/ui/theme/app_elevation.dart';
import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/features/billing/presentation/models/invoice_list_controls.dart';
import 'package:ai_clinic/features/billing/presentation/models/invoice_list_filters.dart';
import 'package:ai_clinic/features/billing/presentation/providers/invoice_list_notifier.dart';
import 'package:ai_clinic/features/billing/presentation/widgets/invoice_list_controls.dart';
import 'package:ai_clinic/features/billing/presentation/widgets/invoice_table.dart';

/// Invoice ledger list (`/billing/invoices`).
class InvoiceListPage extends ConsumerStatefulWidget {
  const InvoiceListPage({super.key});

  @override
  ConsumerState<InvoiceListPage> createState() => _InvoiceListPageState();
}

class _InvoiceListPageState extends ConsumerState<InvoiceListPage> with SingleTickerProviderStateMixin {
  static const _defaultControls = InvoiceListControls.defaultControls;

  late final AnimationController _enterController;
  CurvedAnimation? _enterAnimation;
  var _enterStarted = false;
  var _defaultControlsApplied = false;

  @override
  void initState() {
    super.initState();
    _enterController = AnimationController(vsync: this, duration: const Duration(milliseconds: 220));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(invoiceListProvider.notifier).reload();
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_enterStarted) {
      _enterStarted = true;
      final reducedMotion = AppMotion.prefersReducedMotion(context);
      _enterController.duration = reducedMotion ? Duration.zero : const Duration(milliseconds: 220);
      _enterAnimation = CurvedAnimation(
        parent: _enterController,
        curve: AppMotion.resolveCurve(AppMotionPreset.fade, reducedMotion: reducedMotion),
      );
      if (reducedMotion) {
        _enterController.value = 1;
      } else {
        _enterController.forward();
      }
    }
  }

  @override
  void dispose() {
    _enterAnimation?.dispose();
    _enterController.dispose();
    super.dispose();
  }

  bool _isPristineNotifierDefault(InvoiceListFilters filters) {
    return InvoiceListControls.fromBackendFilters(filters) == _defaultControls;
  }

  void _ensureDefaultControls() {
    if (_defaultControlsApplied) {
      return;
    }
    _defaultControlsApplied = true;

    final filters = ref.read(invoiceListProvider.notifier).filters;
    if (_isPristineNotifierDefault(filters) && filters.pageSize != _defaultControls.pageSize) {
      _applyControls(_defaultControls);
    }
  }

  bool get _multiBranch {
    final branchIds = ref.read(authSessionProvider).context?.branchIds ?? const <String>[];
    return branchIds.length > 1;
  }

  void _applyControls(InvoiceListControls controls) {
    ref.read(invoiceListProvider.notifier).applyControls(controls, multiBranch: _multiBranch);
  }

  void _clearAll(InvoiceListControls current) {
    _applyControls(InvoiceListControls.defaultControls.copyWith(pageSize: current.pageSize));
  }

  Widget _buildNoMatchCard(BuildContext context, InvoiceListControls controls) {
    final colors = context.appColors;
    final elevation = Theme.of(context).extension<AppElevation>();

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceDefault,
        borderRadius: BorderRadius.circular(AppRadius.x2l),
        border: Border.all(color: colors.borderSubtle),
        boxShadow: elevation?.shadows1 ?? AppElevation.level1,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space6, vertical: 56),
        child: Center(
          child: AppEmptyState(
            variant: AppEmptyStateVariant.noResults,
            title: 'No invoices match',
            description: 'Try a different search term or clear your filters.',
            action: EmptyStateAction(label: 'Clear filters', onPressed: () => _clearAll(controls)),
          ),
        ),
      ),
    );
  }

  Widget _buildBody({
    required BuildContext context,
    required InvoiceListUiState? state,
    required InvoiceListControls controls,
    required bool isLoading,
  }) {
    final filters = state?.filters ?? ref.read(invoiceListProvider.notifier).filters;

    if (isLoading && state == null) {
      return InvoiceLedgerTable(items: const [], loading: true, loadingRows: filters.pageSize);
    }

    if (state == null) {
      return InvoiceLedgerTable(items: const [], loading: true, loadingRows: filters.pageSize);
    }

    if (state.isNoInvoicesYet) {
      return const AppEmptyState(
        variant: AppEmptyStateVariant.firstRun,
        title: 'No invoices yet',
        description: 'Invoices appear here once a completed visit is billed.',
      );
    }

    if (state.isNoMatch) {
      return _buildNoMatchCard(context, controls);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      spacing: AppSpacing.space6,
      children: [
        InvoiceLedgerTable(
          items: state.items,
          loading: isLoading && state.items.isEmpty,
          loadingRows: filters.pageSize,
          onRowClick: (item) => context.nav.pushBillingInvoiceDetail(item.id),
        ),
        if (!state.isEmpty)
          AppPagination(
            page: filters.page,
            pageSize: filters.pageSize,
            total: state.estimatedTotal,
            pageSizeOptions: const [10, 25, 50],
            onPageChange: (page) => _applyControls(controls.copyWith(page: page)),
            onPageSizeChange: (pageSize) => _applyControls(controls.copyWith(page: 1, pageSize: pageSize)),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    _ensureDefaultControls();

    final listAsync = ref.watch(invoiceListProvider);
    final state = listAsync.value;
    final filters = state?.filters ?? ref.read(invoiceListProvider.notifier).filters;
    final controls = InvoiceListControls.fromBackendFilters(filters);
    final isLoading = listAsync.isLoading;
    final hasInvoices = state?.hasInvoices ?? false;

    final content = listAsync.when(
      loading: () => _buildPageContent(
        context: context,
        state: state,
        controls: controls,
        isLoading: true,
        hasInvoices: hasInvoices,
      ),
      error: (error, _) => _buildPageContent(
        context: context,
        state: state,
        controls: controls,
        isLoading: false,
        hasInvoices: hasInvoices,
        error: error,
      ),
      data: (loadedState) => _buildPageContent(
        context: context,
        state: loadedState,
        controls: controls,
        isLoading: isLoading,
        hasInvoices: loadedState.hasInvoices,
      ),
    );

    return FadeTransition(
      opacity: _enterAnimation ?? _enterController,
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.hasBoundedHeight) {
            return SingleChildScrollView(child: content);
          }
          return content;
        },
      ),
    );
  }

  Widget _buildPageContent({
    required BuildContext context,
    required InvoiceListUiState? state,
    required InvoiceListControls controls,
    required bool isLoading,
    required bool hasInvoices,
    Object? error,
  }) {
    if (error != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        spacing: AppSpacing.space6,
        children: [
          const AppPageHeader(
            title: 'Invoices',
            description: "Every invoice for this branch — status, payments collected, and what's still owed.",
          ),
          AppEmptyState(
            variant: AppEmptyStateVariant.error,
            title: 'Could not load invoices',
            description: error.toString(),
            action: EmptyStateAction(label: 'Retry', onPressed: () => ref.invalidate(invoiceListProvider)),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      spacing: AppSpacing.space6,
      children: [
        const AppPageHeader(
          title: 'Invoices',
          description: "Every invoice for this branch — status, payments collected, and what's still owed.",
        ),
        if (hasInvoices) InvoiceListControlsBar(controls: controls, onApply: _applyControls),
        _buildBody(context: context, state: state, controls: controls, isLoading: isLoading),
      ],
    );
  }
}
