import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/core/domain/clinic/branch_list_item.dart';
import 'package:ai_clinic/features/clinic-management/presentation/components/branch_form_dialog.dart';
import 'package:ai_clinic/features/clinic-management/presentation/components/clinic_tab_header.dart';
import 'package:ai_clinic/features/clinic-management/presentation/components/filter_menu_panel.dart';
import 'package:ai_clinic/features/clinic-management/presentation/components/list_control_bar.dart';
import 'package:ai_clinic/features/clinic-management/presentation/models/branch_form_values.dart';
import 'package:ai_clinic/features/clinic-management/presentation/utils/branch_list_controls.dart';
import 'package:ai_clinic/features/clinic-management/presentation/utils/dashed_border.dart';
import 'package:ai_clinic/features/clinic-management/presentation/utils/working_schedule.dart';

class _BranchesTabCopy {
  const _BranchesTabCopy({
    required this.title,
    required this.description,
    required this.addBranch,
    required this.searchPlaceholder,
    required this.searchAriaLabel,
    required this.sortAriaLabel,
    required this.statusSectionLabel,
    required this.allStatuses,
    required this.activeOnly,
    required this.inactiveOnly,
    required this.noBranchesTitle,
    required this.noBranchesDescription,
    required this.noResultsTitle,
    required this.noResultsDescription,
    required this.clearFilters,
    required this.active,
    required this.inactive,
    required this.edit,
    required this.deactivate,
    required this.activate,
    required this.delete,
    required this.deleteTitle,
    required this.deleteDescription,
    required this.deleteConfirm,
    required this.branchActions,
    required this.searchChipPrefix,
  });

  final String title;
  final String description;
  final String addBranch;
  final String searchPlaceholder;
  final String searchAriaLabel;
  final String sortAriaLabel;
  final String statusSectionLabel;
  final String allStatuses;
  final String activeOnly;
  final String inactiveOnly;
  final String noBranchesTitle;
  final String noBranchesDescription;
  final String noResultsTitle;
  final String noResultsDescription;
  final String clearFilters;
  final String active;
  final String inactive;
  final String edit;
  final String deactivate;
  final String activate;
  final String delete;
  final String deleteTitle;
  final String deleteDescription;
  final String deleteConfirm;
  final String branchActions;
  final String searchChipPrefix;
}

const _copyEn = _BranchesTabCopy(
  title: 'Branches',
  description: 'Every location your clinic operates. Staff and services are assigned per branch.',
  addBranch: 'Add branch',
  searchPlaceholder: 'Search by name, code, address, or phone…',
  searchAriaLabel: 'Search branches',
  sortAriaLabel: 'Sort branches',
  statusSectionLabel: 'Status',
  allStatuses: 'All statuses',
  activeOnly: 'Active only',
  inactiveOnly: 'Inactive only',
  noBranchesTitle: 'No branches yet',
  noBranchesDescription: 'Add your first location to start assigning staff and services.',
  noResultsTitle: 'No branches match',
  noResultsDescription: 'Try a different search term or clear your filters.',
  clearFilters: 'Clear filters',
  active: 'Active',
  inactive: 'Inactive',
  edit: 'Edit',
  deactivate: 'Deactivate',
  activate: 'Activate',
  delete: 'Delete',
  deleteTitle: 'Delete branch?',
  deleteDescription:
      '{name} will be removed from settings. Historical records linked to this branch are kept for audit.',
  deleteConfirm: 'Delete branch',
  branchActions: 'Branch actions',
  searchChipPrefix: 'Search',
);

const _copyAr = _BranchesTabCopy(
  title: 'الفروع',
  description: 'كل موقع تعمل فيه العيادة. يتم تعيين الموظفين والخدمات لكل فرع.',
  addBranch: 'إضافة فرع',
  searchPlaceholder: 'ابحث بالاسم أو الرمز أو العنوان أو الهاتف…',
  searchAriaLabel: 'بحث في الفروع',
  sortAriaLabel: 'ترتيب الفروع',
  statusSectionLabel: 'الحالة',
  allStatuses: 'كل الحالات',
  activeOnly: 'النشطة فقط',
  inactiveOnly: 'غير النشطة فقط',
  noBranchesTitle: 'لا توجد فروع بعد',
  noBranchesDescription: 'أضف أول موقع لبدء تعيين الموظفين والخدمات.',
  noResultsTitle: 'لا توجد فروع مطابقة',
  noResultsDescription: 'جرّب مصطلح بحث مختلفًا أو امسح عوامل التصفية.',
  clearFilters: 'مسح عوامل التصفية',
  active: 'نشط',
  inactive: 'غير نشط',
  edit: 'تعديل',
  deactivate: 'إلغاء التفعيل',
  activate: 'تفعيل',
  delete: 'حذف',
  deleteTitle: 'حذف الفرع؟',
  deleteDescription: 'سيتم إزالة {name} من الإعدادات. تُحفظ السجلات التاريخية المرتبطة بهذا الفرع للتدقيق.',
  deleteConfirm: 'حذف الفرع',
  branchActions: 'إجراءات الفرع',
  searchChipPrefix: 'بحث',
);

_BranchesTabCopy _copyFor(String locale) => locale == 'ar' ? _copyAr : _copyEn;

/// Branches list with search, filters, CRUD dialogs (web `BranchesTab`).
class BranchesTab extends StatefulWidget {
  const BranchesTab({
    required this.branches,
    required this.onAddBranch,
    required this.onUpdateBranch,
    required this.onRemoveBranch,
    required this.onToggleBranchActive,
    super.key,
  });

  final List<BranchListItem> branches;
  final Future<void> Function(BranchFormValues values) onAddBranch;
  final Future<void> Function(String branchId, BranchFormValues values) onUpdateBranch;
  final Future<void> Function(String branchId) onRemoveBranch;
  final Future<void> Function({required String branchId, required bool isActive}) onToggleBranchActive;

  @override
  State<BranchesTab> createState() => _BranchesTabState();
}

class _BranchesTabState extends State<BranchesTab> {
  var _controls = DEFAULT_BRANCH_CONTROLS;
  var _dialogOpen = false;
  BranchListItem? _editingBranch;
  BranchListItem? _deleteTarget;

  List<BranchListItem> get _filtered => filterAndSortBranches(widget.branches, _controls);

  bool get _hasBranches => widget.branches.isNotEmpty;

  bool get _hasResults => _filtered.isNotEmpty;

  bool get _isFiltered =>
      _controls.search.isNotEmpty ||
      _controls.status != BranchStatusFilter.all ||
      _controls.sort != DEFAULT_BRANCH_CONTROLS.sort;

  void _setControls(BranchListControls controls) => setState(() => _controls = controls);

  void _clearAll() => _setControls(DEFAULT_BRANCH_CONTROLS);

  void _openCreate() {
    setState(() {
      _editingBranch = null;
      _dialogOpen = true;
    });
  }

  void _openEdit(BranchListItem branch) {
    setState(() {
      _editingBranch = branch;
      _dialogOpen = true;
    });
  }

  Future<void> _handleSubmit(BranchFormValues values) async {
    if (_editingBranch != null) {
      await widget.onUpdateBranch(_editingBranch!.id, values);
    } else {
      await widget.onAddBranch(values);
    }
    if (!mounted) return;
    setState(() {
      _dialogOpen = false;
      _editingBranch = null;
    });
  }

  List<ListControlActiveFilterChip> _activeFilterChips(_BranchesTabCopy copy) {
    final chips = <ListControlActiveFilterChip>[];
    if (_controls.status != BranchStatusFilter.all) {
      chips.add(
        ListControlActiveFilterChip(
          id: 'status',
          label: _controls.status == BranchStatusFilter.active ? copy.activeOnly : copy.inactiveOnly,
        ),
      );
    }
    if (_controls.search.isNotEmpty) {
      chips.add(ListControlActiveFilterChip(id: 'search', label: '${copy.searchChipPrefix}: ${_controls.search}'));
    }
    return chips;
  }

  void _removeChip(String id) {
    switch (id) {
      case 'status':
        _setControls(_controls.copyWith(status: BranchStatusFilter.all));
      case 'search':
        _setControls(_controls.copyWith(search: ''));
    }
  }

  @override
  Widget build(BuildContext context) {
    final copy = _copyFor(Localizations.localeOf(context).languageCode);
    final filterActiveCount = _controls.status != BranchStatusFilter.all ? 1 : 0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClinicTabHeader(
          title: copy.title,
          description: copy.description,
          actions: AppButton(
            leadingIcon: const Icon(Icons.add, size: 16),
            onPressed: _openCreate,
            child: Text(copy.addBranch),
          ),
        ),
        if (_hasBranches) ...[
          const SizedBox(height: AppSpacing.space6),
          ListControlBar(
            searchPlaceholder: copy.searchPlaceholder,
            searchAriaLabel: copy.searchAriaLabel,
            searchQuery: _controls.search,
            onSearchChange: (search) => _setControls(_controls.copyWith(search: search)),
            sortValue: _controls.sort.wireValue,
            defaultSortValue: DEFAULT_BRANCH_CONTROLS.sort.wireValue,
            sortOptions: [
              for (final option in BRANCH_SORT_OPTIONS)
                ListControlSortOption(value: option.value.wireValue, label: option.label),
            ],
            onSortChange: (sort) => _setControls(_controls.copyWith(sort: BranchSortKeyWire.fromWire(sort))),
            onClearSort: _controls.isSortCustom ? () => _setControls(_controls.withDefaultSort()) : null,
            sortAriaLabel: copy.sortAriaLabel,
            filterActiveCount: filterActiveCount,
            filterPanel: FilterMenuPanel(
              sections: [
                FilterMenuSection(
                  id: 'status',
                  label: copy.statusSectionLabel,
                  value: _controls.status.wireValue,
                  options: [
                    FilterMenuOption(value: BranchStatusFilter.all.wireValue, label: copy.allStatuses),
                    FilterMenuOption(value: BranchStatusFilter.active.wireValue, label: copy.activeOnly),
                    FilterMenuOption(value: BranchStatusFilter.inactive.wireValue, label: copy.inactiveOnly),
                  ],
                  onChange: (status) =>
                      _setControls(_controls.copyWith(status: BranchStatusFilterWire.fromWire(status))),
                ),
              ],
            ),
            activeFilterChips: _activeFilterChips(copy),
            onRemoveChip: _removeChip,
            onClearAllFilters: _isFiltered ? _clearAll : null,
          ),
        ],
        const SizedBox(height: AppSpacing.space6),
        if (!_hasBranches)
          _EmptyBranchesState(copy: copy, onAddBranch: _openCreate)
        else if (!_hasResults)
          _NoResultsState(copy: copy, onClearFilters: _clearAll)
        else
          _BranchCardGrid(
            branches: _filtered,
            copy: copy,
            onEdit: _openEdit,
            onToggleActive: (branch) => widget.onToggleBranchActive(branchId: branch.id, isActive: !branch.isActive),
            onDelete: (branch) => setState(() => _deleteTarget = branch),
          ),
        BranchFormDialog(
          open: _dialogOpen,
          onOpenChange: (open) {
            setState(() {
              _dialogOpen = open;
              if (!open) {
                _editingBranch = null;
              }
            });
          },
          mode: _editingBranch == null ? BranchFormDialogMode.create : BranchFormDialogMode.edit,
          initialValues: _editingBranch == null ? emptyBranchFormValues() : branchToFormValues(_editingBranch!),
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
          description: _deleteTarget == null ? '' : copy.deleteDescription.replaceAll('{name}', _deleteTarget!.name),
          confirmLabel: copy.deleteConfirm,
          onConfirm: () {
            final target = _deleteTarget;
            if (target != null) {
              widget.onRemoveBranch(target.id);
            }
            setState(() => _deleteTarget = null);
          },
        ),
      ],
    );
  }
}

class _EmptyBranchesState extends StatelessWidget {
  const _EmptyBranchesState({required this.copy, required this.onAddBranch});

  final _BranchesTabCopy copy;
  final VoidCallback onAddBranch;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return DashedBorder(
      color: colors.borderDefault,
      borderRadius: BorderRadius.circular(AppRadius.x2l),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.x2l),
          color: colors.surfaceSunken.withValues(alpha: 0.5),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space6, vertical: AppSpacing.space16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.location_on, size: 32, color: colors.iconMuted),
              const SizedBox(height: AppSpacing.space4),
              Text(copy.noBranchesTitle, style: AppTypography.bodyStrong(context)),
              const SizedBox(height: AppSpacing.space1),
              Text(
                copy.noBranchesDescription,
                textAlign: TextAlign.center,
                style: AppTypography.bodySm(context).copyWith(color: colors.textSecondary),
              ),
              const SizedBox(height: AppSpacing.space6),
              AppButton(
                leadingIcon: const Icon(Icons.add, size: 16),
                onPressed: onAddBranch,
                child: Text(copy.addBranch),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NoResultsState extends StatelessWidget {
  const _NoResultsState({required this.copy, required this.onClearFilters});

  final _BranchesTabCopy copy;
  final VoidCallback onClearFilters;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final elevation = context.appElevation;

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.x2l),
        border: Border.all(color: colors.borderSubtle),
        color: colors.surfaceDefault,
        boxShadow: elevation.shadows1,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space6, vertical: 56),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off, size: 32, color: colors.iconMuted),
            const SizedBox(height: AppSpacing.space4),
            Text(copy.noResultsTitle, style: AppTypography.bodyStrong(context)),
            const SizedBox(height: AppSpacing.space1),
            Text(
              copy.noResultsDescription,
              textAlign: TextAlign.center,
              style: AppTypography.bodySm(context).copyWith(color: colors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.space6),
            AppButton(variant: AppButtonVariant.secondary, onPressed: onClearFilters, child: Text(copy.clearFilters)),
          ],
        ),
      ),
    );
  }
}

class _BranchCardGrid extends StatelessWidget {
  const _BranchCardGrid({
    required this.branches,
    required this.copy,
    required this.onEdit,
    required this.onToggleActive,
    required this.onDelete,
  });

  final List<BranchListItem> branches;
  final _BranchesTabCopy copy;
  final ValueChanged<BranchListItem> onEdit;
  final ValueChanged<BranchListItem> onToggleActive;
  final ValueChanged<BranchListItem> onDelete;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space1),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final columnCount = constraints.maxWidth >= 1024 ? 3 : 1;
          final cardWidth = columnCount == 1
              ? constraints.maxWidth
              : (constraints.maxWidth - AppSpacing.space4 * (columnCount - 1)) / columnCount;

          return Wrap(
            spacing: AppSpacing.space4,
            runSpacing: AppSpacing.space4,
            clipBehavior: Clip.none,
            children: [
              for (final branch in branches)
                SizedBox(
                  width: cardWidth,
                  child: _BranchCard(
                    branch: branch,
                    copy: copy,
                    onEdit: () => onEdit(branch),
                    onToggleActive: () => onToggleActive(branch),
                    onDelete: () => onDelete(branch),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _BranchCard extends StatefulWidget {
  const _BranchCard({
    required this.branch,
    required this.copy,
    required this.onEdit,
    required this.onToggleActive,
    required this.onDelete,
  });

  final BranchListItem branch;
  final _BranchesTabCopy copy;
  final VoidCallback onEdit;
  final VoidCallback onToggleActive;
  final VoidCallback onDelete;

  @override
  State<_BranchCard> createState() => _BranchCardState();
}

class _BranchCardState extends State<_BranchCard> {
  var _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final elevation = context.appElevation;
    final branch = widget.branch;
    final copy = widget.copy;
    final phone = branch.phone?.trim();
    final address = branch.address?.trim();

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        clipBehavior: Clip.none,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.x2l),
          border: Border.all(color: colors.borderSubtle),
          color: colors.surfaceDefault,
          boxShadow: _hovered ? elevation.shadows2 : elevation.shadows1,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.onEdit,
            borderRadius: BorderRadius.circular(AppRadius.x2l),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.x2l),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: branch.isActive
                            ? [colors.statusSuccessSurface, colors.surfaceDefault]
                            : [colors.statusWarningSurface, colors.surfaceDefault],
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.space5,
                        AppSpacing.space5,
                        AppSpacing.space5,
                        AppSpacing.space3,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Wrap(
                              spacing: AppSpacing.space2,
                              runSpacing: AppSpacing.space2,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Text(
                                  branch.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTypography.bodyStrong(context),
                                ),
                                if ((branch.code ?? '').isNotEmpty)
                                  AppBadge(
                                    label: branch.code,
                                    color: BadgeColor.neutral,
                                    variant: BadgeVariant.soft,
                                    size: BadgeSize.sm,
                                  ),
                                AppBadge(
                                  label: branch.isActive ? copy.active : copy.inactive,
                                  color: branch.isActive ? BadgeColor.success : BadgeColor.warning,
                                  variant: BadgeVariant.soft,
                                  size: BadgeSize.sm,
                                ),
                              ],
                            ),
                          ),
                          Material(
                            color: Colors.transparent,
                            child: AppMenu(
                              align: AppPopoverAlign.end,
                              entries: [
                                AppMenuItem(
                                  id: 'edit',
                                  label: copy.edit,
                                  icon: const Icon(Icons.edit, size: 14),
                                  onSelect: widget.onEdit,
                                ),
                                AppMenuItem(
                                  id: 'toggle-active',
                                  label: branch.isActive ? copy.deactivate : copy.activate,
                                  icon: const Icon(Icons.power_settings_new, size: 14),
                                  onSelect: widget.onToggleActive,
                                ),
                                AppMenuItem(
                                  id: 'delete',
                                  label: copy.delete,
                                  icon: const Icon(Icons.delete_outline, size: 14),
                                  destructive: true,
                                  onSelect: widget.onDelete,
                                ),
                              ],
                              trigger: Semantics(
                                button: true,
                                label: copy.branchActions,
                                child: AppIconButton(
                                  icon: const Icon(Icons.more_horiz, size: 18),
                                  label: copy.branchActions,
                                  variant: AppIconButtonVariant.ghost,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border(top: BorderSide(color: colors.borderSubtle)),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.space5,
                        AppSpacing.space4,
                        AppSpacing.space5,
                        AppSpacing.space4,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.location_on, size: 14, color: colors.iconMuted),
                              const SizedBox(width: AppSpacing.space2),
                              Expanded(
                                child: Text(
                                  address != null && address.isNotEmpty ? address : '—',
                                  style: AppTypography.bodySm(context).copyWith(color: colors.textSecondary),
                                ),
                              ),
                            ],
                          ),
                          if (phone != null && phone.isNotEmpty) ...[
                            const SizedBox(height: AppSpacing.space2),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.phone, size: 14, color: colors.iconMuted),
                                const SizedBox(width: AppSpacing.space2),
                                Directionality(
                                  textDirection: TextDirection.ltr,
                                  child: Text(
                                    _formatBranchPhone(phone),
                                    style: AppTypography.bodySm(context).copyWith(
                                      color: colors.textSecondary,
                                      fontFeatures: const [FontFeature.tabularFigures()],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                          const SizedBox(height: AppSpacing.space2),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.schedule, size: 14, color: colors.iconMuted),
                              const SizedBox(width: AppSpacing.space2),
                              Expanded(
                                child: Text(
                                  formatWorkingHoursSummary(branch.workingSchedule),
                                  style: AppTypography.bodySm(context).copyWith(color: colors.textSecondary),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String _formatBranchPhone(String phone) {
  final trimmed = phone.trim();
  if (trimmed.startsWith('+')) {
    return trimmed;
  }
  return '+$trimmed';
}
