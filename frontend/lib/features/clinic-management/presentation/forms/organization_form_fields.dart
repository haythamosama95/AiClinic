import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/clinic-management/domain/organization_profile.dart';
import 'package:ai_clinic/features/clinic-management/presentation/constants/clinic_constants.dart';

/// Mutable organization form draft (web `OrganizationFormValues`).
class OrganizationFormValues {
  const OrganizationFormValues({
    required this.name,
    this.logoUrl,
    required this.currencyCode,
    required this.timezone,
  });

  final String name;
  final String? logoUrl;
  final String currencyCode;
  final String timezone;

  OrganizationFormValues copyWith({
    String? name,
    Object? logoUrl = _logoUrlSentinel,
    String? currencyCode,
    String? timezone,
  }) {
    return OrganizationFormValues(
      name: name ?? this.name,
      logoUrl: identical(logoUrl, _logoUrlSentinel) ? this.logoUrl : logoUrl as String?,
      currencyCode: currencyCode ?? this.currencyCode,
      timezone: timezone ?? this.timezone,
    );
  }

  static const _logoUrlSentinel = Object();
}

OrganizationFormValues emptyOrganizationFormValues() {
  return const OrganizationFormValues(
    name: '',
    logoUrl: null,
    currencyCode: '',
    timezone: '',
  );
}

OrganizationFormValues organizationToFormValues(OrganizationProfile organization) {
  return OrganizationFormValues(
    name: organization.name,
    logoUrl: organization.logoUrl,
    currencyCode: organization.currencyCode ?? '',
    timezone: organization.timezone ?? '',
  );
}

OrganizationProfile organizationProfileFromFormValues({
  required OrganizationProfile base,
  required OrganizationFormValues values,
}) {
  final trimmedLogo = values.logoUrl?.trim();
  return base.copyWith(
    name: values.name.trim(),
    logoUrl: trimmedLogo == null || trimmedLogo.isEmpty ? null : trimmedLogo,
    currencyCode: values.currencyCode.trim(),
    timezone: values.timezone.trim(),
  );
}

typedef OrganizationFormErrors = Map<String, String>;

OrganizationFormErrors validateOrganization(OrganizationFormValues values) {
  final errors = <String, String>{};
  if (values.name.trim().isEmpty) {
    errors['name'] = 'Organization name is required';
  }
  if (values.currencyCode.trim().isEmpty) {
    errors['currencyCode'] = 'Select a currency code from the list';
  } else if (!kCurrencyCodes.contains(values.currencyCode)) {
    errors['currencyCode'] = 'Select a currency code from the list';
  }
  if (values.timezone.trim().isEmpty) {
    errors['timezone'] = 'Select a timezone from the list';
  } else if (!kTimezones.contains(values.timezone)) {
    errors['timezone'] = 'Select a timezone from the list';
  }
  return errors;
}

class _OrganizationFormCopy {
  const _OrganizationFormCopy({
    required this.organizationNameLabel,
    required this.organizationNamePlaceholder,
    required this.logoUrlLabel,
    required this.logoUrlPlaceholder,
    required this.currencyCodeLabel,
    required this.currencyCodePlaceholder,
    required this.timezoneLabel,
    required this.timezonePlaceholder,
  });

  final String organizationNameLabel;
  final String organizationNamePlaceholder;
  final String logoUrlLabel;
  final String logoUrlPlaceholder;
  final String currencyCodeLabel;
  final String currencyCodePlaceholder;
  final String timezoneLabel;
  final String timezonePlaceholder;
}

const _copyEn = _OrganizationFormCopy(
  organizationNameLabel: 'Organization name',
  organizationNamePlaceholder: 'Enter your clinic name',
  logoUrlLabel: 'Logo URL',
  logoUrlPlaceholder: 'https://example.com/logo.png',
  currencyCodeLabel: 'Currency code',
  currencyCodePlaceholder: 'Type to search (e.g. EGP)',
  timezoneLabel: 'Timezone',
  timezonePlaceholder: 'Type to search (e.g. Africa/Cairo)',
);

const _copyAr = _OrganizationFormCopy(
  organizationNameLabel: 'اسم المنشأة',
  organizationNamePlaceholder: 'أدخل اسم العيادة',
  logoUrlLabel: 'رابط الشعار',
  logoUrlPlaceholder: 'https://example.com/logo.png',
  currencyCodeLabel: 'رمز العملة',
  currencyCodePlaceholder: 'اكتب للبحث (مثال: EGP)',
  timezoneLabel: 'المنطقة الزمنية',
  timezonePlaceholder: 'اكتب للبحث (مثال: Africa/Cairo)',
);

_OrganizationFormCopy _copyFor(String locale) => locale == 'ar' ? _copyAr : _copyEn;

List<AppComboboxItem> _comboboxItems(List<String> options) {
  return options.map((code) => AppComboboxItem(id: code, label: code)).toList();
}

/// Organization profile fields in a responsive two-column grid (web `OrganizationFormFields`).
class OrganizationFormFields extends StatelessWidget {
  const OrganizationFormFields({
    required this.values,
    required this.onChanged,
    this.disabled = false,
    this.errors = const {},
    super.key,
  });

  final OrganizationFormValues values;
  final ValueChanged<OrganizationFormValues> onChanged;
  final bool disabled;
  final OrganizationFormErrors errors;

  static final _currencyItems = _comboboxItems(kCurrencyCodes);
  static final _timezoneItems = _comboboxItems(kTimezones);

  @override
  Widget build(BuildContext context) {
    final copy = _copyFor(Localizations.localeOf(context).languageCode);
    final currencyValue = values.currencyCode.isEmpty
        ? null
        : AppComboboxItem(id: values.currencyCode, label: values.currencyCode);
    final timezoneValue = values.timezone.isEmpty
        ? null
        : AppComboboxItem(id: values.timezone, label: values.timezone);

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 640;
        final columnCount = isWide ? 2 : 1;
        final fieldWidth = columnCount == 1
            ? constraints.maxWidth
            : (constraints.maxWidth - AppSpacing.space5) / 2;

        Widget field(Widget child) => SizedBox(width: fieldWidth, child: child);

        return Wrap(
          spacing: AppSpacing.space5,
          runSpacing: AppSpacing.space5,
          children: [
            field(
              AppFormField(
                id: 'org-name',
                label: copy.organizationNameLabel,
                requiredMark: true,
                error: errors['name'],
                child: AppTextInput(
                  id: 'org-name',
                  initialValue: values.name,
                  placeholder: copy.organizationNamePlaceholder,
                  disabled: disabled,
                  readOnly: disabled,
                  invalid: errors.containsKey('name'),
                  onChanged: (name) => onChanged(values.copyWith(name: name)),
                ),
              ),
            ),
            field(
              AppFormField(
                id: 'org-logo',
                label: copy.logoUrlLabel,
                error: errors['logoUrl'],
                child: AppTextInput(
                  id: 'org-logo',
                  initialValue: values.logoUrl ?? '',
                  placeholder: copy.logoUrlPlaceholder,
                  keyboardType: TextInputType.url,
                  disabled: disabled,
                  readOnly: disabled,
                  invalid: errors.containsKey('logoUrl'),
                  onChanged: (logoUrl) => onChanged(
                    values.copyWith(logoUrl: logoUrl.isEmpty ? null : logoUrl),
                  ),
                ),
              ),
            ),
            field(
              AppFormField(
                id: 'org-currency',
                label: copy.currencyCodeLabel,
                requiredMark: true,
                error: errors['currencyCode'],
                child: AppCombobox(
                  id: 'org-currency',
                  items: _currencyItems,
                  value: currencyValue,
                  placeholder: copy.currencyCodePlaceholder,
                  disabled: disabled,
                  invalid: errors.containsKey('currencyCode'),
                  onValueChange: (item) => onChanged(
                    values.copyWith(currencyCode: item?.id ?? ''),
                  ),
                ),
              ),
            ),
            field(
              AppFormField(
                id: 'org-timezone',
                label: copy.timezoneLabel,
                requiredMark: true,
                error: errors['timezone'],
                child: AppCombobox(
                  id: 'org-timezone',
                  items: _timezoneItems,
                  value: timezoneValue,
                  placeholder: copy.timezonePlaceholder,
                  disabled: disabled,
                  invalid: errors.containsKey('timezone'),
                  onValueChange: (item) => onChanged(
                    values.copyWith(timezone: item?.id ?? ''),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
