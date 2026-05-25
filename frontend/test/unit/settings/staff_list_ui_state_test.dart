import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/settings/data/staff_admin_repository.dart';
import 'package:ai_clinic/features/settings/domain/staff_list_filter.dart';
import 'package:ai_clinic/features/settings/domain/staff_list_item.dart';
import 'package:ai_clinic/features/settings/presentation/providers/staff_list_notifier.dart';
import 'package:flutter_test/flutter_test.dart';

const _staffId = '00000000-0000-4000-8000-000000000101';

StaffListUiState _state({String? togglingStaffId, String? actionError}) {
  return StaffListUiState(
    filter: StaffListFilter.active,
    staff: const [
      StaffListItem(id: _staffId, fullName: 'Dr. Smith', role: StaffRole.doctor, isActive: true, branchNames: ['Main']),
    ],
    isTogglingActive: true,
    togglingStaffId: togglingStaffId ?? _staffId,
    actionError: actionError,
  );
}

void main() {
  group('StaffListUiState.copyWith', () {
    test('clearActionError preserves togglingStaffId', () {
      final original = _state(actionError: 'Previous error');
      final updated = original.copyWith(clearActionError: true);

      expect(updated.actionError, isNull);
      expect(updated.togglingStaffId, _staffId);
      expect(updated.isTogglingActive, isTrue);
    });

    test('clearTogglingStaffId clears togglingStaffId', () {
      final original = _state();
      final updated = original.copyWith(isTogglingActive: false, clearTogglingStaffId: true);

      expect(updated.togglingStaffId, isNull);
      expect(updated.isTogglingActive, isFalse);
    });
  });
}
