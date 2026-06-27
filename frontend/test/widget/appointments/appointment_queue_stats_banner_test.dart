import 'package:ai_clinic/core/ui/theme/app_theme.dart';
import 'package:ai_clinic/core/ui/theme/forui_app_scope.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_queue_display.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/queue/appointment_queue_stats_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppointmentQueueStatsBanner', () {
    testWidgets('BUG-006: shows trends unavailable banner when comparison failed', (tester) async {
      const stats = AppointmentQueueStats(total: 3, completed: 1, noShow: 0, avgWaitMinutes: 10, avgVisitMinutes: 20);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          builder: (context, child) => ForuiAppScope(child: child ?? const SizedBox.shrink()),
          home: const Scaffold(
            body: SizedBox(width: 1200, child: AppointmentQueueStatsBanner(stats: stats, trendsUnavailable: true)),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Day-over-day trends are temporarily unavailable.'), findsOneWidget);
    });
  });
}
