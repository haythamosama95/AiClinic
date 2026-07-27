import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/providers/locale_provider.dart';
import 'package:ai_clinic/features/setup/presentation/providers/staff_assignable_branches_provider.dart';
import 'package:ai_clinic/l10n/app_localizations.dart';

/// Resolves a branch display name by id for cross-feature visit confirmation surfaces.
final branchNameProvider = FutureProvider.autoDispose.family<String, String>((ref, branchId) async {
  final l10n = lookupAppLocalizations(ref.watch(localeProvider));

  try {
    final branches = await ref.watch(staffAssignableBranchesProvider.future);
    for (final branch in branches) {
      if (branch.id == branchId) {
        return branch.name;
      }
    }
    return l10n.branchNameFallback;
  } catch (_) {
    return l10n.branchNameFallback;
  }
});
