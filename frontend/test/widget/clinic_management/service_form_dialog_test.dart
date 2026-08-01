import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/core/ui/theme/app_theme.dart';
import 'package:ai_clinic/features/clinic-management/presentation/components/service_form_dialog.dart';
import 'package:ai_clinic/features/clinic-management/presentation/models/service_form_values.dart';

void main() {
  testWidgets('ServiceFormDialog shows load error instead of spinner', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: ServiceFormDialog(
          open: true,
          onOpenChange: (_) {},
          mode: ServiceFormDialogMode.edit,
          currencyCode: 'USD',
          initialValues: emptyServiceFormValues(),
          loading: false,
          loadError: 'Service unavailable.',
          onSubmit: (_) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Unable to load service'), findsOneWidget);
    expect(find.text('Service unavailable.'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('ServiceFormDialog shows spinner while loading', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: ServiceFormDialog(
          open: true,
          onOpenChange: (_) {},
          mode: ServiceFormDialogMode.edit,
          currencyCode: 'USD',
          initialValues: emptyServiceFormValues(),
          loading: true,
          onSubmit: (_) async {},
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Unable to load service'), findsNothing);
  });

  testWidgets('ServiceFormDialog shows form after loading prop clears', (tester) async {
    final loading = ValueNotifier<bool>(true);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: ValueListenableBuilder<bool>(
          valueListenable: loading,
          builder: (context, isLoading, _) => ServiceFormDialog(
            open: true,
            onOpenChange: (_) {},
            mode: ServiceFormDialogMode.edit,
            currencyCode: 'USD',
            initialValues: const ServiceFormValues(name: 'Consultation', price: 150),
            loading: isLoading,
            onSubmit: (_) async {},
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Consultation'), findsNothing);

    loading.value = false;
    await tester.pump();
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Consultation'), findsOneWidget);
    expect(find.text('Save changes'), findsOneWidget);
  });

  testWidgets('ServiceFormDialog price field keeps focus while typing', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: ServiceFormDialog(
          open: true,
          onOpenChange: (_) {},
          mode: ServiceFormDialogMode.create,
          currencyCode: 'USD',
          initialValues: emptyServiceFormValues(),
          onSubmit: (_) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    final priceField = find.bySemanticsIdentifier('new-service-price');
    expect(priceField, findsOneWidget);

    await tester.tap(priceField);
    await tester.pump();

    final editableTextFinder = find.descendant(of: priceField, matching: find.byType(EditableText));
    final editableText = tester.widget<EditableText>(editableTextFinder);
    expect(editableText.focusNode.hasFocus, isTrue);

    await tester.enterText(editableTextFinder, '125');
    await tester.pump();

    expect(editableText.focusNode.hasFocus, isTrue);
    expect(find.text('125'), findsOneWidget);
    expect(find.text('125.00'), findsNothing);
  });
}
