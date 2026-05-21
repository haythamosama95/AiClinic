import 'package:ai_clinic/features/settings/presentation/widgets/branch_form_fields.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BranchFormFields', () {
    late TextEditingController nameController;
    late TextEditingController codeController;
    late TextEditingController addressController;
    late TextEditingController phoneController;
    late TextEditingController mapsUrlController;

    setUp(() {
      nameController = TextEditingController();
      codeController = TextEditingController();
      addressController = TextEditingController();
      phoneController = TextEditingController();
      mapsUrlController = TextEditingController();
    });

    tearDown(() {
      nameController.dispose();
      codeController.dispose();
      addressController.dispose();
      phoneController.dispose();
      mapsUrlController.dispose();
    });

    Widget host({required BranchFormFieldsMode mode, BranchFormExistingData? existing}) {
      return MaterialApp(
        home: Scaffold(
          body: Form(
            child: BranchFormFields(
              mode: mode,
              nameController: nameController,
              codeController: codeController,
              addressController: addressController,
              phoneController: phoneController,
              mapsUrlController: mapsUrlController,
              existing: existing,
            ),
          ),
        ),
      );
    }

    testWidgets('create mode uses direct text fields', (tester) async {
      await tester.pumpWidget(host(mode: BranchFormFieldsMode.create));
      await tester.pumpAndSettle();

      expect(find.byType(TextFormField), findsNWidgets(5));
      expect(find.text('Modify'), findsNothing);
    });

    testWidgets('all modes show info tooltips on every field', (tester) async {
      for (final mode in BranchFormFieldsMode.values) {
        await tester.pumpWidget(host(mode: mode));
        await tester.pumpAndSettle();
        expect(find.byIcon(Icons.info_outline), findsNWidgets(5), reason: 'mode $mode');
      }
    });

    testWidgets('edit mode shows Modify for stored values', (tester) async {
      await tester.pumpWidget(
        host(
          mode: BranchFormFieldsMode.edit,
          existing: const BranchFormExistingData(name: 'Main', code: 'main'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Main'), findsOneWidget);
      expect(find.text('Modify'), findsNWidgets(5));
    });

    testWidgets('bootstrap mode requires branch name', (tester) async {
      await tester.pumpWidget(host(mode: BranchFormFieldsMode.bootstrap));
      await tester.pumpAndSettle();

      final form = tester.state<FormState>(find.byType(Form));
      expect(form.validate(), isFalse);
      await tester.pumpAndSettle();

      expect(find.text('Branch name is required.'), findsOneWidget);
    });
  });
}
