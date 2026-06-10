import 'package:ai_clinic/app/shell/shell_tokens.dart';
import 'package:ai_clinic/app/shell/widgets/shell_header.dart';
import 'package:ai_clinic/app/shell/widgets/shell_header_icon_button.dart';
import 'package:ai_clinic/app/shell/widgets/shell_header_profile.dart';
import 'package:ai_clinic/core/ui/widgets/input/app_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'shell_test_support.dart';

void main() {
  group('ShellHeader', () {
    testWidgets('fixed height matches ShellTokens.headerHeight', (tester) async {
      await pumpShellWidget(tester, child: const ShellHeader(pageTitle: 'Dashboard'));

      final sizedBox = tester.widget<SizedBox>(find.byType(SizedBox).first);
      expect(sizedBox.height, ShellTokens.headerHeight);
    });

    testWidgets('renders page title when provided', (tester) async {
      await pumpShellWidget(tester, child: const ShellHeader(pageTitle: 'Dashboard'));

      expect(find.text('Dashboard'), findsOneWidget);
    });

    testWidgets('omits title when pageTitle is null', (tester) async {
      await pumpShellWidget(tester, child: const ShellHeader());

      expect(find.text('Dashboard'), findsNothing);
    });

    testWidgets('renders centered search field with hint', (tester) async {
      await pumpShellWidget(tester, child: const ShellHeader(pageTitle: 'Dashboard'));

      expect(find.byType(AppTextInput), findsOneWidget);
      expect(find.text('Search patients, appointments, visits…'), findsOneWidget);
      expect(find.byIcon(Icons.search), findsOneWidget);
    });

    testWidgets('search field max width is constrained', (tester) async {
      await pumpShellWidget(tester, child: const ShellHeader(pageTitle: 'Dashboard'));

      final constrainedBox = tester.widget<ConstrainedBox>(
        find.ancestor(of: find.byType(AppTextInput), matching: find.byType(ConstrainedBox)),
      );
      expect(constrainedBox.constraints.maxWidth, ShellTokens.headerSearchMaxWidth);
    });

    testWidgets('renders ShellHeaderProfile', (tester) async {
      await pumpShellWidget(tester, child: const ShellHeader(pageTitle: 'Dashboard'));

      expect(find.byType(ShellHeaderProfile), findsOneWidget);
      expect(find.text('Alex Morgan'), findsOneWidget);
      expect(find.text('Clinic Administrator'), findsOneWidget);
    });

    testWidgets('renders notifications and settings icon buttons', (tester) async {
      await pumpShellWidget(tester, child: const ShellHeader(pageTitle: 'Dashboard'));

      expect(find.byTooltip('Notifications'), findsOneWidget);
      expect(find.byTooltip('Settings'), findsOneWidget);
      expect(find.byIcon(Icons.notifications_outlined), findsOneWidget);
      expect(find.byIcon(Icons.settings_outlined), findsOneWidget);
      expect(find.byType(ShellHeaderIconButton), findsNWidgets(2));
    });
  });
}
