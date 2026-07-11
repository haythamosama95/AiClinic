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
import 'package:ai_clinic/features/setup/presentation/providers/clinic_setup_notifier.dart';
import 'package:ai_clinic/features/setup/presentation/setup/setup_draft_models.dart';
import 'package:ai_clinic/features/setup/presentation/setup/setup_field_hints.dart';
import 'package:ai_clinic/features/setup/presentation/setup/setup_form_layout.dart';
import 'package:ai_clinic/features/setup/presentation/setup/setup_validation.dart';
import 'package:ai_clinic/features/setup/presentation/setup/widgets/collapsed_branch_card.dart';
import 'package:ai_clinic/features/setup/presentation/setup/widgets/collapsed_summary_enter_transition.dart';
import 'package:ai_clinic/features/setup/presentation/setup/widgets/maps_location_input.dart';
import 'package:ai_clinic/features/setup/presentation/setup/widgets/working_hours_editor.dart';

/// Branch step (web `BranchStep`).
class BranchStep extends StatefulWidget {
  const BranchStep({required this.errors, this.bootstrapMode = false, super.key});

  final Map<String, String> errors;
  final bool bootstrapMode;

  @override
  State<BranchStep> createState() => _BranchStepState();
}

class _BranchStepState extends State<BranchStep> {
  late String _activeBranchId;
  Map<String, String> _localErrors = {};
  String? _savingBranchId;

  @override
  void initState() {
    super.initState();
    _activeBranchId = '';
  }

  Map<String, String> get _mergedErrors => {...widget.errors, ..._localErrors};

  String? _resolveActiveBranchId(List<BranchDraft> branches, Set<String> confirmedIds) {
    if (_activeBranchId.isNotEmpty && !confirmedIds.contains(_activeBranchId)) {
      if (branches.any((branch) => branch.id == _activeBranchId)) {
        return _activeBranchId;
      }
    }

    for (final branch in branches) {
      if (!confirmedIds.contains(branch.id)) {
        return branch.id;
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

  bool _validateAndConfirm(
    List<BranchDraft> branches,
    String branchId,
    ClinicSetupNotifier notifier,
    Set<String> confirmedIds,
  ) {
    final index = branches.indexWhere((branch) => branch.id == branchId);
    if (index < 0) return true;

    final branchErrors = validateSingleBranch(branches[index], index, allBranches: branches);
    if (hasErrors(branchErrors)) {
      setState(() => _localErrors = branchErrors);
      return false;
    }

    setState(() {
      _localErrors = {};
      if (_activeBranchId == branchId) {
        _activeBranchId = '';
      }
    });
    notifier.confirmBranch(branchId);
    return true;
  }

  Future<void> _saveBranch(List<BranchDraft> branches, String branchId, ClinicSetupNotifier notifier) async {
    if (_savingBranchId != null) return;

    setState(() => _savingBranchId = branchId);
    final startedAt = DateTime.now();
    await Future<void>.delayed(Duration.zero);

    final index = branches.indexWhere((branch) => branch.id == branchId);
    if (index < 0) {
      if (mounted) setState(() => _savingBranchId = null);
      return;
    }

    final branchErrors = validateSingleBranch(branches[index], index, allBranches: branches);
    await _ensureMinLoadingDuration(startedAt);
    if (!mounted) return;

    if (hasErrors(branchErrors)) {
      setState(() {
        _localErrors = branchErrors;
        _savingBranchId = null;
      });
      return;
    }

    setState(() {
      _localErrors = {};
      _activeBranchId = '';
      _savingBranchId = null;
    });
    notifier.confirmBranch(branchId);
  }

  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (context, ref, _) {
        final draft = ref.watch(clinicSetupProvider.select((state) => state.draft));
        final confirmedIds = ref.watch(clinicSetupProvider.select((state) => state.confirmedBranchIds));
        final focusBranchId = ref.watch(clinicSetupProvider.select((state) => state.validationFocusEntityId));
        final notifier = ref.read(clinicSetupProvider.notifier);
        final colors = context.appColors;

        if (focusBranchId != null && focusBranchId != _activeBranchId) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            setState(() => _activeBranchId = focusBranchId);
            notifier.clearValidationFocus();
          });
        }

        if (_activeBranchId.isEmpty && draft.branches.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            final nextActiveId = _resolveActiveBranchId(draft.branches, confirmedIds);
            if (nextActiveId != null) {
              setState(() => _activeBranchId = nextActiveId);
            }
          });
        }

        final resolvedActiveId = _resolveActiveBranchId(draft.branches, confirmedIds);
        final activeIndex = resolvedActiveId == null
            ? -1
            : draft.branches.indexWhere((branch) => branch.id == resolvedActiveId);
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
          if (confirmedIds.contains(id)) {
            notifier.unconfirmBranch(id);
          }
        }

        void removeBranch(String id) {
          notifier.removeBranch(id);
          final branches = ref.read(clinicSetupProvider).draft.branches;
          setState(() {
            if (branches.isEmpty) {
              final newBranch = notifier.addBranch();
              _activeBranchId = newBranch.id;
            } else if (id == _activeBranchId) {
              _activeBranchId = branches.last.id;
            }
            _localErrors = {};
          });
        }

        void addBranch() {
          if (activeBranch == null) return;
          if (!_validateAndConfirm(draft.branches, activeBranch.id, notifier, confirmedIds)) return;

          final newBranch = notifier.addBranch();
          setState(() {
            _activeBranchId = newBranch.id;
            _localErrors = {};
          });
        }

        void expandBranch(String branchId) {
          if (branchId == resolvedActiveId) return;

          if (activeBranch != null && !confirmedIds.contains(activeBranch.id)) {
            if (!_validateAndConfirm(draft.branches, activeBranch.id, notifier, confirmedIds)) return;
          }

          setState(() {
            _localErrors = {};
            _activeBranchId = branchId;
          });
          notifier.unconfirmBranch(branchId);
        }

        final collapsedBranches = draft.branches.where((branch) => confirmedIds.contains(branch.id)).toList();

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
                        widget.bootstrapMode
                            ? 'Add your first clinic location. You can add more branches after setup is complete.'
                            : 'Add every location where patients are seen. Each branch needs a unique code for scheduling and billing.',
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
                      isSaving: _savingBranchId == activeBranch.id,
                      onSave: () => _saveBranch(draft.branches, activeBranch.id, notifier),
                      onUpdate: (patch) => updateBranch(
                        activeBranch.id,
                        name: patch.name,
                        code: patch.code,
                        mobile: patch.mobile,
                        mapLocation: patch.mapLocation,
                        workingDays: patch.workingDays,
                      ),
                      onRemove: () => removeBranch(activeBranch.id),
                      canRemove: true,
                    ),
                  ),
              ],
            ),
            if (!widget.bootstrapMode) ...[
              const SizedBox(height: AppSpacing.space4),
              AppButton(
                variant: AppButtonVariant.secondary,
                onPressed: addBranch,
                leadingIcon: const Icon(Icons.add, size: 16),
                child: const Text('Add another branch'),
              ),
            ],
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
    required this.isSaving,
    required this.onSave,
    required this.onUpdate,
    required this.onRemove,
    required this.canRemove,
    super.key,
  });

  final BranchDraft branch;
  final int index;
  final Map<String, String> errors;
  final Map<String, String> dayErrors;
  final bool isSaving;
  final Future<void> Function() onSave;
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
                  variant: AppIconButtonVariant.danger,
                  size: AppIconButtonSize.sm,
                  onPressed: onRemove,
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.space4),
          Builder(
            builder: (context) {
              final useTwoColumns = setupFormUseTwoColumns(context);
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

              if (useTwoColumns) {
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
          const SizedBox(height: AppSpacing.space6),
          SizedBox(
            width: double.infinity,
            child: AppButton(
              variant: AppButtonVariant.primary,
              loading: isSaving,
              disabled: isSaving,
              onPressed: isSaving ? null : onSave,
              child: Text(isSaving ? 'Validating…' : 'Save branch'),
            ),
          ),
        ],
      ),
    );
  }
}
