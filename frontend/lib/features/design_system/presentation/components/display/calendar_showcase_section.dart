import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/components/app_calendar.dart';
import 'package:ai_clinic/features/design_system/presentation/components/showcase_primitives.dart';
import 'package:ai_clinic/features/design_system/presentation/providers/dev_preview_provider.dart';

class _CalendarCopy {
  const _CalendarCopy({
    required this.consultation,
    required this.followUp,
  });

  final String consultation;
  final String followUp;
}

const _copyEn = _CalendarCopy(
  consultation: 'Consultation',
  followUp: 'Follow-up',
);

const _copyAr = _CalendarCopy(
  consultation: 'استشارة',
  followUp: 'متابعة',
);

_CalendarCopy _copyFor(String locale) => locale == 'ar' ? _copyAr : _copyEn;

List<CalendarEvent> _mockEvents(_CalendarCopy copy) => [
  CalendarEvent(
    id: 'e1',
    title: copy.consultation,
    start: DateTime(2026, 7, 4, 9, 0),
    end: DateTime(2026, 7, 4, 9, 30),
    patient: 'Layla Hassan',
    doctor: 'Dr. Ahmed',
  ),
  CalendarEvent(
    id: 'e2',
    title: copy.followUp,
    start: DateTime(2026, 7, 4, 10, 0),
    end: DateTime(2026, 7, 4, 10, 30),
    patient: 'Omar Farouk',
    doctor: 'Dr. Sara',
    conflict: true,
  ),
];

/// Calendar showcase (web `CalendarShowcase`).
class CalendarShowcaseSection extends ConsumerWidget {
  const CalendarShowcaseSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final copy = _copyFor(ref.watch(devPreviewProvider).locale);

    return ShowcaseSection(
      id: 'calendar',
      title: 'Calendar',
      componentName: 'Calendar',
      child: AppCalendar(events: _mockEvents(copy)),
    );
  }
}
