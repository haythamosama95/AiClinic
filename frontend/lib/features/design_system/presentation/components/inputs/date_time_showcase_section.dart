import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/components/app_date_picker.dart';
import 'package:ai_clinic/core/ui/components/app_date_range_picker.dart';
import 'package:ai_clinic/core/ui/components/app_form_field.dart';
import 'package:ai_clinic/core/ui/components/app_time_picker.dart';
import 'package:ai_clinic/features/design_system/presentation/components/showcase_primitives.dart';
import 'package:ai_clinic/features/design_system/presentation/providers/dev_preview_provider.dart';

class _DateTimeCopy {
  const _DateTimeCopy({
    required this.datePickerDescription,
    required this.promotionStartDate,
    required this.datePlaceholder,
    required this.timePickerDescription,
    required this.appointmentTime,
    required this.timePlaceholder,
    required this.dateRangePickerDescription,
    required this.reportPeriod,
    required this.rangePlaceholder,
    required this.selectEndDate,
    required this.inclusiveRangePrefix,
    required this.previous,
    required this.next,
  });

  final String datePickerDescription;
  final String promotionStartDate;
  final String datePlaceholder;
  final String timePickerDescription;
  final String appointmentTime;
  final String timePlaceholder;
  final String dateRangePickerDescription;
  final String reportPeriod;
  final String rangePlaceholder;
  final String selectEndDate;
  final String inclusiveRangePrefix;
  final String previous;
  final String next;
}

const _copyEn = _DateTimeCopy(
  datePickerDescription: 'Calendar popover with keyboard entry, min/max, RTL calendar mirror.',
  promotionStartDate: 'Promotion start date',
  datePlaceholder: 'dd/mm/yyyy',
  timePickerDescription: 'Appointment times with 15-minute step granularity.',
  appointmentTime: 'Appointment time',
  timePlaceholder: 'Select time',
  dateRangePickerDescription: 'Calendar popover with inclusive-range messaging.',
  reportPeriod: 'Report period',
  rangePlaceholder: 'Select date range',
  selectEndDate: 'Select end date',
  inclusiveRangePrefix: 'Inclusive range:',
  previous: 'Previous',
  next: 'Next',
);

const _copyAr = _DateTimeCopy(
  datePickerDescription: 'تقويم منبثق مع إدخال يدوي وحد أدنى/أقصى وانعكاس التقويم في RTL.',
  promotionStartDate: 'تاريخ بداية العرض',
  datePlaceholder: 'يوم/شهر/سنة',
  timePickerDescription: 'أوقات المواعيد بفاصل 15 دقيقة.',
  appointmentTime: 'وقت الموعد',
  timePlaceholder: 'اختر الوقت',
  dateRangePickerDescription: 'تقويم منبثق مع رسالة نطاق شامل.',
  reportPeriod: 'فترة التقرير',
  rangePlaceholder: 'اختر نطاق التاريخ',
  selectEndDate: 'اختر تاريخ النهاية',
  inclusiveRangePrefix: 'نطاق شامل:',
  previous: 'السابق',
  next: 'التالي',
);

_DateTimeCopy _copyFor(String locale) => locale == 'ar' ? _copyAr : _copyEn;

/// Date picker showcase (web `DatePickerShowcase`).
class DatePickerShowcaseSection extends ConsumerWidget {
  const DatePickerShowcaseSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final copy = _copyFor(ref.watch(devPreviewProvider).locale);
    const fieldId = 'date-picker-promotion';

    return ShowcaseSection(
      id: 'date-picker',
      title: 'Date picker',
      componentName: 'DatePicker',
      description: copy.datePickerDescription,
      child: AppFormField(
        id: fieldId,
        label: copy.promotionStartDate,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: AppDatePicker(id: fieldId, placeholder: copy.datePlaceholder),
        ),
      ),
    );
  }
}

/// Time picker showcase (web `TimePickerShowcase`).
class TimePickerShowcaseSection extends ConsumerWidget {
  const TimePickerShowcaseSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final copy = _copyFor(ref.watch(devPreviewProvider).locale);
    const fieldId = 'time-picker-appointment';

    return ShowcaseSection(
      id: 'time-picker',
      title: 'Time picker',
      componentName: 'TimePicker',
      description: copy.timePickerDescription,
      child: AppFormField(
        id: fieldId,
        label: copy.appointmentTime,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: AppTimePicker(id: fieldId, placeholder: copy.timePlaceholder),
        ),
      ),
    );
  }
}

/// Date range picker showcase (web `DateRangePickerShowcase`).
class DateRangePickerShowcaseSection extends ConsumerWidget {
  const DateRangePickerShowcaseSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final copy = _copyFor(ref.watch(devPreviewProvider).locale);
    const fieldId = 'date-range-picker-report';

    return ShowcaseSection(
      id: 'date-range-picker',
      title: 'Date range picker',
      componentName: 'DateRangePicker',
      description: copy.dateRangePickerDescription,
      child: AppFormField(
        id: fieldId,
        label: copy.reportPeriod,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: AppDateRangePicker(
            id: fieldId,
            placeholder: copy.rangePlaceholder,
            selectEndDateLabel: copy.selectEndDate,
            inclusiveRangePrefix: copy.inclusiveRangePrefix,
            previousLabel: copy.previous,
            nextLabel: copy.next,
          ),
        ),
      ),
    );
  }
}
