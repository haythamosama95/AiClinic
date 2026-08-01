import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/auth/permission_service.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/clinic-management/domain/branch_list_item.dart';
import 'package:ai_clinic/features/clinic-management/domain/organization_profile.dart';
import 'package:ai_clinic/features/clinic-management/presentation/components/clinic_tab_header.dart';
import 'package:ai_clinic/features/clinic-management/presentation/components/service_form_dialog.dart';
import 'package:ai_clinic/features/clinic-management/presentation/models/service_form_values.dart';
import 'package:ai_clinic/features/clinic-management/presentation/utils/dashed_border.dart';
import 'package:ai_clinic/features/service_catalog/data/service_catalog_repository.dart';
import 'package:ai_clinic/features/service_catalog/domain/global_status.dart';
import 'package:ai_clinic/features/service_catalog/domain/service_list_item.dart';
import 'package:ai_clinic/features/service_catalog/presentation/providers/service_catalog_list_notifier.dart';
import 'package:ai_clinic/features/service_catalog/presentation/providers/service_editor_notifier.dart';

class _ServicesTabCopy {
  const _ServicesTabCopy({
    required this.title,
    required this.description,
    required this.addService,
    required this.searchPlaceholder,
    required this.searchAriaLabel,
    required this.noServicesTitle,
    required this.noServicesDescription,
    required this.noResultsTitle,
    required this.noResultsDescription,
    required this.clearSearch,
    required this.serviceActions,
    required this.editService,
    required this.removeService,
    required this.deleteTitle,
    required this.deleteConfirm,
  });

  final String title;
  final String description;
  final String addService;
  final String searchPlaceholder;
  final String searchAriaLabel;
  final String noServicesTitle;
  final String noServicesDescription;
  final String noResultsTitle;
  final String noResultsDescription;
  final String clearSearch;
  final String serviceActions;
  final String editService;
  final String removeService;
  final String deleteTitle;
  final String deleteConfirm;
}

const _copyEn = _ServicesTabCopy(
  title: 'Services',
  description: 'Billable procedures and default pricing for invoices.',
  addService: 'Add service',
  searchPlaceholder: 'Search services…',
  searchAriaLabel: 'Search services',
  noServicesTitle: 'No services yet',
  noServicesDescription: 'Add billable procedures to use when creating invoices.',
  noResultsTitle: 'No services match',
  noResultsDescription: 'Try a different search term.',
  clearSearch: 'Clear search',
  serviceActions: 'Service actions',
  editService: 'Edit service',
  removeService: 'Remove service',
  deleteTitle: 'Delete service?',
  deleteConfirm: 'Delete service',
);

const _copyAr = _ServicesTabCopy(
  title: 'الخدمات',
  description: 'الإجراءات القابلة للفوترة والأسعار الافتراضية للفواتير.',
  addService: 'إضافة خدمة',
  searchPlaceholder: 'ابحث في الخدمات…',
  searchAriaLabel: 'بحث الخدمات',
  noServicesTitle: 'لا توجد خدمات بعد',
  noServicesDescription: 'أضف إجراءات قابلة للفوترة لاستخدامها عند إنشاء الفواتير.',
  noResultsTitle: 'لا توجد خدمات مطابقة',
  noResultsDescription: 'جرّب مصطلح بحث مختلف.',
  clearSearch: 'مسح البحث',
  serviceActions: 'إجراءات الخدمة',
  editService: 'تعديل الخدمة',
  removeService: 'إزالة الخدمة',
  deleteTitle: 'حذف الخدمة؟',
  deleteConfirm: 'حذف الخدمة',
);

_ServicesTabCopy _copyFor(String locale) => locale == 'ar' ? _copyAr : _copyEn;

int _serviceCardColumnCount(double maxWidth) {
  if (maxWidth >= 1024) {
    return 4;
  }
  if (maxWidth >= 640) {
    return 2;
  }
  return 1;
}

const _serviceCardExtent = 120.0;

/// Services catalog tab with search and CRUD (web `ServicesTab`).
class ServicesTab extends ConsumerStatefulWidget {
  const ServicesTab({required this.branches, required this.organization, super.key});

  /// Used internally to assign services across all active branches on save.
  final List<BranchListItem> branches;
  final OrganizationProfile organization;

  @override
  ConsumerState<ServicesTab> createState() => _ServicesTabState();
}

class _ServicesTabState extends ConsumerState<ServicesTab> {
  var _dialogOpen = false;
  String? _editingServiceId;
  String? _loadedDetailForServiceId;
  ServiceFormValues _formValues = emptyServiceFormValues();
  ServiceListItem? _deleteTarget;
  var _search = '';

  List<String> get _activeBranchIds => [
    for (final branch in widget.branches)
      if (branch.isActive) branch.id,
  ];

  String get _currencyCode => widget.organization.currencyCode ?? 'USD';

  bool get _canManage => PermissionService(ref.read(authSessionProvider).context).canManageServices();

  Future<void> _applySearch(String query) async {
    final notifier = ref.read(serviceCatalogListProvider.notifier);
    final current = notifier.filters;
    await notifier.applyFilters(current.copyWith(query: query, page: 1));
  }

  void _openCreate() {
    setState(() {
      _editingServiceId = null;
      _loadedDetailForServiceId = null;
      _formValues = emptyServiceFormValues();
      _dialogOpen = true;
    });
  }

  void _openEdit(ServiceListItem service) {
    setState(() {
      _editingServiceId = service.serviceId;
      _loadedDetailForServiceId = null;
      _formValues = serviceListItemToFormValues(service);
      _dialogOpen = true;
    });
  }

  String _loadErrorMessage(Object error) {
    return switch (error) {
      StateError(:final message) when message.isNotEmpty => message,
      _ => 'Unable to load service. Please try again.',
    };
  }

  Future<void> _handleSubmit(ServiceFormValues values) async {
    final trimmedName = values.name.trim();
    final priceWire = priceToWire(values.price!);
    final allBranchIds = _activeBranchIds.toSet();

    if (_editingServiceId == null) {
      await ref
          .read(serviceEditorProvider(null).notifier)
          .createService(
            name: trimmedName,
            defaultPrice: priceWire,
            globalStatus: GlobalStatus.active,
            assignAllBranches: true,
            selectedBranchIds: allBranchIds,
          );
    } else {
      final serviceId = _editingServiceId!;
      final editorState = await ref.read(serviceEditorProvider(serviceId).future);
      final detail = editorState.detail;
      if (detail == null) {
        throw StateError('Service not loaded.');
      }

      await ref
          .read(serviceEditorProvider(serviceId).notifier)
          .updateService(
            name: trimmedName,
            defaultPrice: priceWire,
            globalStatus: detail.service.globalStatus,
            assignAllBranches: true,
            selectedBranchIds: allBranchIds,
            allBranchIds: _activeBranchIds,
          );
    }

    await ref.read(serviceCatalogListProvider.notifier).reload();
    if (!mounted) {
      return;
    }
    setState(() {
      _dialogOpen = false;
      _editingServiceId = null;
    });
  }

  Future<void> _confirmDelete() async {
    final target = _deleteTarget;
    if (target == null) {
      return;
    }

    await ref
        .read(serviceCatalogRepositoryProvider)
        .softDeleteService(serviceId: target.serviceId, expectedUpdatedAt: target.updatedAt);
    await ref.read(serviceCatalogListProvider.notifier).reload();
    if (!mounted) {
      return;
    }
    setState(() => _deleteTarget = null);
  }

  @override
  Widget build(BuildContext context) {
    final copy = _copyFor(Localizations.localeOf(context).languageCode);
    final catalogAsync = ref.watch(serviceCatalogListProvider);
    final editingServiceId = _editingServiceId;
    var dialogLoading = false;
    String? dialogLoadError;

    if (_dialogOpen && editingServiceId != null) {
      final editorAsync = ref.watch(serviceEditorProvider(editingServiceId));
      final loadedDetail = editorAsync.value?.detail;
      dialogLoading = editorAsync.isLoading && loadedDetail == null;
      dialogLoadError = editorAsync.when(
        data: (state) =>
            state.detail == null && !editorAsync.isLoading ? 'Unable to load service. Please try again.' : null,
        error: (error, _) => _loadErrorMessage(error),
        loading: () => null,
      );

      ref.listen(serviceEditorProvider(editingServiceId), (previous, next) {
        next.whenData((state) {
          final detail = state.detail;
          if (detail == null || _loadedDetailForServiceId == editingServiceId) {
            return;
          }
          if (!mounted) {
            return;
          }
          setState(() {
            _loadedDetailForServiceId = editingServiceId;
            _formValues = serviceDetailToFormValues(detail);
          });
        });
      });
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        catalogAsync.when(
          data: (catalog) => _buildContent(
            context,
            copy,
            services: catalog.items,
            appliedQuery: catalog.filters.query,
            total: catalog.total,
          ),
          loading: () => const _ServicesTabLoadingBody(),
          error: (_, _) => AppEmptyState(
            variant: AppEmptyStateVariant.error,
            title: 'Unable to load services',
            description: 'Check connectivity and try again.',
            action: EmptyStateAction(
              label: 'Try again',
              onPressed: () => ref.read(serviceCatalogListProvider.notifier).reload(),
            ),
          ),
        ),
        ServiceFormDialog(
          open: _dialogOpen,
          onOpenChange: (open) => setState(() {
            _dialogOpen = open;
            if (!open) {
              _editingServiceId = null;
              _loadedDetailForServiceId = null;
            }
          }),
          mode: _editingServiceId == null ? ServiceFormDialogMode.create : ServiceFormDialogMode.edit,
          currencyCode: _currencyCode,
          initialValues: _formValues,
          loading: dialogLoading,
          loadError: dialogLoadError,
          onSubmit: _handleSubmit,
        ),
        AppConfirmationDialog(
          open: _deleteTarget != null,
          onOpenChange: (open) {
            if (!open) {
              setState(() => _deleteTarget = null);
            }
          },
          title: copy.deleteTitle,
          description: _deleteTarget == null
              ? ''
              : '${_deleteTarget!.name} will be removed from your service catalog. This cannot be undone.',
          confirmLabel: copy.deleteConfirm,
          onConfirm: _confirmDelete,
        ),
      ],
    );
  }

  Widget _buildContent(
    BuildContext context,
    _ServicesTabCopy copy, {
    required List<ServiceListItem> services,
    required String appliedQuery,
    required int total,
  }) {
    final showSearch = total > 0 || appliedQuery.trim().isNotEmpty;
    final isEmptyCatalog = total == 0 && appliedQuery.trim().isEmpty;
    final hasResults = services.isNotEmpty;
    final showDelete = services.length > 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        ClinicTabHeader(
          title: copy.title,
          description: copy.description,
          actions: _canManage
              ? AppButton(
                  leadingIcon: const Icon(Icons.add, size: 16),
                  onPressed: _openCreate,
                  child: Text(copy.addService),
                )
              : null,
        ),
        if (showSearch) ...[
          const SizedBox(height: AppSpacing.space6),
          Semantics(
            label: copy.searchAriaLabel,
            textField: true,
            child: AppTextInput(
              initialValue: _search,
              placeholder: copy.searchPlaceholder,
              leadingIcon: const Icon(Icons.search, size: 18),
              onChanged: (query) {
                setState(() => _search = query);
                _applySearch(query);
              },
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.space6),
        if (isEmptyCatalog)
          _ServicesEmptyPanel(
            title: copy.noServicesTitle,
            description: copy.noServicesDescription,
            actionLabel: copy.addService,
            onAction: _canManage ? _openCreate : null,
          )
        else if (!hasResults)
          AppEmptyState(
            variant: AppEmptyStateVariant.noResults,
            title: copy.noResultsTitle,
            description: copy.noResultsDescription,
            action: EmptyStateAction(
              label: copy.clearSearch,
              onPressed: () {
                setState(() => _search = '');
                _applySearch('');
              },
            ),
          )
        else
          _ServiceCardGrid(
            services: services,
            copy: copy,
            currencyCode: _currencyCode,
            canManage: _canManage,
            showDelete: showDelete,
            onEdit: _openEdit,
            onDelete: (service) => setState(() => _deleteTarget = service),
          ),
      ],
    );
  }
}

class _ServicesTabLoadingBody extends StatelessWidget {
  const _ServicesTabLoadingBody();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const AppSkeleton(height: 24, width: 120),
        const SizedBox(height: AppSpacing.space2),
        const AppSkeleton(height: 16, width: 420),
        const SizedBox(height: AppSpacing.space6),
        const AppSkeleton(height: 44),
        const SizedBox(height: AppSpacing.space6),
        LayoutBuilder(
          builder: (context, constraints) {
            final columnCount = _serviceCardColumnCount(constraints.maxWidth);

            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columnCount,
                crossAxisSpacing: AppSpacing.space3,
                mainAxisSpacing: AppSpacing.space3,
                mainAxisExtent: _serviceCardExtent,
              ),
              itemCount: columnCount,
              itemBuilder: (context, index) => const AppSkeleton(),
            );
          },
        ),
      ],
    );
  }
}

class _ServicesEmptyPanel extends StatelessWidget {
  const _ServicesEmptyPanel({required this.title, required this.description, required this.actionLabel, this.onAction});

  final String title;
  final String description;
  final String actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return DashedBorder(
      color: colors.borderDefault,
      borderRadius: BorderRadius.circular(AppRadius.x2l),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surfaceSunken.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(AppRadius.x2l),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space6, vertical: AppSpacing.space16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.medical_services_outlined, size: 32, color: colors.iconMuted),
              const SizedBox(height: AppSpacing.space4),
              Text(title, style: AppTypography.bodyStrong(context), textAlign: TextAlign.center),
              const SizedBox(height: AppSpacing.space1),
              Text(
                description,
                style: AppTypography.bodySm(context).copyWith(color: colors.textSecondary),
                textAlign: TextAlign.center,
              ),
              if (onAction != null) ...[
                const SizedBox(height: AppSpacing.space6),
                AppButton(leadingIcon: const Icon(Icons.add, size: 16), onPressed: onAction, child: Text(actionLabel)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ServiceCardGrid extends StatelessWidget {
  const _ServiceCardGrid({
    required this.services,
    required this.copy,
    required this.currencyCode,
    required this.canManage,
    required this.showDelete,
    required this.onEdit,
    required this.onDelete,
  });

  final List<ServiceListItem> services;
  final _ServicesTabCopy copy;
  final String currencyCode;
  final bool canManage;
  final bool showDelete;
  final ValueChanged<ServiceListItem> onEdit;
  final ValueChanged<ServiceListItem> onDelete;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columnCount = _serviceCardColumnCount(constraints.maxWidth);

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columnCount,
            crossAxisSpacing: AppSpacing.space3,
            mainAxisSpacing: AppSpacing.space3,
            mainAxisExtent: _serviceCardExtent,
          ),
          itemCount: services.length,
          itemBuilder: (context, index) {
            final service = services[index];
            return _ServiceCard(
              service: service,
              copy: copy,
              currencyCode: currencyCode,
              canManage: canManage,
              showDelete: showDelete,
              onEdit: () => onEdit(service),
              onDelete: () => onDelete(service),
            );
          },
        );
      },
    );
  }
}

class _ServiceCard extends StatefulWidget {
  const _ServiceCard({
    required this.service,
    required this.copy,
    required this.currencyCode,
    required this.canManage,
    required this.showDelete,
    required this.onEdit,
    required this.onDelete,
  });

  final ServiceListItem service;
  final _ServicesTabCopy copy;
  final String currencyCode;
  final bool canManage;
  final bool showDelete;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  State<_ServiceCard> createState() => _ServiceCardState();
}

class _ServiceCardState extends State<_ServiceCard> {
  var _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final elevation = context.appElevation;
    final copy = widget.copy;
    final serviceName = widget.service.name.trim().isEmpty ? '—' : widget.service.name;
    final motionDuration = AppMotion.prefersReducedMotion(context) ? Duration.zero : AppMotionDuration.fast;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: MouseCursor.defer,
      child: AnimatedContainer(
        duration: motionDuration,
        curve: AppMotion.standardCurve,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: colors.surfaceDefault,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: _hovered ? colors.borderDefault : colors.borderSubtle),
          boxShadow: _hovered ? elevation.shadows2 : elevation.shadows1,
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.space3 + 2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      serviceName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.bodyStrong(context).copyWith(color: colors.textPrimary, height: 1.3),
                    ),
                  ),
                  if (widget.canManage) ...[
                    const SizedBox(width: AppSpacing.space1),
                    Material(
                      color: Colors.transparent,
                      child: AppMenu(
                        align: AppPopoverAlign.end,
                        entries: [
                          AppMenuItem(
                            id: 'edit',
                            label: copy.editService,
                            icon: const Icon(Icons.edit_outlined, size: 14),
                            onSelect: widget.onEdit,
                          ),
                          if (widget.showDelete)
                            AppMenuItem(
                              id: 'delete',
                              label: copy.removeService,
                              icon: const Icon(Icons.delete_outline, size: 14),
                              destructive: true,
                              onSelect: widget.onDelete,
                            ),
                        ],
                        trigger: Semantics(
                          button: true,
                          label: copy.serviceActions,
                          child: AppIconButton(
                            icon: const Icon(Icons.more_horiz, size: 16),
                            label: copy.serviceActions,
                            variant: AppIconButtonVariant.ghost,
                            size: AppIconButtonSize.sm,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const Spacer(),
              DefaultTextStyle(
                style: AppTypography.bodySm(context).copyWith(
                  color: colors.textPrimary,
                  fontFamily: 'monospace',
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
                child: AppMoneyDisplay(amount: widget.service.defaultPrice.asDouble, currency: widget.currencyCode),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
