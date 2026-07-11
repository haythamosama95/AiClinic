import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
import 'package:ai_clinic/features/patients/presentation/models/patient_registration_form.dart';
import 'package:ai_clinic/features/patients/presentation/providers/active_branch_name_provider.dart';

const _kSmBreakpoint = 640.0;

const _registrationGenderOptions = [
  PatientGender.male,
  PatientGender.female,
  PatientGender.other,
];

const _maritalStatusOptions = PatientMaritalStatus.values;

/// Add-patient form body (web `AddPatientFormFields`).
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
    final branchName = ref.watch(activeBranchNameProvider).value ?? 'your active branch';

    return Form(
      child: Focus(
        onKeyEvent: _handleFormKeyEvent,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            _BranchBanner(branchName: branchName),
            const SizedBox(height: AppSpacing.space6),
            _IdentityPreview(
              trimmedName: widget.trimmedName,
              showPreview: widget.showPreview,
              reducedMotion: widget.reducedMotion,
            ),
            const SizedBox(height: AppSpacing.space6),
            _PatientDetailsSection(
              values: widget.values,
              errors: widget.errors,
              autoFocus: widget.autoFocus,
              onFieldChange: widget.onFieldChange,
            ),
            const SizedBox(height: AppSpacing.space6),
            const AppDivider(),
            const SizedBox(height: AppSpacing.space6),
            _ClinicalNotesSection(
              values: widget.values,
              errors: widget.errors,
              onFieldChange: widget.onFieldChange,
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
  const _BranchBanner({required this.branchName});

  final String branchName;

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
                    const TextSpan(text: 'Registering at '),
                    TextSpan(
                      text: branchName,
                      style: AppTypography.bodySm(context).copyWith(
                        color: colors.textPrimary,
                        fontWeight: FontWeight.w500,
                      ),
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
  });

  final String trimmedName;
  final bool showPreview;
  final bool reducedMotion;

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
              return Transform.translate(
                offset: Offset(0, -6 * (1 - animation.value)),
                child: child,
              );
            },
            child: child,
          ),
        );
      },
      child: showPreview
          ? _IdentityPreviewCard(
              key: const ValueKey<String>('identity-preview'),
              trimmedName: trimmedName,
            )
          : const SizedBox.shrink(key: ValueKey<String>('identity-preview-empty')),
    );
  }
}

class _IdentityPreviewCard extends StatelessWidget {
  const _IdentityPreviewCard({required this.trimmedName, super.key});

  final String trimmedName;

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
          colors: [
            colors.surfaceMuted.withValues(alpha: 0.8),
            colors.surfaceDefault,
          ],
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
                  Text(
                    'New record · MRN assigned on save',
                    style: AppTypography.caption(context).copyWith(color: colors.textTertiary),
                  ),
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
  });

  final PatientRegistrationForm values;
  final PatientFormErrors errors;
  final void Function(String key, Object? value) onFieldChange;
  final bool autoFocus;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const AppSectionHeader(
          title: 'Patient details',
          description: 'Core information used to identify the patient and reach them for care.',
        ),
        const SizedBox(height: AppSpacing.space4),
        LayoutBuilder(
          builder: (context, constraints) {
            final twoColumns = constraints.maxWidth >= _kSmBreakpoint;
            final fieldGap = const SizedBox(height: AppSpacing.space4);
            final columnGap = const SizedBox(width: AppSpacing.space4);

            final fullNameField = AppFormField(
              id: 'add-patient-fullName',
              label: 'Full name',
              requiredMark: true,
              hint: 'Legal name as it appears on government ID.',
              error: errors.fullName,
              child: Focus(
                autofocus: autoFocus,
                child: AppTextInput(
                  id: 'add-patient-fullName',
                  initialValue: values.fullName,
                  onChanged: (value) => onFieldChange('fullName', value),
                  placeholder: 'e.g. Sara Hassan Ibrahim',
                  invalid: errors.fullName != null,
                ),
              ),
            );

            final dobField = AppFormField(
              id: 'add-patient-dob',
              label: 'Date of birth',
              hint: 'Used with name for duplicate detection.',
              error: errors.dateOfBirth,
              child: AppDatePicker(
                id: 'add-patient-dob',
                value: values.dateOfBirth,
                onChanged: (date) => onFieldChange('dateOfBirth', date),
                placeholder: 'Select date',
                max: DateTime.now(),
                invalid: errors.dateOfBirth != null,
              ),
            );

            final genderField = AppFormField(
              id: 'add-patient-gender',
              label: 'Gender',
              hint: 'Optional. Shown on the patient profile.',
              error: errors.gender,
              child: AppSelect(
                id: 'add-patient-gender',
                value: values.gender?.wireValue,
                onChanged: (value) => onFieldChange('gender', PatientGender.tryParse(value)),
                options: _registrationGenderOptions
                    .map((gender) => AppSelectOption(value: gender.wireValue, label: gender.label))
                    .toList(),
                placeholder: 'Select gender',
                invalid: errors.gender != null,
              ),
            );

            final phoneField = AppFormField(
              id: 'add-patient-phone',
              label: 'Mobile number',
              hint: 'Used for reminders and duplicate checks.',
              error: errors.phone,
              child: Directionality(
                textDirection: TextDirection.ltr,
                child: AppPhoneInput(
                  id: 'add-patient-phone',
                  initialValue: values.phone,
                  onValueChange: (phone) => onFieldChange('phone', phone),
                  invalid: errors.phone != null,
                ),
              ),
            );

            final maritalField = AppFormField(
              id: 'add-patient-maritalStatus',
              label: 'Marital state',
              hint: 'Optional. Shown on the patient profile.',
              error: errors.maritalStatus,
              child: AppSelect(
                id: 'add-patient-maritalStatus',
                value: values.maritalStatus?.wireValue,
                onChanged: (value) => onFieldChange('maritalStatus', PatientMaritalStatus.tryParse(value)),
                options: _maritalStatusOptions
                    .map((status) => AppSelectOption(value: status.wireValue, label: status.label))
                    .toList(),
                placeholder: 'Select marital state',
                invalid: errors.maritalStatus != null,
              ),
            );

            if (!twoColumns) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  fullNameField,
                  fieldGap,
                  dobField,
                  fieldGap,
                  genderField,
                  fieldGap,
                  phoneField,
                  fieldGap,
                  maritalField,
                ],
              );
            }

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
          },
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
  });

  final PatientRegistrationForm values;
  final PatientFormErrors errors;
  final void Function(String key, Object? value) onFieldChange;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const AppSectionHeader(
          title: 'Clinical notes',
          description: 'Optional context visible to staff on the patient profile.',
        ),
        const SizedBox(height: AppSpacing.space4),
        AppFormField(
          id: 'add-patient-notes',
          label: 'Notes',
          helperText: 'Allergies, referral source, or front-desk remarks.',
          error: errors.notes,
          child: AppTextarea(
            id: 'add-patient-notes',
            initialValue: values.notes,
            onChanged: (value) => onFieldChange('notes', value),
            placeholder: 'e.g. Referred by Dr. Nabil. Penicillin allergy noted verbally.',
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
