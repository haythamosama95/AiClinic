import 'package:ai_clinic/features/patients/domain/patient_gender.dart';
import 'package:ai_clinic/features/patients/presentation/utils/patient_presentation_formatting.dart';
import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final fixedNow = DateTime(2026, 6, 13);

  group('PatientPresentationFormatting.formatCalendarDate', () {
    test('formats calendar date without time component', () {
      final value = DateTime(2026, 3, 15, 23, 59);

      expect(
        PatientPresentationFormatting.formatCalendarDate(value),
        PatientPresentationFormatting.date.format(DateTime(2026, 3, 15)),
      );
    });
  });

  group('PatientPresentationFormatting.displayId', () {
    test('truncates ids longer than eight characters', () {
      expect(
        PatientPresentationFormatting.displayId('abcdefgh-ijkl'),
        'ABCDEFGH',
      );
    });

    test('uppercases short ids without truncation', () {
      expect(PatientPresentationFormatting.displayId('p1'), 'P1');
    });
  });

  group('PatientPresentationFormatting.ageYears', () {
    test('returns age for a normal birth date', () {
      withClock(Clock.fixed(fixedNow), () {
        expect(
          PatientPresentationFormatting.ageYears(DateTime(1990, 5, 15)),
          36,
        );
      });
    });

    test('returns null when date of birth is null', () {
      withClock(Clock.fixed(fixedNow), () {
        expect(PatientPresentationFormatting.ageYears(null), isNull);
      });
    });

    test('does not round up before birthday this year', () {
      withClock(Clock.fixed(fixedNow), () {
        expect(
          PatientPresentationFormatting.ageYears(DateTime(1990, 12, 31)),
          35,
        );
      });
    });

    test('includes birthday on the exact date', () {
      withClock(Clock.fixed(fixedNow), () {
        expect(
          PatientPresentationFormatting.ageYears(DateTime(1990, 6, 13)),
          36,
        );
      });
    });

    test('returns null for a future date of birth', () {
      withClock(Clock.fixed(fixedNow), () {
        expect(
          PatientPresentationFormatting.ageYears(DateTime(2027, 1, 1)),
          isNull,
        );
      });
    });

    test('handles leap-day birthdates on non-leap reference years', () {
      withClock(Clock.fixed(fixedNow), () {
        expect(
          PatientPresentationFormatting.ageYears(DateTime(2000, 2, 29)),
          26,
        );
      });
    });
  });

  group('PatientPresentationFormatting.ageGenderLabel', () {
    test('shows age and gender when both are available', () {
      expect(
        PatientPresentationFormatting.ageGenderLabel(
          age: 36,
          gender: PatientGender.female,
        ),
        '36, Female',
      );
    });

    test('shows gender only when age is null', () {
      expect(
        PatientPresentationFormatting.ageGenderLabel(
          gender: PatientGender.male,
        ),
        'Male',
      );
    });

    test('shows age only when gender is null', () {
      expect(
        PatientPresentationFormatting.ageGenderLabel(age: 36),
        '36',
      );
    });

    test('shows em dash when both are null', () {
      expect(
        PatientPresentationFormatting.ageGenderLabel(),
        '—',
      );
    });
  });

  group('PatientPresentationFormatting.dateOfBirthLabel', () {
    test('returns em dash when date of birth is null', () {
      expect(PatientPresentationFormatting.dateOfBirthLabel(null), '—');
    });

    test('includes formatted date and age when age is available', () {
      withClock(Clock.fixed(fixedNow), () {
        final dob = DateTime(1990, 6, 13);
        final formatted = PatientPresentationFormatting.formatCalendarDate(dob);

        expect(
          PatientPresentationFormatting.dateOfBirthLabel(dob),
          '$formatted (36 yrs)',
        );
      });
    });

    test('shows formatted date only when age cannot be computed', () {
      withClock(Clock.fixed(fixedNow), () {
        final dob = DateTime(2027, 1, 1);
        final formatted = PatientPresentationFormatting.formatCalendarDate(dob);

        expect(
          PatientPresentationFormatting.dateOfBirthLabel(dob),
          formatted,
        );
      });
    });
  });

  group('PatientPresentationFormatting.orDash', () {
    test('returns em dash for null', () {
      expect(PatientPresentationFormatting.orDash(null), '—');
    });

    test('returns em dash for empty string', () {
      expect(PatientPresentationFormatting.orDash(''), '—');
    });

    test('returns em dash for whitespace-only string', () {
      expect(PatientPresentationFormatting.orDash('   '), '—');
    });

    test('returns value when non-empty after trim', () {
      expect(PatientPresentationFormatting.orDash('  Main  '), '  Main  ');
    });
  });

  group('PatientPresentationFormatting.formatFileSize', () {
    test('formats zero bytes', () {
      expect(PatientPresentationFormatting.formatFileSize(0), '0 B');
    });

    test('formats sub-kilobyte sizes in bytes', () {
      expect(PatientPresentationFormatting.formatFileSize(512), '512 B');
    });

    test('formats exactly 1024 bytes as one kilobyte', () {
      expect(PatientPresentationFormatting.formatFileSize(1024), '1.0 KB');
    });

    test('formats kilobyte range with one decimal', () {
      expect(PatientPresentationFormatting.formatFileSize(1536), '1.5 KB');
    });

    test('formats exactly one megabyte', () {
      expect(
        PatientPresentationFormatting.formatFileSize(1024 * 1024),
        '1.0 MB',
      );
    });

    test('formats megabyte range with one decimal', () {
      expect(
        PatientPresentationFormatting.formatFileSize(1024 * 1024 + 512 * 1024),
        '1.5 MB',
      );
    });
  });
}
