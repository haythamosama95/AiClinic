import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/components/app_button.dart';
import 'package:ai_clinic/core/ui/components/app_card.dart';
import 'package:ai_clinic/core/ui/components/app_form_field.dart';
import 'package:ai_clinic/core/ui/components/app_icon_button.dart';
import 'package:ai_clinic/core/ui/components/app_phone_input.dart';
import 'package:ai_clinic/core/ui/components/app_text_input.dart';
import 'package:ai_clinic/core/ui/motion/app_motion.dart';
import 'package:ai_clinic/core/ui/theme/app_color_primitives.dart';
import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';
import 'package:ai_clinic/features/settings/presentation/providers/clinic_setup_draft_notifier.dart';
import 'package:ai_clinic/features/settings/presentation/setup/setup_draft_models.dart';
import 'package:ai_clinic/features/settings/presentation/setup/setup_field_hints.dart';
import 'package:ai_clinic/features/settings/presentation/setup/setup_validation.dart';
import 'package:ai_clinic/features/settings/presentation/setup/widgets/collapsed_branch_card.dart';
import 'package:ai_clinic/features/settings/presentation/setup/widgets/maps_location_input.dart';
import 'package:ai_clinic/features/settings/presentation/setup/widgets/working_hours_editor.dart';

/// Branch step (web `BranchStep`).
class BranchStep extends StatefulWidget {
  const BranchStep({required this.errors, super.key});

  final Map<String, String> errors;

  @override
  State<BranchStep> createState() => _BranchStepState();
}

class _BranchStepState extends State<BranchStep> {
  late String _activeBranchId;
  final Set<String> _confirmedIds = {};
  Map<String, String> _localErrors = {};

  @override
  void initState() {
    super.initState();
    _activeBranchId = '';
  }

  Map<String, String> get _mergedErrors => {...widget.errors, ..._localErrors};

  Map<String, String> _branchDayErrors(Map<String, String> errors, String prefix) {
    final dayErrors = <String, String>{};
    final marker = '$prefix-';
    for (final entry in errors.entries) {
      if (entry.key.startsWith(marker) && entry.key.endsWith('-time')) {
        dayErrors[entry.key.substring(prefix.length + 1)] = entry.value;
      }
    }
    return dayErrors;
  }

  bool _validateAndConfirm(List<BranchDraft> branches, String branchId) {
    final index = branches.indexWhere((branch) => branch.id == branchId);
    if (index < 0) return true;

    final branchErrors = validateSingleBranch(branches[index], index, allBranches: branches);
    if (hasErrors(branchErrors)) {
      setState(() => _localErrors = branchErrors);
      return false;
    }

    setState(() {
      _localErrors = {};
      _confirmedIds.add(branchId);
    });
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (context, ref, _) {
        final draft = ref.watch(clinicSetupDraftProvider.select((state) => state.draft));
        final notifier = ref.read(clinicSetupDraftProvider.notifier);
        final colors = context.appColors;

        if (_activeBranchId.isEmpty && draft.branches.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            setState(() => _activeBranchId = draft.branches.first.id);
          });
        }

        final resolvedActiveId = draft.branches.any((branch) => branch.id == _activeBranchId)
            ? _activeBranchId
            : (draft.branches.isNotEmpty ? draft.branches.first.id : '');
        final activeIndex = draft.branches.indexWhere((branch) => branch.id == resolvedActiveId);
        final activeBranch = activeIndex >= 0 ? draft.branches[activeIndex] : null;

        void updateBranch(
          String id, {
          String? name,
          String? code,
          String? mobile,
          String? mapLocation,
          List<WorkingDay>? workingDays,
        }) {
          notifier.updateBranch(
            id,
            name: name,
            code: code,
            mobile: mobile,
            mapLocation: mapLocation,
            workingDays: workingDays,
          );
        }

        void removeBranch(String id) {
          final next = draft.branches.where((branch) => branch.id != id).toList();
          notifier.setBranches(next);
          setState(() {
            _confirmedIds.remove(id);
            if (id == _activeBranchId) {
              _activeBranchId = next.isNotEmpty ? next.last.id : '';
            }
            _localErrors = {};
          });
        }

        void addBranch() {
          if (activeBranch == null) return;
          if (!_validateAndConfirm(draft.branches, activeBranch.id)) return;

          final newBranch = notifier.addBranch();
          setState(() => _activeBranchId = newBranch.id);
        }

        void expandBranch(String branchId) {
          if (branchId == resolvedActiveId) return;

          if (activeBranch != null && !_confirmedIds.contains(activeBranch.id)) {
            if (!_validateAndConfirm(draft.branches, activeBranch.id)) return;
          }

          setState(() {
            _localErrors = {};
            _activeBranchId = branchId;
          });
        }

        final collapsedBranches = draft.branches
            .where((branch) => branch.id != resolvedActiveId && _confirmedIds.contains(branch.id))
            .toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppColorPrimitives.violet50,
                    borderRadius: BorderRadius.circular(AppRadius.xl),
                  ),
                  child: const SizedBox(
                    width: 44,
                    height: 44,
                    child: Icon(Icons.location_on, size: 22, color: AppColorPrimitives.violet600),
                  ),
                ),
                const SizedBox(width: AppSpacing.space4),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Branches', style: AppTypography.h2(context).copyWith(color: colors.textPrimary)),
                      const SizedBox(height: AppSpacing.space1),
                      Text(
                        'Add every location where patients are seen. Each branch needs a unique code for scheduling and billing.',
                        style: AppTypography.body(context).copyWith(color: colors.textSecondary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.space6),
            if (_mergedErrors['_form'] != null) ...[
              Semantics(
                liveRegion: true,
                child: Text(
                  _mergedErrors['_form']!,
                  style: AppTypography.body(context).copyWith(color: colors.statusDangerFg),
                ),
              ),
              const SizedBox(height: AppSpacing.space4),
            ],
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final branch in collapsedBranches) ...[
                  CollapsedBranchCard(
                    key: ValueKey('collapsed-${branch.id}'),
                    branch: branch,
                    index: draft.branches.indexWhere((item) => item.id == branch.id),
                    onExpand: () => expandBranch(branch.id),
                    onRemove: () => removeBranch(branch.id),
                    canRemove: draft.branches.length > 1,
                  ),
                  const SizedBox(height: AppSpacing.space3),
                ],
                if (activeBranch != null)
                  AnimatedSwitcher(
                    duration: AppMotion.resolveDuration(AppMotionPreset.slideInline),
                    switchInCurve: AppMotionEasing.out,
                    switchOutCurve: AppMotionEasing.out,
                    // Only mount the active branch form. Keeping previous children
                    // duplicates AppTimePicker/AppPopover GlobalKeys during the transition.
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
                    child: _BranchForm(
                      key: ValueKey(activeBranch.id),
                      branch: activeBranch,
                      index: activeIndex >= 0 ? activeIndex : 0,
                      errors: _mergedErrors,
                      dayErrors: _branchDayErrors(_mergedErrors, 'branch-${activeIndex >= 0 ? activeIndex : 0}'),
                      onUpdate: (patch) => updateBranch(
                        activeBranch.id,
                        name: patch.name,
                        code: patch.code,
                        mobile: patch.mobile,
                        mapLocation: patch.mapLocation,
                        workingDays: patch.workingDays,
                      ),
                      onRemove: () => removeBranch(activeBranch.id),
                      canRemove: draft.branches.length > 1,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.space4),
            AppButton(
              variant: AppButtonVariant.secondary,
              onPressed: addBranch,
              leadingIcon: const Icon(Icons.add, size: 16),
              child: const Text('Add another branch'),
            ),
          ],
        );
      },
    );
  }
}

class _BranchFormPatch {
  const _BranchFormPatch({this.name, this.code, this.mobile, this.mapLocation, this.workingDays});

  final String? name;
  final String? code;
  final String? mobile;
  final String? mapLocation;
  final List<WorkingDay>? workingDays;
}

class _BranchForm extends StatelessWidget {
  const _BranchForm({
    required this.branch,
    required this.index,
    required this.errors,
    required this.dayErrors,
    required this.onUpdate,
    required this.onRemove,
    required this.canRemove,
    super.key,
  });

  final BranchDraft branch;
  final int index;
  final Map<String, String> errors;
  final Map<String, String> dayErrors;
  final void Function(_BranchFormPatch patch) onUpdate;
  final VoidCallback onRemove;
  final bool canRemove;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final prefix = 'branch-$index';
    final hoursError = errors['$prefix-hours'];

    return AppCard(
      variant: CardVariant.flat,
      padding: CardPadding.lg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(child: Text('Branch ${index + 1}', style: AppTypography.bodyStrong(context))),
              if (canRemove)
                AppIconButton(
                  icon: const Icon(Icons.delete_outline, size: 16),
                  label: 'Remove branch',
                  variant: AppIconButtonVariant.ghost,
                  size: AppIconButtonSize.sm,
                  onPressed: onRemove,
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.space4),
          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 640;
              final nameField = AppFormField(
                id: '${branch.id}-name',
                label: 'Branch name',
                requiredMark: true,
                hint: SetupFieldHints.branchName,
                error: errors['$prefix-name'],
                child: AppTextInput(
                  id: '${branch.id}-name',
                  initialValue: branch.name,
                  onChanged: (name) => onUpdate(_BranchFormPatch(name: name)),
                  placeholder: 'e.g. Zamalek',
                  invalid: errors['$prefix-name'] != null,
                ),
              );
              final codeField = AppFormField(
                id: '${branch.id}-code',
                label: 'Branch code',
                requiredMark: true,
                hint: SetupFieldHints.branchCode,
                error: errors['$prefix-code'],
                child: AppTextInput(
                  id: '${branch.id}-code',
                  initialValue: branch.code,
                  onChanged: (code) => onUpdate(_BranchFormPatch(code: code.toUpperCase())),
                  placeholder: 'e.g. ZML',
                  invalid: errors['$prefix-code'] != null,
                ),
              );

              if (isWide) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: nameField),
                    const SizedBox(width: AppSpacing.space4),
                    Expanded(child: codeField),
                  ],
                );
              }

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  nameField,
                  const SizedBox(height: AppSpacing.space4),
                  codeField,
                ],
              );
            },
          ),
          const SizedBox(height: AppSpacing.space4),
          AppFormField(
            id: '${branch.id}-mobile',
            label: 'Mobile',
            requiredMark: true,
            hint: SetupFieldHints.branchMobile,
            error: errors['$prefix-mobile'],
            child: AppPhoneInput(
              id: '${branch.id}-mobile',
              initialValue: branch.mobile,
              onValueChange: (mobile) => onUpdate(_BranchFormPatch(mobile: mobile)),
              invalid: errors['$prefix-mobile'] != null,
            ),
          ),
          const SizedBox(height: AppSpacing.space4),
          MapsLocationInput(
            id: '${branch.id}-map',
            value: branch.mapLocation,
            onChange: (mapLocation) => onUpdate(_BranchFormPatch(mapLocation: mapLocation)),
            error: errors['$prefix-map'],
            invalid: errors['$prefix-map'] != null,
          ),
          if (hoursError != null) ...[
            const SizedBox(height: AppSpacing.space2),
            Semantics(
              liveRegion: true,
              child: Text(hoursError, style: AppTypography.caption(context).copyWith(color: colors.statusDangerFg)),
            ),
          ],
          const SizedBox(height: AppSpacing.space4),
          WorkingHoursEditor(
            value: branch.workingDays,
            onChange: (workingDays) => onUpdate(_BranchFormPatch(workingDays: workingDays)),
            errors: dayErrors,
          ),
        ],
      ),
    );
  }
}
