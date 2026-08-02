import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/ai/acceptance/clinical_accept_controller.dart';
import 'package:ai_clinic/features/ai/acceptance/clinical_acceptance_port.dart';
import 'package:ai_clinic/features/ai/surface/first_ai_feature_surface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../unit/core/ai/fakes.dart';
import 'ai_surface_test_harness.dart';

const kClinicalAcceptKey = Key('clinical_accept');
const kClinicalDiscardKey = Key('clinical_discard');

/// Spy port recording every [recordAcceptance] invocation for widget tests.
class SpyClinicalAcceptancePort implements ClinicalAcceptancePort {
  final List<ClinicalAcceptanceCall> calls = [];

  @override
  Future<RpcResult> recordAcceptance({
    required String requestReference,
    required String targetKey,
    required Map<String, dynamic> targetArgs,
  }) async {
    calls.add(
      ClinicalAcceptanceCall(
        requestReference: requestReference,
        targetKey: targetKey,
        targetArgs: Map<String, dynamic>.from(targetArgs),
      ),
    );
    return const RpcResult(
      success: true,
      data: {
        'acceptance_id': 'acceptance-1',
        'table_name': 'visit_clinical_notes',
        'record_id': testVisitId,
        'audit_log_id': 'audit-1',
      },
    );
  }
}

class ClinicalAcceptanceCall {
  ClinicalAcceptanceCall({
    required this.requestReference,
    required this.targetKey,
    required this.targetArgs,
  });

  final String requestReference;
  final String targetKey;
  final Map<String, dynamic> targetArgs;
}

class _ClinicalAcceptHarnessSurface extends StatefulWidget {
  const _ClinicalAcceptHarnessSurface({
    required this.controller,
    required this.requestReference,
    required this.terminalText,
    required this.expectedUpdatedAt,
    this.autoAccept = false,
  });

  final ClinicalAcceptController controller;
  final String requestReference;
  final String terminalText;
  final DateTime expectedUpdatedAt;
  final bool autoAccept;

  @override
  State<_ClinicalAcceptHarnessSurface> createState() =>
      _ClinicalAcceptHarnessSurfaceState();
}

class _ClinicalAcceptHarnessSurfaceState extends State<_ClinicalAcceptHarnessSurface> {
  bool _discarded = false;

  @override
  void initState() {
    super.initState();
    if (widget.autoAccept) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _accept());
    }
  }

  Future<void> _accept() async {
    await widget.controller.acceptVisitClinicalNotes(
      requestReference: widget.requestReference,
      visitId: testVisitId,
      complaint: widget.terminalText,
      expectedUpdatedAt: widget.expectedUpdatedAt,
    );
  }

  void _discard() {
    widget.controller.discard();
    setState(() => _discarded = true);
  }

  @override
  Widget build(BuildContext context) {
    if (_discarded) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(widget.terminalText),
        ElevatedButton(
          key: kClinicalAcceptKey,
          onPressed: () => _accept(),
          child: const Text('Accept into record'),
        ),
        TextButton(
          key: kClinicalDiscardKey,
          onPressed: _discard,
          child: const Text('Discard'),
        ),
      ],
    );
  }
}

void main() {
  group('clinical accept path', () {
    testWidgets('clinical_accept_never_auto_commits', (tester) async {
      final spy = SpyClinicalAcceptancePort();
      final controller = ClinicalAcceptController(port: spy);
      final harness = AiSurfaceHarness();

      await harness.pumpWidgetWithTheme(
        tester,
        _ClinicalAcceptHarnessSurface(
          controller: controller,
          requestReference: 'A1B2-C3D4',
          terminalText: 'Validated AI clinical note',
          expectedUpdatedAt: DateTime.utc(2026, 8, 1, 10),
          autoAccept: false,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Validated AI clinical note'), findsOneWidget);
      expect(spy.calls, isEmpty);

      await tester.tap(find.byKey(kClinicalAcceptKey));
      await tester.pumpAndSettle();

      expect(spy.calls, hasLength(1));
      expect(spy.calls.single.targetKey, 'visit_clinical_notes');
    });

    testWidgets('advisory_display_accept_unchanged', (tester) async {
      final spy = SpyClinicalAcceptancePort();
      final harness = AiSurfaceHarness(
        submitScript: [
          SubmitOpenStreamStep(
            streamingThenCompleted(
              provisionalText: 'draft',
              terminalText: 'Advisory summary',
            ),
          ),
        ],
      );

      await harness.pumpSurface(tester);
      await tester.pumpAndSettle();

      expect(find.text('Advisory summary'), findsOneWidget);
      await tester.tap(find.byKey(kAiAcceptKey));
      await tester.pumpAndSettle();

      expect(find.byKey(kAiAcknowledgedKey), findsOneWidget);
      expect(spy.calls, isEmpty);
      expect(harness.persistenceProbe.writes, isEmpty);
    });

    testWidgets('acceptance_writes_domain_change_and_request_reference_together', (tester) async {
      final spy = SpyClinicalAcceptancePort();
      final controller = ClinicalAcceptController(port: spy);
      final harness = AiSurfaceHarness();
      const requestReference = 'B2C3-D4E5';

      await harness.pumpWidgetWithTheme(
        tester,
        _ClinicalAcceptHarnessSurface(
          controller: controller,
          requestReference: requestReference,
          terminalText: 'Accepted documentation',
          expectedUpdatedAt: DateTime.utc(2026, 8, 1, 12),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(kClinicalAcceptKey));
      await tester.pumpAndSettle();

      expect(spy.calls, hasLength(1));
      expect(spy.calls.single.requestReference, requestReference);
      expect(spy.calls.single.targetKey, 'visit_clinical_notes');
      expect(spy.calls.single.targetArgs['p_visit_id'], testVisitId);
      expect(spy.calls.single.targetArgs['p_complaint'], 'Accepted documentation');
    });

    testWidgets('discard_path_writes_nothing', (tester) async {
      final spy = SpyClinicalAcceptancePort();
      final controller = ClinicalAcceptController(port: spy);
      final harness = AiSurfaceHarness();

      await harness.pumpWidgetWithTheme(
        tester,
        _ClinicalAcceptHarnessSurface(
          controller: controller,
          requestReference: 'C3D4-E5F6',
          terminalText: 'Discard this draft',
          expectedUpdatedAt: DateTime.utc(2026, 8, 1, 12),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(kClinicalDiscardKey));
      await tester.pumpAndSettle();

      expect(spy.calls, isEmpty);
      expect(find.text('Discard this draft'), findsNothing);
    });

    testWidgets('unaccepted_content_never_persisted', (tester) async {
      final spy = SpyClinicalAcceptancePort();
      final controller = ClinicalAcceptController(port: spy);
      final harness = AiSurfaceHarness();

      await harness.pumpWidgetWithTheme(
        tester,
        _ClinicalAcceptHarnessSurface(
          controller: controller,
          requestReference: 'D4E5-F6G7',
          terminalText: 'Visible but unaccepted',
          expectedUpdatedAt: DateTime.utc(2026, 8, 1, 12),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Visible but unaccepted'), findsOneWidget);
      expect(spy.calls, isEmpty);
      expect(harness.persistenceProbe.writes, isEmpty);
    });
  });
}
