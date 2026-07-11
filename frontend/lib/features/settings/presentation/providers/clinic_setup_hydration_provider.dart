import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/features/settings/presentation/providers/clinic_setup_draft_notifier.dart';

/// Loads organization, branches, staff, and service catalog from the backend
/// when the settings setup screen is opened.
final clinicSetupHydrationProvider = FutureProvider.autoDispose<void>((ref) async {
  await ref.read(clinicSetupDraftProvider.notifier).hydrateFromBackend();
});
