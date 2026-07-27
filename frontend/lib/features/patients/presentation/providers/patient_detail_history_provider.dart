import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Past vs upcoming tab on the patient detail timeline.
enum PatientDetailHistoryTab { past, upcoming }

class PatientDetailHistoryTabNotifier extends Notifier<PatientDetailHistoryTab> {
  PatientDetailHistoryTabNotifier(this.patientId);

  final String patientId;

  @override
  PatientDetailHistoryTab build() => PatientDetailHistoryTab.past;

  void select(PatientDetailHistoryTab tab) => state = tab;
}

/// Selected timeline tab for a patient detail page (survives provider reloads).
final patientDetailHistoryTabProvider =
    NotifierProvider.family<PatientDetailHistoryTabNotifier, PatientDetailHistoryTab, String>(
      PatientDetailHistoryTabNotifier.new,
      isAutoDispose: true,
    );
