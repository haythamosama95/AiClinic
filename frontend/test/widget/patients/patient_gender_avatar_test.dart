import 'package:ai_clinic/core/ui/theme/app_theme.dart';
import 'package:ai_clinic/core/ui/theme/forui_app_scope.dart';
import 'package:ai_clinic/features/patients/domain/patient_gender.dart';
import 'package:ai_clinic/features/patients/presentation/widgets/patient_gender_avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PatientGenderAvatar medium-severity regressions', () {
    test('M3: decode cache size matches display pixels at device ratio', () {
      expect(PatientGenderAvatar.decodeCacheSize(88, 1), 88);
      expect(PatientGenderAvatar.decodeCacheSize(88, 2), 176);
    });
  });

  group('PatientGenderAvatar low-severity regressions', () {
    group('UI-002 — Avatar null gender', () {
      testWidgets('null gender shows neutral person icon instead of male avatar', (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light(),
            builder: (context, child) => ForuiAppScope(child: child ?? const SizedBox.shrink()),
            home: const Scaffold(body: PatientGenderAvatar(gender: null, size: 72)),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byIcon(Icons.person_outline), findsOneWidget);
        expect(find.byIcon(Icons.face_outlined), findsNothing);
        expect(find.byType(Image), findsNothing);
      });
    });

    testWidgets('L4: male gender still uses male portrait asset', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          builder: (context, child) => ForuiAppScope(child: child ?? const SizedBox.shrink()),
          home: const Scaffold(body: PatientGenderAvatar(gender: PatientGender.male, size: 72)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(Image), findsOneWidget);
      expect(find.byIcon(Icons.person_outline), findsNothing);
    });
  });
}
