import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/setup/domain/bootstrap_field_options.dart';
import 'package:ai_clinic/features/setup/presentation/widgets/organization_form_fields.dart';
import 'package:ai_clinic/features/setup/presentation/widgets/setup_form_grid.dart';

void main() {
  group('OrganizationFormFields', () {
    late TextEditingController nameController;
    late TextEditingController logoUrlController;

    setUp(() {
      nameController = TextEditingController();
      logoUrlController = TextEditingController();
    });

    tearDown(() {
      nameController.dispose();
      logoUrlController.dispose();
    });

    Widget buildSubject({
      OrganizationFormFieldsMode mode = OrganizationFormFieldsMode.create,
      bool isEditing = false,
      OrganizationFormExistingData? existing,
    }) {
      return MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              return OrganizationFormFields(
                mode: mode,
                isEditing: isEditing,
                existing: existing,
                nameController: nameController,
                logoUrlController: logoUrlController,
                currency: BootstrapCurrencyOptions.defaultCode,
                timezone: BootstrapTimezoneOptions.defaultZone,
                onCurrencyChanged: (_) => setState(() {}),
                onTimezoneChanged: (_) => setState(() {}),
                enabled: true,
              );
            },
          ),
        ),
      );
    }

    testWidgets('create mode shows editable fields', (tester) async {
      await tester.pumpWidget(buildSubject());

      expect(find.text('Organization name *'), findsOneWidget);
      expect(find.byType(AppTextField), findsWidgets);
      expect(find.text('This value has not been set before.'), findsNothing);
    });

    testWidgets('edit mode shows read-only values until editing', (tester) async {
      await tester.pumpWidget(
        buildSubject(
          mode: OrganizationFormFieldsMode.edit,
          existing: const OrganizationFormExistingData(
            name: 'Demo Clinic',
            logoUrl: 'https://example.com/logo.png',
            currencyCode: 'EGP',
            timezone: 'Africa/Cairo',
          ),
        ),
      );

      expect(find.text('Demo Clinic'), findsOneWidget);
      expect(find.text('EGP'), findsOneWidget);
      expect(find.text('Africa/Cairo'), findsOneWidget);
      expect(find.text('Organization name *'), findsNothing);
    });

    testWidgets('edit mode lays out four fields in one horizontal row on wide screens', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        buildSubject(
          mode: OrganizationFormFieldsMode.edit,
          existing: const OrganizationFormExistingData(
            name: 'Demo Clinic',
            logoUrl: 'https://example.com/logo.png',
            currencyCode: 'EGP',
            timezone: 'Africa/Cairo',
          ),
        ),
      );

      final grid = tester.widget<SetupFormGrid>(find.byType(SetupFormGrid));
      expect(grid.columns, 4);

      final row = tester.widget<Row>(find.descendant(of: find.byType(SetupFormGrid), matching: find.byType(Row)));
      expect(row.children.whereType<Expanded>().length, 4);
    });

    testWidgets('edit mode with isEditing shows editable fields', (tester) async {
      await tester.pumpWidget(
        buildSubject(
          mode: OrganizationFormFieldsMode.edit,
          isEditing: true,
          existing: const OrganizationFormExistingData(name: 'Demo Clinic'),
        ),
      );

      expect(find.text('Organization name *'), findsOneWidget);
      expect(find.text('Demo Clinic'), findsNothing);
    });
  });
}
