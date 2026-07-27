import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/features/clinic-management/presentation/providers/clinic_setup_providers.dart';

/// Resolves the display name of the user's active branch for registration copy.
final activeBranchNameProvider = FutureProvider<String>((ref) async {
  final activeBranchId = ref.watch(authSessionProvider.select((session) => session.context?.activeBranchId));
  final branches = await ref.watch(clinicSetupBranchesProvider.future);

  return branches.where((branch) => branch.id == activeBranchId).map((branch) => branch.name).firstOrNull ??
      'your active branch';
});
