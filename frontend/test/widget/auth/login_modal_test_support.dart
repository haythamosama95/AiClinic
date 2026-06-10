import 'package:ai_clinic/core/ui/theme/app_theme.dart';
import 'package:ai_clinic/core/ui/theme/forui_app_scope.dart';
import 'package:ai_clinic/features/auth/presentation/widgets/login_modal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const loginStatusPanelKey = ValueKey('login-status-panel');

/// Finds visible text inside the animated login status panel.
Finder visiblePanelText(String text) {
  return find.descendant(
    of: find.descendant(of: find.byKey(loginStatusPanelKey), matching: find.byType(FadeTransition)),
    matching: find.textContaining(text),
  );
}

Finder get loginStatusFadeTransition {
  return find.descendant(of: find.byKey(loginStatusPanelKey), matching: find.byType(FadeTransition));
}

/// Pumps [LoginModal] inside the app theme shell at [size].
Future<void> pumpLoginModal(
  WidgetTester tester, {
  required Widget child,
  Size size = const Size(1280, 900),
  bool settle = true,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      builder: (context, appChild) => ForuiAppScope(child: appChild ?? const SizedBox.shrink()),
      home: Scaffold(body: child),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

Future<void> pumpLoginModalWidget(
  WidgetTester tester, {
  bool initialShowForgotPasswordInfo = false,
  String? errorMessage,
  bool isSubmitting = false,
  VoidCallback? onClose,
  VoidCallback? onDismissSignInError,
  void Function(String username, String password)? onSubmit,
  Size size = const Size(1280, 900),
  bool settle = true,
}) {
  return pumpLoginModal(
    tester,
    size: size,
    settle: settle,
    child: LoginModal(
      initialShowForgotPasswordInfo: initialShowForgotPasswordInfo,
      errorMessage: errorMessage,
      isSubmitting: isSubmitting,
      onClose: onClose,
      onDismissSignInError: onDismissSignInError,
      onSubmit: onSubmit,
    ),
  );
}
