import 'package:ai_clinic/features/appointments/domain/appointment_row_parsing.dart';
import 'package:flutter/foundation.dart';

/// Server-derived availability state for a simplified booking time block (011).
enum SlotAvailabilityState { available, alternateDoctorsAvailable, fullyUnavailable, past }

/// A single bookable time block returned by `get_simplified_booking_slots`.
@immutable
class SimplifiedBookingSlot {
  const SimplifiedBookingSlot({
    required this.startTime,
    required this.endTime,
    required this.state,
    required this.availableDoctorIds,
  });

  final DateTime startTime;
  final DateTime endTime;
  final SlotAvailabilityState state;
  final List<String> availableDoctorIds;

  static SimplifiedBookingSlot? fromRpcBlock(Map<String, dynamic>? block) {
    if (block == null) {
      return null;
    }

    final startTime = parseAppointmentDateTime(block['start_time']);
    final endTime = parseAppointmentDateTime(block['end_time']);
    final state = _parseState(block['state']?.toString());
    if (startTime == null || endTime == null || state == null) {
      return null;
    }

    final rawDoctorIds = block['available_doctor_ids'];
    final doctorIds = <String>[];
    if (rawDoctorIds is List) {
      for (final id in rawDoctorIds) {
        final text = id?.toString().trim();
        if (text != null && text.isNotEmpty) {
          doctorIds.add(text);
        }
      }
    }

    return SimplifiedBookingSlot(
      startTime: startTime,
      endTime: endTime,
      state: state,
      availableDoctorIds: List.unmodifiable(doctorIds),
    );
  }
}

/// Parsed response from `get_simplified_booking_slots` for one calendar day.
@immutable
class SimplifiedBookingDaySlots {
  const SimplifiedBookingDaySlots({required this.defaultDurationMinutes, required this.blocks});

  final int defaultDurationMinutes;
  final List<SimplifiedBookingSlot> blocks;

  static SimplifiedBookingDaySlots? fromRpcData(Map<String, dynamic>? data) {
    if (data == null) {
      return null;
    }

    final defaultMinutes = _parseInt(data['default_duration_minutes']);
    if (defaultMinutes == null) {
      return null;
    }

    final rawBlocks = data['blocks'];
    if (rawBlocks is! List) {
      return SimplifiedBookingDaySlots(defaultDurationMinutes: defaultMinutes, blocks: const []);
    }

    final blocks = <SimplifiedBookingSlot>[];
    for (final raw in rawBlocks) {
      final block = SimplifiedBookingSlot.fromRpcBlock(
        raw is Map<String, dynamic>
            ? raw
            : raw is Map
            ? Map<String, dynamic>.from(raw)
            : null,
      );
      if (block != null) {
        blocks.add(block);
      }
    }

    return SimplifiedBookingDaySlots(defaultDurationMinutes: defaultMinutes, blocks: blocks);
  }
}

SlotAvailabilityState? _parseState(String? value) {
  switch (value) {
    case 'available':
      return SlotAvailabilityState.available;
    case 'alternate_doctors_available':
      return SlotAvailabilityState.alternateDoctorsAvailable;
    case 'fully_unavailable':
      return SlotAvailabilityState.fullyUnavailable;
    case 'past':
      return SlotAvailabilityState.past;
    default:
      return null;
  }
}

int? _parseInt(dynamic value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return int.tryParse(value?.toString() ?? '');
}
