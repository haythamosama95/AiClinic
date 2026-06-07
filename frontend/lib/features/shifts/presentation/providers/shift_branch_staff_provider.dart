import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/features/shifts/data/shift_repository.dart';
import 'package:ai_clinic/features/shifts/domain/shift_branch_staff.dart';

/// Active branch staff for shift assignment pickers (V1-7).
final shiftBranchStaffProvider = FutureProvider.autoDispose.family<List<ShiftBranchStaffMember>, String>((
  ref,
  branchId,
) {
  final normalized = branchId.trim();
  if (normalized.isEmpty) {
    return Future.value(const []);
  }
  return ref.watch(shiftRepositoryProvider).listActiveStaffForBranch(normalized);
});
