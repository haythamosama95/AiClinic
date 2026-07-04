import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/core/ui/theme/theme.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/service_catalog/application/service_catalog_rpc_messages.dart';
import 'package:ai_clinic/features/service_catalog/domain/pending_branch_configuration.dart';
import 'package:ai_clinic/features/service_catalog/presentation/models/service_form_draft_snapshot.dart';
import 'package:ai_clinic/features/service_catalog/presentation/providers/service_catalog_list_notifier.dart';
import 'package:ai_clinic/features/service_catalog/presentation/providers/service_editor_notifier.dart';
import 'package:ai_clinic/features/service_catalog/presentation/widgets/service_create_branch_config_section.dart';
import 'package:ai_clinic/features/service_catalog/presentation/widgets/service_form.dart';
import 'package:ai_clinic/features/settings/presentation/providers/clinic_setup_providers.dart';

abstract final class _CreateServiceModalPalette {
  static const modalRadius = 24.0;
  static const maxWidth = 720.0;
}

/// Blurred overlay with the service create form for adding services from settings.
class CreateServiceModal extends ConsumerStatefulWidget {
  const CreateServiceModal({super.key});

  /// Presents the create-service form over a blurred scrim.
  static Future<bool?> show(BuildContext context) {
    return showGeneralDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      barrierColor: Colors.transparent,
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        return UncontrolledProviderScope(
          container: ProviderScope.containerOf(context, listen: false),
          child: const _CreateServiceModalOverlay(),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(opacity: animation, child: child);
      },
    );
  }

  @override
  ConsumerState<CreateServiceModal> createState() => _CreateServiceModalState();
}

class _CreateServiceModalOverlay extends StatelessWidget {
  const _CreateServiceModalOverlay();

  @override
  Widget build(BuildContext context) {
    final colors = context.semanticColors;

    return Material(
      type: MaterialType.transparency,
      child: Stack(
        fit: StackFit.expand,
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).pop(false),
            child: ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: ColoredBox(color: colors.background.withValues(alpha: 0.35)),
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: SpacingTokens.lg, vertical: SpacingTokens.xl),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: _CreateServiceModalPalette.maxWidth),
                  child: const CreateServiceModal(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CreateServiceModalState extends ConsumerState<CreateServiceModal> {
  final _formKey = GlobalKey<ServiceFormState>();
  ServiceFormDraftSnapshot _formSnapshot = const ServiceFormDraftSnapshot(
    defaultPrice: '',
    assignAllBranches: true,
    selectedBranchIds: {},
  );
  Map<String, PendingBranchConfiguration> _draftBranchConfigs = {};

  Future<void> _create() async {
    await _formKey.currentState?.submit();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.semanticColors;
    final branchesAsync = ref.watch(clinicSetupBranchesProvider);
    final editorAsync = ref.watch(serviceEditorProvider(null));
    final isSaving = editorAsync.value?.isSaving ?? false;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.enter): () {
          if (!isSaving) {
            _create();
          }
        },
      },
      child: Focus(
        autofocus: true,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.card,
            borderRadius: BorderRadius.circular(_CreateServiceModalPalette.modalRadius),
            boxShadow: ShadowTokens.shadowLg,
          ),
          child: Padding(
            padding: const EdgeInsets.all(SpacingTokens.xl),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Add service',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: SpacingTokens.sm),
                  Text(
                    'Create an organization-wide service and assign it to branches for invoicing.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(color: colors.mutedForeground),
                  ),
                  const SizedBox(height: SpacingTokens.xl),
                  branchesAsync.when(
                    loading: () => const Center(child: AppCircularProgress()),
                    error: (error, _) =>
                        AppAlert(variant: AppAlertVariant.destructive, title: 'Unable to load branches: $error'),
                    data: (branches) => Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ServiceForm(
                          key: _formKey,
                          branches: branches,
                          isSaving: isSaving,
                          showSubmitButton: false,
                          onDraftChanged: (snapshot) => setState(() => _formSnapshot = snapshot),
                          onSubmit:
                              ({
                                required name,
                                required defaultPrice,
                                required globalStatus,
                                required assignAllBranches,
                                required selectedBranchIds,
                              }) async {
                                try {
                                  await ref
                                      .read(serviceEditorProvider(null).notifier)
                                      .createService(
                                        name: name,
                                        defaultPrice: defaultPrice,
                                        globalStatus: globalStatus,
                                        assignAllBranches: assignAllBranches,
                                        selectedBranchIds: selectedBranchIds,
                                        pendingBranchConfigs: _draftBranchConfigs.values.toList(growable: false),
                                      );
                                  if (!context.mounted) {
                                    return;
                                  }
                                  ref.invalidate(serviceCatalogListProvider);
                                  AppToast.success(context, message: 'Service created.');
                                  Navigator.of(context).pop(true);
                                } on RpcFailure catch (error) {
                                  if (context.mounted) {
                                    AppToast.error(context, message: serviceCatalogMessageForRpc(error));
                                  }
                                }
                              },
                        ),
                        const SizedBox(height: SpacingTokens.xl),
                        ServiceCreateBranchConfigSection(
                          formSnapshot: _formSnapshot,
                          branches: branches,
                          draftConfigs: _draftBranchConfigs,
                          isSaving: isSaving,
                          onDraftConfigsChanged: (configs) => setState(() => _draftBranchConfigs = configs),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: SpacingTokens.xl),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      AppButton(
                        label: 'Cancel',
                        variant: AppButtonVariant.outline,
                        expand: false,
                        onPressed: isSaving ? null : () => Navigator.of(context).pop(false),
                      ),
                      const SizedBox(width: SpacingTokens.sm),
                      AppButton(
                        label: 'Save service',
                        expand: false,
                        isLoading: isSaving,
                        onPressed: isSaving ? null : _create,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
