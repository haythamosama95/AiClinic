import 'dart:async';

import 'package:ai_clinic/core/config/supabase_config.dart';
import 'package:ai_clinic/features/auth/data/permission_repository.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/auth/domain/repositories/permission_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postgrest/postgrest.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _RolesPermissionsQueryRecorder {
  String? table;
  String? selectColumns;
  final filters = <MapEntry<String, Object>>[];
}

/// Supabase fake whose PostgREST builders are real [Future]s for list queries.
class _RolesPermissionsTestClient extends Fake implements SupabaseClient {
  _RolesPermissionsTestClient(this._tables, {this.queryError, this.recorder});

  final Map<String, List<Map<String, dynamic>>> _tables;
  final Object? queryError;
  final _RolesPermissionsQueryRecorder? recorder;

  @override
  SupabaseQueryBuilder from(String table) {
    recorder?.table = table;
    return _RolesPermissionsQueryBuilder(
      List<Map<String, dynamic>>.from(_tables[table] ?? []),
      queryError: queryError,
      recorder: recorder,
    );
  }
}

class _RolesPermissionsQueryBuilder extends Fake implements SupabaseQueryBuilder {
  _RolesPermissionsQueryBuilder(this._rows, {this.queryError, this.recorder});

  final List<Map<String, dynamic>> _rows;
  final Object? queryError;
  final _RolesPermissionsQueryRecorder? recorder;

  @override
  PostgrestFilterBuilder<List<Map<String, dynamic>>> select([String columns = '*']) {
    recorder?.selectColumns = columns;
    return _RolesPermissionsFilterBuilder(
      _rows,
      queryError: queryError,
      recorder: recorder,
    );
  }
}

class _RolesPermissionsFilterBuilder extends Fake implements PostgrestFilterBuilder<List<Map<String, dynamic>>> {
  _RolesPermissionsFilterBuilder(this._rows, {this.queryError, this.recorder});

  final List<Map<String, dynamic>> _rows;
  final Object? queryError;
  final _RolesPermissionsQueryRecorder? recorder;

  @override
  PostgrestFilterBuilder<List<Map<String, dynamic>>> eq(String column, Object value) {
    recorder?.filters.add(MapEntry(column, value));
    _rows.retainWhere((row) => row[column] == value);
    return this;
  }

  @override
  Future<R> then<R>(FutureOr<R> Function(List<Map<String, dynamic>> value) onValue, {Function? onError}) {
    if (queryError != null) {
      return Future<R>.error(queryError!).then(onValue, onError: onError);
    }
    return Future<List<Map<String, dynamic>>>.value(
      List<Map<String, dynamic>>.from(_rows),
    ).then(onValue, onError: onError);
  }
}

void main() {
  group('PermissionRepositoryImpl.parseGrantedPermissionKeys', () {
    test('returns empty set for empty rows', () {
      expect(PermissionRepositoryImpl.parseGrantedPermissionKeys([]), isEmpty);
    });

    test('ignores null, empty, and whitespace-only keys', () {
      final result = PermissionRepositoryImpl.parseGrantedPermissionKeys([
        {'permission_key': null},
        {'permission_key': ''},
        {'permission_key': '   '},
        {'permission_key': 'patients.view'},
      ]);

      expect(result, {'patients.view'});
    });

    test('deduplicates repeated keys', () {
      final result = PermissionRepositoryImpl.parseGrantedPermissionKeys([
        {'permission_key': 'ai.access'},
        {'permission_key': 'ai.access'},
      ]);

      expect(result, {'ai.access'});
    });

    test('trims surrounding whitespace on keys', () {
      final result = PermissionRepositoryImpl.parseGrantedPermissionKeys([
        {'permission_key': '  settings.manage_staff  '},
      ]);

      expect(result, {'settings.manage_staff'});
    });

    test('skips non-map rows (malformed API responses)', () {
      final result = PermissionRepositoryImpl.parseGrantedPermissionKeys([
        'not-a-map',
        42,
        {'permission_key': 'patients.view'},
      ]);

      expect(result, {'patients.view'});
    });

    test('skips rows missing permission_key field', () {
      final result = PermissionRepositoryImpl.parseGrantedPermissionKeys([
        {'role': 'administrator'},
        {'permission_key': 'patients.view'},
      ]);

      expect(result, {'patients.view'});
    });

    test('stringifies non-string permission_key values without throwing', () {
      final result = PermissionRepositoryImpl.parseGrantedPermissionKeys([
        {'permission_key': 42},
        {'permission_key': {'nested': 'map'}},
      ]);

      expect(result, contains('42'));
      expect(result.length, 2);
    });

    test('deduplicates a large row list', () {
      final rows = List.generate(
        500,
        (index) => {'permission_key': index.isEven ? 'patients.view' : 'ai.access'},
      );

      expect(
        PermissionRepositoryImpl.parseGrantedPermissionKeys(rows),
        {'patients.view', 'ai.access'},
      );
    });

    test('parses full owner seed sample from PostgREST shape', () {
      final rows = [
        {'permission_key': 'settings.manage_staff'},
        {'permission_key': 'patients.view'},
        {'permission_key': 'analytics.view'},
        {'permission_key': 'ai.access'},
      ];

      expect(PermissionRepositoryImpl.parseGrantedPermissionKeys(rows), {
        'settings.manage_staff',
        'patients.view',
        'analytics.view',
        'ai.access',
      });
    });
  });

  group('PermissionRepositoryImpl.loadGrantedPermissions', () {
    test('returns parsed grants for a role from realistic PostgREST rows', () async {
      final recorder = _RolesPermissionsQueryRecorder();
      final client = _RolesPermissionsTestClient(
        {
          'roles_permissions': [
            {
              'permission_key': 'patients.view',
              'role': 'lab_staff',
              'is_granted': true,
              'is_deleted': false,
            },
            {
              'permission_key': 'ai.access',
              'role': 'lab_staff',
              'is_granted': true,
              'is_deleted': false,
            },
            {
              'permission_key': 'patients.create',
              'role': 'lab_staff',
              'is_granted': false,
              'is_deleted': false,
            },
            {
              'permission_key': 'settings.manage_staff',
              'role': 'administrator',
              'is_granted': true,
              'is_deleted': false,
            },
          ],
        },
        recorder: recorder,
      );
      final repository = PermissionRepositoryImpl(client);

      final grants = await repository.loadGrantedPermissions(StaffRole.labStaff);

      expect(grants, {'patients.view', 'ai.access'});
      expect(recorder.table, 'roles_permissions');
      expect(recorder.selectColumns, 'permission_key');
      expect(recorder.filters, [
        const MapEntry('role', 'lab_staff'),
        const MapEntry('is_granted', true),
        const MapEntry('is_deleted', false),
      ]);
    });

    test('returns empty set when query returns zero rows', () async {
      final client = _RolesPermissionsTestClient({'roles_permissions': []});
      final repository = PermissionRepositoryImpl(client);

      final grants = await repository.loadGrantedPermissions(StaffRole.doctor);

      expect(grants, isEmpty);
    });

    test('skips malformed response rows end-to-end without throwing', () async {
      final client = _RolesPermissionsTestClient({
        'roles_permissions': [
          {
            'permission_key': 'patients.view',
            'role': 'receptionist',
            'is_granted': true,
            'is_deleted': false,
          },
          'not-a-map',
          {'role': 'receptionist', 'is_granted': true, 'is_deleted': false},
          {
            'permission_key': null,
            'role': 'receptionist',
            'is_granted': true,
            'is_deleted': false,
          },
        ],
      });
      final repository = PermissionRepositoryImpl(client);

      final grants = await repository.loadGrantedPermissions(StaffRole.receptionist);

      expect(grants, {'patients.view'});
    });

    test('rethrows PostgrestException instead of returning empty set', () async {
      final client = _RolesPermissionsTestClient(
        {},
        queryError: const PostgrestException(message: 'permission denied', code: '42501'),
      );
      final repository = PermissionRepositoryImpl(client);

      await expectLater(
        repository.loadGrantedPermissions(StaffRole.administrator),
        throwsA(isA<PostgrestException>()),
      );
    });

    test('rethrows generic Exception instead of returning empty set', () async {
      final client = _RolesPermissionsTestClient(
        {},
        queryError: Exception('network unavailable'),
      );
      final repository = PermissionRepositoryImpl(client);

      await expectLater(
        repository.loadGrantedPermissions(StaffRole.administrator),
        throwsA(isA<Exception>()),
      );
    });

    test('sends role.wireValue for every StaffRole', () async {
      for (final role in StaffRole.values) {
        final recorder = _RolesPermissionsQueryRecorder();
        final client = _RolesPermissionsTestClient(
          {
            'roles_permissions': [
              {
                'permission_key': 'patients.view',
                'role': role.wireValue,
                'is_granted': true,
                'is_deleted': false,
              },
            ],
          },
          recorder: recorder,
        );
        final repository = PermissionRepositoryImpl(client);

        await repository.loadGrantedPermissions(role);

        expect(
          recorder.filters.where((entry) => entry.key == 'role').map((entry) => entry.value),
          [role.wireValue],
        );
        expect(role.wireValue, isNot(contains(RegExp(r'[A-Z]'))));
      }
    });
  });

  test('PermissionRepositoryImpl satisfies PermissionRepository interface', () {
    PermissionRepository repository = PermissionRepositoryImpl(_RolesPermissionsTestClient({}));
    expect(repository, isA<PermissionRepository>());
  });

  test('permissionRepositoryProvider returns cached PermissionRepositoryImpl', () {
    final client = _RolesPermissionsTestClient({});
    final container = ProviderContainer(
      overrides: [supabaseClientProvider.overrideWithValue(client)],
    );
    addTearDown(container.dispose);

    final first = container.read(permissionRepositoryProvider);
    final second = container.read(permissionRepositoryProvider);

    expect(first, isA<PermissionRepository>());
    expect(first, isA<PermissionRepositoryImpl>());
    expect(identical(first, second), isTrue);
  });
}
