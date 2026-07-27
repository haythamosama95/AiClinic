import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:ai_clinic/features/appointments/domain/appointment_list_item.dart';

const appointmentCalendarSkeletonRevealDelay = Duration(milliseconds: 180);

/// Drives staggered skeleton reveal for calendar appointment tiles.
class AppointmentCalendarRevealController {
  Set<String> revealedAppointmentIds = {};
  int _revealGeneration = 0;
  int _lastRevealSourceFingerprint = -1;

  void scheduleRevealIfNeeded(
    List<AppointmentListItem> items, {
    required bool loading,
    required VoidCallback onChanged,
  }) {
    if (loading) {
      if (revealedAppointmentIds.isEmpty && _lastRevealSourceFingerprint == -1) {
        return;
      }
      revealedAppointmentIds = {};
      _lastRevealSourceFingerprint = -1;
      _revealGeneration++;
      onChanged();
      return;
    }

    final sourceFingerprint = Object.hashAll(items.map((item) => item.id));
    if (sourceFingerprint == _lastRevealSourceFingerprint) {
      return;
    }

    _lastRevealSourceFingerprint = sourceFingerprint;
    startSkeletonReveal(items.map((item) => item.id).toList(growable: false), onChanged: onChanged);
  }

  void startSkeletonReveal(List<String> appointmentIds, {required VoidCallback onChanged}) {
    _revealGeneration++;
    final generation = _revealGeneration;

    revealedAppointmentIds = {};
    onChanged();

    if (appointmentIds.isEmpty) {
      return;
    }

    unawaited(
      Future<void>.delayed(appointmentCalendarSkeletonRevealDelay, () {
        if (generation != _revealGeneration) {
          return;
        }
        revealedAppointmentIds = appointmentIds.toSet();
        onChanged();
      }),
    );
  }

  void dispose() {
    _revealGeneration++;
  }
}
