import 'dart:async';

import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/core/ui/theme/spacing_tokens.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/patients/presentation/providers/patient_detail_provider.dart';
import 'package:ai_clinic/features/patients/presentation/widgets/patient_detail_timeline_section.dart';
import 'package:ai_clinic/features/patients/presentation/pages/patient_detail_page.dart';
import 'package:ai_clinic/core/ui/theme/forui_app_scope.dart';
import 'package:ai_clinic/core/ui/theme/app_theme.dart';
import 'package:ai_clinic/features/settings/presentation/providers/clinic_setup_providers.dart';
import 'package:ai_clinic/features/patients/domain/patient_detail.dart';
import 'package:ai_clinic/features/patients/domain/patient_gender.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/patient_test_support.dart';
import '../../support/appointment_rpc_test_client.dart';
import '../../support/visit_rpc_test_client.dart';
import 'create_patient_test_support.dart';
import 'patient_detail_test_support.dart';
import 'patients_list_test_support.dart';

void main() {
  group('B. Patient Detail — Functional (PD-F)', () {
    group('PD-F-001 — Load happy', () {
      testWidgets('loads profile, basic info, notes, timeline, and documents', (tester) async {
        final visitClient = VisitRpcTestClient(
          rpcResults: {
            'list_patient_visits': {
              'success': true,
              'data': {'items': samplePastVisitItems(), 'total_count': 2, 'limit': 50, 'offset': 0},
            },
            'list_patient_visit_attachments': {
              'success': true,
              'data': {'items': sampleDocumentAttachmentItems(), 'total_count': 1, 'limit': 100, 'offset': 0},
            },
          },
        );

        await pumpPatientDetailPage(
          tester,
          patientDetailHost(
            visitItems: samplePastVisitItems(),
            appointmentItems: sampleUpcomingAppointmentItems(),
            documentItems: sampleDocumentAttachmentItems(),
            visitClient: visitClient,
          ),
        );
        await settlePatientDetail(tester);

        expect(find.text('Sara Ali'), findsWidgets);
        expect(find.text('Basic information'), findsOneWidget);
        expect(find.text('Allergic to penicillin'), findsOneWidget);
        expect(find.text('Past visits'), findsOneWidget);
        expect(find.text('Documents'), findsOneWidget);
        expect(find.text('Dr Ahmed'), findsOneWidget);
        expect(find.text('Lab PDF'), findsOneWidget);
        expect(visitClient.rpcLog.where((fn) => fn == 'list_patient_visit_attachments').length, 1);
      });
    });

    group('PD-F-002 — Preview while loading', () {
      testWidgets('shows preview name and deferred loading overlay during fetch', (tester) async {
        final completer = Completer<void>();
        await pumpPatientDetailPage(
          tester,
          patientDetailHost(
            getPatient: (_) async {
              await completer.future;
              return sampleDetailForWidgetTests();
            },
            preview: samplePreviewForWidgetTests(),
          ),
        );
        await tester.pump();

        expect(find.text('Sara Ali'), findsOneWidget);
        expect(find.byType(AppDeferredLoading), findsOneWidget);
        expect(find.text('Allergic to penicillin'), findsNothing);

        completer.complete();
        await tester.pumpAndSettle();

        expect(find.text('Allergic to penicillin'), findsOneWidget);
      });

      testWidgets('shows deferred spinner only after slow-load threshold', (tester) async {
        final completer = Completer<void>();
        await pumpPatientDetailPage(
          tester,
          patientDetailHost(
            getPatient: (_) async {
              await completer.future;
              return sampleDetailForWidgetTests();
            },
          ),
        );
        await tester.pump();

        expect(find.text('Loading patient…'), findsNothing);

        await tester.pump(const Duration(milliseconds: 250));
        await tester.pump();

        expect(find.text('Loading patient…'), findsOneWidget);
      });
    });

    group('PD-F-003 — Deep link no preview', () {
      testWidgets('loads without preview layout or crash', (tester) async {
        final completer = Completer<PatientDetail>();
        await pumpPatientDetailPage(
          tester,
          patientDetailHost(
            getPatient: (_) async {
              await completer.future;
              return sampleDetailForWidgetTests();
            },
          ),
        );
        await tester.pump();

        expect(find.byType(AppDeferredLoading), findsOneWidget);
        expect(find.byType(AppSkeletonBox), findsWidgets);
        expect(find.text('Loading patient…'), findsNothing);

        completer.complete(sampleDetailForWidgetTests());
        await settlePatientDetail(tester);

        expect(find.text('Basic information'), findsOneWidget);
      });
    });

    group('PD-F-004 — Not found', () {
      testWidgets('shows error view with retry for missing patient', (tester) async {
        await pumpPatientDetailPage(
          tester,
          patientDetailHost(getPatient: (_) async => throw StateError('Patient not found')),
        );
        await tester.pumpAndSettle();

        expect(find.text('Unable to load patient details'), findsOneWidget);
        expect(find.textContaining('Patient not found'), findsOneWidget);
        expect(find.text('Retry'), findsOneWidget);
      });
    });

    group('PD-F-005 — Permission denied', () {
      testWidgets('shows permission denied without loading patient', (tester) async {
        var getPatientCalled = false;
        await pumpPatientDetailPage(
          tester,
          patientDetailHost(
            permissions: const {'patients.create'},
            getPatient: (_) async {
              getPatientCalled = true;
              return sampleDetailForWidgetTests();
            },
          ),
        );
        await tester.pumpAndSettle();

        expect(find.textContaining('do not have permission'), findsOneWidget);
        expect(find.text('Basic information'), findsNothing);
        expect(getPatientCalled, isFalse);
      });
    });

    group('PD-F-006 — Past visits tab', () {
      testWidgets('renders past visits sorted newest first', (tester) async {
        await pumpPatientDetailPage(tester, patientDetailHost(visitItems: samplePastVisitItems()));
        await settlePatientDetail(tester);

        expect(find.text('Dr Ahmed'), findsOneWidget);
        expect(find.text('Dr Sara'), findsOneWidget);

        final ahmedY = tester.getTopLeft(find.text('Dr Ahmed')).dy;
        final saraY = tester.getTopLeft(find.text('Dr Sara')).dy;
        expect(ahmedY, lessThan(saraY));
      });
    });

    group('PD-F-007 — Upcoming tab', () {
      testWidgets('shows only patient appointments sorted ascending', (tester) async {
        final appointmentClient = AppointmentRpcTestClient(
          rpcResults: {
            'list_appointments': {
              'success': true,
              'data': {'items': sampleUpcomingAppointmentItems()},
            },
          },
        );

        await pumpPatientDetailPage(
          tester,
          patientDetailHost(appointmentItems: sampleUpcomingAppointmentItems(), appointmentClient: appointmentClient),
        );
        await settlePatientDetail(tester);

        await tester.tap(
          find.descendant(of: find.byType(PatientDetailTimelineSection), matching: find.text('Upcoming')),
        );
        await tester.pumpAndSettle();

        expect(find.text('Dr Future'), findsOneWidget);
        expect(find.text('Dr Later'), findsOneWidget);
        expect(appointmentClient.lastParams?['p_patient_id'], patientDetailTestId);

        final futureY = tester.getTopLeft(find.text('Dr Future')).dy;
        final laterY = tester.getTopLeft(find.text('Dr Later')).dy;
        expect(futureY, lessThan(laterY));
      });
    });

    group('PD-F-008 — Upcoming empty', () {
      testWidgets('shows empty state when no upcoming appointments', (tester) async {
        await pumpPatientDetailPage(tester, patientDetailHost());
        await settlePatientDetail(tester);

        await tester.tap(
          find.descendant(of: find.byType(PatientDetailTimelineSection), matching: find.text('Upcoming')),
        );
        await tester.pumpAndSettle();

        expect(find.text('No upcoming appointments scheduled.'), findsOneWidget);
      });
    });

    group('PD-F-009 — Documents list', () {
      testWidgets('lists attachments with visit date via single RPC', (tester) async {
        final visitClient = VisitRpcTestClient(
          rpcResults: {
            'list_patient_visit_attachments': {
              'success': true,
              'data': {'items': sampleDocumentAttachmentItems(), 'total_count': 1, 'limit': 100, 'offset': 0},
            },
          },
        );

        await pumpPatientDetailPage(
          tester,
          patientDetailHost(documentItems: sampleDocumentAttachmentItems(), visitClient: visitClient),
        );
        await settlePatientDetail(tester);

        expect(find.text('Lab PDF'), findsOneWidget);
        expect(find.textContaining('31 May'), findsWidgets);
        expect(visitClient.rpcLog.where((fn) => fn == 'list_patient_visit_attachments').length, 1);
        expect(visitClient.paramsForFunction('get_visit'), isNull);
      });
    });

    group('PD-F-010 — Documents download gate', () {
      testWidgets('hides download action when can_download is false', (tester) async {
        await pumpPatientDetailPage(
          tester,
          patientDetailHost(documentItems: sampleDocumentAttachmentItems(canDownload: false)),
        );
        await settlePatientDetail(tester);

        expect(find.text('Lab PDF'), findsOneWidget);
        expect(find.byTooltip('Download'), findsNothing);
      });

      testWidgets('shows download action when can_download is true', (tester) async {
        await pumpPatientDetailPage(
          tester,
          patientDetailHost(documentItems: sampleDocumentAttachmentItems(canDownload: true)),
        );
        await settlePatientDetail(tester);

        expect(find.byTooltip('Download'), findsOneWidget);
      });
    });

    group('PD-F-011 — Notes display', () {
      testWidgets('renders patient notes text in notes card', (tester) async {
        await pumpPatientDetailPage(
          tester,
          patientDetailHost(detail: sampleDetailForWidgetTests(notes: 'Desk note about allergies')),
        );
        await settlePatientDetail(tester);

        expect(find.text('Desk note about allergies'), findsOneWidget);
        expect(find.text('Notes'), findsOneWidget);
      });
    });

    group('PD-F-012 — Back navigation', () {
      testWidgets('back button pops the page when stack allows', (tester) async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: patientDetailOverrides(),
            child: ForuiAppScope(
              child: MaterialApp(
                theme: AppTheme.light(),
                home: Scaffold(
                  body: Center(
                    child: Builder(
                      builder: (context) {
                        return FilledButton(
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => const PatientDetailPage(patientId: patientDetailTestId),
                              ),
                            );
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
    });

    group('PD-F-013 — Back with empty stack', () {
      testWidgets('falls back to patients list when navigation stack is empty', (tester) async {
        final repo = FakePatientRepository(detail: sampleDetailForWidgetTests());
        final router = patientDetailTestRouter(initialLocation: AppRoutes.patientDetail(patientDetailTestId));

        await pumpPatientDetailPage(
          tester,
          ProviderScope(
            overrides: [
              ...patientDetailOverrides(repository: repo),
              clinicSetupBranchesProvider.overrideWith((ref) async => defaultClinicBranches),
            ],
            child: ForuiAppScope(
              child: MaterialApp.router(theme: AppTheme.light(), routerConfig: router),
            ),
          ),
        );
        await settlePatientDetail(tester);

        expect(find.text('Basic information'), findsOneWidget);

        await tester.tap(find.byTooltip('Back to patients'));
        await tester.pumpAndSettle();

        expect(find.text('Basic information'), findsNothing);
        expect(find.byType(TextField), findsOneWidget);
      });
    });

    group('PD-F-014 — Retry on error', () {
      testWidgets('invalidates provider and reloads on retry', (tester) async {
        var attempts = 0;

        await pumpPatientDetailPage(
          tester,
          patientDetailHost(
            getPatient: (_) async {
              attempts++;
              if (attempts == 1) {
                throw StateError('Network error');
              }
              return sampleDetailForWidgetTests();
            },
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Unable to load patient details'), findsOneWidget);
        expect(attempts, 1);

        await tester.tap(find.text('Retry'));
        await tester.pumpAndSettle();

        expect(attempts, 2);
        expect(find.text('Allergic to penicillin'), findsOneWidget);
      });
    });

    group('PD-F-015 — Retry timeline', () {
      testWidgets('invalidates past visits provider on timeline retry', (tester) async {
        final visitClient = VisitRpcTestClient(
          rpcResults: {
            'list_patient_visits': {
              'success': true,
              'data': {'items': samplePastVisitItems(), 'total_count': 2, 'limit': 50, 'offset': 0},
            },
          },
        );
        final flakyRepo = FlakyVisitRepository(visitClient, failListVisitsUntil: 1);

        await pumpPatientDetailPage(
          tester,
          patientDetailHost(
            visitItems: samplePastVisitItems(),
            visitClient: visitClient,
            flakyVisitRepository: flakyRepo,
          ),
        );
        await settlePatientDetail(tester);

        expect(find.text('Unable to load past visits.'), findsOneWidget);
        expect(flakyRepo.listVisitsCallCount, 1);

        await tester.tap(find.descendant(of: find.byType(PatientDetailTimelineSection), matching: find.text('Retry')));
        await settlePatientDetail(tester);

        expect(flakyRepo.listVisitsCallCount, 2);
        expect(find.text('Dr Ahmed'), findsOneWidget);
      });
    });

    group('PD-F-016 — Wide layout', () {
      testWidgets('uses split layout with notes and documents on the right at ≥1080px', (tester) async {
        await pumpPatientDetailPage(tester, patientDetailHost(), surfaceSize: const Size(1200, 900));
        await settlePatientDetail(tester);

        expect(find.text('Basic information'), findsOneWidget);
        expect(find.text('Past visits'), findsOneWidget);
        expect(find.text('Notes'), findsOneWidget);
        expect(isNotesRightOfTimeline(tester), isTrue);
      });

      testWidgets('notes and documents cards each use half page height', (tester) async {
        const surfaceHeight = 800.0;
        await pumpPatientDetailPage(tester, patientDetailHost(), surfaceSize: const Size(1200, surfaceHeight));
        await settlePatientDetail(tester);

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

        expect(notesHeight, closeTo(halfCardHeight, 1));
        expect(documentsHeight, closeTo(halfCardHeight, 1));
      });
    });

    group('PD-F-017 — Medium layout', () {
      testWidgets('renders split layout with profile above timeline at 720–1079px', (tester) async {
        await pumpPatientDetailPage(tester, patientDetailHost(), surfaceSize: const Size(900, 900));
        await settlePatientDetail(tester);

        expect(find.text('Basic information'), findsOneWidget);
        expect(find.text('Past visits'), findsOneWidget);
        expect(find.text('Notes'), findsOneWidget);
        expect(isNotesRightOfTimeline(tester), isTrue);

        final profileY = tester.getTopLeft(find.text('Sara Ali').first).dy;
        final timelineY = tester.getTopLeft(find.text('Past visits')).dy;
        expect(profileY, lessThan(timelineY));
      });
    });

    group('PD-F-018 — Compact layout', () {
      testWidgets('stacks profile, info, notes, timeline, and documents below 720px', (tester) async {
        await pumpPatientDetailPage(tester, patientDetailHost(), surfaceSize: const Size(400, 900));
        await settlePatientDetail(tester);

        final profileY = tester.getTopLeft(find.text('Sara Ali').first).dy;
        final basicInfoY = tester.getTopLeft(find.text('Basic information')).dy;
        final notesY = tester.getTopLeft(find.text('Notes')).dy;
        final timelineY = tester.getTopLeft(find.text('Past visits')).dy;
        final documentsY = tester.getTopLeft(find.text('Documents')).dy;

        expect(profileY, lessThan(basicInfoY));
        expect(basicInfoY, lessThan(notesY));
        expect(notesY, lessThan(timelineY));
        expect(timelineY, lessThan(documentsY));
        expect(isNotesAboveTimeline(tester), isTrue);
      });
    });

    group('PD-F-019 — Resize during view', () {
      testWidgets('adapts layout without overflow exceptions on rapid resize', (tester) async {
        final errors = <Object>[];
        final old = FlutterError.onError;
        FlutterError.onError = (details) => errors.add(details.exception);
        addTearDown(() => FlutterError.onError = old);

        await pumpPatientDetailPage(tester, patientDetailHost(), surfaceSize: const Size(1280, 900));
        await settlePatientDetail(tester);

        for (final width in [360.0, 900.0, 1200.0, 480.0, 1080.0]) {
          await setDetailViewport(tester, width);
        }

        expect(errors.where((e) => e.toString().contains('overflowed')), isEmpty);
        expect(errors.where((e) => e.toString().contains('parentDataDirty')), isEmpty);
        expect(find.text('Basic information'), findsOneWidget);
      });
    });

    group('PD-F-020 — Container transform', () {
      testWidgets('opens detail via container transform route from list row tap', (tester) async {
        final repo = FakePatientRepository(
          patients: [samplePatientListItem(fullName: 'Row Patient')],
          detail: sampleDetailForWidgetTests(),
        );
        final router = patientDetailTestRouter();

        await pumpPatientDetailPage(
          tester,
          ProviderScope(
            overrides: [
              ...patientDetailOverrides(repository: repo),
              clinicSetupBranchesProvider.overrideWith((ref) async => defaultClinicBranches),
            ],
            child: ForuiAppScope(
              child: MaterialApp.router(theme: AppTheme.light(), routerConfig: router),
            ),
          ),
          surfaceSize: const Size(1280, 900),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Row Patient'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 150));

        expect(router.state.uri.path, AppRoutes.patientDetail(patientDetailTestId));
        expect(find.byType(ExcludeSemantics), findsWidgets);

        await tester.pump(const Duration(milliseconds: 200));
        await tester.pumpAndSettle();
        expect(find.text('Basic information'), findsOneWidget);
      });
    });

    group('regression — tab selection survives reload', () {
      testWidgets('keeps upcoming tab selected after patient detail reload', (tester) async {
        await pumpPatientDetailPage(tester, patientDetailHost());
        await settlePatientDetail(tester);

        await tester.tap(
          find.descendant(of: find.byType(PatientDetailTimelineSection), matching: find.text('Upcoming')),
        );
        await tester.pumpAndSettle();

        expect(find.text('No upcoming appointments scheduled.'), findsOneWidget);

        final container = ProviderScope.containerOf(tester.element(find.byType(PatientDetailPage)));
        container.invalidate(patientDetailProvider(patientDetailTestId));
        await tester.pumpAndSettle();

        expect(find.text('No upcoming appointments scheduled.'), findsOneWidget);
        expect(find.text('No past visits recorded.'), findsNothing);
      });
    });
  });

  group('C. Create / Edit Patient — Detail header (CP-F)', () {
    group('CP-F-011 — Edit / Happy path', () {
      testWidgets('opens edit modal from detail header and updates patient', (tester) async {
        final detail = sampleDetailForWidgetTests();
        final repository = FakePatientRepository(detail: detail);

        await pumpPatientDetailPage(
          tester,
          patientDetailHost(
            repository: repository,
            detail: detail,
            permissions: const {'patients.view', 'patients.edit'},
          ),
        );
        await settlePatientDetail(tester);

        await tester.tap(find.byTooltip('Edit patient'));
        await tester.pumpAndSettle();

        await tester.enterText(find.widgetWithText(AppTextField, 'Full name *'), 'Updated Sara');
        await tapUpdatePatient(tester);

        expect(find.text('Patient updated successfully.'), findsOneWidget);
        expect(repository.lastUpdateInput?.fullName, 'Updated Sara');
      });
    });

    group('CP-F-012 — Edit / No permission', () {
      testWidgets('hides edit button without patients.edit', (tester) async {
        await pumpPatientDetailPage(tester, patientDetailHost(permissions: const {'patients.view'}));
        await settlePatientDetail(tester);

        expect(find.byTooltip('Edit patient'), findsNothing);
      });
    });

    group('CP-F-014 — Edit / Pre-filled fields', () {
      testWidgets('prefills all fields with phone digits stripped', (tester) async {
        final detail = samplePatientDetail(
          id: patientDetailTestId,
          fullName: 'Sara Ali',
          phone: '+20 111 111 1111',
          notes: 'Desk note',
          gender: PatientGender.female,
        );
        await pumpPatientDetailPage(
          tester,
          patientDetailHost(detail: detail, permissions: const {'patients.view', 'patients.edit'}),
        );
        await settlePatientDetail(tester);

        await tester.tap(find.byTooltip('Edit patient'));
        await tester.pumpAndSettle();

        final phoneField = tester.widget<AppTextField>(find.widgetWithText(AppTextField, 'Mobile number *').last);
        final notesField = tester.widget<AppTextField>(find.widgetWithText(AppTextField, 'Notes').last);
        expect(phoneField.controller?.text, '201111111111');
        expect(notesField.controller?.text, 'Desk note');
      });
    });

    group('CP-F-016 — Edit / Modal during loading', () {
      testWidgets('disables edit button until patient is loaded', (tester) async {
        final completer = Completer<PatientDetail>();
        await pumpPatientDetailPage(
          tester,
          patientDetailHost(
            permissions: const {'patients.view', 'patients.edit'},
            getPatient: (_) async => completer.future,
          ),
        );
        await tester.pump();

        final editButton = tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.edit_outlined));
        expect(editButton.onPressed, isNull);

        completer.complete(sampleDetailForWidgetTests());
        await settlePatientDetail(tester);

        final loadedEditButton = tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.edit_outlined));
        expect(loadedEditButton.onPressed, isNotNull);
      });
    });
  });

  group('D. Delete Patient — Functional (DL-F)', () {
    Future<void> pumpDeleteDetail(WidgetTester tester, FakePatientRepository repo, {Set<String>? permissions}) async {
      final router = patientsListTestRouter(initialLocation: AppRoutes.patientDetail(patientDetailTestId));
      await pumpPatientDetailPage(
        tester,
        patientDetailRouterHost(
          router: router,
          patientsRepository: repo,
          permissions: permissions ?? const {'patients.view', 'patients.delete'},
        ),
      );
      await settlePatientDetail(tester);
    }

    group('DL-F-001 — Delete / Happy path', () {
      testWidgets('archives patient, shows toast, and returns to list', (tester) async {
        final detail = sampleDetailForWidgetTests();
        final repo = FakePatientRepository(
          detail: detail,
          patients: [samplePatientListItem(id: patientDetailTestId, fullName: detail.fullName)],
        );

        await pumpDeleteDetail(tester, repo);

        await tapPatientDeleteHeader(tester);
        expect(find.text('Delete patient?'), findsOneWidget);

        await confirmPatientDelete(tester);

        expect(find.text('Patient deleted.'), findsOneWidget);
        expect(repo.lastArchivedId, patientDetailTestId);
        expect(find.text('Basic information'), findsNothing);
        expect(find.byType(TextField), findsOneWidget);
      });
    });

    group('DL-F-002 — Delete / List staleness', () {
      testWidgets('reloads patient list after delete so archived patient is removed', (tester) async {
        final detail = sampleDetailForWidgetTests();
        final repo = FakePatientRepository(
          detail: detail,
          patients: [samplePatientListItem(id: patientDetailTestId, fullName: detail.fullName)],
        );

        await pumpDeleteDetail(tester, repo);
        expect(repo.searchCallCount, 0);

        await tapPatientDeleteHeader(tester);
        await confirmPatientDelete(tester);
        await tester.pumpAndSettle();

        expect(find.text(detail.fullName), findsNothing);
        expect(repo.searchCallCount, greaterThan(0));
      });
    });

    group('DL-F-003 — Delete / No permission', () {
      testWidgets('hides delete button without patients.delete', (tester) async {
        final repo = FakePatientRepository(detail: sampleDetailForWidgetTests());
        await pumpDeleteDetail(tester, repo, permissions: const {'patients.view'});

        expect(find.byTooltip('Delete patient'), findsNothing);
      });
    });

    group('DL-F-004 — Delete / Cancel confirm', () {
      testWidgets('leaves patient unchanged when delete is cancelled', (tester) async {
        final repo = FakePatientRepository(detail: sampleDetailForWidgetTests());

        await pumpDeleteDetail(tester, repo);

        await tapPatientDeleteHeader(tester);
        await cancelPatientDelete(tester);

        expect(repo.archiveCallCount, 0);
        expect(find.text('Basic information'), findsOneWidget);
      });
    });

    group('DL-F-005 — Delete / Double confirm', () {
      testWidgets('issues a single archive call when confirm is double-tapped', (tester) async {
        final repo = FakePatientRepository(
          detail: sampleDetailForWidgetTests(),
          archiveDelay: const Duration(milliseconds: 400),
        );

        await pumpDeleteDetail(tester, repo);

        await tapPatientDeleteHeader(tester);
        final confirm = find.widgetWithText(AppButton, 'Delete patient');
        await tester.tap(confirm);
        await tester.tap(confirm);
        await tester.pump(const Duration(milliseconds: 100));

        expect(repo.archiveCallCount, 1);
        await tester.pumpAndSettle();
        expect(repo.archiveCallCount, 1);
      });
    });

    group('DL-F-006 — Delete / In-flight guard', () {
      testWidgets('disables delete header button with spinner while archive is in progress', (tester) async {
        final repo = FakePatientRepository(
          detail: sampleDetailForWidgetTests(),
          archiveDelay: const Duration(milliseconds: 400),
        );

        await pumpDeleteDetail(tester, repo);

        await tapPatientDeleteHeader(tester);
        await tester.tap(find.widgetWithText(AppButton, 'Delete patient'));
        await tester.pump();

        expect(find.byType(CircularProgressIndicator), findsWidgets);
        await tester.tap(find.byTooltip('Delete patient'));
        await tester.pump();

        expect(repo.archiveCallCount, 1);
        await tester.pumpAndSettle();
      });
    });

    group('DL-F-007 — Delete / RPC error', () {
      testWidgets('shows error toast and stays on detail when archive fails', (tester) async {
        final repo = FakePatientRepository(
          detail: sampleDetailForWidgetTests(),
          archiveException: RpcFailure(
            const RpcResult(success: false, errorCode: 'FORBIDDEN', errorMessage: 'Forbidden'),
          ),
        );

        await pumpDeleteDetail(tester, repo);

        await tapPatientDeleteHeader(tester);
        await confirmPatientDelete(tester);

        expect(find.textContaining('do not have permission'), findsOneWidget);
        expect(find.text('Basic information'), findsOneWidget);
        expect(repo.archiveCallCount, 1);
      });
    });
  });

  group('J. User Abuse & Edge Cases (AB) — Detail', () {
    group('AB-005 — Invalid patient URL', () {
      testWidgets('shows graceful error for non-UUID id', (tester) async {
        final router = patientDetailTestRouter(initialLocation: '/patients/not-a-uuid');
        final repo = FakePatientRepository();

        await pumpPatientDetailPage(tester, patientDetailRouterHost(router: router, patientsRepository: repo));
        await tester.pumpAndSettle();

        expect(find.text('Unable to load patient details'), findsOneWidget);
        expect(find.text('Retry'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    });

    group('AB-006 — XSS in patient name', () {
      testWidgets('renders script tags as plain text on detail', (tester) async {
        const xssName = '<script>alert(1)</script>';
        await pumpPatientDetailPage(
          tester,
          patientDetailHost(detail: sampleDetailForWidgetTests().copyWith(fullName: xssName)),
        );
        await settlePatientDetail(tester);

        expect(find.textContaining('<script>'), findsWidgets);
      });
    });

    group('AB-007 — Extremely long name', () {
      testWidgets('detail header ellipsis without overflow', (tester) async {
        final longName = 'B' * 500;
        final errors = <Object>[];
        final old = FlutterError.onError;
        FlutterError.onError = (details) => errors.add(details.exception);
        addTearDown(() => FlutterError.onError = old);

        await pumpPatientDetailPage(
          tester,
          patientDetailHost(detail: sampleDetailForWidgetTests().copyWith(fullName: longName)),
        );
        await settlePatientDetail(tester);

        expect(errors.where((e) => e.toString().contains('overflowed')), isEmpty);
        expect(find.textContaining('BBB'), findsWidgets);
      });
    });

    group('AB-009 — Refresh during delete', () {
      testWidgets('re-entering detail route after mid-delete does not crash', (tester) async {
        final repo = FakePatientRepository(
          detail: sampleDetailForWidgetTests(),
          archiveDelay: const Duration(milliseconds: 200),
        );
        final router = patientsListTestRouter(initialLocation: AppRoutes.patientDetail(patientDetailTestId));

        await pumpPatientDetailPage(
          tester,
          patientDetailRouterHost(
            router: router,
            patientsRepository: repo,
            permissions: const {'patients.view', 'patients.delete'},
          ),
        );
        await settlePatientDetail(tester);

        await tapPatientDeleteHeader(tester);
        await tester.tap(find.widgetWithText(AppButton, 'Delete patient'));
        await tester.pump(const Duration(milliseconds: 50));

        await pumpPatientDetailPage(
          tester,
          patientDetailRouterHost(
            router: patientDetailTestRouter(initialLocation: AppRoutes.patientDetail(patientDetailTestId)),
            patientsRepository: repo,
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
      });
    });
  });

  group('K. Frontend UI / Visual (UI) — Detail', () {
    group('UI-002 — Avatar null gender', () {
      testWidgets('detail shows neutral person icon for null gender', (tester) async {
        await pumpPatientDetailPage(
          tester,
          patientDetailHost(detail: sampleDetailForWidgetTests().copyWith(gender: null)),
        );
        await settlePatientDetail(tester);

        expect(find.byIcon(Icons.person_outline), findsWidgets);
      });
    });

    group('UI-005 — Dark mode tokens', () {
      testWidgets('detail page uses dark theme brightness', (tester) async {
        await pumpPatientDetailPage(
          tester,
          ProviderScope(
            overrides: patientDetailOverrides(detail: sampleDetailForWidgetTests()),
            child: ForuiAppScope(
              child: MaterialApp(
                theme: AppTheme.dark(),
                home: PatientDetailPage(patientId: patientDetailTestId),
              ),
            ),
          ),
        );
        await settlePatientDetail(tester);

        expect(Theme.of(tester.element(find.byType(PatientDetailPage))).brightness, Brightness.dark);
      });
    });
  });
}
