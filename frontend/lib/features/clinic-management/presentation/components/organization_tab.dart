import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/clinic-management/domain/organization_profile.dart';
import 'package:ai_clinic/features/clinic-management/presentation/components/clinic_hero.dart';
import 'package:ai_clinic/features/clinic-management/presentation/forms/organization_form_fields.dart';

class _OrganizationTabCopy {
  const _OrganizationTabCopy({
    required this.profileTitle,
    required this.profileDescription,
    required this.editOrganization,
    required this.cancel,
    required this.saveChanges,
  });

  final String profileTitle;
  final String profileDescription;
  final String editOrganization;
  final String cancel;
  final String saveChanges;
}

const _copyEn = _OrganizationTabCopy(
  profileTitle: 'Organization profile',
  profileDescription:
      'Clinic-wide defaults for billing, scheduling, and branding. Branch settings override per location.',
  editOrganization: 'Edit organization',
  cancel: 'Cancel',
  saveChanges: 'Save changes',
);

const _copyAr = _OrganizationTabCopy(
  profileTitle: 'ملف المنشأة',
  profileDescription:
      'الإعدادات الافتراضية على مستوى العيادة للفوترة والجدولة والهوية البصرية. إعدادات الفرع تتجاوزها لكل موقع.',
  editOrganization: 'تعديل المنشأة',
  cancel: 'إلغاء',
  saveChanges: 'حفظ التغييرات',
);

_OrganizationTabCopy _copyFor(String locale) => locale == 'ar' ? _copyAr : _copyEn;

/// Organization tab with read/edit toggle (web `OrganizationTab`).
class OrganizationTab extends StatefulWidget {
  const OrganizationTab({
    required this.organization,
    required this.onSave,
    required this.branchCount,
    required this.staffCount,
    required this.activeBranchCount,
    super.key,
  });

  final OrganizationProfile organization;
  final ValueChanged<OrganizationProfile> onSave;
  final int branchCount;
  final int staffCount;
  final int activeBranchCount;

  @override
  State<OrganizationTab> createState() => _OrganizationTabState();
}

class _OrganizationTabState extends State<OrganizationTab> {
  var _editing = false;
  late OrganizationFormValues _draft = organizationToFormValues(widget.organization);
  OrganizationFormErrors _errors = const {};

  @override
  void didUpdateWidget(covariant OrganizationTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.organization != widget.organization && !_editing) {
      _draft = organizationToFormValues(widget.organization);
    }
  }

  void _startEdit() {
    setState(() {
      _draft = organizationToFormValues(widget.organization);
      _errors = const {};
      _editing = true;
    });
  }

  void _cancel() {
    setState(() {
      _draft = organizationToFormValues(widget.organization);
      _errors = const {};
      _editing = false;
    });
  }

  void _save() {
    final nextErrors = validateOrganization(_draft);
    if (nextErrors.isNotEmpty) {
      setState(() => _errors = nextErrors);
      return;
    }
    widget.onSave(organizationProfileFromFormValues(base: widget.organization, values: _draft));
    setState(() {
      _errors = const {};
      _editing = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final copy = _copyFor(Localizations.localeOf(context).languageCode);
    final formValues = _editing ? _draft : organizationToFormValues(widget.organization);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        ClinicHero(
          organization: widget.organization,
          branchCount: widget.branchCount,
          staffCount: widget.staffCount,
          activeBranchCount: widget.activeBranchCount,
        ),
        const SizedBox(height: AppSpacing.space6),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.start,
          spacing: AppSpacing.space4,
          runSpacing: AppSpacing.space4,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 576),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(copy.profileTitle, style: AppTypography.h3(context)),
                  const SizedBox(height: AppSpacing.space1),
                  Text(copy.profileDescription, style: AppTypography.bodySm(context)),
                ],
              ),
            ),
            Wrap(
              spacing: AppSpacing.space2,
              runSpacing: AppSpacing.space2,
              children: [
                if (_editing) ...[
                  AppButton(
                    variant: AppButtonVariant.secondary,
                    size: AppButtonSize.lg,
                    leadingIcon: const Icon(Icons.close, size: 16),
                    onPressed: _cancel,
                    child: Text(copy.cancel),
                  ),
                  AppButton(
                    variant: AppButtonVariant.primary,
                    size: AppButtonSize.lg,
                    leadingIcon: const Icon(Icons.save, size: 16),
                    onPressed: _save,
                    child: Text(copy.saveChanges),
                  ),
                ] else
                  AppButton(
                    variant: AppButtonVariant.primary,
                    size: AppButtonSize.lg,
                    leadingIcon: const Icon(Icons.edit, size: 16),
                    onPressed: _startEdit,
                    child: Text(copy.editOrganization),
                  ),
              ],
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.space6),
        DecoratedBox(
          decoration: BoxDecoration(
            color: colors.surfaceDefault,
            borderRadius: BorderRadius.circular(AppRadius.x2l),
            border: Border.all(color: colors.borderSubtle),
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.space6),
            child: OrganizationFormFields(
              values: formValues,
              onChanged: _editing ? (values) => setState(() => _draft = values) : (_) {},
              disabled: !_editing,
              errors: _editing ? _errors : const {},
            ),
          ),
        ),
      ],
    );
  }
}
