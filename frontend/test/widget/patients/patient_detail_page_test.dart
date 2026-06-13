import 'dart:async';

import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/ui/theme/app_theme.dart';
import 'package:ai_clinic/core/ui/theme/variants/app_theme_variant.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/patients/domain/create_patient_input.dart';
import 'package:ai_clinic/features/patients/domain/duplicate_candidate.dart';
import 'package:ai_clinic/features/patients/domain/patient_list_scope.dart';
import 'package:ai_clinic/features/patients/domain/patient_search_page.dart';
import 'package:ai_clinic/features/patients/domain/update_patient_input.dart';
import 'package:ai_clinic/core/ui/theme/forui_app_scope.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/patients/domain/patient_detail.dart';
import 'package:ai_clinic/features/patients/domain/patient_gender.dart';
import 'package:ai_clinic/features/patients/domain/patient_list_item.dart';
import 'package:ai_clinic/features/patients/domain/patient_marital_status.dart';
import 'package:ai_clinic/features/patients/domain/repositories/patient_repository.dart';
import 'package:ai_clinic/features/patients/domain/usecases/get_patient.dart';
import 'package:ai_clinic/features/patients/domain/usecases/patient_use_case_providers.dart';
import 'package:ai_clinic/features/patients/presentation/pages/patient_detail_page.dart';
import 'package:ai_clinic/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/auth_test_support.dart';

void main() {
  const patientId = '11111111-1111-4111-8111-111111111111';

  final sampleDetail = PatientDetail(
    id: patientId,
    fullName: 'Sara Ali',
    phone: '201111111111',
    dateOfBirth: DateTime.utc(1985, 3, 20),
    gender: PatientGender.female,
    maritalStatus: PatientMaritalStatus.married,
    notes: 'Allergic to penicillin',
    branchId: 'b1',
    branchName: 'Main',
    createdAt: DateTime.utc(2026, 1, 1, 8),
    updatedAt: DateTime.utc(2026, 1, 2, 9, 30),
    createdByDisplay: 'Reception',
  );

  group('PatientDetailPage', () {
    testWidgets('shows preview header then full profile when loaded', (tester) async {
      final completer = Completer<PatientDetail>();
      final preview = PatientListItem(
        id: patientId,
        fullName: 'Sara Ali',
        phone: '201111111111',
        dateOfBirth: DateTime.utc(1985, 3, 20),
        gender: PatientGender.female,
        registeringBranchId: 'b1',
        registeringBranchName: 'Main',
      );

      await tester.pumpWidget(_host(getPatient: (_) => completer.future, preview: preview));
      await tester.pump();

      expect(find.text('Sara Ali'), findsOneWidget);
      expect(find.byType(AppFullPageLoading), findsNothing);
      expect(find.text('Loading patient…'), findsNothing);
      expect(find.text('Allergic to penicillin'), findsNothing);

      completer.complete(sampleDetail);
      await tester.pumpAndSettle();

      expect(find.text('Allergic to penicillin'), findsOneWidget);
      expect(find.text('Married'), findsOneWidget);
      expect(find.text('Reception'), findsOneWidget);
    });

    testWidgets('shows deferred spinner only when loading is slow', (tester) async {
      final completer = Completer<PatientDetail>();

      await tester.pumpWidget(_host(getPatient: (_) => completer.future));
      await tester.pump();

      expect(find.text('Loading patient…'), findsNothing);

      await tester.pump(const Duration(milliseconds: 250));
      await tester.pump();

      expect(find.text('Loading patient…'), findsOneWidget);
    });

    testWidgets('shows error with retry and re-invokes get patient', (tester) async {
      var attempts = 0;

      await tester.pumpWidget(
        _host(
          getPatient: (_) async {
            attempts++;
            if (attempts == 1) {
              throw StateError('Network error');
            }
            return sampleDetail;
          },
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Unable to load patient details'), findsOneWidget);
      expect(find.textContaining('Network error'), findsOneWidget);
      expect(attempts, 1);

      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(attempts, 2);
      expect(find.text('Allergic to penicillin'), findsOneWidget);
    });

    testWidgets('back button pops the page', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authSessionProvider.overrideWith(_PatientsAuthNotifier.new),
            getPatientUseCaseProvider.overrideWith(
              (ref) => GetPatient(_FakePatientRepository((_) async => sampleDetail)),
            ),
          ],
          child: ForuiAppScope(
            child: MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              theme: AppTheme.light(AppThemeVariant.clinic),
              home: Scaffold(
                body: Center(
                  child: Builder(
                    builder: (context) {
                      return FilledButton(
                        onPressed: () {
                          Navigator.of(
                            context,
                          ).push(MaterialPageRoute<void>(builder: (_) => PatientDetailPage(patientId: patientId)));
                        },
                        child: const Text('Open detail'),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open detail'));
      await tester.pumpAndSettle();

      expect(find.text('Patient detail'), findsOneWidget);

      await tester.tap(find.byTooltip('Back to patients'));
      await tester.pumpAndSettle();

      expect(find.text('Open detail'), findsOneWidget);
    });
  });
}

Widget _host({required Future<PatientDetail> Function(String patientId) getPatient, PatientListItem? preview}) {
  return ProviderScope(
    overrides: [
      authSessionProvider.overrideWith(_PatientsAuthNotifier.new),
      getPatientUseCaseProvider.overrideWith((ref) => GetPatient(_FakePatientRepository(getPatient))),
    ],
    child: ForuiAppScope(
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: AppTheme.light(AppThemeVariant.clinic),
        home: PatientDetailPage(patientId: '11111111-1111-4111-8111-111111111111', preview: preview),
      ),
    ),
  );
}

class _PatientsAuthNotifier extends TestAuthSessionNotifier {
  @override
  AuthSessionState build() {
    return AuthSessionState(
      status: AuthSessionStatus.authenticated,
      context: sampleAuthSessionContext(permissions: const {'patients.view'}),
    );
  }
}

class _FakePatientRepository implements PatientRepository {
  _FakePatientRepository(this._getPatient);

  final Future<PatientDetail> Function(String patientId) _getPatient;

  @override
  Future<PatientDetail> getPatient(String patientId) => _getPatient(patientId);

  @override
  Future<void> archivePatient(String patientId) => throw UnimplementedError();

  @override
  Future<List<DuplicateCandidate>> checkDuplicates({
    String? fullName,
    String? phone,
    DateTime? dateOfBirth,
    String? excludePatientId,
  }) => throw UnimplementedError();

  @override
  Future<String> createPatient(CreatePatientInput input) => throw UnimplementedError();

  @override
  Future<PatientSearchPage> searchPatients({
    String? query,
    required PatientListScope scope,
    String? branchId,
    int limit = 25,
    int offset = 0,
  }) => throw UnimplementedError();

  @override
  Future<DateTime> updatePatient(UpdatePatientInput input) => throw UnimplementedError();
}
