import 'package:ai_clinic/core/ui/theme/app_theme.dart';
import 'package:ai_clinic/core/ui/theme/forui_app_scope.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/settings/data/role_permissions_repository.dart';
import 'package:ai_clinic/features/settings/presentation/pages/role_permissions_page.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/auth_test_support.dart';
import '../../support/settings_table_test_client.dart';

void main() {
  group('RolePermissionsMatrix', () {
    List<Map<String, dynamic>> largeMatrixRows() {
      const keys = [
        'settings.manage_branches',
        'settings.manage_staff',
        'settings.manage_organization',
        'patients.view',
        'patients.create',
        'patients.edit',
        'patients.delete',
        'billing.view',
        'billing.manage',
        'ai.chat',
        'ai.summarize',
        'appointments.view',
        'appointments.manage',
      ];
      const roles = ['administrator', 'doctor', 'receptionist', 'lab_staff'];

      return [
        for (final key in keys)
          for (final role in roles)
            {'role': role, 'permission_key': key, 'is_granted': role == 'administrator', 'is_deleted': false},
      ];
    }

    Future<void> pumpMatrix(WidgetTester tester, {Size size = const Size(900, 640)}) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authSessionProvider.overrideWith(_TestAuthSessionNotifier.new),
            rolePermissionsRepositoryProvider.overrideWithValue(
              RolePermissionsRepositoryImpl(SettingsTableTestClient({'roles_permissions': largeMatrixRows()})),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            builder: (context, child) => ForuiAppScope(child: child ?? const SizedBox.shrink()),
            home: Scaffold(
              body: SizedBox(width: size.width, height: size.height, child: const RolePermissionsPage(embedded: true)),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
    }

    Finder horizontalScrollables() {
      return find.byWidgetPredicate(
        (widget) =>
            widget is Scrollable &&
            (widget.axisDirection == AxisDirection.left || widget.axisDirection == AxisDirection.right),
      );
    }

    testWidgets('horizontal scroll syncs header and body', (tester) async {
      await pumpMatrix(tester, size: const Size(360, 640));

      final scrollables = horizontalScrollables();
      expect(scrollables, findsAtLeastNWidgets(2));

      final bodyPosition = Scrollable.of(tester.element(scrollables.last)).position;
      bodyPosition.jumpTo(140);
      await tester.pump();

      final headerPosition = Scrollable.of(tester.element(scrollables.first)).position;
      expect(headerPosition.pixels, closeTo(bodyPosition.pixels, 1));
    });

    testWidgets('pinned column headers stay visible on vertical scroll', (tester) async {
      await pumpMatrix(tester);

      expect(find.text('Permission'), findsOneWidget);
      expect(find.text('Administrator'), findsOneWidget);

      final verticalPosition = tester
          .widgetList<Scrollable>(find.byType(Scrollable))
          .map((scrollable) => scrollable.controller?.position)
          .whereType<ScrollPosition>()
          .firstWhere((position) => position.axisDirection == AxisDirection.down);

      verticalPosition.jumpTo(240);
      await tester.pumpAndSettle();

      expect(find.text('Permission'), findsOneWidget);
      expect(find.text('Administrator'), findsOneWidget);
    });
  });
}

class _TestAuthSessionNotifier extends TestAuthSessionNotifier {
  @override
  AuthSessionState build() {
    return AuthSessionState(
      status: AuthSessionStatus.authenticated,
      context: sampleAuthSessionContext(role: StaffRole.administrator),
    );
  }
}
