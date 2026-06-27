import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/theme/semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/spacing_tokens.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_list_item.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/appointment_status_journey_dialog.dart';

/// Opens the appointment status journey dialog from a queue schedule row.
class AppointmentQueueRowStatusButton extends StatelessWidget {
  const AppointmentQueueRowStatusButton({required this.item, super.key});

  final AppointmentListItem item;

  static const _buttonSize = 32.0;

  @override
  Widget build(BuildContext context) {
    final colors = context.semanticColors;

    final button = Material(
      color: colors.primary,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => AppointmentStatusJourneyDialog.show(context, item: item),
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: _buttonSize,
          height: _buttonSize,
          child: Center(child: Icon(Icons.play_arrow_rounded, size: 18, color: colors.primaryForeground)),
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(left: SpacingTokens.sm),
      child: Tooltip(
        key: Key('appointment_queue_status_${item.id}'),
        message: 'Manage status',
        waitDuration: const Duration(milliseconds: 400),
        child: Semantics(button: true, enabled: true, label: 'Manage status', child: button),
      ),
    );
  }
}
