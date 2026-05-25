import 'package:ai_clinic/features/auth/data/permission_repository.dart';
import 'package:flutter_test/flutter_test.dart';

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
}
