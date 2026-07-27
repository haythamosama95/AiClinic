import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/patients/application/patient_rpc_messages.dart';
import 'package:ai_clinic/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

RpcFailure _failure({required String code, String message = 'backend message'}) {
  return RpcFailure(RpcResult(success: false, errorCode: code, errorMessage: message));
}

void main() {
  late AppLocalizations l10n;

  setUp(() {
    l10n = lookupAppLocalizations(const Locale('en'));
  });

  group('patientMessageForRpc', () {
    test('NOT_FOUND returns access-denied-style message', () {
      expect(
        patientMessageForRpc(_failure(code: 'NOT_FOUND'), l10n),
        l10n.patientRpcNotFound,
      );
    });

    test('DUPLICATE_WARNING returns review message', () {
      expect(
        patientMessageForRpc(_failure(code: 'DUPLICATE_WARNING'), l10n),
        l10n.patientRpcDuplicateWarning,
      );
    });

    test('STALE_PATIENT returns reload message', () {
      expect(
        patientMessageForRpc(_failure(code: 'STALE_PATIENT'), l10n),
        l10n.patientRpcStalePatient,
      );
    });

    test('PATIENT_ARCHIVED returns archived message', () {
      expect(
        patientMessageForRpc(_failure(code: 'PATIENT_ARCHIVED'), l10n),
        l10n.patientRpcPatientArchived,
      );
    });

    test('FORBIDDEN returns permission message', () {
      expect(
        patientMessageForRpc(_failure(code: 'FORBIDDEN'), l10n),
        l10n.patientRpcForbidden,
      );
    });

    test('BRANCH_REQUIRED returns branch selection message', () {
      expect(
        patientMessageForRpc(_failure(code: 'BRANCH_REQUIRED'), l10n),
        l10n.patientRpcBranchRequired,
      );
    });

    test('INVALID_INPUT passes through backend message', () {
      expect(
        patientMessageForRpc(_failure(code: 'INVALID_INPUT', message: 'Phone too short'), l10n),
        'Phone too short',
      );
    });

    test('unknown code falls through to backend message', () {
      expect(
        patientMessageForRpc(_failure(code: 'UNEXPECTED_ERROR', message: 'Something broke'), l10n),
        'Something broke',
      );
    });

    test('unknown code with default RpcFailure message', () {
      final failure = RpcFailure(const RpcResult(success: false));
      expect(patientMessageForRpc(failure, l10n), l10n.patientRpcDefaultError);
    });

    test('all known codes produce non-empty strings', () {
      const knownCodes = [
        'NOT_FOUND',
        'DUPLICATE_WARNING',
        'STALE_PATIENT',
        'PATIENT_ARCHIVED',
        'FORBIDDEN',
        'BRANCH_REQUIRED',
        'INVALID_INPUT',
      ];

      for (final code in knownCodes) {
        final message = patientMessageForRpc(_failure(code: code), l10n);
        expect(message, isNotEmpty, reason: 'code=$code should produce non-empty message');
      }
    });
  });
}
