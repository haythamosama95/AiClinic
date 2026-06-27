import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/theme/spacing_tokens.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_detail.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_list_item.dart';
import 'package:ai_clinic/features/appointments/presentation/providers/appointment_detail_provider.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/appointment_status_timeline_widget.dart';

/// Pop-out dialog for managing appointment status from the queue card.
class AppointmentStatusJourneyDialog extends ConsumerWidget {
  const AppointmentStatusJourneyDialog({required this.item, super.key});

  final AppointmentListItem item;

  static Future<void> show(BuildContext context, {required AppointmentListItem item}) {
    return AppDialog.show<void>(
      context: context,
      title: item.patientName,
      body: AppointmentStatusJourneyDialog(item: item),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailAsync = ref.watch(appointmentDetailProvider(item.id));
    final maxHeight = MediaQuery.sizeOf(context).height * 0.72;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight, maxWidth: 720),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Flexible(
            child: detailAsync.when(
              skipLoadingOnReload: true,
              loading: () =>
                  SingleChildScrollView(child: AppointmentStatusTimelineWidget(detail: _previewAsDetail(item))),
              error: (error, _) {
                debugPrint('AppointmentStatusJourneyDialog detail load failed: $error');
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Unable to load appointment details. Try again.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: SpacingTokens.md),
                    Align(
                      alignment: Alignment.centerRight,
                      child: AppButton(
                        label: 'Retry',
                        expand: false,
                        onPressed: () => ref.invalidate(appointmentDetailProvider(item.id)),
                      ),
                    ),
                  ],
                );
              },
              data: (detail) => SingleChildScrollView(child: AppointmentStatusTimelineWidget(detail: detail)),
            ),
          ),
          const SizedBox(height: SpacingTokens.md),
          Align(
            alignment: Alignment.centerRight,
            child: AppButton(
              label: 'Close',
              variant: AppButtonVariant.secondary,
              expand: false,
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
        ],
      ),
    );
  }
}

AppointmentDetail _previewAsDetail(AppointmentListItem preview) {
  final referenceTime = preview.updatedAt ?? preview.startTime;
  return AppointmentDetail(
    id: preview.id,
    branchId: '',
    patientId: preview.patientId,
    patientName: preview.patientName,
    doctorId: preview.doctorId,
    doctorName: preview.doctorName,
    startTime: preview.startTime,
    endTime: preview.endTime,
    type: preview.type,
    status: preview.status,
    createdAt: referenceTime,
    updatedAt: referenceTime,
  );
}
