import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/components/app_timeline.dart';
import 'package:ai_clinic/features/design_system/presentation/components/showcase_primitives.dart';
import 'package:ai_clinic/features/design_system/presentation/providers/dev_preview_provider.dart';

class _TimelineCopy {
  const _TimelineCopy({
    required this.sectionDescription,
    required this.visitCompleted,
    required this.visitDescription,
    required this.vitalsRecorded,
    required this.vitalsDescription,
    required this.invoicePaid,
    required this.invoiceDescription,
    required this.groupJul4,
    required this.groupJul2,
  });

  final String sectionDescription;
  final String visitCompleted;
  final String visitDescription;
  final String vitalsRecorded;
  final String vitalsDescription;
  final String invoicePaid;
  final String invoiceDescription;
  final String groupJul4;
  final String groupJul2;
}

const _copyEn = _TimelineCopy(
  sectionDescription:
      'Chronological event feed. Groups by date when multiple groups exist.',
  visitCompleted: 'Visit completed',
  visitDescription: 'General consultation with Dr. Ahmed',
  vitalsRecorded: 'Vitals recorded',
  vitalsDescription: 'BP 120/80, temp 37.1°C',
  invoicePaid: 'Invoice paid',
  invoiceDescription: 'EGP 850.00 via card',
  groupJul4: 'Jul 4, 2026',
  groupJul2: 'Jul 2, 2026',
);

const _copyAr = _TimelineCopy(
  sectionDescription:
      'تغذية أحداث زمنية. تُجمّع حسب التاريخ عند وجود مجموعات متعددة.',
  visitCompleted: 'اكتملت الزيارة',
  visitDescription: 'استشارة عامة مع د. أحمد',
  vitalsRecorded: 'تم تسجيل العلامات الحيوية',
  vitalsDescription: 'ضغط الدم 120/80، حرارة 37.1°م',
  invoicePaid: 'تم دفع الفاتورة',
  invoiceDescription: 'جنيه 850.00 عبر البطاقة',
  groupJul4: '4 يوليو 2026',
  groupJul2: '2 يوليو 2026',
);

_TimelineCopy _copyFor(String locale) => locale == 'ar' ? _copyAr : _copyEn;

/// Timeline showcase (web `TimelineShowcase`).
class TimelineShowcaseSection extends ConsumerWidget {
  const TimelineShowcaseSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final copy = _copyFor(ref.watch(devPreviewProvider).locale);

    return ShowcaseSection(
      id: 'timeline',
      title: 'Timeline',
      description: copy.sectionDescription,
      componentName: 'Timeline',
      child: AppTimeline(
        events: [
          TimelineEvent(
            time: '10:30 AM',
            title: copy.visitCompleted,
            description: copy.visitDescription,
            group: copy.groupJul4,
          ),
          TimelineEvent(
            time: '10:15 AM',
            title: copy.vitalsRecorded,
            description: copy.vitalsDescription,
            group: copy.groupJul4,
          ),
          TimelineEvent(
            time: '2:00 PM',
            title: copy.invoicePaid,
            description: copy.invoiceDescription,
            group: copy.groupJul2,
          ),
        ],
      ),
    );
  }
}
