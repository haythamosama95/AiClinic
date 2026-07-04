import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/features/patients/presentation/widgets/patient_editor_form.dart';

/// Full-page patient registration flow (`/patients/new`).
class RegisterPatientPage extends ConsumerWidget {
  const RegisterPatientPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const PatientEditorForm();
  }
}
