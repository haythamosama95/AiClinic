import 'package:ai_clinic/features/appointments/domain/simplified_booking_slot.dart';
import 'package:ai_clinic/features/patients/domain/patient_list_item.dart';
import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';

/// In-memory state for the simplified two-step booking flow (011).
@immutable
class SimplifiedBookingSession {
  const SimplifiedBookingSession({
    required this.branchId,
    this.patient,
    this.preferredDoctorId,
    this.effectiveDoctorId,
    required this.selectedDate,
    this.selectedSlot,
    this.defaultDurationMinutes,
    this.notes,
  });

  final String branchId;
  final PatientListItem? patient;
  final String? preferredDoctorId;
  final String? effectiveDoctorId;
  final DateTime selectedDate;
  final SimplifiedBookingSlot? selectedSlot;
  final int? defaultDurationMinutes;
  final String? notes;

  String? get patientId => patient?.id;

  bool get canAdvanceFromStepOne => patient != null;

  factory SimplifiedBookingSession.initial({required String branchId, DateTime? reference}) {
    final today = simplifiedBookingDateOnly(reference ?? clock.now());
    return SimplifiedBookingSession(branchId: branchId, selectedDate: today);
  }

  SimplifiedBookingSession copyWith({
    PatientListItem? patient,
    bool clearPatient = false,
    String? preferredDoctorId,
    bool clearPreferredDoctor = false,
    String? effectiveDoctorId,
    bool clearEffectiveDoctor = false,
    DateTime? selectedDate,
    SimplifiedBookingSlot? selectedSlot,
    bool clearSelectedSlot = false,
    int? defaultDurationMinutes,
    String? notes,
  }) {
    return SimplifiedBookingSession(
      branchId: branchId,
      patient: clearPatient ? null : (patient ?? this.patient),
      preferredDoctorId: clearPreferredDoctor ? null : (preferredDoctorId ?? this.preferredDoctorId),
      effectiveDoctorId: clearEffectiveDoctor ? null : (effectiveDoctorId ?? this.effectiveDoctorId),
      selectedDate: selectedDate ?? this.selectedDate,
      selectedSlot: clearSelectedSlot ? null : (selectedSlot ?? this.selectedSlot),
      defaultDurationMinutes: defaultDurationMinutes ?? this.defaultDurationMinutes,
      notes: notes ?? this.notes,
    );
  }

  SimplifiedBookingSession clearSlot() => copyWith(clearSelectedSlot: true);

  SimplifiedBookingSession forStepTwoEntry({required int defaultDurationMinutes}) {
    final doctorId = preferredDoctorId;
    return copyWith(
      effectiveDoctorId: doctorId,
      clearEffectiveDoctor: doctorId == null,
      defaultDurationMinutes: defaultDurationMinutes,
      clearSelectedSlot: true,
    );
  }
}
