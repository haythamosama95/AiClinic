import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/features/setup/presentation/providers/clinic_setup_notifier.dart';

/// Loads organization, branches, staff, and service catalog from the backend
/// when the settings setup screen is opened.
final clinicSetupHydrationProvider = FutureProvider.autoDispose<void>((ref) async {
  await ref.read(clinicSetupProvider.notifier).hydrateFromBackend();
<<<<<<< HEAD
});
=======
}, retry: (_, _) => null);
>>>>>>> master
