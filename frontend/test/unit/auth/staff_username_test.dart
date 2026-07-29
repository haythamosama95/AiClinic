import 'package:ai_clinic/features/auth/domain/staff_username.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('staffUsernameRequirements', () {
    test('is a non-empty user-facing requirements string', () {
      expect(staffUsernameRequirements, isNotEmpty);
      expect(
        staffUsernameRequirements,
        '3–32 characters. Letters, numbers, underscore, and hyphen. Must start and end with a letter or number.',
      );
    });
  });

  group('normalizeStaffUsername', () {
    test('trims leading and trailing whitespace', () {
      expect(normalizeStaffUsername('  alice  '), 'alice');
    });

    test('lowercases mixed-case input', () {
      expect(normalizeStaffUsername('Alice'), 'alice');
      expect(normalizeStaffUsername('STAFF-1'), 'staff-1');
    });

    test('returns already-normalized input unchanged', () {
      expect(normalizeStaffUsername('staff_1'), 'staff_1');
    });

    test('returns empty string for empty input', () {
      expect(normalizeStaffUsername(''), '');
    });

    test('returns empty string for whitespace-only input', () {
      expect(normalizeStaffUsername('   '), '');
      expect(normalizeStaffUsername('\t\n'), '');
    });

    test('preserves internal whitespace (only outer trim is applied)', () {
      expect(normalizeStaffUsername('  ab c  '), 'ab c');
    });

    test('treats tabs and newlines as trimmable outer whitespace', () {
      expect(normalizeStaffUsername('\tstaff\n'), 'staff');
    });

    test('does not throw for unicode input', () {
      expect(() => normalizeStaffUsername('ábc'), returnsNormally);
      expect(normalizeStaffUsername('ábc'), 'ábc');
    });
  });

  group('validateStaffUsername required path', () {
    test('rejects empty string with required message', () {
      expect(validateStaffUsername(''), 'Username is required.');
    });

    test('rejects whitespace-only string with required message', () {
      expect(validateStaffUsername('   '), 'Username is required.');
    });

    test('rejects tab-newline-only string with required message', () {
      expect(validateStaffUsername('\t\n'), 'Username is required.');
    });
  });

  group('validateStaffUsername rejects @', () {
    test('rejects user@clinic even when otherwise valid length', () {
      expect(validateStaffUsername('user@clinic'), 'Enter a valid username.');
    });

    test('rejects @user', () {
      expect(validateStaffUsername('@user'), 'Enter a valid username.');
    });

    test('rejects user@', () {
      expect(validateStaffUsername('user@'), 'Enter a valid username.');
    });
  });

  group('validateStaffUsername length boundaries', () {
    test('rejects length 2 after normalization', () {
      final twoChars = 'a' * 2;
      expect(twoChars.length, 2);
      expect(validateStaffUsername(twoChars), 'Enter a valid username.');
    });

    test('accepts length 3 after normalization', () {
      final threeChars = 'a' * 3;
      expect(threeChars.length, 3);
      expect(validateStaffUsername(threeChars), isNull);
    });

    test('accepts length 32 after normalization', () {
      final thirtyTwoChars = 'a' * 32;
      expect(thirtyTwoChars.length, 32);
      expect(validateStaffUsername(thirtyTwoChars), isNull);
    });

    test('rejects length 33 after normalization', () {
      final thirtyThreeChars = 'a' * 33;
      expect(thirtyThreeChars.length, 33);
      expect(validateStaffUsername(thirtyThreeChars), 'Enter a valid username.');
    });

    test('measures length after normalization so padded valid usernames pass', () {
      expect(validateStaffUsername('  abc  '), isNull);
    });
  });

  group('validateStaffUsername pattern rules', () {
    test('rejects leading underscore', () {
      expect(validateStaffUsername('_user'), 'Username may use letters, numbers, underscore, and hyphen.');
    });

    test('rejects trailing underscore', () {
      expect(validateStaffUsername('user_'), 'Username may use letters, numbers, underscore, and hyphen.');
    });

    test('rejects leading hyphen', () {
      expect(validateStaffUsername('-user'), 'Username may use letters, numbers, underscore, and hyphen.');
    });

    test('rejects trailing hyphen', () {
      expect(validateStaffUsername('user-'), 'Username may use letters, numbers, underscore, and hyphen.');
    });

    test('accepts internal underscore and hyphen', () {
      expect(validateStaffUsername('a_b-c1'), isNull);
      expect(validateStaffUsername('a-b'), isNull);
      expect(validateStaffUsername('a_b'), isNull);
    });

    test('accepts all-digit usernames at minimum length', () {
      expect(validateStaffUsername('123'), isNull);
    });

    test('accepts three-character minimum valid combinations', () {
      expect(validateStaffUsername('a1b'), isNull);
      expect(validateStaffUsername('1a2'), isNull);
      expect(validateStaffUsername('a_b'), isNull);
    });
  });

  group('validateStaffUsername rejects disallowed characters', () {
    test('rejects internal spaces', () {
      expect(validateStaffUsername('ab c'), 'Username may use letters, numbers, underscore, and hyphen.');
    });

    test('rejects dots', () {
      expect(validateStaffUsername('a.b'), 'Username may use letters, numbers, underscore, and hyphen.');
    });

    test('rejects plus sign', () {
      expect(validateStaffUsername('a+b'), 'Username may use letters, numbers, underscore, and hyphen.');
    });

    test('rejects slash', () {
      expect(validateStaffUsername('a/b'), 'Username may use letters, numbers, underscore, and hyphen.');
    });

    test('rejects unicode letters outside allowed class', () {
      expect(validateStaffUsername('ábc'), 'Username may use letters, numbers, underscore, and hyphen.');
    });

    test('rejects emoji', () {
      expect(validateStaffUsername('ab😀'), 'Username may use letters, numbers, underscore, and hyphen.');
    });
  });

  group('validateStaffUsername case insensitivity', () {
    test('accepts uppercase input that is valid when lowercased', () {
      expect(validateStaffUsername('Staff1'), isNull);
    });

    test('accepts padded mixed-case input that is valid when normalized', () {
      expect(validateStaffUsername(' STAFF-1 '), isNull);
    });
  });

  group('validateStaffUsername error message categories', () {
    test('required message is distinct from validity and pattern messages', () {
      const required = 'Username is required.';
      const validity = 'Enter a valid username.';
      const pattern = 'Username may use letters, numbers, underscore, and hyphen.';

      expect(required, isNot(equals(validity)));
      expect(required, isNot(equals(pattern)));
      expect(validity, isNot(equals(pattern)));

      expect(validateStaffUsername(''), required);
      expect(validateStaffUsername('ab'), validity);
      expect(validateStaffUsername('_ab'), pattern);
    });
  });
}
