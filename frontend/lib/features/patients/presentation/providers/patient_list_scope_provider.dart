import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/features/patients/domain/patient_list_scope.dart';
import 'package:ai_clinic/shared/providers/auth_session_provider.dart';

/// In-memory list scope for patient search; resets to [PatientListScope.thisBranch] on sign-in.
class PatientListScopeNotifier extends Notifier<PatientListScope> {
  @override
  PatientListScope build() {
    ref.listen<AuthSessionState>(authSessionProvider, (previous, next) {
      final wasAuthenticated = previous?.isAuthenticated ?? false;
      final isAuthenticated = next.isAuthenticated;

      if (!wasAuthenticated && isAuthenticated) {
        state = PatientListScope.thisBranch;
      }

      if (wasAuthenticated && !isAuthenticated) {
        state = PatientListScope.thisBranch;
      }
    });

    return PatientListScope.thisBranch;
  }

  void setScope(PatientListScope scope) {
    state = scope;
  }
}

final patientListScopeProvider = NotifierProvider<PatientListScopeNotifier, PatientListScope>(
  PatientListScopeNotifier.new,
);
