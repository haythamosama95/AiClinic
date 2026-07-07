import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/components/app_description_list.dart';
import 'package:ai_clinic/features/design_system/presentation/components/showcase_primitives.dart';
import 'package:ai_clinic/features/design_system/presentation/providers/dev_preview_provider.dart';

class _DescriptionListCopy {
  const _DescriptionListCopy({
    required this.sectionDescription,
    required this.mrn,
    required this.dateOfBirth,
    required this.phone,
    required this.insurance,
    required this.mrnValue,
    required this.dateOfBirthValue,
    required this.phoneValue,
    required this.insuranceValue,
  });

  final String sectionDescription;
  final String mrn;
  final String dateOfBirth;
  final String phone;
  final String insurance;
  final String mrnValue;
  final String dateOfBirthValue;
  final String phoneValue;
  final String insuranceValue;
}

const _copyEn = _DescriptionListCopy(
  sectionDescription: 'Read-only label/value pairs for patient and record details.',
  mrn: 'MRN',
  dateOfBirth: 'Date of birth',
  phone: 'Phone',
  insurance: 'Insurance',
  mrnValue: '10482',
  dateOfBirthValue: 'Mar 14, 1988',
  phoneValue: '+20 100 234 5678',
  insuranceValue: 'AXA Egypt',
);

const _copyAr = _DescriptionListCopy(
  sectionDescription: 'أزواج تسمية/قيمة للقراءة فقط لتفاصيل المريض والسجل.',
  mrn: 'الرقم الطبي',
  dateOfBirth: 'تاريخ الميلاد',
  phone: 'الهاتف',
  insurance: 'التأمين',
  mrnValue: '10482',
  dateOfBirthValue: '14 مارس 1988',
  phoneValue: '+20 100 234 5678',
  insuranceValue: 'أكسا مصر',
);

_DescriptionListCopy _copyFor(String locale) => locale == 'ar' ? _copyAr : _copyEn;

/// Description list showcase (web `DescriptionListShowcase`).
class DescriptionListShowcaseSection extends ConsumerWidget {
  const DescriptionListShowcaseSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final copy = _copyFor(ref.watch(devPreviewProvider).locale);

    return ShowcaseSection(
      id: 'description-list',
      title: 'Description list',
      description: copy.sectionDescription,
      componentName: 'DescriptionList',
      child: AppDescriptionList(
        items: [
          DescriptionItem(
            label: copy.mrn,
            value: Text(copy.mrnValue),
            tabular: true,
          ),
          DescriptionItem(
            label: copy.dateOfBirth,
            value: Text(copy.dateOfBirthValue),
          ),
          DescriptionItem(
            label: copy.phone,
            value: Text(copy.phoneValue),
            tabular: true,
          ),
          DescriptionItem(
            label: copy.insurance,
            value: Text(copy.insuranceValue),
          ),
        ],
      ),
    );
  }
}
