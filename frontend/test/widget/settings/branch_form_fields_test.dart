import 'package:ai_clinic/features/settings/presentation/widgets/branch_form_fields.dart';
import 'package:ai_clinic/features/settings/domain/branch_working_schedule.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BranchFormFields', () {
    late TextEditingController nameController;
    late TextEditingController codeController;
    late TextEditingController addressController;
    late TextEditingController phoneController;
    late TextEditingController mapsUrlController;
    late Map<BranchWeekday, bool> dayEnabled;
    late Map<BranchWeekday, TextEditingController> openControllers;
    late Map<BranchWeekday, TextEditingController> closeControllers;

    setUp(() {
      nameController = TextEditingController();
      codeController = TextEditingController();
      addressController = TextEditingController();
      phoneController = TextEditingController();
      mapsUrlController = TextEditingController();
      dayEnabled = {for (final day in BranchWeekday.values) day: day != BranchWeekday.sunday};
      openControllers = {for (final day in BranchWeekday.values) day: TextEditingController(text: '09:00')};
      closeControllers = {for (final day in BranchWeekday.values) day: TextEditingController(text: '17:00')};
      dayEnabled[BranchWeekday.sunday] = false;
      openControllers[BranchWeekday.sunday]!.clear();
      closeControllers[BranchWeekday.sunday]!.clear();
    });

    tearDown(() {
      nameController.dispose();
      codeController.dispose();
      addressController.dispose();
      phoneController.dispose();
      mapsUrlController.dispose();
      for (final controller in openControllers.values) {
        controller.dispose();
      }
      for (final controller in closeControllers.values) {
        controller.dispose();
      }
    });

    Widget host({required BranchFormFieldsMode mode, BranchFormExistingData? existing}) {
      return MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Form(
              child: BranchFormFields(
                mode: mode,
                nameController: nameController,
                codeController: codeController,
                addressController: addressController,
                phoneController: phoneController,
                mapsUrlController: mapsUrlController,
                dayEnabled: dayEnabled,
                openTimeControllers: openControllers,
                closeTimeControllers: closeControllers,
                onDayEnabledChanged: (day, enabled) => dayEnabled[day] = enabled,
                existing: existing,
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('create mode uses direct text fields', (tester) async {
      await tester.pumpWidget(host(mode: BranchFormFieldsMode.create));
      await tester.pumpAndSettle();

      expect(find.byType(TextFormField), findsNWidgets(19));
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

    testWidgets('working hours fields are read-only clock pickers', (tester) async {
      await tester.pumpWidget(host(mode: BranchFormFieldsMode.create));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.access_time), findsNWidgets(14));
    });
  });
}
