import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/core/errors/failures.dart';
import 'package:ai_clinic/core/widgets/app_button.dart';
import 'package:ai_clinic/core/widgets/app_card.dart';
import 'package:ai_clinic/core/widgets/app_data_table.dart';
import 'package:ai_clinic/core/widgets/app_dialog.dart';
import 'package:ai_clinic/core/widgets/app_form_field.dart';
import 'package:ai_clinic/core/widgets/app_loading_state.dart';
import 'package:ai_clinic/core/widgets/demo_scaffold.dart';
import 'package:ai_clinic/core/widgets/error_state_panel.dart';
import 'package:ai_clinic/core/widgets/snackbar_service.dart';
import 'package:ai_clinic/app/providers/connectivity_provider.dart';
import 'package:ai_clinic/app/providers/theme_provider.dart';

/// Placeholder screen exercising shared foundations for US3 verification.
class FoundationDemoPage extends ConsumerStatefulWidget {
  const FoundationDemoPage({super.key});

  @override
  ConsumerState<FoundationDemoPage> createState() => _FoundationDemoPageState();
}

class _FoundationDemoPageState extends ConsumerState<FoundationDemoPage> {
  final _notesController = TextEditingController();
  var _showLoading = false;

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);
    final connectivity = ref.watch(connectivityStatusProvider);

    return DemoScaffold(
      title: 'Shared foundations demo',
      subtitle: 'Representative screen using theme, widgets, loading, and error patterns.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppCard(
            title: 'Session context',
            subtitle: 'Values from shared providers (no domain data).',
            child: Text(
              'Theme: ${themeModeLabel(themeMode)} · Connectivity: ${connectivityStatusLabel(connectivity)}',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ),
          const SizedBox(height: 16),
          if (_showLoading)
            const AppLoadingState(title: 'Loading sample data', message: 'Blocking state for demonstrations.')
          else ...[
            AppCard(
              title: 'Actions and forms',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AppFormField(label: 'Sample notes', hint: 'Enter placeholder text', controller: _notesController),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      AppButton(
                        label: 'Show snackbar',
                        icon: Icons.notifications_outlined,
                        onPressed: () =>
                            SnackbarService.showMessage(context, 'Transient feedback from shared service.'),
                      ),
                      AppButton(
                        label: 'Show dialog',
                        variant: AppButtonVariant.secondary,
                        onPressed: () async {
                          await AppDialog.show(
                            context,
                            title: 'Confirm action',
                            message: 'Dialogs use the shared AppDialog wrapper.',
                          );
                        },
                      ),
                      AppButton(
                        label: 'Toggle loading',
                        variant: AppButtonVariant.secondary,
                        onPressed: () => setState(() => _showLoading = !_showLoading),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            AppCard(
              title: 'Sample table',
              child: AppDataTable(
                columns: const [
                  AppDataColumn(label: 'Item'),
                  AppDataColumn(label: 'Status'),
                  AppDataColumn(label: 'Updated', numeric: true),
                ],
                rows: [
                  ['Deployment profile', 'Valid', 'Just now'],
                  ['Gateway probe', connectivityStatusLabel(connectivity), 'Just now'],
                ],
              ),
            ),
            const SizedBox(height: 16),
            ErrorStatePanel(
              failure: const ConnectivityFailure('Example recoverable error for foundation review.'),
              onRetry: () => SnackbarService.showSuccess(context, 'Retry acknowledged.'),
              compact: true,
            ),
          ],
          const SizedBox(height: 20),
          AppButton(
            label: 'Back to startup entry',
            variant: AppButtonVariant.secondary,
            icon: Icons.arrow_back,
            onPressed: () => context.go(AppRoutes.startupEntry),
          ),
        ],
      ),
    );
  }
}
