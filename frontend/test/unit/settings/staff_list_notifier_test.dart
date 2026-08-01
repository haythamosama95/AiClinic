import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/auth/domain/permission_keys.dart';
import 'package:ai_clinic/features/clinic-management/domain/repositories/staff_admin_repository.dart';
import 'package:ai_clinic/features/clinic-management/domain/staff_member_detail.dart';
import 'package:ai_clinic/features/clinic-management/domain/update_staff_member_input.dart';
import 'package:ai_clinic/features/clinic-management/domain/staff_list_filter.dart';
import 'package:ai_clinic/features/clinic-management/domain/staff_list_item.dart';
import 'package:ai_clinic/features/clinic-management/domain/usecases/clinic_management_use_case_providers.dart';
import 'package:ai_clinic/features/clinic-management/domain/usecases/list_staff.dart';
import 'package:ai_clinic/features/clinic-management/presentation/providers/staff_list_notifier.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/auth_test_support.dart';

void main() {
  group('StaffListNotifier', () {
    const staff = [
      StaffListItem(
        id: '22222222-2222-4222-8222-222222222222',
        fullName: 'Jane Doe',
        role: StaffRole.doctor,
        isActive: true,
        username: 'jane',
      ),
    ];

    ProviderContainer container({
      required AuthSessionState authState,
      required _TrackingStaffAdminRepository staffRepository,
    }) {
      return ProviderContainer(
        overrides: [
          authSessionProvider.overrideWith(() => _PresetAuthSessionNotifier(authState)),
          listStaffUseCaseProvider.overrideWith((ref) => ListStaff(staffRepository)),
        ],
      );
    }

    test('build returns empty staff when no staff management permission', () async {
      final staffRepository = _TrackingStaffAdminRepository(staff: staff);
      final c = container(
        authState: AuthSessionState(
          status: AuthSessionStatus.authenticated,
          context: sampleAuthSessionContext(
            role: StaffRole.doctor,
            permissions: {PermissionKeys.manageBranches},
          ),
        ),
        staffRepository: staffRepository,
      );
      addTearDown(c.dispose);

      final state = await c.read(staffListProvider.future);

      expect(state.staff, isEmpty);
      expect(staffRepository.listCallCount, 0);
    });

    test('build loads staff when permitted', () async {
      final staffRepository = _TrackingStaffAdminRepository(staff: staff);
      final c = container(
        authState: AuthSessionState(
          status: AuthSessionStatus.authenticated,
          context: sampleAuthSessionContext(
            role: StaffRole.administrator,
            permissions: {PermissionKeys.manageStaff},
          ),
        ),
        staffRepository: staffRepository,
      );
      addTearDown(c.dispose);

      final state = await c.read(staffListProvider.future);

      expect(state.staff, staff);
      expect(staffRepository.listCallCount, 1);
      expect(staffRepository.lastFilter, StaffListFilter.all);
    });

    test('reload invalidates and refetches', () async {
      final staffRepository = _TrackingStaffAdminRepository(staff: staff);
      final c = container(
        authState: AuthSessionState(
          status: AuthSessionStatus.authenticated,
          context: sampleAuthSessionContext(
            role: StaffRole.administrator,
            permissions: {PermissionKeys.manageStaff},
          ),
        ),
        staffRepository: staffRepository,
      );
      addTearDown(c.dispose);

      await c.read(staffListProvider.future);
      expect(staffRepository.listCallCount, 1);

      staffRepository.staff = const [
        StaffListItem(
          id: '33333333-3333-4333-8333-333333333333',
          fullName: 'John Smith',
          role: StaffRole.receptionist,
          isActive: true,
        ),
      ];

      await c.read(staffListProvider.notifier).reload();
      final refreshed = await c.read(staffListProvider.future);

      expect(staffRepository.listCallCount, 2);
      expect(refreshed.staff, staffRepository.staff);
      expect(refreshed.staff.single.fullName, 'John Smith');
    });

    test('stupid usage: reload without permission still returns empty without RPC', () async {
      final staffRepository = _TrackingStaffAdminRepository(staff: staff);
      final c = container(
        authState: AuthSessionState(
          status: AuthSessionStatus.authenticated,
          context: sampleAuthSessionContext(permissions: {PermissionKeys.patientsView}),
        ),
        staffRepository: staffRepository,
      );
      addTearDown(c.dispose);

      await c.read(staffListProvider.future);
      await c.read(staffListProvider.notifier).reload();
      final state = await c.read(staffListProvider.future);

      expect(state.staff, isEmpty);
      expect(staffRepository.listCallCount, 0);
    });
  });
}

class _PresetAuthSessionNotifier extends TestAuthSessionNotifier {
  _PresetAuthSessionNotifier(this.initial);

  final AuthSessionState initial;

  @override
  AuthSessionState build() => initial;
}

class _TrackingStaffAdminRepository implements StaffAdminRepository {
  _TrackingStaffAdminRepository({required this.staff});

  List<StaffListItem> staff;
  int listCallCount = 0;
  StaffListFilter? lastFilter;

  @override
  Future<List<StaffListItem>> listStaff({StaffListFilter filter = StaffListFilter.all}) async {
    listCallCount++;
    lastFilter = filter;
    return staff;
  }

  @override
  Future<StaffMemberDetail?> fetchStaffMember(String staffMemberId) => throw UnimplementedError();

  @override
  Future<String> updateStaffMember(UpdateStaffMemberInput input) => throw UnimplementedError();

  @override
  Future<RpcResult> setStaffActive({required String staffMemberId, required bool isActive}) =>
      throw UnimplementedError();

  @override
  Future<RpcResult> deleteStaffMember({required String staffMemberId}) => throw UnimplementedError();
}
