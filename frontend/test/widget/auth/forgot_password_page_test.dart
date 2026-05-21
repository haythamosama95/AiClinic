import 'package:ai_clinic/features/auth/presentation/pages/forgot_password_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows administrator-mediated recovery message only', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: ForgotPasswordPage()));

    expect(find.textContaining('administrator'), findsOneWidget);
    expect(find.textContaining('Contact your clinic administrator'), findsOneWidget);
    expect(find.byType(TextFormField), findsNothing);
  });
}
