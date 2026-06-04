import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_working_hours.dart';
import 'package:ai_clinic/features/appointments/presentation/providers/appointment_branch_providers.dart';
import 'package:ai_clinic/features/settings/data/branch_repository.dart';
import 'package:ai_clinic/features/settings/domain/branch_list_filter.dart';
import 'package:ai_clinic/features/settings/domain/branch_list_item.dart';
import 'package:ai_clinic/features/settings/domain/branch_working_schedule.dart';
import 'package:ai_clinic/features/settings/domain/create_branch_input.dart';
import 'package:ai_clinic/features/settings/domain/repositories/branch_repository.dart';
import 'package:ai_clinic/features/settings/domain/update_branch_input.dart';

import '../../helpers/auth_test_support.dart';

void main() {
  group('appointmentActiveBranchesProvider', () {
    test('returns refreshed working schedule after invalidation (branch hours edit scenario)', () async {
      const branchId = '44444444-4444-4444-8444-444444444444';
      final repo = _MutableFakeBranchRepository(branchId: branchId, schedule: BranchWorkingSchedule.defaultSchedule());
      final container = _container(repo, branchId: branchId);
      addTearDown(container.dispose);

      final slotStart = DateTime(2026, 6, 1, 8, 0);
      final slotEnd = slotStart.add(const Duration(minutes: 30));

      final cachedBranches = await container.read(appointmentActiveBranchesProvider.future);
      final cachedSchedule = cachedBranches.single.workingSchedule!;
      expect(
        AppointmentWorkingHours.isWithinSchedule(schedule: cachedSchedule, start: slotStart, end: slotEnd),
        isFalse,
        reason: '8:00 is before the default 09:00 open time',
      );

      repo.schedule = _scheduleWithMondayOpen('08:00');

      final stillCached = await container.read(appointmentActiveBranchesProvider.future);
      expect(stillCached.single.workingSchedule, cachedSchedule);

      container.invalidate(appointmentActiveBranchesProvider);
      final refreshed = await container.read(appointmentActiveBranchesProvider.future);
      expect(
        AppointmentWorkingHours.isWithinSchedule(
          schedule: refreshed.single.workingSchedule!,
          start: slotStart,
          end: slotEnd,
        ),
        isTrue,
        reason: 'After invalidation, booking should see the updated branch hours',
      );
      expect(repo.listBranchesCalls, 2);
    });
  });
}

ProviderContainer _container(_MutableFakeBranchRepository repo, {required String branchId}) {
  return ProviderContainer(
    overrides: [
      branchRepositoryProvider.overrideWithValue(repo),
      authSessionProvider.overrideWith(
        () => _PresetAuth(
          AuthSessionState(
            status: AuthSessionStatus.authenticated,
            context: sampleAuthSessionContext(branchIds: [branchId], activeBranchId: branchId),
          ),
        ),
      ),
    ],
  );
}

BranchWorkingSchedule _scheduleWithMondayOpen(String openTime) {
  return BranchWorkingSchedule(
    BranchWeekday.values
        .map(
          (day) => BranchWorkingDayHours(
            day: day,
            isWorkingDay: day != BranchWeekday.sunday,
            openTime: day == BranchWeekday.monday ? openTime : (day == BranchWeekday.sunday ? null : '09:00'),
            closeTime: day == BranchWeekday.sunday ? null : '17:00',
          ),
        )
        .toList(growable: false),
  );
}

class _MutableFakeBranchRepository implements BranchRepository {
  _MutableFakeBranchRepository({required this.branchId, required this.schedule});

  final String branchId;
  BranchWorkingSchedule schedule;
  int listBranchesCalls = 0;

  @override
  Future<List<BranchListItem>> listBranches({
    required String organizationId,
    BranchListFilter filter = BranchListFilter.all,
  }) async {
    listBranchesCalls++;
    return [BranchListItem(id: branchId, name: 'Main Branch', isActive: true, workingSchedule: schedule)];
  }

  @override
  Future<String> createBranch(CreateBranchInput input) => throw UnimplementedError();

  @override
  Future<RpcResult> setBranchActive({required String branchId, required bool isActive}) => throw UnimplementedError();

  @override
  Future<String> updateBranch(UpdateBranchInput input) => throw UnimplementedError();
}

class _PresetAuth extends TestAuthSessionNotifier {
  _PresetAuth(this.initial);

  final AuthSessionState initial;

  @override
  AuthSessionState build() => initial;
}
