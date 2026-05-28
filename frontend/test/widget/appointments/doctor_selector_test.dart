import 'package:ai_clinic/features/appointments/presentation/widgets/doctor_selector.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/settings/data/staff_admin_repository.dart';
import 'package:ai_clinic/features/settings/domain/repositories/staff_admin_repository.dart';
import 'package:ai_clinic/features/settings/domain/staff_list_filter.dart';
import 'package:ai_clinic/features/settings/domain/staff_list_item.dart';
import 'package:ai_clinic/features/settings/domain/staff_member_detail.dart';
import 'package:ai_clinic/features/settings/domain/update_staff_member_input.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DoctorSelector', () {
    testWidgets('lists doctors and unassigned option', (tester) async {
      String? selected;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [staffAdminRepositoryProvider.overrideWithValue(_FakeStaffRepo())],
          child: MaterialApp(
            home: Scaffold(body: DoctorSelector(selectedDoctorId: null, onChanged: (id) => selected = id)),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('doctor_selector')), findsOneWidget);
      expect(find.text('No doctor assigned'), findsOneWidget);

      await tester.tap(find.byKey(const Key('doctor_selector')));
      await tester.pumpAndSettle();
      expect(find.text('Dr Smith'), findsOneWidget);

      await tester.tap(find.text('Dr Smith').last);
      await tester.pumpAndSettle();
      expect(selected, '22222222-2222-4222-8222-222222222222');
    });

    testWidgets('shows message when no doctors configured', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [staffAdminRepositoryProvider.overrideWithValue(_EmptyStaffRepo())],
          child: MaterialApp(
            home: Scaffold(body: DoctorSelector(selectedDoctorId: null, onChanged: (_) {})),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('book without assigning'), findsOneWidget);
    });
  });
}

class _FakeStaffRepo implements StaffAdminRepository {
  @override
  Future<List<StaffListItem>> listStaff({StaffListFilter filter = StaffListFilter.all}) async {
    return const [
      StaffListItem(
        id: '22222222-2222-4222-8222-222222222222',
        fullName: 'Dr Smith',
        role: StaffRole.doctor,
        isActive: true,
      ),
      StaffListItem(
        id: '33333333-3333-4333-8333-333333333333',
        fullName: 'Reception',
        role: StaffRole.receptionist,
        isActive: true,
      ),
    ];
  }

  @override
  Future<StaffMemberDetail?> fetchStaffMember(String staffMemberId) => throw UnimplementedError();

  @override
  Future<bool> organizationHasOwner() => throw UnimplementedError();

  @override
  Future<String> updateStaffMember(UpdateStaffMemberInput input) => throw UnimplementedError();

  @override
  Future<RpcResult> setStaffActive({required String staffMemberId, required bool isActive}) =>
      throw UnimplementedError();
}

class _EmptyStaffRepo implements StaffAdminRepository {
  @override
  Future<List<StaffListItem>> listStaff({StaffListFilter filter = StaffListFilter.all}) async => [];

  @override
  Future<StaffMemberDetail?> fetchStaffMember(String staffMemberId) => throw UnimplementedError();

  @override
  Future<bool> organizationHasOwner() => throw UnimplementedError();

  @override
  Future<String> updateStaffMember(UpdateStaffMemberInput input) => throw UnimplementedError();

  @override
  Future<RpcResult> setStaffActive({required String staffMemberId, required bool isActive}) =>
      throw UnimplementedError();
}
