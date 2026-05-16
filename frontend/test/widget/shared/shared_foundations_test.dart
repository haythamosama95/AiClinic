import 'package:ai_clinic/app/theme/app_theme.dart';
import 'package:ai_clinic/core/errors/failures.dart';
import 'package:ai_clinic/core/widgets/app_button.dart';
import 'package:ai_clinic/core/widgets/app_card.dart';
import 'package:ai_clinic/core/widgets/app_data_table.dart';
import 'package:ai_clinic/core/widgets/app_loading_state.dart';
import 'package:ai_clinic/core/widgets/error_state_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget wrap(Widget child) {
    return MaterialApp(
      theme: AppTheme.lightTheme(),
      home: Scaffold(body: child),
    );
  }

  group('Shared foundations', () {
    testWidgets('AppButton renders primary label and respects loading state', (tester) async {
      await tester.pumpWidget(wrap(const AppButton(label: 'Save changes', isLoading: true)));

      expect(find.byType(FilledButton), findsOneWidget);
      expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('AppCard shows title and child content', (tester) async {
      await tester.pumpWidget(wrap(const AppCard(title: 'Profile', child: Text('Card body'))));

      expect(find.text('Profile'), findsOneWidget);
      expect(find.text('Card body'), findsOneWidget);
    });

    testWidgets('AppLoadingState shows title and optional message', (tester) async {
      await tester.pumpWidget(wrap(const AppLoadingState(title: 'Loading', message: 'Please wait')));

      expect(find.text('Loading'), findsOneWidget);
      expect(find.text('Please wait'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('ErrorStatePanel shows failure details and retry action', (tester) async {
      var retried = false;

      await tester.pumpWidget(
        wrap(ErrorStatePanel(failure: const ConnectivityFailure('Gateway unreachable'), onRetry: () => retried = true)),
      );

      expect(find.text('Connectivity issue'), findsOneWidget);
      expect(find.text('Gateway unreachable'), findsOneWidget);

      await tester.tap(find.text('Try again'));
      await tester.pump();

      expect(retried, isTrue);
    });

    testWidgets('AppDataTable renders headers and row cells', (tester) async {
      await tester.pumpWidget(
        wrap(
          const AppDataTable(
            columns: [
              AppDataColumn(label: 'Name'),
              AppDataColumn(label: 'Role'),
            ],
            rows: [
              ['Reception', 'Staff'],
            ],
          ),
        ),
      );

      expect(find.text('Name'), findsOneWidget);
      expect(find.text('Reception'), findsOneWidget);
    });

    testWidgets('AppDataTable shows empty message when there are no rows', (tester) async {
      await tester.pumpWidget(
        wrap(
          const AppDataTable(
            columns: [AppDataColumn(label: 'Name')],
            rows: [],
            emptyMessage: 'Nothing here yet',
          ),
        ),
      );

      expect(find.text('Nothing here yet'), findsOneWidget);
    });
  });
}
