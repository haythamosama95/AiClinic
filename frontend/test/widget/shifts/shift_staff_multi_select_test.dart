import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/shifts/data/shift_repository.dart';
import 'package:ai_clinic/features/shifts/presentation/widgets/shift_staff_multi_select.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/auth_test_support.dart';
import '../../support/shift_rpc_test_client.dart';

const _branchA = '44444444-4444-4444-8444-444444444444';
const _branchB = '55555555-5555-5555-8555-555555555555';
const _staffA = '22222222-2222-4222-8222-222222222222';

class _MutableAuth extends AuthSessionNotifier {
  _MutableAuth(this._state);

  AuthSessionState _state;

  void update(AuthSessionState state) {
    _state = state;
    this.state = state;
  }

  @override
  AuthSessionState build() => _state;
}

void main() {
  testWidgets('reloads staff when active branch changes (#9)', (tester) async {
    final client = ShiftRpcTestClient(branchId: _branchA, staffId: _staffA);
    client.rpcResults['staff_branch_assignments'] = null;

    final auth = _MutableAuth(
      AuthSessionState(
        status: AuthSessionStatus.authenticated,
        context: sampleAuthSessionContext(activeBranchId: _branchA, branchIds: [_branchA, _branchB]),
      ),
    );

    final selected = <String>{_staffA};
    var changeCount = 0;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authSessionProvider.overrideWith(() => auth),
          shiftRepositoryProvider.overrideWith((ref) => ShiftRepository(client)),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: ShiftStaffMultiSelect(
              selectedStaffIds: selected,
              onChanged: (next) {
                changeCount++;
                selected
                  ..clear()
                  ..addAll(next);
              },
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    expect(find.byKey(Key('shift_staff_option_$_staffA')), findsOneWidget);

    auth.update(
      AuthSessionState(
        status: AuthSessionStatus.authenticated,
        context: sampleAuthSessionContext(activeBranchId: _branchB, branchIds: [_branchA, _branchB]),
      ),
    );

    await tester.pump();
    await tester.pumpAndSettle();

    expect(changeCount, greaterThanOrEqualTo(1));
    expect(selected, isEmpty);
    expect(find.text('No active staff are assigned to this branch. You can save an unassigned shift.'), findsOneWidget);
  });
}
