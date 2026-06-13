import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/auth/domain/staff_username.dart';
import 'package:ai_clinic/features/setup/domain/branch_summary.dart';
import 'package:ai_clinic/features/setup/domain/staff_password_validation.dart';
import 'package:ai_clinic/features/setup/presentation/widgets/staff_form_fields.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('StaffFormFields create mode', () {
    late TextEditingController usernameController;
    late TextEditingController fullNameController;
    late TextEditingController phoneController;
    late TextEditingController passwordController;

    setUp(() {
      usernameController = TextEditingController();
      fullNameController = TextEditingController();
      phoneController = TextEditingController();
      passwordController = TextEditingController();
    });

    tearDown(() {
      usernameController.dispose();
      fullNameController.dispose();
      phoneController.dispose();
      passwordController.dispose();
    });

    Future<void> pumpFields(
      WidgetTester tester, {
      StaffFormFieldsMode mode = StaffFormFieldsMode.create,
      StaffFormExistingData? existing,
      bool showBranchAssignments = true,
      List<StaffRole> selectableRoles = const [
        StaffRole.administrator,
        StaffRole.doctor,
        StaffRole.receptionist,
        StaffRole.labStaff,
      ],
      StaffRole? selectedRole,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: StaffFormFields(
                mode: mode,
                usernameController: usernameController,
                fullNameController: fullNameController,
                phoneController: phoneController,
                passwordController: passwordController,
                existing: existing,
                selectableRoles: selectableRoles,
                selectedRole: selectedRole ?? StaffRole.receptionist,
                onRoleChanged: (_) {},
                branchIds: const ['branch-1'],
                branchById: const {
                  'branch-1': BranchSummary(
                    id: 'branch-1',
                    name: 'Main',
                    code: 'MAIN',
                    address: '123 Street',
                    phone: '201000000000',
                    mapsUrl: 'https://maps.example.com/main',
                  ),
                },
                selectedBranchIds: const {'branch-1'},
                primaryBranchId: 'branch-1',
                onBranchChecked: (_, _) {},
                onPrimaryBranchChanged: (_) {},
                showBranchAssignments: showBranchAssignments,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('create mode shows username password role fields', (tester) async {
      await pumpFields(tester);

      expect(find.widgetWithText(AppTextField, 'Username *'), findsOneWidget);
      expect(find.widgetWithText(AppTextField, 'Initial password *'), findsOneWidget);
      expect(find.text('Role *'), findsOneWidget);
    });

    testWidgets('password obscured by default with visibility toggle', (tester) async {
      await pumpFields(tester);

      final passwordField = tester.widget<AppTextField>(find.widgetWithText(AppTextField, 'Initial password *'));
      expect(passwordField.obscureText, isTrue);

      await tester.tap(find.byIcon(Icons.visibility_outlined));
      await tester.pump();

      final revealed = tester.widget<AppTextField>(find.widgetWithText(AppTextField, 'Initial password *'));
      expect(revealed.obscureText, isFalse);
    });

    testWidgets('password requirements hint matches backend', (tester) async {
      await pumpFields(tester);

      expect(find.textContaining(StaffPasswordValidation.initialPasswordRequirements), findsOneWidget);
      expect(find.textContaining('digit'), findsNothing);
    });

    testWidgets('role dropdown lists only selectableRoles without owner', (tester) async {
      await pumpFields(tester);

      expect(StaffFormFields.roleLabel(StaffRole.administrator), 'Administrator');
      expect(StaffFormFields.roleLabel(StaffRole.doctor), 'Doctor');
      expect(StaffFormFields.roleLabel(StaffRole.receptionist), 'Receptionist');
      expect(StaffFormFields.roleLabel(StaffRole.labStaff), 'Lab staff');
      expect(find.text('Owner'), findsNothing);
    });

    testWidgets('role label for administrator is Administrator not Owner', (tester) async {
      expect(StaffFormFields.roleLabel(StaffRole.administrator), 'Administrator');
    });

    testWidgets('username validation rejects @ and short names', (tester) async {
      await pumpFields(tester);

      expect(validateStaffUsername('ab'), isNotNull);
      expect(validateStaffUsername('user@clinic'), isNotNull);
      expect(validateStaffUsername('valid_user'), isNull);
    });

    testWidgets('setup wizard hides branch assignment controls when configured', (tester) async {
      await pumpFields(tester, showBranchAssignments: false);

      expect(find.text('Branch assignments *'), findsNothing);
      expect(find.text('Role *'), findsOneWidget);
    });
  });

  group('StaffFormFields edit mode', () {
    testWidgets('edit mode shows editable fields and credential inputs', (tester) async {
      final fullNameController = TextEditingController(text: 'Existing Name');
      final phoneController = TextEditingController(text: '201000000000');
      final usernameController = TextEditingController(text: 'staff1');
      final passwordController = TextEditingController();

      addTearDown(() {
        fullNameController.dispose();
        phoneController.dispose();
        usernameController.dispose();
        passwordController.dispose();
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: StaffFormFields(
                mode: StaffFormFieldsMode.edit,
                usernameController: usernameController,
                fullNameController: fullNameController,
                phoneController: phoneController,
                passwordController: passwordController,
                showCredentials: true,
                existing: const StaffFormExistingData(
                  fullName: 'Existing Name',
                  phone: '201000000000',
                  role: StaffRole.doctor,
                ),
                selectableRoles: const [StaffRole.doctor, StaffRole.receptionist],
                selectedRole: StaffRole.doctor,
                onRoleChanged: (_) {},
                branchIds: const ['branch-1'],
                branchById: const {
                  'branch-1': BranchSummary(
                    id: 'branch-1',
                    name: 'Main',
                    code: 'MAIN',
                    address: '123 Street',
                    phone: '201000000000',
                    mapsUrl: 'https://maps.example.com/main',
                  ),
                },
                selectedBranchIds: const {'branch-1'},
                primaryBranchId: 'branch-1',
                onBranchChecked: (_, _) {},
                onPrimaryBranchChanged: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.widgetWithText(AppTextField, 'Full name *'), findsOneWidget);
      expect(find.widgetWithText(AppTextField, 'Username *'), findsOneWidget);
      expect(find.widgetWithText(AppTextField, 'New password'), findsOneWidget);
      expect(find.text('Modify'), findsNothing);

      final passwordField = tester.widget<AppTextField>(find.widgetWithText(AppTextField, 'New password'));
      expect(passwordField.obscureText, isTrue);

      await tester.tap(find.byIcon(Icons.visibility_outlined));
      await tester.pump();

      final revealed = tester.widget<AppTextField>(find.widgetWithText(AppTextField, 'New password'));
      expect(revealed.obscureText, isFalse);
    });
  });
}
