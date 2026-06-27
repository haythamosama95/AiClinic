import 'package:flutter/material.dart';

import 'package:ai_clinic/app/navigation/app_navigator.dart';
import 'package:ai_clinic/core/ui/theme/semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/spacing_tokens.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_list_item.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_queue_display.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_queue_shift_doctors.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/appointment_scale_down_text.dart';

/// Column 3 — doctors on the current shift and next-up preview.
class AppointmentQueueSessionColumn extends StatelessWidget {
  const AppointmentQueueSessionColumn({
    required this.nextUp,
    required this.now,
    this.shiftLookup = AppointmentQueueShiftDoctorLookup.empty,
    this.doctorsLoading = false,
    super.key,
  });

  final AppointmentListItem? nextUp;
  final DateTime now;
  final AppointmentQueueShiftDoctorLookup shiftLookup;
  final bool doctorsLoading;

  @override
  Widget build(BuildContext context) {
    final colors = context.semanticColors;
    final doctorsOnShift = shiftLookup.doctorsOnCurrentShiftAt(now);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(SpacingTokens.lg),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(SpacingTokens.md, SpacingTokens.md, SpacingTokens.md, SpacingTokens.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Doctors', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: SpacingTokens.xs / 2),
                Text(
                  'Staff on shift right now',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.mutedForeground),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(SpacingTokens.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: doctorsLoading
                        ? const Center(child: CircularProgressIndicator())
                        : doctorsOnShift.isEmpty
                        ? const _NoDoctorsOnShiftPlaceholder()
                        : ListView.separated(
                            itemCount: doctorsOnShift.length,
                            separatorBuilder: (_, _) => const SizedBox(height: SpacingTokens.sm),
                            itemBuilder: (context, index) {
                              return _DoctorOnShiftRow(doctor: doctorsOnShift[index]);
                            },
                          ),
                  ),
                  if (nextUp != null) ...[
                    const SizedBox(height: SpacingTokens.md),
                    _NextUpPreview(item: nextUp!, shiftLookup: shiftLookup),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DoctorOnShiftRow extends StatelessWidget {
  const _DoctorOnShiftRow({required this.doctor});

  final QueueShiftDoctor doctor;

  @override
  Widget build(BuildContext context) {
    final colors = context.semanticColors;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.muted.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(SpacingTokens.md),
        border: Border.all(color: colors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: SpacingTokens.md, vertical: SpacingTokens.sm),
        child: Row(
          children: [
            Icon(Icons.medical_services_outlined, size: 20, color: colors.primary),
            const SizedBox(width: SpacingTokens.sm),
            Expanded(
              child: AppointmentScaleDownText(
                text: doctor.name,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoDoctorsOnShiftPlaceholder extends StatelessWidget {
  const _NoDoctorsOnShiftPlaceholder();

  @override
  Widget build(BuildContext context) {
    final colors = context.semanticColors;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.muted.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(SpacingTokens.lg),
        border: Border.all(color: colors.border, style: BorderStyle.solid),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(SpacingTokens.lg),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.medical_services_outlined, size: 48, color: colors.mutedForeground),
              const SizedBox(height: SpacingTokens.md),
              Text(
                'No doctors on shift',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: SpacingTokens.sm),
              Text(
                'Assign doctors to an active shift for this branch.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.mutedForeground),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NextUpPreview extends StatelessWidget {
  const _NextUpPreview({required this.item, required this.shiftLookup});

  final AppointmentListItem item;
  final AppointmentQueueShiftDoctorLookup shiftLookup;

  @override
  Widget build(BuildContext context) {
    final colors = context.semanticColors;
    final doctorLabel = AppointmentQueueDisplay.queueDoctorLabel(item, shiftLookup: shiftLookup);

    return Material(
      color: colors.background,
      borderRadius: BorderRadius.circular(SpacingTokens.md),
      child: InkWell(
        onTap: () => AppNavigator(context).pushAppointmentDetail(item.id, preview: item),
        borderRadius: BorderRadius.circular(SpacingTokens.md),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(SpacingTokens.md),
            border: Border.all(color: colors.border),
          ),
          padding: const EdgeInsets.symmetric(horizontal: SpacingTokens.md, vertical: SpacingTokens.sm),
          child: Row(
            children: [
              Icon(Icons.skip_next_outlined, size: 20, color: colors.primary),
              const SizedBox(width: SpacingTokens.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Next up',
                      style: Theme.of(
                        context,
                      ).textTheme.labelSmall?.copyWith(color: colors.mutedForeground, fontWeight: FontWeight.w600),
                    ),
                    AppointmentScaleDownText(
                      text: item.patientName,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: AppointmentScaleDownText(
                  text: doctorLabel,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.mutedForeground),
                  alignment: Alignment.centerRight,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
