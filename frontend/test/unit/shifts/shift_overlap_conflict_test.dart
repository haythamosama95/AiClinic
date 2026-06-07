import 'package:ai_clinic/features/shifts/domain/shift_overlap_conflict.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ShiftOverlapConflict.parseFromRpc (#8)', () {
    test('reads conflicts from PostgREST details channel', () {
      const details =
          '[{"staff_member_id":"11111111-1111-4111-8111-111111111111","display_name":"Detail Channel","conflicting_shift_id":"22222222-2222-4222-8222-222222222222","start_time":"08:00","end_time":"09:00"}]';

      final conflicts = ShiftOverlapConflict.parseFromRpc(message: 'shift_overlap', details: details);

      expect(conflicts, hasLength(1));
      expect(conflicts.first.displayName, 'Detail Channel');
    });

    test('falls back to legacy message payload when details are absent', () {
      const message =
          'shift_overlap: [{"staff_member_id":"11111111-1111-4111-8111-111111111111","display_name":"Legacy","conflicting_shift_id":"22222222-2222-4222-8222-222222222222","start_time":"08:00","end_time":"09:00"}]';

      final conflicts = ShiftOverlapConflict.parseFromRpc(message: message);

      expect(conflicts, hasLength(1));
      expect(conflicts.first.displayName, 'Legacy');
    });
  });
}
