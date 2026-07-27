import 'package:intl/intl.dart';

import 'package:ai_clinic/core/ui/models/booking_slot.dart';

/// Formats a booking slot start time for display in the slot grid.
String formatAppointmentSlotLabel(DateTime start) {
  return DateFormat.jm().format(start.toLocal());
}

/// Adds user-facing labels to domain slots at the presentation boundary.
List<BookingTimeSlot> withAppointmentSlotLabels(List<BookingTimeSlot> slots) {
  return slots
      .map(
        (slot) => BookingTimeSlot(
          start: slot.start,
          label: formatAppointmentSlotLabel(slot.start),
          status: slot.status,
          availableDoctorIds: slot.availableDoctorIds,
        ),
      )
      .toList(growable: false);
}
