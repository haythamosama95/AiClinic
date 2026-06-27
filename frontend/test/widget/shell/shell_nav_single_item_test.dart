import 'package:ai_clinic/app/shell/config/shell_nav_config.dart';
import 'package:ai_clinic/app/shell/models/shell_nav_models.dart';
import 'package:ai_clinic/app/shell/widgets/shell_nav_badge.dart';
import 'package:ai_clinic/app/shell/widgets/shell_nav_single_item.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_list_item.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_type.dart';
import 'package:ai_clinic/features/appointments/presentation/providers/appointment_queue_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'shell_test_support.dart';

const _queueItem = ShellNavSingle(
  id: ShellNavConfig.queueNavItemId,
  label: 'Queue',
  icon: Icons.queue_outlined,
  badgeTone: ShellNavBadgeTone.success,
);

class _StaticQueueNotifier extends AppointmentQueueController {
  _StaticQueueNotifier(this.initial);

  final AppointmentQueueState initial;

  @override
  AppointmentQueueState build() => initial;
}

void main() {
  group('ShellNavSingleItem queue badge', () {
    testWidgets('shows checked-in patient count from queue provider', (tester) async {
      final start = DateTime.utc(2026, 6, 4, 10);
      await pumpShellWidget(
        tester,
        overrides: [
          appointmentQueueProvider.overrideWith(
            () => _StaticQueueNotifier(
              AppointmentQueueState(
                items: [
                  _item(id: 'a1', status: AppointmentStatus.checkedIn, startTime: start),
                  _item(id: 'a2', status: AppointmentStatus.checkedIn, startTime: start.add(const Duration(hours: 1))),
                  _item(id: 'a3', status: AppointmentStatus.confirmed, startTime: start.add(const Duration(hours: 2))),
                ],
              ),
            ),
          ),
        ],
        child: ShellNavSingleItem(item: _queueItem, isSelected: false, onSelected: (_) {}),
      );

      expect(find.text('2'), findsOneWidget);
      expect(find.byType(ShellNavBadge), findsOneWidget);
    });

    testWidgets('hides badge when no patients are checked in', (tester) async {
      await pumpShellWidget(
        tester,
        overrides: [
          appointmentQueueProvider.overrideWith(() => _StaticQueueNotifier(const AppointmentQueueState(items: []))),
        ],
        child: ShellNavSingleItem(item: _queueItem, isSelected: false, onSelected: (_) {}),
      );

      expect(find.byType(ShellNavBadge), findsOneWidget);
      expect(
        find.descendant(of: find.byType(ShellNavBadge), matching: find.textContaining(RegExp(r'^\d+$'))),
        findsNothing,
      );
    });
  });
}

AppointmentListItem _item({required String id, required AppointmentStatus status, required DateTime startTime}) {
  return AppointmentListItem(
    id: id,
    patientId: 'p1',
    patientName: 'Patient',
    doctorId: null,
    doctorName: null,
    startTime: startTime,
    endTime: startTime.add(const Duration(minutes: 30)),
    status: status,
    type: AppointmentType.planned,
    updatedAt: startTime,
  );
}
