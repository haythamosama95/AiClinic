import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/components/app_combobox.dart';
import 'package:ai_clinic/core/ui/components/app_form_field.dart';
import 'package:ai_clinic/core/ui/components/app_multi_select.dart';
import 'package:ai_clinic/core/ui/components/app_password_input.dart';
import 'package:ai_clinic/core/ui/components/app_phone_input.dart';
import 'package:ai_clinic/core/ui/components/app_select.dart';
import 'package:ai_clinic/core/ui/components/app_text_input.dart';
import 'package:ai_clinic/core/ui/theme/app_color_primitives.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';
import 'package:ai_clinic/features/settings/presentation/providers/clinic_setup_draft_notifier.dart';
import 'package:ai_clinic/features/settings/presentation/setup/setup_draft_models.dart';
import 'package:ai_clinic/features/settings/presentation/setup/setup_field_hints.dart';
import 'package:ai_clinic/features/settings/presentation/setup/widgets/entity_list.dart';

/// Staff step (web `StaffStep`).
class StaffStep extends ConsumerWidget {
  const StaffStep({required this.errors, super.key});

  final Map<String, String> errors;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draft = ref.watch(clinicSetupDraftProvider.select((state) => state.draft));
    final notifier = ref.read(clinicSetupDraftProvider.notifier);
    final colors = context.appColors;

    final branchOptions = draft.branches
        .map(
          (branch) => AppComboboxItem(
            id: branch.id,
            label: branch.name.isNotEmpty ? branch.name : (branch.code.isNotEmpty ? branch.code : 'Unnamed branch'),
            meta: branch.code.isNotEmpty ? branch.code : null,
          ),
        )
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _StaffStepHeader(colors: colors),
        const SizedBox(height: AppSpacing.space6),
        if (errors['_form'] != null) ...[
          Semantics(
            liveRegion: true,
            child: Text(errors['_form']!, style: AppTypography.bodySm(context).copyWith(color: colors.statusDangerFg)),
          ),
          const SizedBox(height: AppSpacing.space4),
        ],
        EntityList<StaffDraft>(
          items: draft.staff,
          itemId: (member) => member.id,
          getItemLabel: (member, index) => member.name.isNotEmpty ? member.name : 'New staff member',
          onAdd: notifier.addStaff,
          onRemove: notifier.removeStaff,
          addLabel: 'Add another staff member',
          renderItem: (member, index) {
            final prefix = 'staff-$index';
            final selectedBranches = branchOptions.where((option) => member.branchIds.contains(option.id)).toList();

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
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
                                onChanged: (name) => notifier.updateStaff(member.id, name: name),
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
                                onValueChange: (mobile) => notifier.updateStaff(member.id, mobile: mobile),
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
                            onChanged: (name) => notifier.updateStaff(member.id, name: name),
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
                            onValueChange: (mobile) => notifier.updateStaff(member.id, mobile: mobile),
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
                                onChanged: (username) => notifier.updateStaff(member.id, username: username),
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
                                onChanged: (password) => notifier.updateStaff(member.id, password: password),
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
                            onChanged: (username) => notifier.updateStaff(member.id, username: username),
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
                            onChanged: (password) => notifier.updateStaff(member.id, password: password),
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
                                onChanged: (role) => notifier.updateStaff(member.id, role: role),
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
                                onValueChange: (items) =>
                                    notifier.updateStaff(member.id, branchIds: items.map((item) => item.id).toList()),
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
                            onChanged: (role) => notifier.updateStaff(member.id, role: role),
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
                            onValueChange: (items) =>
                                notifier.updateStaff(member.id, branchIds: items.map((item) => item.id).toList()),
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
              ],
            );
          },
        ),
      ],
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
