import 'package:ai_clinic/features/shifts/domain/shift_overlap_conflict.dart';
import 'package:ai_clinic/features/shifts/presentation/widgets/shift_conflict_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ShiftConflictBanner', () {
    testWidgets('renders staff name and conflicting time range', (tester) async {
      const conflicts = [
        ShiftOverlapConflict(
          staffMemberId: '11111111-1111-4111-8111-111111111111',
          displayName: 'Dr Ahmed',
          conflictingShiftId: '22222222-2222-4222-8222-222222222222',
          startTime: '09:00',
          endTime: '17:00',
        ),
      ];

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: ShiftConflictBanner(conflicts: conflicts)),
        ),
      );

      expect(find.byKey(const Key('shift_conflict_banner')), findsOneWidget);
      expect(find.textContaining('Dr Ahmed'), findsOneWidget);
      expect(find.textContaining('09:00–17:00'), findsOneWidget);
    });

    test('formatMessage falls back when conflicts list is empty', () {
      expect(
        ShiftConflictBanner.formatMessage(const []),
        'One or more staff members already have an overlapping shift at this branch.',
      );
    });

    test('formatMessage joins multiple conflicts', () {
      const conflicts = [
        ShiftOverlapConflict(
          staffMemberId: '11111111-1111-4111-8111-111111111111',
          displayName: 'Dr Ahmed',
          conflictingShiftId: '22222222-2222-4222-8222-222222222222',
          startTime: '09:00',
          endTime: '12:00',
        ),
        ShiftOverlapConflict(
          staffMemberId: '33333333-3333-4333-8333-333333333333',
          displayName: 'Nurse Sam',
          conflictingShiftId: '44444444-4444-4444-8444-444444444444',
          startTime: '13:00',
          endTime: '17:00',
        ),
      ];

      final message = ShiftConflictBanner.formatMessage(conflicts);

      expect(message, contains('Dr Ahmed'));
      expect(message, contains('Nurse Sam'));
    });
  });
}
