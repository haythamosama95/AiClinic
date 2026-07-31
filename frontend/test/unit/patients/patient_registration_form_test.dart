import 'package:ai_clinic/features/patients/domain/patient_gender.dart';
import 'package:ai_clinic/features/patients/domain/patient_marital_status.dart';
import 'package:ai_clinic/features/patients/presentation/models/patient_registration_form.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/patient_test_support.dart';

void main() {
  group('PatientFormErrors.empty', () {
    test('has no field errors', () {
      expect(PatientFormErrors.empty.hasErrors, isFalse);
      expect(PatientFormErrors.empty.fullName, isNull);
      expect(PatientFormErrors.empty.phone, isNull);
      expect(PatientFormErrors.empty.dateOfBirth, isNull);
      expect(PatientFormErrors.empty.gender, isNull);
      expect(PatientFormErrors.empty.maritalStatus, isNull);
      expect(PatientFormErrors.empty.notes, isNull);
      expect(PatientFormErrors.empty.form, isNull);
    });
  });

  group('PatientFormErrors.hasErrors', () {
    test('true when fullName is set', () {
      expect(const PatientFormErrors(fullName: 'x').hasErrors, isTrue);
    });

    test('true when phone is set', () {
      expect(const PatientFormErrors(phone: 'x').hasErrors, isTrue);
    });

    test('true when dateOfBirth is set', () {
      expect(const PatientFormErrors(dateOfBirth: 'x').hasErrors, isTrue);
    });

    test('true when gender is set', () {
      expect(const PatientFormErrors(gender: 'x').hasErrors, isTrue);
    });

    test('true when maritalStatus is set', () {
      expect(const PatientFormErrors(maritalStatus: 'x').hasErrors, isTrue);
    });

    test('true when notes is set', () {
      expect(const PatientFormErrors(notes: 'x').hasErrors, isTrue);
    });

    test('true when form is set', () {
      expect(const PatientFormErrors(form: 'x').hasErrors, isTrue);
    });
  });

  group('PatientFormErrors.copyWith', () {
    const seeded = PatientFormErrors(
      fullName: 'name',
      phone: 'phone',
      dateOfBirth: 'dob',
      gender: 'gender',
      maritalStatus: 'marital',
      notes: 'notes',
      form: 'form',
    );

    test('sets fullName then clears with clearFullName', () {
      expect(
        seeded.copyWith(fullName: 'new').copyWith(clearFullName: true).fullName,
        isNull,
      );
    });

    test('sets phone then clears with clearPhone', () {
      expect(
        seeded.copyWith(phone: 'new').copyWith(clearPhone: true).phone,
        isNull,
      );
    });

    test('sets dateOfBirth then clears with clearDateOfBirth', () {
      expect(
        seeded
            .copyWith(dateOfBirth: 'new')
            .copyWith(clearDateOfBirth: true)
            .dateOfBirth,
        isNull,
      );
    });

    test('sets gender then clears with clearGender', () {
      expect(
        seeded.copyWith(gender: 'new').copyWith(clearGender: true).gender,
        isNull,
      );
    });

    test('sets maritalStatus then clears with clearMaritalStatus', () {
      expect(
        seeded
            .copyWith(maritalStatus: 'new')
            .copyWith(clearMaritalStatus: true)
            .maritalStatus,
        isNull,
      );
    });

    test('sets notes then clears with clearNotes', () {
      expect(
        seeded.copyWith(notes: 'new').copyWith(clearNotes: true).notes,
        isNull,
      );
    });

    test('sets form then clears with clearForm', () {
      expect(
        seeded.copyWith(form: 'new').copyWith(clearForm: true).form,
        isNull,
      );
    });
  });

  group('PatientRegistrationForm.empty', () {
    test('starts with blank required strings and null optionals', () {
      expect(PatientRegistrationForm.empty.fullName, '');
      expect(PatientRegistrationForm.empty.phone, '');
      expect(PatientRegistrationForm.empty.dateOfBirth, isNull);
      expect(PatientRegistrationForm.empty.gender, isNull);
      expect(PatientRegistrationForm.empty.maritalStatus, isNull);
      expect(PatientRegistrationForm.empty.notes, '');
    });
  });

  group('PatientRegistrationForm.fromPatientDetail', () {
    test('maps every populated field from patient detail', () {
      final dob = DateTime.utc(1985, 7, 4);
      final detail = samplePatientDetail(
        fullName: 'Sara Ali',
        phone: '201005551234',
        dateOfBirth: dob,
        gender: PatientGender.female,
        notes: 'Allergic to penicillin',
      ).copyWith(maritalStatus: PatientMaritalStatus.married);

      final form = PatientRegistrationForm.fromPatientDetail(detail);

      expect(form.fullName, 'Sara Ali');
      expect(form.phone, '201005551234');
      expect(form.dateOfBirth, dob);
      expect(form.gender, PatientGender.female);
      expect(form.maritalStatus, PatientMaritalStatus.married);
      expect(form.notes, 'Allergic to penicillin');
    });

    test('maps null optional fields to empty strings or null', () {
      final detail = samplePatientDetail(
        phone: null,
        dateOfBirth: null,
        gender: null,
        notes: null,
      ).copyWith(maritalStatus: null);

      final form = PatientRegistrationForm.fromPatientDetail(detail);

      expect(form.phone, '');
      expect(form.dateOfBirth, isNull);
      expect(form.gender, isNull);
      expect(form.maritalStatus, isNull);
      expect(form.notes, '');
    });
  });

  group('PatientRegistrationForm.copyWith', () {
    final seeded = PatientRegistrationForm(
      fullName: 'Sara Ali',
      phone: '201005551234',
      dateOfBirth: DateTime.utc(1990, 1, 15),
      gender: PatientGender.female,
      maritalStatus: PatientMaritalStatus.single,
      notes: 'Notes',
    );

    test('preserves dateOfBirth when omitted', () {
      expect(seeded.copyWith(fullName: 'x').dateOfBirth, seeded.dateOfBirth);
    });

    test('clears dateOfBirth when explicitly set to null', () {
      expect(seeded.copyWith(dateOfBirth: null).dateOfBirth, isNull);
    });

    test('preserves gender when omitted', () {
      expect(seeded.copyWith(fullName: 'x').gender, PatientGender.female);
    });

    test('clears gender when explicitly set to null', () {
      expect(seeded.copyWith(gender: null).gender, isNull);
    });

    test('preserves maritalStatus when omitted', () {
      expect(
        seeded.copyWith(fullName: 'x').maritalStatus,
        PatientMaritalStatus.single,
      );
    });

    test('clears maritalStatus when explicitly set to null', () {
      expect(seeded.copyWith(maritalStatus: null).maritalStatus, isNull);
    });

    test('updates fullName and phone', () {
      final updated = seeded.copyWith(fullName: 'New Name', phone: '12345678');

      expect(updated.fullName, 'New Name');
      expect(updated.phone, '12345678');
    });

    test('updates notes', () {
      expect(seeded.copyWith(notes: 'Updated').notes, 'Updated');
    });
  });

  group('validateRegistration', () {
    test('empty name reports required message', () {
      final errors = validateRegistration(const PatientRegistrationForm());

      expect(errors.fullName, "Enter the patient's full name.");
      expect(errors.phone, 'Mobile number is required.');
      expect(errors.hasErrors, isTrue);
    });

    test('whitespace-only name reports required message', () {
      final errors = validateRegistration(
        const PatientRegistrationForm(fullName: '   '),
      );

      expect(errors.fullName, "Enter the patient's full name.");
    });

    test('one-character name reports minimum length message', () {
      final errors = validateRegistration(
        const PatientRegistrationForm(fullName: 'A'),
      );

      expect(errors.fullName, 'Full name must be at least 2 characters.');
    });

    test('valid name with valid phone produces no errors', () {
      final errors = validateRegistration(
        const PatientRegistrationForm(
          fullName: 'Sara Ali',
          phone: '201005551234',
        ),
      );

      expect(errors.fullName, isNull);
      expect(errors.phone, isNull);
      expect(errors.hasErrors, isFalse);
    });

    test('non-numeric phone reports digits-only message', () {
      final errors = validateRegistration(
        const PatientRegistrationForm(
          fullName: 'Sara Ali',
          phone: '20abc12345',
        ),
      );

      expect(errors.fullName, isNull);
      expect(errors.phone, 'Only numbers are allowed.');
    });

    test('short phone reports length message', () {
      final errors = validateRegistration(
        const PatientRegistrationForm(
          fullName: 'Sara Ali',
          phone: '1234567',
        ),
      );

      expect(errors.phone, 'Mobile number must be 8 to 15 digits.');
    });

    test('multiple simultaneous field errors are returned together', () {
      final errors = validateRegistration(
        const PatientRegistrationForm(fullName: 'A', phone: 'abc'),
      );

      expect(errors.fullName, 'Full name must be at least 2 characters.');
      expect(errors.phone, 'Only numbers are allowed.');
      expect(errors.hasErrors, isTrue);
    });
  });
}
