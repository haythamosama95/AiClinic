import 'package:ai_clinic/app/shell/shell_tokens.dart';
import 'package:ai_clinic/app/shell/widgets/shell_header_profile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'shell_test_support.dart';

void main() {
  group('ShellHeaderProfile', () {
    testWidgets('renders default name and role', (tester) async {
      await pumpShellWidget(tester, child: const ShellHeaderProfile());

      expect(find.text('Alex Morgan'), findsOneWidget);
      expect(find.text('Clinic Administrator'), findsOneWidget);
    });

    testWidgets('avatar shows initials from name', (tester) async {
      await pumpShellWidget(tester, child: const ShellHeaderProfile(name: 'Alex Morgan'));

      expect(find.text('AM'), findsOneWidget);
    });

    testWidgets('single-word name uses first character', (tester) async {
      await pumpShellWidget(tester, child: const ShellHeaderProfile(name: 'Admin'));

      expect(find.text('A'), findsOneWidget);
    });

    testWidgets('empty name shows question mark', (tester) async {
      await pumpShellWidget(tester, child: const ShellHeaderProfile(name: '   '));

      expect(find.text('?'), findsOneWidget);
    });

    testWidgets('avatar size matches headerAvatarSize', (tester) async {
      await pumpShellWidget(tester, child: const ShellHeaderProfile());

      final avatar = tester.widget<CircleAvatar>(find.byType(CircleAvatar));
      expect(avatar.radius, ShellTokens.headerAvatarSize / 2);
    });
  });
}
