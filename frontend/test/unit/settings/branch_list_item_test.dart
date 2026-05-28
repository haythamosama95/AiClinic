import 'package:ai_clinic/features/settings/domain/branch_list_item.dart';
import 'package:ai_clinic/features/settings/domain/branch_working_schedule.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BranchListItem.fromRow', () {
    test('parses active branch with optional fields', () {
      final item = BranchListItem.fromRow({
        'id': 'branch-1',
        'name': 'Main',
        'code': ' MAIN ',
        'is_active': true,
        'address': 'Street 1',
        'phone': '+20 100',
        'maps_url': 'https://maps.example',
      });

      expect(item, isNotNull);
      expect(item!.isActive, isTrue);
      expect(item.code, 'MAIN');
      expect(item.mapsUrl, 'https://maps.example');
    });

    test('returns null without id or name', () {
      expect(BranchListItem.fromRow({'id': '', 'name': 'X'}), isNull);
      expect(BranchListItem.fromRow({'id': 'x', 'name': '  '}), isNull);
    });

    test('parses is_active from string and int representations', () {
      expect(BranchListItem.fromRow({'id': '1', 'name': 'A', 'is_active': 'true'})!.isActive, isTrue);
      expect(BranchListItem.fromRow({'id': '1', 'name': 'A', 'is_active': 'false'})!.isActive, isFalse);
      expect(BranchListItem.fromRow({'id': '1', 'name': 'A', 'is_active': '1'})!.isActive, isTrue);
      expect(BranchListItem.fromRow({'id': '1', 'name': 'A', 'is_active': null})!.isActive, isFalse);
    });

    test('strips blank optional strings', () {
      final item = BranchListItem.fromRow({'id': '1', 'name': 'A', 'is_active': true, 'code': '', 'phone': '  '});

      expect(item!.code, isNull);
      expect(item.phone, isNull);
    });

    test('parses nested working_schedule maps from supabase rows', () {
      final item = BranchListItem.fromRow({
        'id': '1',
        'name': 'A',
        'is_active': true,
        'working_schedule': <String, Object?>{
          'days': [
            <String, Object?>{
              'day': 'monday',
              'is_working_day': true,
              'open_time': '09:00:00',
              'close_time': '17:00:00',
            },
          ],
        },
      });

      expect(item, isNotNull);
      expect(item!.workingSchedule, isA<BranchWorkingSchedule>());
      final monday = item.workingSchedule!.days.firstWhere((day) => day.day.name == 'monday');
      expect(monday.openTime, '09:00:00');
      expect(monday.isWorkingDay, isTrue);
    });
  });

  group('BranchListItem.normalizeCode', () {
    test('lowercases and trims code for uniqueness checks', () {
      expect(BranchListItem.normalizeCode('  AbC '), 'abc');
    });

    test('returns null for empty or whitespace code', () {
      expect(BranchListItem.normalizeCode(null), isNull);
      expect(BranchListItem.normalizeCode(''), isNull);
      expect(BranchListItem.normalizeCode('   '), isNull);
    });
  });

  group('BranchListItem equality', () {
    test('copyWith and == respect isActive flag', () {
      const active = BranchListItem(id: '1', name: 'A', isActive: true);
      final inactive = active.copyWith(isActive: false);

      expect(active == inactive, isFalse);
      expect(inactive.isActive, isFalse);
    });
  });
}
