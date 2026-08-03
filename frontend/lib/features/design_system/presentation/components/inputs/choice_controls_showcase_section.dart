import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/components/app_checkbox.dart';
import 'package:ai_clinic/core/ui/components/app_radio_group.dart';
import 'package:ai_clinic/core/ui/components/app_switch.dart';
import 'package:ai_clinic/features/design_system/presentation/components/showcase_primitives.dart';
import 'package:ai_clinic/features/design_system/presentation/providers/dev_preview_provider.dart';

class _ChoiceControlsCopy {
  const _ChoiceControlsCopy({
    required this.sendReminders,
    required this.selectAllRows,
    required this.disabledOption,
    required this.cash,
    required this.card,
    required this.insurance,
    required this.day,
    required this.week,
    required this.month,
    required this.serviceActive,
    required this.disabledToggle,
  });

  final String sendReminders;
  final String selectAllRows;
  final String disabledOption;
  final String cash;
  final String card;
  final String insurance;
  final String day;
  final String week;
  final String month;
  final String serviceActive;
  final String disabledToggle;
}

const _copyEn = _ChoiceControlsCopy(
  sendReminders: 'Send appointment reminders',
  selectAllRows: 'Select all rows',
  disabledOption: 'Disabled option',
  cash: 'Cash',
  card: 'Card',
  insurance: 'Insurance',
  day: 'Day',
  week: 'Week',
  month: 'Month',
  serviceActive: 'Service active on this branch',
  disabledToggle: 'Disabled toggle',
);

const _copyAr = _ChoiceControlsCopy(
  sendReminders: 'إرسال تذكيرات المواعيد',
  selectAllRows: 'تحديد كل الصفوف',
  disabledOption: 'خيار معطّل',
  cash: 'نقداً',
  card: 'بطاقة',
  insurance: 'تأمين',
  day: 'يوم',
  week: 'أسبوع',
  month: 'شهر',
  serviceActive: 'الخدمة مفعّلة في هذا الفرع',
  disabledToggle: 'مفتاح معطّل',
);

_ChoiceControlsCopy _copyFor(String locale) => locale == 'ar' ? _copyAr : _copyEn;

/// Checkbox showcase (web `CheckboxShowcase`).
class CheckboxShowcaseSection extends ConsumerWidget {
  const CheckboxShowcaseSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final copy = _copyFor(ref.watch(devPreviewProvider).locale);

    return ShowcaseSection(
      id: 'checkbox',
      title: 'Checkbox',
      componentName: 'Checkbox',
      child: ShowcaseDemoGrid(
        columns: 3,
        children: [
          AppCheckbox(initialValue: AppCheckboxState.checked, label: copy.sendReminders),
          AppCheckbox(value: AppCheckboxState.indeterminate, label: copy.selectAllRows),
          AppCheckbox(disabled: true, label: copy.disabledOption),
        ],
      ),
    );
  }
}

/// Radio group showcase (web `RadioGroupShowcase`).
class RadioGroupShowcaseSection extends ConsumerWidget {
  const RadioGroupShowcaseSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final copy = _copyFor(ref.watch(devPreviewProvider).locale);

    return ShowcaseSection(
      id: 'radio-group',
      title: 'Radio group',
      componentName: 'RadioGroup',
      child: ShowcaseDemoGrid(
        children: [
          ShowcaseDemo(
            label: 'Vertical',
            child: AppRadioGroup(
              initialValue: 'card',
              options: [
                AppRadioOption(value: 'cash', label: copy.cash),
                AppRadioOption(value: 'card', label: copy.card),
                AppRadioOption(value: 'insurance', label: copy.insurance),
              ],
            ),
          ),
          ShowcaseDemo(
            label: 'Horizontal',
            propsHint: 'orientation=horizontal',
            child: AppRadioGroup(
              orientation: AppRadioGroupOrientation.horizontal,
              initialValue: 'day',
              options: [
                AppRadioOption(value: 'day', label: copy.day),
                AppRadioOption(value: 'week', label: copy.week),
                AppRadioOption(value: 'month', label: copy.month),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Switch showcase (web `SwitchShowcase`).
class SwitchShowcaseSection extends ConsumerWidget {
  const SwitchShowcaseSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final copy = _copyFor(ref.watch(devPreviewProvider).locale);

    return ShowcaseSection(
      id: 'switch',
      title: 'Switch',
      componentName: 'Switch',
      child: ShowcaseDemoGrid(
        children: [
          AppSwitch(initialValue: true, label: copy.serviceActive),
          AppSwitch(disabled: true, label: copy.disabledToggle),
        ],
      ),
    );
  }
}
