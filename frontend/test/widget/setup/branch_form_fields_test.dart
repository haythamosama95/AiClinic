import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';

import 'package:ai_clinic/core/ui/theme/app_theme.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/setup/presentation/widgets/branch_form_fields.dart';
import 'package:ai_clinic/features/setup/presentation/widgets/setup_form_grid.dart';

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

    Widget buildSubject({
      BranchFormFieldsMode mode = BranchFormFieldsMode.create,
      bool isEditing = false,
      BranchFormExistingData? existing,
    }) {
      return MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: Form(
              child: BranchFormFields(
                mode: mode,
                isEditing: isEditing,
                existing: existing,
                nameController: nameController,
                codeController: codeController,
                addressController: addressController,
                phoneController: phoneController,
                mapsUrlController: mapsUrlController,
                enabled: true,
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('create mode shows editable fields', (tester) async {
      await tester.pumpWidget(buildSubject());

      expect(find.text('Branch name *'), findsOneWidget);
      expect(find.text('Branch code *'), findsOneWidget);
      expect(find.byType(AppTextField), findsWidgets);
      expect(find.widgetWithText(AppButton, 'Working hours'), findsNothing);
    });

    testWidgets('create mode shows working hours beside maps URL when configured', (tester) async {
      await tester.binding.setSurfaceSize(const Size(920, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: Form(
                child: BranchFormFields(
                  mode: BranchFormFieldsMode.create,
                  nameController: nameController,
                  codeController: codeController,
                  addressController: addressController,
                  phoneController: phoneController,
                  mapsUrlController: mapsUrlController,
                  enabled: true,
                  onWorkingHours: () {},
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.text('Working hours *'), findsOneWidget);
      expect(find.widgetWithText(FButton, 'Working hours'), findsOneWidget);
      expect(find.byIcon(Icons.check), findsNothing);
      expect(find.byType(SetupFormGrid), findsOneWidget);
    });

    testWidgets('create mode shows check mark when working hours are configured', (tester) async {
      await tester.binding.setSurfaceSize(const Size(920, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: Form(
                child: BranchFormFields(
                  mode: BranchFormFieldsMode.create,
                  nameController: nameController,
                  codeController: codeController,
                  addressController: addressController,
                  phoneController: phoneController,
                  mapsUrlController: mapsUrlController,
                  enabled: true,
                  workingHoursConfigured: true,
                  onWorkingHours: () {},
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.check), findsOneWidget);
    });

    testWidgets('create mode shows validation error when working hours are required but missing', (tester) async {
      final formKey = GlobalKey<FormState>();

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: Form(
              key: formKey,
              child: BranchFormFields(
                mode: BranchFormFieldsMode.create,
                nameController: nameController,
                codeController: codeController,
                addressController: addressController,
                phoneController: phoneController,
                mapsUrlController: mapsUrlController,
                enabled: true,
                onWorkingHours: () {},
              ),
            ),
          ),
        ),
      );

      expect(formKey.currentState!.validate(), isFalse);
      await tester.pump();

      expect(find.text('Working hours are required'), findsOneWidget);
    });

    testWidgets('edit mode uses a two-column grid inside settings cards', (tester) async {
      await tester.binding.setSurfaceSize(const Size(480, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        buildSubject(
          mode: BranchFormFieldsMode.edit,
          existing: const BranchFormExistingData(
            name: 'Main Branch',
            code: 'MAIN',
            address: '123 Street',
            phone: '1234567890',
            mapsUrl: 'https://maps.example.com',
          ),
        ),
      );

      final grid = tester.widget<SetupFormGrid>(find.byType(SetupFormGrid));
      expect(grid.columns, 2);
      expect(grid.compactBreakpoint, SetupFormGrid.settingsCardBreakpoint);

      final rows = tester.widgetList<Row>(find.descendant(of: find.byType(SetupFormGrid), matching: find.byType(Row)));
      expect(rows.any((row) => row.children.whereType<Expanded>().length == 2), isTrue);
    });

    testWidgets('edit mode shows read-only values until editing', (tester) async {
      await tester.pumpWidget(
        buildSubject(
          mode: BranchFormFieldsMode.edit,
          existing: const BranchFormExistingData(
            name: 'Main Branch',
            code: 'MAIN',
            address: '123 Street',
            phone: '1234567890',
            mapsUrl: 'https://maps.example.com',
          ),
        ),
      );

      expect(find.text('Main Branch'), findsOneWidget);
      expect(find.text('MAIN'), findsOneWidget);
      expect(find.text('123 Street'), findsOneWidget);
      expect(find.text('Branch name *'), findsNothing);
      expect(find.text('Working hours'), findsNothing);
    });

    testWidgets('readOnly mode never shows editable fields', (tester) async {
      await tester.pumpWidget(
        buildSubject(
          mode: BranchFormFieldsMode.readOnly,
          existing: const BranchFormExistingData(name: 'Main Branch', code: 'MAIN'),
        ),
      );

      expect(find.text('Main Branch'), findsOneWidget);
      expect(find.text('Branch name *'), findsNothing);
      expect(find.text('Working hours'), findsNothing);
    });
  });
}
