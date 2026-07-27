import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/components/app_menu.dart';
import 'package:ai_clinic/features/appointments/application/appointment_edit_policy.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_list_item.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status_transitions.dart';

/// Right-click menu entries for a calendar appointment tile.
List<AppMenuEntry> appointmentCalendarTileMenuEntries({
  required AppointmentListItem item,
  required bool canEdit,
  required bool canCancel,
  required VoidCallback onEdit,
  required VoidCallback onCancel,
}) {
  final canEditItem = canEdit && AppointmentEditPolicy.canEditAppointment(item.status);
  final canCancelItem = canCancel && canCancelAppointment(item);

  return [
    AppMenuItem(
      id: 'edit',
      label: AppointmentEditPolicy.editActionLabel(item.status),
      icon: const Icon(Icons.edit_outlined, size: 16),
      disabled: !canEditItem,
      disabledReason: AppointmentEditPolicy.editDisabledReason(canEdit: canEdit, status: item.status),
      onSelect: onEdit,
    ),
    const AppMenuSeparator(),
    AppMenuItem(
      id: 'cancel',
      label: 'Cancel appointment',
      icon: const Icon(Icons.delete_outline, size: 16),
      destructive: true,
      disabled: !canCancelItem,
      disabledReason: AppointmentEditPolicy.cancelDisabledReason(canCancel: canCancel, item: item),
      onSelect: onCancel,
    ),
  ];
}
