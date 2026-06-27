import 'package:ai_clinic/app/shell/shell_tokens.dart';
import 'package:ai_clinic/app/shell/widgets/shell_header_profile.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/auth_test_support.dart';
import 'shell_test_support.dart';

void main() {
  group('ShellHeaderProfileView', () {
    testWidgets('renders name and role', (tester) async {
      await pumpShellWidget(
        tester,
        child: const ShellHeaderProfileView(name: 'Alex Morgan', role: 'Administrator'),
      );

      expect(find.text('Alex Morgan'), findsOneWidget);
      expect(find.text('Administrator'), findsOneWidget);
    });

    testWidgets('avatar shows initials from name', (tester) async {
      await pumpShellWidget(
        tester,
        child: const ShellHeaderProfileView(name: 'Alex Morgan', role: 'Administrator'),
      );

      expect(find.text('AM'), findsOneWidget);
    });

    testWidgets('single-word name uses first character', (tester) async {
      await pumpShellWidget(
        tester,
        child: const ShellHeaderProfileView(name: 'Admin', role: 'Administrator'),
      );

      expect(find.text('A'), findsOneWidget);
    });

    testWidgets('empty name shows question mark', (tester) async {
      await pumpShellWidget(
        tester,
        child: const ShellHeaderProfileView(name: '   ', role: 'Administrator'),
      );

      expect(find.text('?'), findsOneWidget);
    });

    testWidgets('avatar size matches headerAvatarSize', (tester) async {
      await pumpShellWidget(
        tester,
        child: const ShellHeaderProfileView(name: 'Alex Morgan', role: 'Administrator'),
      );

      final avatar = tester.widget<CircleAvatar>(find.byType(CircleAvatar));
      expect(avatar.radius, ShellTokens.headerAvatarSize / 2);
    });
  });

  group('ShellHeaderProfile', () {
    testWidgets('renders current session staff profile', (tester) async {
      await pumpShellWidget(
        tester,
        overrides: [
          shellAuthenticatedSessionOverride(
            context: sampleAuthSessionContext().copyWith(
              staffProfile: const StaffProfile(
                staffMemberId: 'staff-1',
                fullName: 'Dr. Samira Khan',
                role: StaffRole.doctor,
                isBootstrapAdmin: false,
                isActive: true,
              ),
            ),
          ),
        ],
        child: const ShellHeaderProfile(),
      );

      expect(find.text('Dr. Samira Khan'), findsOneWidget);
      expect(find.text('Doctor'), findsOneWidget);
      expect(find.text('DK'), findsOneWidget);
    });

    testWidgets('renders nothing without authenticated session', (tester) async {
      await pumpShellWidget(tester, child: const ShellHeaderProfile());

      expect(find.byType(ShellHeaderProfileView), findsNothing);
    });
  });
}
