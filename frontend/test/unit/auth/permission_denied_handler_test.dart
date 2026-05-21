import 'package:ai_clinic/core/auth/permission_denied_handler.dart';
import 'package:ai_clinic/core/auth/permission_service.dart';
import 'package:ai_clinic/features/auth/domain/permission_keys.dart';
import 'package:ai_clinic/testing/auth_test_support.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PermissionDeniedHandler', () {
    testWidgets('show displays default snackbar message', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(onPressed: () => PermissionDeniedHandler.show(context), child: const Text('deny')),
            ),
          ),
        ),
      );

      await tester.tap(find.text('deny'));
      await tester.pump();

      expect(find.text(PermissionDeniedHandler.defaultMessage), findsOneWidget);
    });

    testWidgets('runIfPermitted runs action when permission granted', (tester) async {
      var ran = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              final permissions = PermissionService(
                sampleAuthSessionContext(permissions: {PermissionKeys.patientsView}),
              );
              return Scaffold(
                body: ElevatedButton(
                  onPressed: () => PermissionDeniedHandler.runIfPermitted(
                    context,
                    permissions: permissions,
                    permissionKey: PermissionKeys.patientsView,
                    action: () => ran = true,
                  ),
                  child: const Text('go'),
                ),
              );
            },
          ),
        ),
      );

      await tester.tap(find.text('go'));
      await tester.pump();

      expect(ran, isTrue);
      expect(find.text(PermissionDeniedHandler.defaultMessage), findsNothing);
    });

    testWidgets('runIfPermitted shows snackbar when permission denied', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              final permissions = PermissionService(sampleAuthSessionContext(permissions: {}));
              return Scaffold(
                body: ElevatedButton(
                  onPressed: () => PermissionDeniedHandler.runIfPermitted(
                    context,
                    permissions: permissions,
                    permissionKey: PermissionKeys.manageStaff,
                    action: () {},
                  ),
                  child: const Text('blocked'),
                ),
              );
            },
          ),
        ),
      );

      await tester.tap(find.text('blocked'));
      await tester.pump();

      expect(find.text(PermissionDeniedHandler.defaultMessage), findsOneWidget);
    });

    testWidgets('show is safe when ScaffoldMessenger is absent', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              return ElevatedButton(
                onPressed: () => PermissionDeniedHandler.show(context),
                child: const Text('orphan'),
              );
            },
          ),
        ),
      );

      await tester.tap(find.text('orphan'));
      await tester.pump();

      expect(tester.takeException(), isNull);
    });
  });
}
