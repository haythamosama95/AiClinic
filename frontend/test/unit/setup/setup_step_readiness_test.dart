import 'package:ai_clinic/features/setup/domain/bootstrap_field_options.dart';
import 'package:ai_clinic/features/setup/domain/setup_step_readiness.dart';
import 'package:ai_clinic/features/settings/domain/branch_working_schedule.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('isOrganizationStepReady', () {
    test('returns true when name and defaults are valid', () {
      expect(
        isOrganizationStepReady(
          name: 'Sunrise Clinic',
          currency: BootstrapCurrencyOptions.defaultCode,
          timezone: BootstrapTimezoneOptions.defaultZone,
        ),
        isTrue,
      );
    });

    test('returns false when name is empty or whitespace', () {
      expect(
        isOrganizationStepReady(
          name: '   ',
          currency: BootstrapCurrencyOptions.defaultCode,
          timezone: BootstrapTimezoneOptions.defaultZone,
        ),
        isFalse,
      );
    });

    test('returns false when currency is null or invalid', () {
      expect(
        isOrganizationStepReady(name: 'Clinic', currency: null, timezone: BootstrapTimezoneOptions.defaultZone),
        isFalse,
      );
      expect(
        isOrganizationStepReady(name: 'Clinic', currency: 'NOTREAL', timezone: BootstrapTimezoneOptions.defaultZone),
        isFalse,
      );
    });

    test('returns false when timezone is null or invalid', () {
      expect(
        isOrganizationStepReady(name: 'Clinic', currency: BootstrapCurrencyOptions.defaultCode, timezone: null),
        isFalse,
      );
      expect(
        isOrganizationStepReady(
          name: 'Clinic',
          currency: BootstrapCurrencyOptions.defaultCode,
          timezone: 'Invalid/Zone',
        ),
        isFalse,
      );
    });

    test('accepts lowercase timezone matching a known zone', () {
      expect(
        isOrganizationStepReady(
          name: 'Clinic',
          currency: BootstrapCurrencyOptions.defaultCode,
          timezone: 'africa/cairo',
        ),
        isTrue,
      );
    });
  });

  group('isBranchStepFieldsReady', () {
    const validBranch = (
      name: 'Main',
      code: 'MAIN',
      address: '123 Street',
      phone: '201000000000',
      mapsUrl: 'https://maps.example.com/main',
    );

    test('returns true when text fields are valid regardless of working hours', () {
      expect(
        isBranchStepFieldsReady(
          name: validBranch.name,
          code: validBranch.code,
          address: validBranch.address,
          phone: validBranch.phone,
          mapsUrl: validBranch.mapsUrl,
        ),
        isTrue,
      );
    });
  });

  group('isBranchStepReady', () {
    const validBranch = (
      name: 'Main',
      code: 'MAIN',
      address: '123 Street',
      phone: '201000000000',
      mapsUrl: 'https://maps.example.com/main',
    );
    final configuredSchedule = BranchWorkingSchedule.defaultSchedule();

    test('returns true when all mandatory branch fields are valid', () {
      expect(
        isBranchStepReady(
          name: validBranch.name,
          code: validBranch.code,
          address: validBranch.address,
          phone: validBranch.phone,
          mapsUrl: validBranch.mapsUrl,
          workingSchedule: configuredSchedule,
        ),
        isTrue,
      );
    });

    test('returns false when working hours are not configured', () {
      expect(
        isBranchStepReady(
          name: validBranch.name,
          code: validBranch.code,
          address: validBranch.address,
          phone: validBranch.phone,
          mapsUrl: validBranch.mapsUrl,
          workingSchedule: BranchWorkingSchedule.emptySchedule(),
        ),
        isFalse,
      );
    });

    test('returns false when name is empty', () {
      expect(
        isBranchStepReady(
          name: '',
          code: validBranch.code,
          address: validBranch.address,
          phone: validBranch.phone,
          mapsUrl: validBranch.mapsUrl,
          workingSchedule: configuredSchedule,
        ),
        isFalse,
      );
    });

    test('returns false when code is empty', () {
      expect(
        isBranchStepReady(
          name: validBranch.name,
          code: '',
          address: validBranch.address,
          phone: validBranch.phone,
          mapsUrl: validBranch.mapsUrl,
          workingSchedule: configuredSchedule,
        ),
        isFalse,
      );
    });

    test('returns false when address is empty', () {
      expect(
        isBranchStepReady(
          name: validBranch.name,
          code: validBranch.code,
          address: '',
          phone: validBranch.phone,
          mapsUrl: validBranch.mapsUrl,
          workingSchedule: configuredSchedule,
        ),
        isFalse,
      );
    });

    test('returns false when phone or maps URL fails validation', () {
      expect(
        isBranchStepReady(
          name: validBranch.name,
          code: validBranch.code,
          address: validBranch.address,
          phone: '+20 100 000 0000',
          mapsUrl: validBranch.mapsUrl,
          workingSchedule: configuredSchedule,
        ),
        isFalse,
      );
      expect(
        isBranchStepReady(
          name: validBranch.name,
          code: validBranch.code,
          address: validBranch.address,
          phone: validBranch.phone,
          mapsUrl: 'not a url',
          workingSchedule: configuredSchedule,
        ),
        isFalse,
      );
    });
  });
}
