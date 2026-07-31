import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/components/app_tabs.dart';
import 'package:ai_clinic/core/ui/motion/app_motion.dart';
import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_list_item.dart';
import 'package:ai_clinic/features/queue/presentation/providers/queue_shift_provider.dart';
import 'package:ai_clinic/features/queue/presentation/widgets/queue_checked_in_panel.dart';
import 'package:ai_clinic/features/queue/presentation/widgets/queue_doctors_panel.dart';
import 'package:ai_clinic/features/queue/presentation/widgets/queue_secretary_utils.dart';

/// Side-rail flow control with waiting and doctors tabs (web `FlowControlPanel`).
class QueueFlowControlPanel extends ConsumerStatefulWidget {
  const QueueFlowControlPanel({
    required this.appointments,
    required this.now,
    super.key,
  });

  final List<AppointmentListItem> appointments;
  final DateTime now;

  @override
  ConsumerState<QueueFlowControlPanel> createState() =>
      _QueueFlowControlPanelState();
}

class _QueueFlowControlPanelState extends ConsumerState<QueueFlowControlPanel> {
  static const _waitingTab = 'waiting';
  static const _doctorsTab = 'doctors';

  var _activeTab = _waitingTab;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final shiftLookup = ref.watch(appointmentQueueShiftDoctorLookupProvider).maybeWhen(
          data: (lookup) => lookup,
          orElse: () => null,
        );
    final checkedInPatients = queueCheckedInPatients(
      widget.appointments,
      widget.now,
    );
    final doctors = shiftLookup?.doctorsOnCurrentShiftAt(widget.now) ?? const [];

    return Semantics(
      container: true,
      label: 'Flow control',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surfaceDefault,
          borderRadius: BorderRadius.circular(AppRadius.xl),
          border: Border.all(color: colors.borderDefault),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(
                AppSpacing.space3,
                AppSpacing.space3,
                AppSpacing.space3,
                0,
              ),
              child: AppTabs(
                variant: AppTabsVariant.underline,
                ariaLabel: 'Flow control sections',
                value: _activeTab,
                onChanged: (id) => setState(() => _activeTab = id),
                items: [
                  AppTabItem(
                    id: _waitingTab,
                    label: 'Waiting (${checkedInPatients.length})',
                  ),
                  AppTabItem(
                    id: _doctorsTab,
                    label: 'Doctors (${doctors.length})',
                  ),
                ],
              ),
            ),
            AnimatedSwitcher(
              duration: AppMotion.resolveDuration(
                AppMotionPreset.fade,
                reducedMotion: MediaQuery.disableAnimationsOf(context),
              ),
              switchInCurve: AppMotion.outCurve,
              switchOutCurve: AppMotion.inCurve,
              child: _activeTab == _waitingTab
                  ? QueueCheckedInPanel(
                      key: const ValueKey(_waitingTab),
                      patients: checkedInPatients,
                      now: widget.now,
                      embedded: true,
                    )
                  : QueueDoctorsPanel(
                      key: const ValueKey(_doctorsTab),
                      doctors: doctors,
                      appointments: widget.appointments,
                      now: widget.now,
                      embedded: true,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
