import 'package:ai_clinic/features/appointments/domain/simplified_booking_slot.dart';
import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SimplifiedBookingSlot.fromRpcBlock', () {
    test('maps available state and doctor ids', () {
      final slot = SimplifiedBookingSlot.fromRpcBlock({
        'start_time': '2026-11-12T07:15:00.000Z',
        'end_time': '2026-11-12T07:30:00.000Z',
        'state': 'available',
        'available_doctor_ids': ['doctor-a', 'doctor-b'],
      });

      expect(slot, isNotNull);
      expect(slot!.state, SlotAvailabilityState.available);
      expect(slot.availableDoctorIds, ['doctor-a', 'doctor-b']);
      expect(slot.startTime, DateTime.utc(2026, 11, 12, 7, 15));
      expect(slot.endTime, DateTime.utc(2026, 11, 12, 7, 30));
    });

    test('maps alternate, fully unavailable, and past states', () {
      expect(
        SimplifiedBookingSlot.fromRpcBlock({
          'start_time': '2026-01-01T09:00:00.000Z',
          'end_time': '2026-01-01T09:30:00.000Z',
          'state': 'alternate_doctors_available',
          'available_doctor_ids': [],
        })!.state,
        SlotAvailabilityState.alternateDoctorsAvailable,
      );
      expect(
        SimplifiedBookingSlot.fromRpcBlock({
          'start_time': '2026-01-01T09:00:00.000Z',
          'end_time': '2026-01-01T09:30:00.000Z',
          'state': 'fully_unavailable',
          'available_doctor_ids': [],
        })!.state,
        SlotAvailabilityState.fullyUnavailable,
      );
      expect(
        SimplifiedBookingSlot.fromRpcBlock({
          'start_time': '2026-01-01T09:00:00.000Z',
          'end_time': '2026-01-01T09:30:00.000Z',
          'state': 'past',
          'available_doctor_ids': [],
        })!.state,
        SlotAvailabilityState.past,
      );
    });

    test('returns null for unknown state or missing timestamps', () {
      expect(
        SimplifiedBookingSlot.fromRpcBlock({
          'start_time': '2026-01-01T09:00:00.000Z',
          'end_time': '2026-01-01T09:30:00.000Z',
          'state': 'unknown',
          'available_doctor_ids': [],
        }),
        isNull,
      );
      expect(SimplifiedBookingSlot.fromRpcBlock({'state': 'available'}), isNull);
    });
  });

  group('SimplifiedBookingDaySlots.fromRpcData', () {
    test('parses default duration and blocks', () {
      final daySlots = SimplifiedBookingDaySlots.fromRpcData({
        'default_duration_minutes': 20,
        'blocks': [
          {
            'start_time': '2026-11-12T07:15:00.000Z',
            'end_time': '2026-11-12T07:35:00.000Z',
            'state': 'available',
            'available_doctor_ids': ['doctor-a'],
          },
        ],
      });

      expect(daySlots, isNotNull);
      expect(daySlots!.defaultDurationMinutes, 20);
      expect(daySlots.blocks, hasLength(1));
      expect(daySlots.blocks.single.state, SlotAvailabilityState.available);
    });
  });

  group('clampSimplifiedBookingDate', () {
    final reference = DateTime(2026, 6, 27);

    test('clamps before today to today', () {
      withClock(Clock.fixed(reference), () {
        final clamped = clampSimplifiedBookingDate(DateTime(2026, 6, 20));
        expect(clamped, DateTime(2026, 6, 27));
      });
    });

    test('clamps after today+90 to max date', () {
      withClock(Clock.fixed(reference), () {
        final clamped = clampSimplifiedBookingDate(DateTime(2026, 12, 1));
        expect(clamped, DateTime(2026, 9, 25));
      });
    });

    test('preserves in-range dates', () {
      withClock(Clock.fixed(reference), () {
        final target = DateTime(2026, 7, 4);
        expect(clampSimplifiedBookingDate(target), target);
      });
    });

    test('simplifiedBookingDateRange is inclusive through +90 days', () {
      withClock(Clock.fixed(reference), () {
        final range = simplifiedBookingDateRange();
        expect(range.minDate, DateTime(2026, 6, 27));
        expect(range.maxDate, DateTime(2026, 9, 25));
        expect(clampSimplifiedBookingDate(range.maxDate), range.maxDate);
      });
    });
  });
}
