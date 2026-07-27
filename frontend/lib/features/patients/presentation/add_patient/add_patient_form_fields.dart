import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/l10n/app_localizations_x.dart';
import 'package:ai_clinic/core/ui/components/app_avatar.dart';
import 'package:ai_clinic/core/ui/components/app_date_picker.dart';
import 'package:ai_clinic/core/ui/components/app_divider.dart';
import 'package:ai_clinic/core/ui/components/app_form_field.dart';
import 'package:ai_clinic/core/ui/components/app_phone_input.dart';
import 'package:ai_clinic/core/ui/components/app_section_header.dart';
import 'package:ai_clinic/core/ui/components/app_select.dart';
import 'package:ai_clinic/core/ui/components/app_text_input.dart';
import 'package:ai_clinic/core/ui/components/app_textarea.dart';
import 'package:ai_clinic/core/ui/motion/app_motion.dart';
import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';
import 'package:ai_clinic/features/patients/domain/patient_gender.dart';
import 'package:ai_clinic/features/patients/domain/patient_marital_status.dart';
import 'package:ai_clinic/features/patients/domain/patient_row_parsing.dart';
import 'package:ai_clinic/features/patients/presentation/models/patient_registration_form.dart';
import 'package:ai_clinic/features/clinic-management/presentation/providers/active_branch_name_provider.dart';
import 'package:ai_clinic/l10n/app_localizations.dart';

const _genderOptions = [PatientGender.male, PatientGender.female];

const _maritalStatusOptions = PatientMaritalStatus.values;

/// Add-patient form body (web `AddPatientFormFields`).
///
/// Shared with the edit-patient dialog via optional [branchName],
/// [branchBannerLabel], and [identityPreviewSubtitle].
class AddPatientFormFields extends ConsumerStatefulWidget {
  const AddPatientFormFields({
    required this.values,
    required this.errors,
    required this.trimmedName,
    required this.showPreview,
    required this.reducedMotion,
    required this.onSubmit,
    required this.onFieldChange,
    this.autoFocus = false,
    this.branchName,
    this.branchBannerLabel,
    this.identityPreviewSubtitle,
    this.fieldIdPrefix = 'add-patient',
    super.key,
  });

  final PatientRegistrationForm values;
  final PatientFormErrors errors;
  final String trimmedName;
  final bool showPreview;
  final bool reducedMotion;
  final bool autoFocus;
  final VoidCallback onSubmit;
  final void Function(String key, Object? value) onFieldChange;
  final String? branchName;
  final String? branchBannerLabel;
  final String? identityPreviewSubtitle;
  final String fieldIdPrefix;

  @override
  ConsumerState<AddPatientFormFields> createState() => _AddPatientFormFieldsState();
}

class _AddPatientFormFieldsState extends ConsumerState<AddPatientFormFields> {
  @override
  void didUpdateWidget(covariant AddPatientFormFields oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.autoFocus && !oldWidget.autoFocus) {
      _requestInitialFocus();
    }
  }

  @override
  void initState() {
    super.initState();
    if (widget.autoFocus) {
      _requestInitialFocus();
    }
  }

  void _requestInitialFocus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      FocusScope.of(context).nextFocus();
    });
  }

  KeyEventResult _handleFormKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent || event.logicalKey != LogicalKeyboardKey.enter) {
      return KeyEventResult.ignored;
    }

    final focusedContext = FocusManager.instance.primaryFocus?.context;
    if (focusedContext != null && focusedContext.findAncestorWidgetOfExactType<AppTextarea>() != null) {
      return KeyEventResult.ignored;
    }

    widget.onSubmit();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final branchName = widget.branchName ?? ref.watch(activeBranchNameProvider).value ?? l10n.yourActiveBranch;
    final branchBannerLabel = widget.branchBannerLabel ?? l10n.registeringAt;

    return Form(
      child: Focus(
        onKeyEvent: _handleFormKeyEvent,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            _BranchBanner(branchName: branchName, labelPrefix: branchBannerLabel),
            const SizedBox(height: AppSpacing.space6),
            _IdentityPreview(
              trimmedName: widget.trimmedName,
              showPreview: widget.showPreview,
              reducedMotion: widget.reducedMotion,
              subtitle: widget.identityPreviewSubtitle ?? l10n.newRecordMrsAssignedOnSave,
            ),
            const SizedBox(height: AppSpacing.space6),
            _PatientDetailsSection(
              values: widget.values,
              errors: widget.errors,
              autoFocus: widget.autoFocus,
              onFieldChange: widget.onFieldChange,
              fieldIdPrefix: widget.fieldIdPrefix,
            ),
            const SizedBox(height: AppSpacing.space6),
            const AppDivider(),
            const SizedBox(height: AppSpacing.space6),
            _ClinicalNotesSection(
              values: widget.values,
              errors: widget.errors,
              onFieldChange: widget.onFieldChange,
              fieldIdPrefix: widget.fieldIdPrefix,
            ),
            if (widget.errors.form != null) ...[
              const SizedBox(height: AppSpacing.space6),
              Semantics(
                liveRegion: true,
                child: Text(
                  widget.errors.form!,
                  style: AppTypography.bodySm(context).copyWith(color: context.appColors.statusDangerFg),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _BranchBanner extends StatelessWidget {
  const _BranchBanner({required this.branchName, required this.labelPrefix});

  final String branchName;
  final String labelPrefix;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceMuted.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: colors.borderSubtle),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space3, vertical: 10),
        child: Row(
          children: [
            Icon(Icons.location_on, size: 15, color: colors.iconMuted),
            const SizedBox(width: AppSpacing.space2),
            Expanded(
              child: Text.rich(
                TextSpan(
                  style: AppTypography.bodySm(context).copyWith(color: colors.textSecondary),
                  children: [
                    TextSpan(text: labelPrefix),
                    TextSpan(
                      text: branchName,
                      style: AppTypography.bodySm(
                        context,
                      ).copyWith(color: colors.textPrimary, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _IdentityPreview extends StatelessWidget {
  const _IdentityPreview({
    required this.trimmedName,
    required this.showPreview,
    required this.reducedMotion,
    required this.subtitle,
  });

  final String trimmedName;
  final bool showPreview;
  final bool reducedMotion;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final duration = reducedMotion ? Duration.zero : AppMotion.base;

    return AnimatedSwitcher(
      duration: duration,
      switchInCurve: AppMotion.outCurve,
      switchOutCurve: AppMotion.inCurve,
      transitionBuilder: (child, animation) {
        if (reducedMotion) {
          return child;
        }
        return FadeTransition(
          opacity: animation,
          child: AnimatedBuilder(
            animation: animation,
            builder: (context, child) {
              return Transform.translate(offset: Offset(0, -6 * (1 - animation.value)), child: child);
            },
            child: child,
          ),
        );
      },
      child: showPreview
          ? _IdentityPreviewCard(
              key: const ValueKey<String>('identity-preview'),
              trimmedName: trimmedName,
              subtitle: subtitle,
            )
          : const SizedBox.shrink(key: ValueKey<String>('identity-preview-empty')),
    );
  }
}

class _IdentityPreviewCard extends StatelessWidget {
  const _IdentityPreviewCard({required this.trimmedName, required this.subtitle, super.key});

  final String trimmedName;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: colors.borderSubtle),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [colors.surfaceMuted.withValues(alpha: 0.8), colors.surfaceDefault],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space4, vertical: 14),
        child: Row(
          children: [
            AppAvatar(name: trimmedName, size: AvatarSize.lg),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    trimmedName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.bodyStrong(context).copyWith(color: colors.textPrimary),
                  ),
                  Text(subtitle, style: AppTypography.caption(context).copyWith(color: colors.textTertiary)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PatientDetailsSection extends StatelessWidget {
  const _PatientDetailsSection({
    required this.values,
    required this.errors,
    required this.onFieldChange,
    required this.autoFocus,
    required this.fieldIdPrefix,
  });

  final PatientRegistrationForm values;
  final PatientFormErrors errors;
  final void Function(String key, Object? value) onFieldChange;
  final bool autoFocus;
  final String fieldIdPrefix;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        AppSectionHeader(
          title: l10n.patientDetailsSectionTitle,
          description: l10n.patientDetailsSectionDescription,
        ),
        const SizedBox(height: AppSpacing.space4),
        _buildPatientDetailsFields(context),
      ],
    );
  }

  Widget _buildPatientDetailsFields(BuildContext context) {
    final l10n = context.l10n;
    const fieldGap = SizedBox(height: AppSpacing.space4);
    const columnGap = SizedBox(width: AppSpacing.space4);

    final fullNameField = AppFormField(
      id: '$fieldIdPrefix-fullName',
      label: l10n.fullNameLabel,
      requiredMark: true,
      hint: l10n.fullNameHint,
      error: errors.fullName,
      child: Focus(
        autofocus: autoFocus,
        child: AppTextInput(
          id: '$fieldIdPrefix-fullName',
          initialValue: values.fullName,
          onChanged: (value) => onFieldChange('fullName', value),
          placeholder: l10n.fullNamePlaceholder,
          invalid: errors.fullName != null,
        ),
      ),
    );

    final dobField = AppFormField(
      id: '$fieldIdPrefix-dob',
      label: l10n.dateOfBirthLabel,
      hint: l10n.dateOfBirthHint,
      error: errors.dateOfBirth,
      child: AppDatePicker(
        id: '$fieldIdPrefix-dob',
        value: values.dateOfBirth,
        onChanged: (date) => onFieldChange('dateOfBirth', date == null ? null : normalizePatientDate(date)),
        placeholder: l10n.selectDate,
        max: DateTime.now(),
        invalid: errors.dateOfBirth != null,
      ),
    );

    final genderField = AppFormField(
      id: '$fieldIdPrefix-gender',
      label: l10n.genderLabel,
      hint: l10n.genderHint,
      error: errors.gender,
      child: AppSelect(
        id: '$fieldIdPrefix-gender',
        value: values.gender?.wireValue,
        onChanged: (value) => onFieldChange('gender', PatientGender.tryParse(value)),
        options: _genderOptions
            .map((gender) => AppSelectOption(value: gender.wireValue, label: _genderLabel(l10n, gender)))
            .toList(),
        placeholder: l10n.selectGender,
        invalid: errors.gender != null,
      ),
    );

    final phoneField = AppFormField(
      id: '$fieldIdPrefix-phone',
      label: l10n.mobileNumberLabel,
      hint: l10n.mobileNumberHint,
      error: errors.phone,
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: AppPhoneInput(
          id: '$fieldIdPrefix-phone',
          initialValue: values.phone,
          onValueChange: (phone) => onFieldChange('phone', phone),
          invalid: errors.phone != null,
        ),
      ),
    );

    final maritalField = AppFormField(
      id: '$fieldIdPrefix-maritalStatus',
      label: l10n.maritalStateLabel,
      hint: l10n.maritalStateHint,
      error: errors.maritalStatus,
      child: AppSelect(
        id: '$fieldIdPrefix-maritalStatus',
        value: values.maritalStatus?.wireValue,
        onChanged: (value) => onFieldChange('maritalStatus', PatientMaritalStatus.tryParse(value)),
        options: _maritalStatusOptions
            .map((status) => AppSelectOption(value: status.wireValue, label: _maritalStatusLabel(l10n, status)))
            .toList(),
        placeholder: l10n.selectMaritalState,
        invalid: errors.maritalStatus != null,
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        fullNameField,
        fieldGap,
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: dobField),
            columnGap,
            Expanded(child: genderField),
          ],
        ),
        fieldGap,
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: phoneField),
            columnGap,
            Expanded(child: maritalField),
          ],
        ),
      ],
    );
  }
}

class _ClinicalNotesSection extends StatelessWidget {
  const _ClinicalNotesSection({
    required this.values,
    required this.errors,
    required this.onFieldChange,
    required this.fieldIdPrefix,
  });

  final PatientRegistrationForm values;
  final PatientFormErrors errors;
  final void Function(String key, Object? value) onFieldChange;
  final String fieldIdPrefix;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        AppSectionHeader(
          title: l10n.clinicalNotesSectionTitle,
          description: l10n.clinicalNotesSectionDescription,
        ),
        const SizedBox(height: AppSpacing.space4),
        AppFormField(
          id: '$fieldIdPrefix-notes',
          label: l10n.notesLabel,
          helperText: l10n.notesHelperText,
          error: errors.notes,
          child: AppTextarea(
            id: '$fieldIdPrefix-notes',
            initialValue: values.notes,
            onChanged: (value) => onFieldChange('notes', value),
            placeholder: l10n.notesPlaceholder,
            rows: 3,
            autoGrow: true,
            maxLength: 500,
            showCounter: true,
            invalid: errors.notes != null,
          ),
        ),
      ],
    );
  }
}

String _genderLabel(AppLocalizations l10n, PatientGender gender) {
  return switch (gender) {
    PatientGender.male => l10n.genderMale,
    PatientGender.female => l10n.genderFemale,
    PatientGender.other => l10n.genderOther,
    PatientGender.preferNotToSay => l10n.genderPreferNotToSay,
    PatientGender.unknown => l10n.genderUnknown,
  };
}

String _maritalStatusLabel(AppLocalizations l10n, PatientMaritalStatus status) {
  return switch (status) {
    PatientMaritalStatus.single => l10n.maritalStatusSingle,
    PatientMaritalStatus.married => l10n.maritalStatusMarried,
    PatientMaritalStatus.divorced => l10n.maritalStatusDivorced,
    PatientMaritalStatus.widowed => l10n.maritalStatusWidowed,
  };
}
