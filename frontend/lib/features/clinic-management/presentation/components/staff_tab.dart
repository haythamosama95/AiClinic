import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/clinic-management/domain/branch_list_item.dart';
import 'package:ai_clinic/features/clinic-management/domain/staff_list_item.dart';
import 'package:ai_clinic/features/clinic-management/presentation/components/clinic_tab_header.dart';
import 'package:ai_clinic/features/clinic-management/presentation/components/list_control_bar.dart';
import 'package:ai_clinic/features/clinic-management/presentation/components/staff_detail_dialog.dart';
import 'package:ai_clinic/features/clinic-management/presentation/components/staff_filter_panel.dart';
import 'package:ai_clinic/features/clinic-management/presentation/components/staff_form_dialog.dart';
import 'package:ai_clinic/features/clinic-management/presentation/constants/clinic_constants.dart';
import 'package:ai_clinic/features/clinic-management/presentation/models/staff_form_values.dart';
import 'package:ai_clinic/features/clinic-management/presentation/utils/dashed_border.dart';
import 'package:ai_clinic/features/clinic-management/presentation/utils/role_theme.dart';
import 'package:ai_clinic/features/clinic-management/presentation/utils/staff_list_controls.dart';

typedef StaffAddCallback = Future<void> Function(StaffFormValues values);
typedef StaffUpdateCallback = Future<void> Function(String id, StaffFormValues values);
typedef StaffRemoveCallback = Future<void> Function(String id);

class _StaffTabCopy {
  const _StaffTabCopy({
    required this.title,
    required this.description,
    required this.addStaffMember,
    required this.searchPlaceholder,
    required this.searchAriaLabel,
    required this.sortAriaLabel,
    required this.allRoles,
    required this.allBranches,
    required this.noStaffTitle,
    required this.noStaffDescription,
    required this.noResultsTitle,
    required this.noResultsDescription,
    required this.clearFilters,
    required this.phoneLabel,
    required this.deleteTitle,
    required this.deleteConfirm,
    required this.noBranches,
    required this.searchChipPrefix,
  });

  final String title;
  final String description;
  final String addStaffMember;
  final String searchPlaceholder;
  final String searchAriaLabel;
  final String sortAriaLabel;
  final String allRoles;
  final String allBranches;
  final String noStaffTitle;
  final String noStaffDescription;
  final String noResultsTitle;
  final String noResultsDescription;
  final String clearFilters;
  final String phoneLabel;
  final String deleteTitle;
  final String deleteConfirm;
  final String noBranches;
  final String searchChipPrefix;
}

const _copyEn = _StaffTabCopy(
  title: 'Staff',
  description: 'People who sign in to AiClinic. Each account has a role and branch assignments.',
  addStaffMember: 'Add staff member',
  searchPlaceholder: 'Search by name, username, phone, or role…',
  searchAriaLabel: 'Search staff',
  sortAriaLabel: 'Sort staff',
  allRoles: 'All roles',
  allBranches: 'All branches',
  noStaffTitle: 'No staff accounts yet',
  noStaffDescription: 'Create accounts for administrators, clinicians, and front-desk staff.',
  noResultsTitle: 'No staff match',
  noResultsDescription: 'Try a different search term or clear your filters.',
  clearFilters: 'Clear filters',
  phoneLabel: 'Phone',
  deleteTitle: 'Delete staff account?',
  deleteConfirm: 'Delete account',
  noBranches: 'No branches',
  searchChipPrefix: 'Search',
);

const _copyAr = _StaffTabCopy(
  title: 'الموظفون',
  description: 'الأشخاص الذين يسجلون الدخول إلى AiClinic. لكل حساب دور وتعيينات فروع.',
  addStaffMember: 'إضافة موظف',
  searchPlaceholder: 'ابحث بالاسم أو اسم المستخدم أو الهاتف أو الدور…',
  searchAriaLabel: 'بحث الموظفين',
  sortAriaLabel: 'ترتيب الموظفين',
  allRoles: 'كل الأدوار',
  allBranches: 'كل الفروع',
  noStaffTitle: 'لا توجد حسابات موظفين بعد',
  noStaffDescription: 'أنشئ حسابات للمسؤولين والأطباء وموظفي الاستقبال.',
  noResultsTitle: 'لا يوجد موظفون مطابقون',
  noResultsDescription: 'جرّب مصطلح بحث مختلفًا أو امسح عوامل التصفية.',
  clearFilters: 'مسح عوامل التصفية',
  phoneLabel: 'الهاتف',
  deleteTitle: 'حذف حساب الموظف؟',
  deleteConfirm: 'حذف الحساب',
  noBranches: 'لا توجد فروع',
  searchChipPrefix: 'بحث',
);

_StaffTabCopy _copyFor(String locale) => locale == 'ar' ? _copyAr : _copyEn;

/// Staff list tab with CRUD dialogs (web `StaffTab`).
class StaffTab extends StatefulWidget {
  const StaffTab({
    required this.staff,
    required this.branches,
    required this.onAdd,
    required this.onUpdate,
    required this.onRemove,
    super.key,
  });

  final List<StaffListItem> staff;
  final List<BranchListItem> branches;
  final StaffAddCallback onAdd;
  final StaffUpdateCallback onUpdate;
  final StaffRemoveCallback onRemove;

  @override
  State<StaffTab> createState() => _StaffTabState();
}

class _StaffTabState extends State<StaffTab> {
  var _controls = DEFAULT_STAFF_CONTROLS;
  var _dialogOpen = false;
  StaffListItem? _editingStaff;
  StaffListItem? _deleteTarget;
  StaffListItem? _detailTarget;

  List<StaffListItem> get _filtered =>
      filterAndSortStaff(staff: widget.staff, branches: widget.branches, controls: _controls);

  bool get _isFiltered =>
      _controls.search.isNotEmpty ||
      _controls.role != null ||
      (_controls.branchId != null && _controls.branchId!.isNotEmpty) ||
      _controls.sort != defaultStaffSort;

  int get _filterActiveCount =>
      (_controls.role != null || (_controls.branchId != null && _controls.branchId!.isNotEmpty)) ? 1 : 0;

  void _openCreate() {
    setState(() {
      _editingStaff = null;
      _dialogOpen = true;
    });
  }

  void _openEdit(StaffListItem member) {
    setState(() {
      _editingStaff = member;
      _dialogOpen = true;
    });
  }

  void _openDetail(StaffListItem member) {
    setState(() => _detailTarget = member);
  }

  void _clearSort() {
    setState(() => _controls = resetStaffSort(_controls));
  }

  Future<void> _handleSubmit(StaffFormValues values) async {
    if (_editingStaff case final member?) {
      await widget.onUpdate(member.id, values);
    } else {
      await widget.onAdd(values);
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _dialogOpen = false;
      _editingStaff = null;
    });
  }

  Future<void> _confirmDelete() async {
    final target = _deleteTarget;
    if (target == null) {
      return;
    }
    await widget.onRemove(target.id);
    if (!mounted) {
      return;
    }
    setState(() => _deleteTarget = null);
  }

  void _clearFilters() {
    setState(() => _controls = _controls.copyWith(clearRole: true, clearBranchId: true));
  }

  void _clearAll() {
    setState(() => _controls = DEFAULT_STAFF_CONTROLS);
  }

  void _removeFilterChip(String chipId) {
    setState(() {
      switch (chipId) {
        case 'filters':
          _controls = _controls.copyWith(clearRole: true, clearBranchId: true);
        case 'search':
          _controls = _controls.copyWith(search: '');
      }
    });
  }

  List<ListControlActiveFilterChip> _activeFilterChips(_StaffTabCopy copy) {
    final chips = <ListControlActiveFilterChip>[];
    final filterParts = <String>[];

    if (_controls.role != null) {
      filterParts.add(kRoleLabels[_controls.role] ?? _controls.role!.displayLabel);
    }
    if (_controls.branchId != null && _controls.branchId!.isNotEmpty) {
      final branch = widget.branches.where((item) => item.id == _controls.branchId).firstOrNull;
      filterParts.add(branch?.name ?? 'Branch');
    }
    if (filterParts.isNotEmpty) {
      chips.add(ListControlActiveFilterChip(id: 'filters', label: filterParts.join(' · ')));
    }
    if (_controls.search.isNotEmpty) {
      chips.add(ListControlActiveFilterChip(id: 'search', label: '${copy.searchChipPrefix}: ${_controls.search}'));
    }
    return chips;
  }

  List<AppSelectOption> _roleFilterOptions(_StaffTabCopy copy) {
    return [
      AppSelectOption(value: 'all', label: copy.allRoles),
      for (final role in kStaffRoles) AppSelectOption(value: role.value.wireValue, label: role.label),
    ];
  }

  List<AppSelectOption> _branchFilterOptions(_StaffTabCopy copy) {
    return [
      AppSelectOption(value: 'all', label: copy.allBranches),
      for (final branch in widget.branches)
        AppSelectOption(
          value: branch.id,
          label: branch.code != null && branch.code!.isNotEmpty ? '${branch.name} (${branch.code})' : branch.name,
        ),
    ];
  }

  String _branchNames(StaffListItem member, _StaffTabCopy copy) {
    final names = member.branches.map((branch) => branch.name).where((name) => name.isNotEmpty).toList();
    if (names.isEmpty) {
      return copy.noBranches;
    }
    if (names.length <= 2) {
      return names.join(', ');
    }
    return '${names.take(2).join(', ')} +${names.length - 2}';
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final copy = _copyFor(Localizations.localeOf(context).languageCode);
    final hasStaff = widget.staff.isNotEmpty;
    final hasResults = _filtered.isNotEmpty;
    final showPhone = MediaQuery.sizeOf(context).width >= 640;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        ClinicTabHeader(
          title: copy.title,
          description: copy.description,
          actions: AppButton(
            leadingIcon: const Icon(Icons.add, size: 16),
            onPressed: _openCreate,
            child: Text(copy.addStaffMember),
          ),
        ),
        if (hasStaff) ...[
          const SizedBox(height: AppSpacing.space6),
          ListControlBar(
            searchPlaceholder: copy.searchPlaceholder,
            searchAriaLabel: copy.searchAriaLabel,
            searchQuery: _controls.search,
            onSearchChange: (search) => setState(() => _controls = _controls.copyWith(search: search)),
            sortValue: _controls.sort.name,
            defaultSortValue: StaffSortKey.nameAsc.name,
            sortOptions: [
              for (final option in STAFF_SORT_OPTIONS)
                ListControlSortOption(value: option.value.name, label: option.label),
            ],
            onSortChange: (sort) {
              final next = StaffSortKey.values.where((key) => key.name == sort).firstOrNull;
              if (next != null) {
                setState(() => _controls = _controls.copyWith(sort: next));
              }
            },
            onClearSort: _controls.sort != defaultStaffSort ? _clearSort : null,
            sortAriaLabel: copy.sortAriaLabel,
            filterActiveCount: _filterActiveCount,
            filterPanel: StaffFilterPanel(
              role: _controls.role,
              branchId: _controls.branchId,
              roleOptions: _roleFilterOptions(copy),
              branchOptions: _branchFilterOptions(copy),
              onRoleChange: (role) =>
                  setState(() => _controls = _controls.copyWith(role: role, clearRole: role == null)),
              onBranchChange: (branchId) =>
                  setState(() => _controls = _controls.copyWith(branchId: branchId, clearBranchId: branchId == null)),
              onClearAll: _clearFilters,
            ),
            activeFilterChips: _activeFilterChips(copy),
            onRemoveChip: _removeFilterChip,
            onClearAllFilters: _isFiltered ? _clearAll : null,
          ),
        ],
        const SizedBox(height: AppSpacing.space6),
        if (!hasStaff)
          _StaffEmptyPanel(
            icon: Icons.person,
            title: copy.noStaffTitle,
            description: copy.noStaffDescription,
            actionLabel: copy.addStaffMember,
            onAction: _openCreate,
            dashed: true,
          )
        else if (!hasResults)
          AppEmptyState(
            variant: AppEmptyStateVariant.noResults,
            title: copy.noResultsTitle,
            description: copy.noResultsDescription,
            action: EmptyStateAction(label: copy.clearFilters, onPressed: _clearAll),
          )
        else
          DecoratedBox(
            decoration: BoxDecoration(
              color: colors.surfaceDefault,
              borderRadius: BorderRadius.circular(AppRadius.x2l),
              border: Border.all(color: colors.borderSubtle),
              boxShadow: context.appElevation.shadows1,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var index = 0; index < _filtered.length; index++) ...[
                  if (index > 0) Divider(height: 1, color: colors.borderSubtle),
                  _AnimatedStaffRow(
                    key: ValueKey(_filtered[index].id),
                    index: index,
                    child: _StaffRow(
                      member: _filtered[index],
                      branchSummary: _branchNames(_filtered[index], copy),
                      copy: copy,
                      showPhone: showPhone,
                      onTap: () => _openDetail(_filtered[index]),
                    ),
                  ),
                ],
              ],
            ),
          ),
        if (_detailTarget case final member?)
          StaffDetailDialog(
            open: true,
            onOpenChange: (open) {
              if (!open) {
                setState(() => _detailTarget = null);
              }
            },
            member: member,
            branches: widget.branches,
            onEdit: () => _openEdit(member),
            onDelete: () => setState(() => _deleteTarget = member),
          ),
        StaffFormDialog(
          open: _dialogOpen,
          onOpenChange: (open) => setState(() {
            _dialogOpen = open;
            if (!open) {
              _editingStaff = null;
            }
          }),
          mode: _editingStaff == null ? StaffFormMode.create : StaffFormMode.edit,
          branches: widget.branches,
          initialValues: _editingStaff == null ? emptyStaffFormValues() : staffToFormValues(_editingStaff!),
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
              : '${_deleteTarget!.fullName} will lose access to AiClinic. This cannot be undone.',
          confirmLabel: copy.deleteConfirm,
          onConfirm: _confirmDelete,
        ),
      ],
    );
  }
}

class _StaffEmptyPanel extends StatelessWidget {
  const _StaffEmptyPanel({
    required this.icon,
    required this.title,
    required this.description,
    required this.actionLabel,
    required this.onAction,
    required this.dashed,
  });

  final IconData icon;
  final String title;
  final String description;
  final String actionLabel;
  final VoidCallback onAction;
  final bool dashed;

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
              Icon(icon, size: 32, color: colors.iconMuted),
              const SizedBox(height: AppSpacing.space4),
              Text(title, style: AppTypography.bodyStrong(context), textAlign: TextAlign.center),
              const SizedBox(height: AppSpacing.space1),
              Text(
                description,
                style: AppTypography.bodySm(context).copyWith(color: colors.textSecondary),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.space6),
              AppButton(leadingIcon: const Icon(Icons.add, size: 16), onPressed: onAction, child: Text(actionLabel)),
            ],
          ),
        ),
      ),
    );
  }
}

class _AnimatedStaffRow extends StatefulWidget {
  const _AnimatedStaffRow({required this.index, required this.child, super.key});

  final int index;
  final Widget child;

  @override
  State<_AnimatedStaffRow> createState() => _AnimatedStaffRowState();
}

class _AnimatedStaffRowState extends State<_AnimatedStaffRow> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  var _enterStarted = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: AppMotion.resolveDuration(AppMotionPreset.rowEnter));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_enterStarted) return;
    _enterStarted = true;
    final reducedMotion = AppMotion.prefersReducedMotion(context);
    _controller.duration = AppMotion.resolveDuration(AppMotionPreset.rowEnter, reducedMotion: reducedMotion);
    _startEnterAnimation(reducedMotion);
  }

  @override
  void didUpdateWidget(covariant _AnimatedStaffRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.key != oldWidget.key) {
      final reducedMotion = AppMotion.prefersReducedMotion(context);
      _controller
        ..reset()
        ..duration = AppMotion.resolveDuration(AppMotionPreset.rowEnter, reducedMotion: reducedMotion);
      _startEnterAnimation(reducedMotion);
    }
  }

  void _startEnterAnimation(bool reducedMotion) {
    if (reducedMotion) {
      _controller.value = 1;
      return;
    }
    final delay = AppMotion.staggerStep(context, stepMs: 25) * widget.index.clamp(0, 4);
    Future<void>.delayed(delay, () {
      if (mounted) {
        _controller.forward();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppMotion.animatedPreset(
      context: context,
      preset: AppMotionPreset.rowEnter,
      animation: CurvedAnimation(parent: _controller, curve: AppMotion.outCurve),
      child: widget.child,
    );
  }
}

class _StaffRow extends StatefulWidget {
  const _StaffRow({
    required this.member,
    required this.branchSummary,
    required this.copy,
    required this.showPhone,
    required this.onTap,
  });

  final StaffListItem member;
  final String branchSummary;
  final _StaffTabCopy copy;
  final bool showPhone;
  final VoidCallback onTap;

  @override
  State<_StaffRow> createState() => _StaffRowState();
}

class _StaffRowState extends State<_StaffRow> {
  var _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final username = widget.member.username ?? '';

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: Material(
        color: _hovered ? colors.surfaceHover.withValues(alpha: 0.5) : Colors.transparent,
        child: InkWell(
          onTap: widget.onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space5, vertical: AppSpacing.space4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                AppAvatar(name: widget.member.fullName, size: AvatarSize.md),
                const SizedBox(width: AppSpacing.space4),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Wrap(
                        spacing: AppSpacing.space2,
                        runSpacing: AppSpacing.space1,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            widget.member.fullName,
                            style: AppTypography.bodyStrong(context),
                            overflow: TextOverflow.ellipsis,
                          ),
                          AppBadge(
                            label: kRoleLabels[widget.member.role],
                            color: kRoleBadgeColors[widget.member.role] ?? BadgeColor.neutral,
                            variant: BadgeVariant.soft,
                            size: BadgeSize.sm,
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '@$username · ${widget.branchSummary}',
                        style: AppTypography.bodySm(context).copyWith(color: colors.textSecondary),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                if (widget.showPhone && widget.member.phone != null && widget.member.phone!.isNotEmpty) ...[
                  const SizedBox(width: AppSpacing.space6),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        widget.copy.phoneLabel,
                        style: AppTypography.caption(context).copyWith(color: colors.textTertiary),
                      ),
                      Directionality(
                        textDirection: TextDirection.ltr,
                        child: Text(
                          '+${widget.member.phone}',
                          style: AppTypography.bodySm(
                            context,
                          ).copyWith(color: colors.textSecondary, fontFeatures: const [FontFeature.tabularFigures()]),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
