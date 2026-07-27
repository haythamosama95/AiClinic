import 'package:decimal/decimal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/auth/domain/permission_keys.dart';
import 'package:ai_clinic/features/billing/application/visit_finalize_outcome.dart';
import 'package:ai_clinic/features/billing/application/visit_invoice_finalization_service.dart';
import 'package:ai_clinic/features/billing/data/invoice_item_repository.dart';
import 'package:ai_clinic/features/billing/data/invoice_repository.dart';
import 'package:ai_clinic/features/billing/domain/invoice_detail.dart';
import 'package:ai_clinic/features/billing/domain/invoice_status.dart';
import 'package:ai_clinic/features/billing/domain/visit_billing_models.dart';
import 'package:ai_clinic/core/money/money.dart';
import 'package:ai_clinic/features/visits/application/visit_finalization_service.dart';
import 'package:ai_clinic/features/visits/data/visit_repository.dart';
import 'package:ai_clinic/features/visits/domain/visit_status.dart';
import 'package:ai_clinic/features/visits/presentation/providers/visit_documentation_notifier.dart';

import '../../helpers/auth_test_support.dart';
import '../../support/visit_encounter_test_support.dart';
import '../../support/visit_rpc_test_client.dart';

void main() {
  group('VisitFinalizationService', () {
    late VisitRpcTestClient client;
    late _TrackingVisitDocumentationNotifier trackingNotifier;

    ProviderContainer createContainer({
      required VisitDocumentationState seedState,
      required VisitInvoiceFinalizationService invoiceService,
    }) {
      trackingNotifier = _TrackingVisitDocumentationNotifier(seedState);
      return ProviderContainer(
        overrides: [
          authSessionProvider.overrideWith(
            () => _PresetAuthSessionNotifier(
              AuthSessionState(
                status: AuthSessionStatus.authenticated,
                context: sampleAuthSessionContext(
                  branchIds: [encounterTestBranchId],
                  activeBranchId: encounterTestBranchId,
                  permissions: {
                    PermissionKeys.visitsEditSoap,
                    PermissionKeys.visitsCreate,
                    PermissionKeys.invoicesCreate,
                  },
                ),
              ),
            ),
          ),
          visitRepositoryProvider.overrideWith((ref) => VisitRepository(client)),
          visitDocumentationProvider(encounterTestVisitId).overrideWith(() => trackingNotifier),
          visitInvoiceFinalizationServiceProvider.overrideWithValue(invoiceService),
        ],
      );
    }

    VisitFinalizationRequest sampleRequest() {
      return VisitFinalizationRequest(
        lines: [
          VisitSelectedServiceLine(
            id: 'line-1',
            serviceId: 'service-1',
            name: 'Consultation',
            unitPrice: Money.parse('50'),
            quantity: 1,
          ),
        ],
        discountType: VisitBillingDiscountType.none,
        discountValue: Decimal.zero,
      );
    }

    InvoiceDetail sampleInvoice() {
      return InvoiceDetail(
        id: '11111111-1111-4111-8111-111111111111',
        status: InvoiceStatus.issued,
        branchId: encounterTestBranchId,
        patientId: encounterTestPatientId,
        visitId: encounterTestVisitId,
        subtotal: Money.parse('50'),
        discountAmount: Money.zero,
        insuranceCoveredAmount: Money.zero,
        currency: 'USD',
        balance: Money.parse('50'),
        createdAt: DateTime.utc(2026, 5, 31),
        updatedAt: DateTime.utc(2026, 5, 31, 11),
        items: const [],
        payments: const [],
      );
    }

    setUp(() {
      client = VisitRpcTestClient();
      client.rpcResults['get_visit'] = {
        'success': true,
        'data': {
          'id': encounterTestVisitId,
          'branch_id': encounterTestBranchId,
          'appointment_id': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
          'patient_id': encounterTestPatientId,
          'doctor_id': 'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
          'doctor_name': 'Dr Test',
          'visit_date': '2026-05-31',
          'status': 'completed',
          'documentation': {
            'complaint': null,
            'history': null,
            'examination': null,
            'diagnosis': null,
            'plan': null,
            'updated_at': '2026-05-31T10:00:00.000Z',
          },
        },
      };
    });

    test('invoice failure does not complete the visit', () async {
      final invoiceService = _ThrowingInvoiceFinalizationService();
      final container = createContainer(
        seedState: sampleEncounterDocState(),
        invoiceService: invoiceService,
      );
      addTearDown(container.dispose);

      await container.read(visitDocumentationProvider(encounterTestVisitId).future);
      final service = container.read(visitFinalizationServiceProvider);

      final outcome = await service.finalize(
        visitId: encounterTestVisitId,
        request: sampleRequest(),
        canCreateInvoices: true,
        canApplyDiscount: true,
      );

      expect(outcome, isA<VisitFinalizeInvoiceFailed>());
      expect(trackingNotifier.completeVisitCalls, 0);
      expect(client.rpcCalls.where((call) => call.fn == 'complete_visit'), isEmpty);
    });

    test('success issues invoice then completes visit once with expectedUpdatedAt', () async {
      final invoiceService = _SuccessfulInvoiceFinalizationService(sampleInvoice());
      final expectedAt = DateTime.utc(2026, 5, 31, 10);
      final visit = sampleEncounterVisit().copyWith(updatedAt: expectedAt);
      final container = createContainer(
        seedState: sampleEncounterDocState(visit: visit),
        invoiceService: invoiceService,
      );
      addTearDown(container.dispose);

      await container.read(visitDocumentationProvider(encounterTestVisitId).future);
      final service = container.read(visitFinalizationServiceProvider);

      final outcome = await service.finalize(
        visitId: encounterTestVisitId,
        request: sampleRequest(),
        canCreateInvoices: true,
        canApplyDiscount: true,
      );

      expect(outcome, isA<VisitFinalizeSucceeded>());
      expect(trackingNotifier.completeVisitCalls, 1);
      expect(trackingNotifier.lastExpectedUpdatedAt, expectedAt);
      expect(invoiceService.createCalls, 1);
    });

    test('skips invoice and still completes when canCreateInvoices is false', () async {
      final invoiceService = _SuccessfulInvoiceFinalizationService(sampleInvoice());
      final container = createContainer(
        seedState: sampleEncounterDocState(),
        invoiceService: invoiceService,
      );
      addTearDown(container.dispose);

      await container.read(visitDocumentationProvider(encounterTestVisitId).future);
      final service = container.read(visitFinalizationServiceProvider);

      final outcome = await service.finalize(
        visitId: encounterTestVisitId,
        request: sampleRequest(),
        canCreateInvoices: false,
        canApplyDiscount: false,
      );

      expect(outcome, isA<VisitFinalizeSucceeded>());
      expect(trackingNotifier.completeVisitCalls, 1);
      expect(invoiceService.createCalls, 0);
    });
  });
}

class _TrackingVisitDocumentationNotifier extends VisitDocumentationNotifier {
  _TrackingVisitDocumentationNotifier(this._state) : super(encounterTestVisitId);

  final VisitDocumentationState _state;
  int completeVisitCalls = 0;
  DateTime? lastExpectedUpdatedAt;

  @override
  Future<VisitDocumentationState> build() async => _state;

  @override
  Future<CompleteVisitResult> completeVisit({DateTime? expectedUpdatedAt}) async {
    completeVisitCalls++;
    lastExpectedUpdatedAt = expectedUpdatedAt;
    final completedVisit = _state.persistedVisit.copyWith(status: VisitStatus.completed);
    state = AsyncData(_state.copyWith(persistedVisit: completedVisit));
    return const CompleteVisitResult(
      visitId: encounterTestVisitId,
      visitStatus: 'completed',
      appointmentId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      appointmentStatus: 'completed',
    );
  }
}

class _ThrowingInvoiceFinalizationService extends VisitInvoiceFinalizationService {
  _ThrowingInvoiceFinalizationService()
    : super(InvoiceRepository(VisitRpcTestClient()), InvoiceItemRepository(VisitRpcTestClient()));

  @override
  Future<InvoiceDetail> createIssuedInvoiceForVisit({
    required String visitId,
    String? existingDraftId,
    required List<VisitSelectedServiceLine> lines,
    required VisitBillingDiscountType discountType,
    required Decimal discountValue,
    required bool canApplyDiscount,
  }) {
    throw RpcFailure(const RpcResult(success: false, errorCode: 'INVOICE_FAILED', errorMessage: 'Invoice failed'));
  }
}

class _SuccessfulInvoiceFinalizationService extends VisitInvoiceFinalizationService {
  _SuccessfulInvoiceFinalizationService(this._invoice)
    : super(InvoiceRepository(VisitRpcTestClient()), InvoiceItemRepository(VisitRpcTestClient()));

  final InvoiceDetail _invoice;
  int createCalls = 0;

  @override
  Future<InvoiceDetail> createIssuedInvoiceForVisit({
    required String visitId,
    String? existingDraftId,
    required List<VisitSelectedServiceLine> lines,
    required VisitBillingDiscountType discountType,
    required Decimal discountValue,
    required bool canApplyDiscount,
  }) async {
    createCalls++;
    return _invoice;
  }
}

class _PresetAuthSessionNotifier extends TestAuthSessionNotifier {
  _PresetAuthSessionNotifier(this.initial);

  final AuthSessionState initial;

  @override
  AuthSessionState build() => initial;
}
