import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/components/app_form_field.dart';
import 'package:ai_clinic/core/ui/components/app_select.dart';
import 'package:ai_clinic/core/ui/components/app_text_input.dart';
import 'package:ai_clinic/core/ui/theme/app_color_primitives.dart';
import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';
import 'package:ai_clinic/features/settings/presentation/providers/clinic_setup_draft_notifier.dart';
import 'package:ai_clinic/features/settings/presentation/setup/setup_draft_models.dart';
import 'package:ai_clinic/features/settings/presentation/setup/setup_field_hints.dart';

/// Organization step (web `OrganizationStep`).
class OrganizationStep extends ConsumerWidget {
  const OrganizationStep({required this.errors, super.key});

  final Map<String, String> errors;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final organization = ref.watch(
      clinicSetupDraftProvider.select((state) => state.draft.organization),
    );
    final notifier = ref.read(clinicSetupDraftProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _StepHeader(
          icon: Icons.business,
          iconBackground: AppColorPrimitives.teal50,
          iconColor: AppColorPrimitives.teal600,
          title: 'Your organization',
          description:
              'Set the legal name and regional defaults for your clinic. These apply across every branch.',
        ),
        const SizedBox(height: AppSpacing.space6),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 576),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              AppFormField(
                id: 'org-name',
                label: 'Organization name',
                requiredMark: true,
                hint: SetupFieldHints.organizationName,
                error: errors['name'],
                child: AppTextInput(
                  id: 'org-name',
                  initialValue: organization.name,
                  onChanged: (name) => notifier.updateOrganization(name: name),
                  placeholder: 'e.g. Nile Dental Group',
                  invalid: errors['name'] != null,
                ),
              ),
              const SizedBox(height: AppSpacing.space4),
              AppFormField(
                id: 'org-timezone',
                label: 'Timezone',
                requiredMark: true,
                hint: SetupFieldHints.timezone,
                error: errors['timezone'],
                child: AppSelect(
                  id: 'org-timezone',
                  value: organization.timezone,
                  onChanged: (timezone) => notifier.updateOrganization(timezone: timezone),
                  options: TIMEZONE_OPTIONS
                      .map((option) => AppSelectOption(value: option.value, label: option.label))
                      .toList(),
                  invalid: errors['timezone'] != null,
                ),
              ),
              const SizedBox(height: AppSpacing.space4),
              AppFormField(
                id: 'org-currency',
                label: 'Currency',
                requiredMark: true,
                hint: SetupFieldHints.currency,
                error: errors['currency'],
                child: AppSelect(
                  id: 'org-currency',
                  value: organization.currency,
                  onChanged: (currency) => notifier.updateOrganization(currency: currency),
                  options: CURRENCY_OPTIONS
                      .map((option) => AppSelectOption(value: option.value, label: option.label))
                      .toList(),
                  invalid: errors['currency'] != null,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StepHeader extends StatelessWidget {
  const _StepHeader({
    required this.icon,
    required this.iconBackground,
    required this.iconColor,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final Color iconBackground;
  final Color iconColor;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: iconBackground,
            borderRadius: BorderRadius.circular(AppRadius.xl),
          ),
          child: SizedBox(
            width: 44,
            height: 44,
            child: Icon(icon, size: 22, color: iconColor),
          ),
        ),
        const SizedBox(width: AppSpacing.space4),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, style: AppTypography.h2(context).copyWith(color: colors.textPrimary)),
              const SizedBox(height: AppSpacing.space1),
              Text(
                description,
                style: AppTypography.body(context).copyWith(color: colors.textSecondary),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
