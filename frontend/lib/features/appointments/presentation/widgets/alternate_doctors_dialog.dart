import 'package:ai_clinic/core/ui/theme/theme.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/appointments/domain/simplified_booking_slot.dart';
import 'package:ai_clinic/features/settings/domain/staff_list_item.dart';
import 'package:flutter/material.dart';
import 'package:forui/forui.dart';
import 'package:intl/intl.dart';

/// Lists doctors available for a simplified booking time block (011).
class AlternateDoctorsDialog extends StatelessWidget {
  const AlternateDoctorsDialog({
    required this.slot,
    required this.doctors,
    required this.onDoctorSelected,
    required this.dialogStyle,
    required this.animation,
    this.hasPreferredDoctor = true,
    super.key,
  });

  final SimplifiedBookingSlot slot;
  final List<StaffListItem> doctors;
  final ValueChanged<String> onDoctorSelected;
  final FDialogStyle dialogStyle;
  final Animation<double> animation;
  final bool hasPreferredDoctor;

  static Future<void> show(
    BuildContext context, {
    required SimplifiedBookingSlot slot,
    required List<StaffListItem> doctors,
    required ValueChanged<String> onDoctorSelected,
    bool hasPreferredDoctor = true,
  }) {
    final fTheme = context.theme;
    final availableIds = slot.availableDoctorIds.toSet();
    final filtered = doctors.where((doctor) => availableIds.contains(doctor.id)).toList()
      ..sort(StaffListItem.compareByFullName);

    return showFDialog<void>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: true,
      builder: (dialogContext, style, animation) {
        return FTheme(
          data: fTheme,
          child: AlternateDoctorsDialog(
            slot: slot,
            doctors: filtered,
            onDoctorSelected: onDoctorSelected,
            dialogStyle: style,
            animation: animation,
            hasPreferredDoctor: hasPreferredDoctor,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.semanticColors;
    final timeLabel = DateFormat.jm().format(slot.startTime.toLocal());
    final title = hasPreferredDoctor ? 'Other doctors available' : 'Select a doctor';
    final body = hasPreferredDoctor ? 'Other doctors are available at $timeLabel.' : 'Select a doctor for $timeLabel.';
    final emptyMessage = hasPreferredDoctor
        ? 'No alternate doctors are available.'
        : 'No doctors are available at this time.';

    return FDialog(
      style: dialogStyle,
      animation: animation,
      direction: Axis.horizontal,
      title: Text(title, style: theme.textTheme.titleLarge),
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(body, style: theme.textTheme.bodyMedium),
          const SizedBox(height: SpacingTokens.md),
          if (doctors.isEmpty)
            Text(emptyMessage, style: theme.textTheme.bodySmall?.copyWith(color: colors.mutedForeground))
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 280),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: doctors.length,
                separatorBuilder: (_, __) => const SizedBox(height: SpacingTokens.xs),
                itemBuilder: (context, index) {
                  final doctor = doctors[index];
                  return Semantics(
                    button: true,
                    label: doctor.fullName,
                    child: Material(
                      color: colors.card,
                      borderRadius: BorderRadius.circular(context.shapeTokens.md),
                      child: ListTile(
                        title: Text(doctor.fullName),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(context.shapeTokens.md),
                          side: BorderSide(color: colors.border),
                        ),
                        onTap: () {
                          Navigator.of(context, rootNavigator: true).pop();
                          onDoctorSelected(doctor.id);
                        },
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
      actions: [
        AppButton(
          label: 'Cancel',
          variant: AppButtonVariant.secondary,
          onPressed: () => Navigator.of(context, rootNavigator: true).pop(),
        ),
      ],
    );
  }
}
