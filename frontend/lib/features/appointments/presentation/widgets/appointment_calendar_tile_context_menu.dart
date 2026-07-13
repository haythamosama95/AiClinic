import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/components/app_menu.dart';
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
  final canEditItem = canEdit && _canEditAppointment(item);
  final canCancelItem = canCancel && canCancelAppointment(item);

  return [
    AppMenuItem(
      id: 'edit',
      label: 'Edit appointment',
      icon: const Icon(Icons.edit_outlined, size: 16),
      disabled: !canEditItem,
      disabledReason: _editDisabledReason(canEdit: canEdit, item: item),
      onSelect: onEdit,
    ),
    const AppMenuSeparator(),
    AppMenuItem(
      id: 'cancel',
      label: 'Cancel appointment',
      icon: const Icon(Icons.delete_outline, size: 16),
      destructive: true,
      disabled: !canCancelItem,
      disabledReason: _cancelDisabledReason(canCancel: canCancel, item: item),
      onSelect: onCancel,
    ),
  ];
}

bool _canEditAppointment(AppointmentListItem item) {
  return !item.status.isTerminal;
}

String? _editDisabledReason({required bool canEdit, required AppointmentListItem item}) {
  if (!canEdit) {
    return 'You do not have permission to edit appointments.';
  }
  if (item.status.isTerminal) {
    return '${item.status.label} appointments cannot be edited.';
  }
  return null;
}

String? _cancelDisabledReason({required bool canCancel, required AppointmentListItem item}) {
  if (!canCancel) {
    return 'You do not have permission to cancel appointments.';
  }
  if (!canCancelAppointment(item)) {
    return '${item.status.label} appointments cannot be cancelled.';
  }
  return null;
}
