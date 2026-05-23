import 'package:flutter/material.dart';

/// Placeholder until US2 list page is implemented (Phase 4).
class PatientListPage extends StatelessWidget {
  const PatientListPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: Text('Patient list — coming in Phase 4')));
  }
}

/// Placeholder until US1 registration page is implemented (Phase 3).
class PatientRegistrationPage extends StatelessWidget {
  const PatientRegistrationPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: Text('Patient registration — coming in Phase 3')));
  }
}

/// Placeholder until US3 detail page is implemented (Phase 5).
class PatientDetailPage extends StatelessWidget {
  const PatientDetailPage({required this.patientId, super.key});

  final String? patientId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(body: Center(child: Text('Patient detail ($patientId) — coming in Phase 5')));
  }
}

/// Placeholder until US4 edit page is implemented (Phase 6).
class PatientEditPage extends StatelessWidget {
  const PatientEditPage({required this.patientId, super.key});

  final String? patientId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(body: Center(child: Text('Patient edit ($patientId) — coming in Phase 6')));
  }
}
