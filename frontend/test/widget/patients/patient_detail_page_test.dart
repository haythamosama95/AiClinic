import 'dart:async';

import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/ui/theme/app_theme.dart';
import 'package:ai_clinic/core/ui/theme/spacing_tokens.dart';
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
import 'package:ai_clinic/features/appointments/data/appointment_repository.dart';
import 'package:ai_clinic/features/patients/presentation/widgets/patient_detail_timeline_section.dart';
import 'package:ai_clinic/features/patients/presentation/providers/patient_detail_provider.dart';
import 'package:ai_clinic/features/patients/presentation/pages/patient_detail_page.dart';
import 'package:ai_clinic/features/visits/data/visit_repository.dart';
import 'package:ai_clinic/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/auth_test_support.dart';
import '../../support/appointment_rpc_test_client.dart';
import '../../support/visit_rpc_test_client.dart';

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
      expect(find.byType(AppDeferredLoading), findsOneWidget);
      expect(find.text('Loading patient…'), findsNothing);
      expect(find.text('Allergic to penicillin'), findsNothing);

      completer.complete(sampleDetail);
      await tester.pumpAndSettle();

      expect(find.text('Allergic to penicillin'), findsOneWidget);
      expect(find.text('Married'), findsOneWidget);
      expect(find.textContaining('Created by Reception'), findsOneWidget);
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

    testWidgets('wide layout renders timeline visits without layout errors', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final errors = <Object>[];
      final old = FlutterError.onError;
      FlutterError.onError = (details) => errors.add(details.exception);
      addTearDown(() => FlutterError.onError = old);

      await tester.pumpWidget(
        _host(
          getPatient: (_) async => sampleDetail,
          visitItems: [
            {
              'id': '22222222-2222-4222-8222-222222222222',
              'visit_date': '2026-05-20T09:00:00.000Z',
              'doctor_name': 'Dr Ahmed',
              'status': 'completed',
              'branch_name': 'Main',
            },
            {
              'id': '33333333-3333-4333-8333-333333333333',
              'visit_date': '2026-04-10T14:30:00.000Z',
              'doctor_name': 'Dr Sara',
              'status': 'completed',
              'branch_name': 'Downtown',
            },
          ],
        ),
      );
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Dr Ahmed'), findsOneWidget);
      expect(find.text('Dr Sara'), findsOneWidget);
      expect(errors.where((e) => e.toString().contains('intrinsic dimensions')), isEmpty);
      expect(errors.where((e) => e.toString().contains('parentDataDirty')), isEmpty);
      expect(errors.where((e) => e.toString().contains('hasSize')), isEmpty);
    });

    testWidgets('wide layout renders without scheduler assertions', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final errors = <Object>[];
      final old = FlutterError.onError;
      FlutterError.onError = (details) => errors.add(details.exception);
      addTearDown(() => FlutterError.onError = old);

      await tester.pumpWidget(_host(getPatient: (_) async => sampleDetail));
      await tester.pumpAndSettle();

      expect(find.text('Basic information'), findsOneWidget);
      expect(find.text('Past visits'), findsOneWidget);
      expect(errors.where((e) => e.toString().contains('parentDataDirty')), isEmpty);
    });

    testWidgets('back button pops the page', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: _detailPageOverrides(getPatient: (_) async => sampleDetail),
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

      expect(find.text('Basic information'), findsOneWidget);

      await tester.tap(find.byTooltip('Back to patients'));
      await tester.pumpAndSettle();

      expect(find.text('Open detail'), findsOneWidget);
    });

    testWidgets('keeps upcoming tab selected after patient detail reload', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(_host(getPatient: (_) async => sampleDetail));
      await tester.pumpAndSettle();

      await tester.tap(find.descendant(of: find.byType(PatientDetailTimelineSection), matching: find.text('Upcoming')));
      await tester.pumpAndSettle();

      expect(find.text('No upcoming appointments scheduled.'), findsOneWidget);

      final container = ProviderScope.containerOf(tester.element(find.byType(PatientDetailPage)));
      container.invalidate(patientDetailProvider(patientId));
      await tester.pumpAndSettle();

      expect(find.text('No upcoming appointments scheduled.'), findsOneWidget);
      expect(find.text('No past visits recorded.'), findsNothing);
    });

    testWidgets('wide layout notes and documents cards each use half page height', (tester) async {
      const surfaceHeight = 800.0;
      await tester.binding.setSurfaceSize(const Size(1200, surfaceHeight));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_host(getPatient: (_) async => sampleDetail));
      await tester.pumpAndSettle();

      RenderBox cardBoxFor(Finder label) {
        final container = find.ancestor(
          of: label,
          matching: find.byWidgetPredicate((widget) {
            if (widget is! DecoratedBox) {
              return false;
            }
            final decoration = widget.decoration;
            return decoration is BoxDecoration && decoration.border != null && decoration.color != null;
          }),
        );
        expect(container, findsOneWidget);
        return tester.renderObject<RenderBox>(container);
      }

      const headerHeight = 40.0;
      final pageHeight = surfaceHeight - (SpacingTokens.lg * 2) - headerHeight - SpacingTokens.md;
      final halfCardHeight = (pageHeight - SpacingTokens.lg) / 2;
      final notesHeight = cardBoxFor(find.text('Notes')).size.height;
      final documentsHeight = cardBoxFor(find.text('Documents')).size.height;
      final profileHeight = cardBoxFor(find.text('Sara Ali')).size.height;
      final basicInfoHeight = cardBoxFor(find.text('Basic information')).size.height;

      expect(notesHeight, closeTo(halfCardHeight, 1));
      expect(documentsHeight, closeTo(halfCardHeight, 1));
      expect(profileHeight, greaterThan(0));
      expect(basicInfoHeight, greaterThan(0));
    });
  });
}

Widget _host({
  required Future<PatientDetail> Function(String patientId) getPatient,
  PatientListItem? preview,
  List<Map<String, dynamic>> visitItems = const [],
}) {
  return ProviderScope(
    overrides: _detailPageOverrides(getPatient: getPatient, visitItems: visitItems),
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

_detailPageOverrides({
  required Future<PatientDetail> Function(String patientId) getPatient,
  List<Map<String, dynamic>> visitItems = const [],
}) {
  return [
    authSessionProvider.overrideWith(_PatientsAuthNotifier.new),
    getPatientUseCaseProvider.overrideWith((ref) => GetPatient(_FakePatientRepository(getPatient))),
    visitRepositoryProvider.overrideWith(
      (ref) => VisitRepository(
        VisitRpcTestClient(
          rpcResults: {
            'list_patient_visits': {
              'success': true,
              'data': {'items': visitItems, 'total_count': visitItems.length, 'limit': 50, 'offset': 0},
            },
          },
        ),
      ),
    ),
    appointmentRepositoryProvider.overrideWith(
      (ref) => AppointmentRepository(
        AppointmentRpcTestClient(
          rpcResults: {
            'list_appointments': {
              'success': true,
              'data': {'items': <Map<String, dynamic>>[]},
            },
          },
        ),
      ),
    ),
  ];
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
