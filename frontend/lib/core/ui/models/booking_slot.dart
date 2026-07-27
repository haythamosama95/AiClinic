import 'package:flutter/foundation.dart';

/// Availability state for a bookable time slot (web `SlotStatus`).
enum BookingSlotStatus { locked, available, preferred, alternate }

/// A single selectable booking slot.
@immutable
class BookingTimeSlot {
  const BookingTimeSlot({
    required this.start,
    required this.label,
    required this.status,
    required this.availableDoctorIds,
  });

  final DateTime start;
  final String label;
  final BookingSlotStatus status;
  final List<String> availableDoctorIds;
}
