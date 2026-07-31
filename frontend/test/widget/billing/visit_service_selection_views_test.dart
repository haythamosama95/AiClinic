import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/core/ui/components/app_checkbox.dart';
import 'package:ai_clinic/core/ui/components/app_icon_button.dart';
import 'package:ai_clinic/core/ui/theme/app_theme.dart';
import 'package:ai_clinic/features/billing/domain/money.dart';
import 'package:ai_clinic/features/billing/domain/visit_billing_models.dart';
import 'package:ai_clinic/features/billing/presentation/widgets/visit_billing/visit_service_selection_grid_view.dart';
import 'package:ai_clinic/features/billing/presentation/widgets/visit_billing/visit_service_selection_list_view.dart';
import 'package:ai_clinic/features/billing/presentation/widgets/visit_billing/visit_service_selection_sidebar.dart';
import 'package:ai_clinic/features/service_catalog/domain/effective_price.dart';
import 'package:ai_clinic/features/service_catalog/domain/eligible_service.dart';

EligibleService _service({String id = 'svc-1', String name = 'Consultation', String price = '100.00'}) {
  return EligibleService(
    serviceId: id,
    name: name,
    unitPrice: Money.parse(price),
    appliedRule: AppliedPriceRule.defaultPrice,
    onPromotion: false,
  );
}

VisitSelectedServiceLine _line({
  String serviceId = 'svc-1',
  String name = 'Consultation',
  int quantity = 1,
}) {
  return VisitSelectedServiceLine(
    id: 'line-$serviceId',
    serviceId: serviceId,
    name: name,
    unitPrice: 100,
    quantity: quantity,
  );
}

Future<void> _pumpWide(WidgetTester tester, Widget child) async {
  await tester.binding.setSurfaceSize(const Size(1400, 1000));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(body: child),
    ),
  );
}

AppIconButton _iconButton(WidgetTester tester, String label) {
  return tester.widget<AppIconButton>(find.bySemanticsLabel(label));
}

void main() {
  group('VisitServiceSelectionGridView', () {
    testWidgets('renders services and reflects selection', (tester) async {
      final services = [_service(), _service(id: 'svc-2', name: 'Labs')];

      await _pumpWide(
        tester,
        VisitServiceSelectionGridView(
          services: services,
          selectedIds: const {'svc-1'},
          selectedLines: [_line()],
          currency: 'USD',
          onToggle: (_, __) {},
          onQuantityChange: (_, __) {},
        ),
      );

      expect(find.text('Consultation'), findsOneWidget);
      expect(find.text('Labs'), findsOneWidget);
      expect(find.text('Qty'), findsOneWidget);
    });

    testWidgets('tapping a card invokes onToggle with the service', (tester) async {
      final service = _service();
      EligibleService? toggledService;
      bool? toggledSelected;

      await _pumpWide(
        tester,
        VisitServiceSelectionGridView(
          services: [service],
          selectedIds: const {},
          selectedLines: const [],
          currency: 'USD',
          onToggle: (candidate, selected) {
            toggledService = candidate;
            toggledSelected = selected;
          },
          onQuantityChange: (_, __) {},
        ),
      );

      await tester.tap(find.text('Consultation'));
      await tester.pump();

      expect(toggledService?.serviceId, service.serviceId);
      expect(toggledSelected, isTrue);
    });

    testWidgets('quantity stepper invokes onQuantityChange at boundaries', (tester) async {
      final service = _service();
      final changes = <(String, int)>[];

      await _pumpWide(
        tester,
        VisitServiceSelectionGridView(
          services: [service],
          selectedIds: {service.serviceId},
          selectedLines: [_line()],
          currency: 'USD',
          onToggle: (_, __) {},
          onQuantityChange: (serviceId, next) => changes.add((serviceId, next)),
        ),
      );

      expect(
        _iconButton(tester, 'Decrease quantity for Consultation').disabled,
        isTrue,
      );

      await tester.tap(find.bySemanticsLabel('Increase quantity for Consultation'));
      await tester.pump();

      expect(changes, contains((service.serviceId, 2)));
    });

    testWidgets('increase control is disabled at quantity 99', (tester) async {
      final service = _service();

      await _pumpWide(
        tester,
        VisitServiceSelectionGridView(
          services: [service],
          selectedIds: {service.serviceId},
          selectedLines: [_line(quantity: 99)],
          currency: 'USD',
          onToggle: (_, __) {},
          onQuantityChange: (_, __) {},
        ),
      );

      expect(
        _iconButton(tester, 'Increase quantity for Consultation').disabled,
        isTrue,
      );
    });
  });

  group('VisitServiceSelectionListView', () {
    testWidgets('renders services and reflects selection', (tester) async {
      await _pumpWide(
        tester,
        VisitServiceSelectionListView(
          services: [_service()],
          selectedIds: const {'svc-1'},
          selectedLines: [_line()],
          currency: 'USD',
          onToggle: (_, __) {},
          onQuantityChange: (_, __) {},
        ),
      );

      expect(find.text('Consultation'), findsOneWidget);
      expect(find.byType(AppCheckbox), findsOneWidget);
    });

    testWidgets('tapping the row invokes onToggle with the service', (tester) async {
      final service = _service();
      EligibleService? toggledService;

      await _pumpWide(
        tester,
        VisitServiceSelectionListView(
          services: [service],
          selectedIds: const {},
          selectedLines: const [],
          currency: 'USD',
          onToggle: (candidate, selected) {
            if (selected) {
              toggledService = candidate;
            }
          },
          onQuantityChange: (_, __) {},
        ),
      );

      await tester.tap(find.text('Consultation'));
      await tester.pump();

      expect(toggledService?.serviceId, service.serviceId);
    });

    testWidgets('checkbox invokes onToggle with the service', (tester) async {
      final service = _service();
      EligibleService? toggledService;

      await _pumpWide(
        tester,
        VisitServiceSelectionListView(
          services: [service],
          selectedIds: const {},
          selectedLines: const [],
          currency: 'USD',
          onToggle: (candidate, selected) {
            if (selected) {
              toggledService = candidate;
            }
          },
          onQuantityChange: (_, __) {},
        ),
      );

      await tester.tap(find.byType(AppCheckbox));
      await tester.pump();

      expect(toggledService?.serviceId, service.serviceId);
    });

    testWidgets('quantity stepper invokes onQuantityChange at boundaries', (tester) async {
      final service = _service();
      final changes = <(String, int)>[];

      await _pumpWide(
        tester,
        VisitServiceSelectionListView(
          services: [service],
          selectedIds: {service.serviceId},
          selectedLines: [_line()],
          currency: 'USD',
          onToggle: (_, __) {},
          onQuantityChange: (serviceId, next) => changes.add((serviceId, next)),
        ),
      );

      expect(
        _iconButton(tester, 'Decrease quantity for Consultation').disabled,
        isTrue,
      );

      await tester.tap(find.bySemanticsLabel('Increase quantity for Consultation'));
      await tester.pump();

      expect(changes, contains((service.serviceId, 2)));

      await _pumpWide(
        tester,
        VisitServiceSelectionListView(
          services: [service],
          selectedIds: {service.serviceId},
          selectedLines: [_line(quantity: 99)],
          currency: 'USD',
          onToggle: (_, __) {},
          onQuantityChange: (serviceId, next) => changes.add((serviceId, next)),
        ),
      );

      expect(
        _iconButton(tester, 'Increase quantity for Consultation').disabled,
        isTrue,
      );
    });
  });

  group('VisitServiceSelectionSidebar', () {
    testWidgets('shows empty copy when nothing is selected', (tester) async {
      await _pumpWide(
        tester,
        const VisitServiceSelectionSidebar(
          selectedLines: [],
          subtotal: 0,
          currency: 'USD',
        ),
      );

      expect(
        find.text('No services selected yet. Pick from the catalog.'),
        findsOneWidget,
      );
    });

    testWidgets('shows each selected line and subtotal when populated', (tester) async {
      await _pumpWide(
        tester,
        VisitServiceSelectionSidebar(
          selectedLines: [
            _line(name: 'Consultation'),
            _line(serviceId: 'svc-2', name: 'Labs', quantity: 2),
          ],
          subtotal: 300,
          currency: 'USD',
        ),
      );

      expect(find.text('Consultation'), findsOneWidget);
      expect(find.textContaining('Labs'), findsOneWidget);
      expect(find.textContaining('× 2'), findsOneWidget);
      expect(find.text('Subtotal'), findsOneWidget);
      expect(find.textContaining('USD'), findsWidgets);
    });
  });
}
