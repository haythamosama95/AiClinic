import 'dart:async';
import 'dart:convert';

import 'package:ai_clinic/app/providers/session_context_loader.dart';
import 'package:ai_clinic/core/config/supabase_config.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/auth/domain/repositories/permission_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('SessionContextLoader.parseBranchIdsFromClaim', () {
    test('filters null and undefined string literals', () {
      expect(
        SessionContextLoader.parseBranchIdsFromClaim('null,undefined,  ,branch-a'),
        ['branch-a'],
      );
    });

    test('trims whitespace and drops empty segments', () {
      expect(
        SessionContextLoader.parseBranchIdsFromClaim(' branch-a , branch-b '),
        ['branch-a', 'branch-b'],
      );
    });
  });

  group('SessionContextLoader.load', () {
  test('throws expired_access_token category for expired JWT', () async {
    final loader = SessionContextLoader(_ThrowingSupabaseClient(), _FakePermissionRepository());
    final session = Session(
      accessToken: _fakeJwt({
        'exp': DateTime.now().toUtc().subtract(const Duration(hours: 1)).millisecondsSinceEpoch ~/ 1000,
        'staff_member_id': 'b0000000-0000-4000-8000-000000000001',
      }),
      tokenType: 'bearer',
      user: const User(id: 'user', appMetadata: {}, userMetadata: {}, aud: 'authenticated', createdAt: ''),
      refreshToken: 'refresh',
    );

    expect(
      () => loader.load(session),
      throwsA(
        predicate<StateError>((error) => error.message.contains('access token has expired')),
      ),
    );
    expect(
      SessionContextLoader.contextFailureReason(
        StateError('Authenticated session access token has expired.'),
      ),
      'expired_access_token',
    );
  });

  test('throws missing_staff_claims when staff_member_id absent', () async {
    final loader = SessionContextLoader(_ThrowingSupabaseClient(), _FakePermissionRepository());
    final session = Session(
      accessToken: _fakeJwt({'staff_role': 'administrator'}),
      tokenType: 'bearer',
      user: const User(id: 'user', appMetadata: {}, userMetadata: {}, aud: 'authenticated', createdAt: ''),
      refreshToken: 'refresh',
    );

    expect(
      () => loader.load(session),
      throwsA(
        predicate<StateError>((error) => error.message.contains('missing staff claims')),
      ),
    );
  });

  test('retries a failed query once before succeeding', () async {
    final client = _RetryOnceSupabaseClient(
      staffRow: {
        'id': 'b0000000-0000-4000-8000-000000000001',
        'full_name': 'Retry Staff',
        'role': 'doctor',
        'is_bootstrap_admin': false,
        'is_active': true,
      },
    );
    final loader = SessionContextLoader(
      client,
      _FakePermissionRepository(permissions: {'patients.view'}),
      queryTimeout: const Duration(milliseconds: 200),
      retryBackoff: const Duration(milliseconds: 10),
    );
    final session = Session(
      accessToken: _fakeJwt({
        'staff_member_id': 'b0000000-0000-4000-8000-000000000001',
      }),
      tokenType: 'bearer',
      user: const User(id: 'user', appMetadata: {}, userMetadata: {}, aud: 'authenticated', createdAt: ''),
      refreshToken: 'refresh',
    );

    final context = await loader.load(session);

    expect(context.staffProfile.role, StaffRole.doctor);
    expect(client.staffMembersAttempts, 2);
  });

  test('loads branch ids from claim while filtering placeholders', () async {
    const branchId = '22222222-2222-4222-8222-222222222222';
    final client = _SessionTableTestClient(
      staffRow: {
        'id': 'b0000000-0000-4000-8000-000000000001',
        'full_name': 'Branch Staff',
        'role': 'receptionist',
        'is_bootstrap_admin': false,
        'is_active': true,
      },
      primaryBranchRow: {'branch_id': branchId},
      organizationRow: {'timezone': 'Africa/Cairo'},
    );
    final loader = SessionContextLoader(client, _FakePermissionRepository());
    final session = Session(
      accessToken: _fakeJwt({
        'staff_member_id': 'b0000000-0000-4000-8000-000000000001',
        'organization_id': '11111111-1111-4111-8111-111111111111',
        'branch_ids': 'null,undefined,$branchId',
      }),
      tokenType: 'bearer',
      user: const User(id: 'user', appMetadata: {}, userMetadata: {}, aud: 'authenticated', createdAt: ''),
      refreshToken: 'refresh',
    );

    final context = await loader.load(session);

    expect(context.branchIds, [branchId]);
    expect(context.activeBranchId, branchId);
    expect(context.organizationTimezone, 'Africa/Cairo');
  });
  });
}

String _fakeJwt(Map<String, dynamic> payload) {
  final header = base64Url.encode(utf8.encode('{"alg":"none"}'));
  final body = base64Url.encode(utf8.encode(jsonEncode(payload)));
  return '$header.$body.signature';
}

class _FakePermissionRepository implements PermissionRepository {
  _FakePermissionRepository({this.permissions = const {}});

  final Set<String> permissions;

  @override
  Future<Set<String>> loadGrantedPermissions(StaffRole role) async => permissions;
}

class _ThrowingSupabaseClient extends Fake implements SupabaseClient {
  @override
  SupabaseQueryBuilder from(String table) {
    throw UnimplementedError('should not query for $table');
  }
}

class _RetryOnceSupabaseClient extends Fake implements SupabaseClient {
  _RetryOnceSupabaseClient({required this.staffRow});

  final Map<String, dynamic> staffRow;
  final _RetryAttemptState staffMembersState = _RetryAttemptState();
  int staffMembersAttempts = 0;

  @override
  SupabaseQueryBuilder from(String table) {
    if (table == 'staff_members') {
      return _RetryOnceStaffMembersBuilder(
        staffRow: staffRow,
        state: staffMembersState,
        onAttempt: () => staffMembersAttempts++,
      );
    }
    throw UnimplementedError('unexpected table $table');
  }
}

class _RetryOnceStaffMembersBuilder extends Fake implements SupabaseQueryBuilder {
  _RetryOnceStaffMembersBuilder({required this.staffRow, required this.state, required this.onAttempt});

  final Map<String, dynamic> staffRow;
  final _RetryAttemptState state;
  final void Function() onAttempt;

  @override
  PostgrestFilterBuilder<List<Map<String, dynamic>>> select([String columns = '*']) {
    return _RetryOnceStaffMembersFilter(staffRow: staffRow, state: state, onAttempt: onAttempt);
  }
}

class _RetryOnceStaffMembersFilter extends Fake implements PostgrestFilterBuilder<List<Map<String, dynamic>>> {
  _RetryOnceStaffMembersFilter({required this.staffRow, required this.state, required this.onAttempt});

  final Map<String, dynamic> staffRow;
  final _RetryAttemptState state;
  final void Function() onAttempt;

  @override
  PostgrestFilterBuilder<List<Map<String, dynamic>>> eq(String column, Object value) => this;

  @override
  PostgrestTransformBuilder<Map<String, dynamic>?> maybeSingle() {
    return _RetryOnceMaybeSingle(
      resolve: () {
        onAttempt();
        state.attempts++;
        if (state.attempts == 1) {
          throw TimeoutException('simulated timeout');
        }
        return staffRow;
      },
    );
  }
}

class _RetryAttemptState {
  int attempts = 0;
}

class _RetryOnceMaybeSingle extends Fake implements PostgrestTransformBuilder<Map<String, dynamic>?> {
  _RetryOnceMaybeSingle({required this.resolve});

  final Map<String, dynamic>? Function() resolve;

  @override
  Future<R> then<R>(FutureOr<R> Function(Map<String, dynamic>? value) onValue, {Function? onError}) {
    try {
      return Future<Map<String, dynamic>?>.value(resolve()).then(onValue, onError: onError);
    } catch (error, stackTrace) {
      return Future<Map<String, dynamic>?>.error(error, stackTrace).then(onValue, onError: onError);
    }
  }
}

class _SessionTableTestClient extends Fake implements SupabaseClient {
  _SessionTableTestClient({
    required this.staffRow,
    this.primaryBranchRow,
    this.organizationRow,
  });

  final Map<String, dynamic> staffRow;
  final Map<String, dynamic>? primaryBranchRow;
  final Map<String, dynamic>? organizationRow;

  @override
  SupabaseQueryBuilder from(String table) => _SessionTableQueryBuilder(
    table: table,
    staffRow: staffRow,
    primaryBranchRow: primaryBranchRow,
    organizationRow: organizationRow,
  );
}

class _SessionTableQueryBuilder extends Fake implements SupabaseQueryBuilder {
  _SessionTableQueryBuilder({
    required this.table,
    required this.staffRow,
    this.primaryBranchRow,
    this.organizationRow,
  });

  final String table;
  final Map<String, dynamic> staffRow;
  final Map<String, dynamic>? primaryBranchRow;
  final Map<String, dynamic>? organizationRow;

  @override
  PostgrestFilterBuilder<List<Map<String, dynamic>>> select([String columns = '*']) {
    return _SessionTableFilter(
      table: table,
      staffRow: staffRow,
      primaryBranchRow: primaryBranchRow,
      organizationRow: organizationRow,
    );
  }
}

class _SessionTableFilter extends Fake implements PostgrestFilterBuilder<List<Map<String, dynamic>>> {
  _SessionTableFilter({
    required this.table,
    required this.staffRow,
    this.primaryBranchRow,
    this.organizationRow,
  });

  final String table;
  final Map<String, dynamic> staffRow;
  final Map<String, dynamic>? primaryBranchRow;
  final Map<String, dynamic>? organizationRow;

  @override
  PostgrestFilterBuilder<List<Map<String, dynamic>>> eq(String column, Object value) => this;

  @override
  PostgrestTransformBuilder<Map<String, dynamic>?> maybeSingle() {
    final row = switch (table) {
      'staff_members' => staffRow,
      'staff_branch_assignments' => primaryBranchRow,
      'organizations' => organizationRow,
      _ => null,
    };
    return _ImmediateMaybeSingle(row);
  }
}

class _ImmediateMaybeSingle extends Fake implements PostgrestTransformBuilder<Map<String, dynamic>?> {
  _ImmediateMaybeSingle(this._row);

  final Map<String, dynamic>? _row;

  @override
  Future<R> then<R>(FutureOr<R> Function(Map<String, dynamic>? value) onValue, {Function? onError}) {
    return Future<Map<String, dynamic>?>.value(_row).then(onValue, onError: onError);
  }
}
