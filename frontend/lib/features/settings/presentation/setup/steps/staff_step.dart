import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/components/app_button.dart';
import 'package:ai_clinic/core/ui/components/app_card.dart';
import 'package:ai_clinic/core/ui/components/app_combobox.dart';
import 'package:ai_clinic/core/ui/components/app_form_field.dart';
import 'package:ai_clinic/core/ui/components/app_icon_button.dart';
import 'package:ai_clinic/core/ui/components/app_multi_select.dart';
import 'package:ai_clinic/core/ui/components/app_password_input.dart';
import 'package:ai_clinic/core/ui/components/app_phone_input.dart';
import 'package:ai_clinic/core/ui/components/app_select.dart';
import 'package:ai_clinic/core/ui/components/app_text_input.dart';
import 'package:ai_clinic/core/ui/motion/app_motion.dart';
import 'package:ai_clinic/core/ui/theme/app_color_primitives.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';
import 'package:ai_clinic/features/settings/presentation/providers/clinic_setup_draft_notifier.dart';
import 'package:ai_clinic/features/settings/presentation/setup/setup_draft_models.dart';
import 'package:ai_clinic/features/settings/presentation/setup/setup_field_hints.dart';
import 'package:ai_clinic/features/settings/presentation/setup/setup_validation.dart';
import 'package:ai_clinic/features/settings/presentation/setup/widgets/collapsed_staff_card.dart';
import 'package:ai_clinic/features/settings/presentation/setup/widgets/collapsed_summary_enter_transition.dart';

/// Staff step (web `StaffStep`).
class StaffStep extends ConsumerStatefulWidget {
  const StaffStep({required this.errors, super.key});

  final Map<String, String> errors;

  @override
  ConsumerState<StaffStep> createState() => _StaffStepState();
}

class _StaffStepState extends ConsumerState<StaffStep> {
  late String _activeStaffId;
  Map<String, String> _localErrors = {};
  String? _savingStaffId;

  @override
  void initState() {
    super.initState();
    _activeStaffId = '';
  }

  Map<String, String> get _mergedErrors => {...widget.errors, ..._localErrors};

  String? _resolveActiveStaffId(List<StaffDraft> staff, Set<String> confirmedIds) {
    if (_activeStaffId.isNotEmpty && !confirmedIds.contains(_activeStaffId)) {
      if (staff.any((member) => member.id == _activeStaffId)) {
        return _activeStaffId;
      }
    }

    for (final member in staff) {
      if (!confirmedIds.contains(member.id)) {
        return member.id;
      }
    }

    return null;
  }

  Future<void> _ensureMinLoadingDuration(DateTime startedAt) async {
    final elapsed = DateTime.now().difference(startedAt);
    final remaining = kSetupSaveMinLoadingDuration - elapsed;
    if (remaining > Duration.zero) {
      await Future<void>.delayed(remaining);
    }
  }

  bool _validateAndConfirm(List<StaffDraft> staff, String staffId, int branchCount, ClinicSetupDraftNotifier notifier) {
    final index = staff.indexWhere((member) => member.id == staffId);
    if (index < 0) return true;

    final memberErrors = validateSingleStaff(staff[index], index, allStaff: staff, branchCount: branchCount);
    if (hasErrors(memberErrors)) {
      setState(() => _localErrors = memberErrors);
      return false;
    }

    setState(() {
      _localErrors = {};
      if (_activeStaffId == staffId) {
        _activeStaffId = '';
      }
    });
    notifier.confirmStaff(staffId);
    return true;
  }

  Future<void> _saveStaff(
    List<StaffDraft> staff,
    String staffId,
    int branchCount,
    ClinicSetupDraftNotifier notifier,
  ) async {
    if (_savingStaffId != null) return;

    setState(() => _savingStaffId = staffId);
    final startedAt = DateTime.now();
    await Future<void>.delayed(Duration.zero);

    final index = staff.indexWhere((member) => member.id == staffId);
    if (index < 0) {
      if (mounted) setState(() => _savingStaffId = null);
      return;
    }

    final memberErrors = validateSingleStaff(staff[index], index, allStaff: staff, branchCount: branchCount);
    await _ensureMinLoadingDuration(startedAt);
    if (!mounted) return;

    if (hasErrors(memberErrors)) {
      setState(() {
        _localErrors = memberErrors;
        _savingStaffId = null;
      });
      return;
    }

    setState(() {
      _localErrors = {};
      _activeStaffId = '';
      _savingStaffId = null;
    });
    notifier.confirmStaff(staffId);
  }

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(clinicSetupDraftProvider.select((state) => state.draft));
    final confirmedIds = ref.watch(clinicSetupDraftProvider.select((state) => state.confirmedStaffIds));
    final notifier = ref.read(clinicSetupDraftProvider.notifier);
    final colors = context.appColors;

    if (_activeStaffId.isEmpty && draft.staff.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final nextActiveId = _resolveActiveStaffId(draft.staff, confirmedIds);
        if (nextActiveId != null) {
          setState(() => _activeStaffId = nextActiveId);
        }
      });
    }

    final branchOptions = draft.branches
        .map(
          (branch) => AppComboboxItem(
            id: branch.id,
            label: branch.name.isNotEmpty ? branch.name : (branch.code.isNotEmpty ? branch.code : 'Unnamed branch'),
            meta: branch.code.isNotEmpty ? branch.code : null,
          ),
        )
        .toList();

    final resolvedActiveId = _resolveActiveStaffId(draft.staff, confirmedIds);
    final activeIndex = resolvedActiveId == null
        ? -1
        : draft.staff.indexWhere((member) => member.id == resolvedActiveId);
    final activeMember = activeIndex >= 0 ? draft.staff[activeIndex] : null;

    void updateStaff(
      String id, {
      String? name,
      String? mobile,
      String? username,
      String? password,
      String? role,
      List<String>? branchIds,
    }) {
      notifier.updateStaff(
        id,
        name: name,
        mobile: mobile,
        username: username,
        password: password,
        role: role,
        branchIds: branchIds,
      );
      if (confirmedIds.contains(id)) {
        notifier.unconfirmStaff(id);
      }
    }

    void removeStaff(String id) {
      notifier.removeStaff(id);
      final staff = ref.read(clinicSetupDraftProvider).draft.staff;
      setState(() {
        if (staff.isEmpty) {
          final newMember = notifier.addStaff();
          _activeStaffId = newMember.id;
        } else if (id == _activeStaffId) {
          _activeStaffId = '';
        }
        _localErrors = {};
      });
    }

    void addStaff() {
      if (activeMember != null && !_validateAndConfirm(draft.staff, activeMember.id, draft.branches.length, notifier)) {
        return;
      }

      final newMember = notifier.addStaff();
      setState(() {
        _activeStaffId = newMember.id;
        _localErrors = {};
      });
    }

    void expandStaff(String staffId) {
      if (staffId == resolvedActiveId) return;

      if (activeMember != null && !confirmedIds.contains(activeMember.id)) {
        if (!_validateAndConfirm(draft.staff, activeMember.id, draft.branches.length, notifier)) return;
      }

      setState(() {
        _localErrors = {};
        _activeStaffId = staffId;
      });
      notifier.unconfirmStaff(staffId);
    }

    final collapsedStaff = draft.staff.where((member) => confirmedIds.contains(member.id)).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _StaffStepHeader(colors: colors),
        const SizedBox(height: AppSpacing.space6),
        if (_mergedErrors['_form'] != null) ...[
          Semantics(
            liveRegion: true,
            child: Text(
              _mergedErrors['_form']!,
              style: AppTypography.bodySm(context).copyWith(color: colors.statusDangerFg),
            ),
          ),
          const SizedBox(height: AppSpacing.space4),
        ],
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final member in collapsedStaff) ...[
              CollapsedStaffCard(
                key: ValueKey('collapsed-${member.id}'),
                member: member,
                index: draft.staff.indexWhere((item) => item.id == member.id),
                onExpand: () => expandStaff(member.id),
                onRemove: () => removeStaff(member.id),
              ),
              const SizedBox(height: AppSpacing.space3),
            ],
            if (activeMember != null)
              AnimatedSwitcher(
                duration: AppMotion.resolveDuration(AppMotionPreset.slideInline),
                switchInCurve: AppMotionEasing.out,
                switchOutCurve: AppMotionEasing.out,
                layoutBuilder: (currentChild, previousChildren) => currentChild ?? const SizedBox.shrink(),
                transitionBuilder: (child, animation) {
                  final offsetAnimation = Tween<Offset>(
                    begin: const Offset(0, 0.04),
                    end: Offset.zero,
                  ).animate(animation);
                  return FadeTransition(
                    opacity: animation,
                    child: SlideTransition(position: offsetAnimation, child: child),
                  );
                },
                child: _StaffForm(
                  key: ValueKey(activeMember.id),
                  member: activeMember,
                  index: activeIndex >= 0 ? activeIndex : 0,
                  branchOptions: branchOptions,
                  errors: _mergedErrors,
                  isSaving: _savingStaffId == activeMember.id,
                  onSave: () => _saveStaff(draft.staff, activeMember.id, draft.branches.length, notifier),
                  onUpdate:
                      ({
                        String? name,
                        String? mobile,
                        String? username,
                        String? password,
                        String? role,
                        List<String>? branchIds,
                      }) => updateStaff(
                        activeMember.id,
                        name: name,
                        mobile: mobile,
                        username: username,
                        password: password,
                        role: role,
                        branchIds: branchIds,
                      ),
                  onRemove: () => removeStaff(activeMember.id),
                  canRemove: true,
                ),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.space4),
        AppButton(
          variant: AppButtonVariant.secondary,
          onPressed: addStaff,
          leadingIcon: const Icon(Icons.add, size: 16),
          child: const Text('Add another staff member'),
        ),
      ],
    );
  }
}

class _StaffForm extends StatelessWidget {
  const _StaffForm({
    required this.member,
    required this.index,
    required this.branchOptions,
    required this.errors,
    required this.isSaving,
    required this.onSave,
    required this.onUpdate,
    required this.onRemove,
    required this.canRemove,
    super.key,
  });

  final StaffDraft member;
  final int index;
  final List<AppComboboxItem> branchOptions;
  final Map<String, String> errors;
  final bool isSaving;
  final Future<void> Function() onSave;
  final void Function({
    String? name,
    String? mobile,
    String? username,
    String? password,
    String? role,
    List<String>? branchIds,
  })
  onUpdate;
  final VoidCallback onRemove;
  final bool canRemove;

  @override
  Widget build(BuildContext context) {
    final prefix = 'staff-$index';
    final selectedBranches = branchOptions.where((option) => member.branchIds.contains(option.id)).toList();

    return AppCard(
      variant: CardVariant.flat,
      padding: CardPadding.lg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  member.name.isNotEmpty ? member.name : 'Staff member ${index + 1}',
                  style: AppTypography.bodyStrong(context),
                ),
              ),
              if (canRemove)
                AppIconButton(
                  icon: const Icon(Icons.delete_outline, size: 16),
                  label: 'Remove staff member',
                  variant: AppIconButtonVariant.danger,
                  size: AppIconButtonSize.sm,
                  onPressed: onRemove,
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.space4),
          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 640;
              if (isWide) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: AppFormField(
                        id: '${member.id}-name',
                        label: 'Full name',
                        requiredMark: true,
                        hint: SetupFieldHints.staffName,
                        error: errors['$prefix-name'],
                        child: AppTextInput(
                          id: '${member.id}-name',
                          initialValue: member.name,
                          onChanged: (name) => onUpdate(name: name),
                          placeholder: 'e.g. Dr. Sara Hassan',
                          invalid: errors['$prefix-name'] != null,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.space4),
                    Expanded(
                      child: AppFormField(
                        id: '${member.id}-mobile',
                        label: 'Mobile',
                        requiredMark: true,
                        hint: SetupFieldHints.staffMobile,
                        error: errors['$prefix-mobile'],
                        child: AppPhoneInput(
                          id: '${member.id}-mobile',
                          initialValue: member.mobile,
                          onValueChange: (mobile) => onUpdate(mobile: mobile),
                          invalid: errors['$prefix-mobile'] != null,
                        ),
                      ),
                    ),
                  ],
                );
              }

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppFormField(
                    id: '${member.id}-name',
                    label: 'Full name',
                    requiredMark: true,
                    hint: SetupFieldHints.staffName,
                    error: errors['$prefix-name'],
                    child: AppTextInput(
                      id: '${member.id}-name',
                      initialValue: member.name,
                      onChanged: (name) => onUpdate(name: name),
                      placeholder: 'e.g. Dr. Sara Hassan',
                      invalid: errors['$prefix-name'] != null,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.space4),
                  AppFormField(
                    id: '${member.id}-mobile',
                    label: 'Mobile',
                    requiredMark: true,
                    hint: SetupFieldHints.staffMobile,
                    error: errors['$prefix-mobile'],
                    child: AppPhoneInput(
                      id: '${member.id}-mobile',
                      initialValue: member.mobile,
                      onValueChange: (mobile) => onUpdate(mobile: mobile),
                      invalid: errors['$prefix-mobile'] != null,
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: AppSpacing.space4),
          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 640;
              if (isWide) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: AppFormField(
                        id: '${member.id}-username',
                        label: 'Username',
                        requiredMark: true,
                        hint: SetupFieldHints.staffUsername,
                        error: errors['$prefix-username'],
                        child: AppTextInput(
                          id: '${member.id}-username',
                          initialValue: member.username,
                          onChanged: (username) => onUpdate(username: username),
                          placeholder: 'e.g. sara_hassan',
                          invalid: errors['$prefix-username'] != null,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.space4),
                    Expanded(
                      child: AppFormField(
                        id: '${member.id}-password',
                        label: 'Password',
                        requiredMark: true,
                        hint: SetupFieldHints.staffPassword,
                        error: errors['$prefix-password'],
                        child: AppPasswordInput(
                          id: '${member.id}-password',
                          initialValue: member.password,
                          onChanged: (password) => onUpdate(password: password),
                          invalid: errors['$prefix-password'] != null,
                        ),
                      ),
                    ),
                  ],
                );
              }

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppFormField(
                    id: '${member.id}-username',
                    label: 'Username',
                    requiredMark: true,
                    hint: SetupFieldHints.staffUsername,
                    error: errors['$prefix-username'],
                    child: AppTextInput(
                      id: '${member.id}-username',
                      initialValue: member.username,
                      onChanged: (username) => onUpdate(username: username),
                      placeholder: 'e.g. sara_hassan',
                      invalid: errors['$prefix-username'] != null,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.space4),
                  AppFormField(
                    id: '${member.id}-password',
                    label: 'Password',
                    requiredMark: true,
                    hint: SetupFieldHints.staffPassword,
                    error: errors['$prefix-password'],
                    child: AppPasswordInput(
                      id: '${member.id}-password',
                      initialValue: member.password,
                      onChanged: (password) => onUpdate(password: password),
                      invalid: errors['$prefix-password'] != null,
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: AppSpacing.space4),
          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 640;
              if (isWide) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: AppFormField(
                        id: '${member.id}-role',
                        label: 'Role',
                        requiredMark: true,
                        hint: SetupFieldHints.staffRole,
                        error: errors['$prefix-role'],
                        child: AppSelect(
                          id: '${member.id}-role',
                          value: member.role,
                          onChanged: (role) => onUpdate(role: role),
                          options: STAFF_ROLE_OPTIONS
                              .map((option) => AppSelectOption(value: option.value, label: option.label))
                              .toList(),
                          invalid: errors['$prefix-role'] != null,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.space4),
                    Expanded(
                      child: AppFormField(
                        id: '${member.id}-branches',
                        label: 'Branches assigned',
                        requiredMark: true,
                        hint: SetupFieldHints.staffBranches,
                        error: errors['$prefix-branches'],
                        child: AppMultiSelect(
                          id: '${member.id}-branches',
                          value: selectedBranches,
                          onValueChange: (items) => onUpdate(branchIds: items.map((item) => item.id).toList()),
                          options: branchOptions,
                          placeholder: 'Select branches',
                          invalid: errors['$prefix-branches'] != null,
                          disabled: branchOptions.isEmpty,
                        ),
                      ),
                    ),
                  ],
                );
              }

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppFormField(
                    id: '${member.id}-role',
                    label: 'Role',
                    requiredMark: true,
                    hint: SetupFieldHints.staffRole,
                    error: errors['$prefix-role'],
                    child: AppSelect(
                      id: '${member.id}-role',
                      value: member.role,
                      onChanged: (role) => onUpdate(role: role),
                      options: STAFF_ROLE_OPTIONS
                          .map((option) => AppSelectOption(value: option.value, label: option.label))
                          .toList(),
                      invalid: errors['$prefix-role'] != null,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.space4),
                  AppFormField(
                    id: '${member.id}-branches',
                    label: 'Branches assigned',
                    requiredMark: true,
                    hint: SetupFieldHints.staffBranches,
                    error: errors['$prefix-branches'],
                    child: AppMultiSelect(
                      id: '${member.id}-branches',
                      value: selectedBranches,
                      onValueChange: (items) => onUpdate(branchIds: items.map((item) => item.id).toList()),
                      options: branchOptions,
                      placeholder: 'Select branches',
                      invalid: errors['$prefix-branches'] != null,
                      disabled: branchOptions.isEmpty,
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: AppSpacing.space6),
          SizedBox(
            width: double.infinity,
            child: AppButton(
              variant: AppButtonVariant.primary,
              loading: isSaving,
              disabled: isSaving,
              onPressed: isSaving ? null : onSave,
              child: Text(isSaving ? 'Validating…' : 'Save staff member'),
            ),
          ),
        ],
      ),
    );
  }
}

class _StaffStepHeader extends StatelessWidget {
  const _StaffStepHeader({required this.colors});

  final AppSemanticColors colors;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(color: AppColorPrimitives.teal50, borderRadius: BorderRadius.circular(12)),
          child: const SizedBox(
            width: 44,
            height: 44,
            child: Icon(Icons.group, size: 22, color: AppColorPrimitives.teal700),
          ),
        ),
        const SizedBox(width: AppSpacing.space4),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Staff', style: AppTypography.h2(context).copyWith(color: colors.textPrimary)),
              const SizedBox(height: AppSpacing.space1),
              Text(
                'Create accounts for your team. Each person needs a role and at least one branch assignment.',
                style: AppTypography.body(context).copyWith(color: colors.textSecondary),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
