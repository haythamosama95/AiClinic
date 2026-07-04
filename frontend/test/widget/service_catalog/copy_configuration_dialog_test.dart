import 'package:ai_clinic/core/ui/theme/theme.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/service_catalog/data/service_catalog_repository.dart';
import 'package:ai_clinic/features/service_catalog/presentation/widgets/copy_configuration_dialog.dart';
import 'package:ai_clinic/features/settings/domain/branch_list_item.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_postgrest_rpc.dart';

void main() {
  const branches = [
    BranchListItem(id: 'branch-a', name: 'Branch A', isActive: true),
    BranchListItem(id: 'branch-b', name: 'Branch B', isActive: true),
    BranchListItem(id: 'branch-c', name: 'Branch C', isActive: true),
  ];

  group('CopyConfigurationDialog', () {
    testWidgets('replace mode requires confirmation and cancel keeps dialog open', (tester) async {
      final rpcClient = RpcCaptureSupabaseClient();
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        ProviderScope(
          overrides: [serviceCatalogRepositoryProvider.overrideWithValue(ServiceCatalogRepository(rpcClient))],
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(body: CopyConfigurationDialog(branches: branches)),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Branch A').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Branch B').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Replace').first);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Copy configuration'));
      await tester.pumpAndSettle();

      expect(find.text('Replace target configuration?'), findsOneWidget);

      await tester.tap(find.text('Cancel').last);
      await tester.pumpAndSettle();

      expect(find.text('Copy branch configuration'), findsOneWidget);
      expect(rpcClient.lastFunction, isNull);
    });

    testWidgets('cancel closes dialog without applying changes', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.light(),
            home: Builder(
              builder: (context) {
                return Scaffold(
                  body: AppButton(
                    label: 'Open',
                    onPressed: () => CopyConfigurationDialog.show(context, branches: branches),
                  ),
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel').first);
      await tester.pumpAndSettle();

      expect(find.text('Copy branch configuration'), findsNothing);
    });
  });
}
