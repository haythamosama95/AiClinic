import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/auth/auth_route_guard.dart';
import 'package:ai_clinic/features/settings/domain/staff_list_filter.dart';
import 'package:ai_clinic/features/settings/domain/staff_list_item.dart';
import 'package:ai_clinic/features/settings/domain/usecases/settings_use_case_providers.dart';

@immutable
class StaffListUiState {
  const StaffListUiState({required this.staff});

  final List<StaffListItem> staff;
}

final staffListProvider = AsyncNotifierProvider<StaffListNotifier, StaffListUiState>(StaffListNotifier.new);

class StaffListNotifier extends AsyncNotifier<StaffListUiState> {
  @override
  Future<StaffListUiState> build() async {
    final auth = ref.read(authSessionProvider);
    if (!AuthRouteGuard.canAccessStaffManagement(auth)) {
      return const StaffListUiState(staff: []);
    }

    final staff = await ref.read(listStaffUseCaseProvider)(filter: StaffListFilter.all);
    return StaffListUiState(staff: staff);
  }

  Future<void> reload() async {
    state = const AsyncLoading();
    ref.invalidateSelf();
  }
}
