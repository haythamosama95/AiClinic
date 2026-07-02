import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/auth/auth_route_guard.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/core/ui/theme/semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/spacing_tokens.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/service_catalog/application/service_catalog_rpc_messages.dart';
import 'package:ai_clinic/features/service_catalog/domain/global_status.dart';
import 'package:ai_clinic/features/service_catalog/domain/service_branch_config.dart';
import 'package:ai_clinic/features/service_catalog/presentation/providers/service_editor_notifier.dart';
import 'package:ai_clinic/features/service_catalog/presentation/widgets/branch_configuration_matrix.dart';
import 'package:ai_clinic/features/service_catalog/presentation/widgets/service_form.dart';
import 'package:ai_clinic/features/settings/presentation/providers/clinic_setup_providers.dart';

/// Create or view a catalog service with branch assignment (Service Catalog 015 US1).
class ServiceEditorPage extends ConsumerWidget {
  const ServiceEditorPage({super.key, this.serviceId});

  /// `null` opens create mode.
  final String? serviceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authSessionProvider);
    if (!AuthRouteGuard.canAccessServiceEditor(auth)) {
      return const Scaffold(body: Center(child: Text('You do not have permission to manage the service catalog.')));
    }

    final editorAsync = ref.watch(serviceEditorProvider(serviceId));
    final branchesAsync = ref.watch(clinicSetupBranchesProvider);
    final isCreate = serviceId == null || serviceId!.isEmpty;

    return Scaffold(
      backgroundColor: context.semanticColors.background,
      body: Padding(
        padding: const EdgeInsets.all(SpacingTokens.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                AppIconButton(icon: const Icon(Icons.arrow_back), tooltip: 'Back', onPressed: () => context.pop()),
                const SizedBox(width: SpacingTokens.sm),
                Expanded(
                  child: Text(
                    isCreate ? 'New service' : 'Service details',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: SpacingTokens.lg),
            Expanded(
              child: editorAsync.when(
                loading: () => const Center(child: AppCircularProgress()),
                error: (error, _) => Center(child: Text('Unable to load service: $error')),
                data: (editorState) {
                  return branchesAsync.when(
                    loading: () => const Center(child: AppCircularProgress()),
                    error: (error, _) => Center(child: Text('Unable to load branches: $error')),
                    data: (branches) {
                      if (!isCreate && editorState.detail == null) {
                        return const Center(child: Text('Service was not found.'));
                      }

                      final detail = editorState.detail;
                      final activeBranches = branches.where((branch) => branch.isActive).toList(growable: false);
                      final allBranchIds = activeBranches.map((branch) => branch.id).toList(growable: false);

                      return SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            ServiceForm(
                              branches: branches,
                              isSaving: editorState.isSaving,
                              isEditMode: !isCreate,
                              saveButtonLabel: isCreate ? 'Save service' : 'Save changes',
                              initialName: detail?.service.name ?? '',
                              initialDefaultPrice: detail?.service.defaultPrice.wireValue ?? '',
                              initialGlobalStatus: detail?.service.globalStatus ?? GlobalStatus.active,
                              initialAssignAllBranches: detail == null,
                              initialSelectedBranchIds: {for (final row in detail?.branches ?? const []) row.branchId},
                              onSubmit:
                                  ({
                                    required name,
                                    required defaultPrice,
                                    required globalStatus,
                                    required assignAllBranches,
                                    required selectedBranchIds,
                                  }) async {
                                    try {
                                      if (isCreate) {
                                        await ref
                                            .read(serviceEditorProvider(serviceId).notifier)
                                            .createService(
                                              name: name,
                                              defaultPrice: defaultPrice,
                                              globalStatus: globalStatus,
                                              assignAllBranches: assignAllBranches,
                                              selectedBranchIds: selectedBranchIds,
                                            );
                                        if (context.mounted) {
                                          AppToast.success(context, message: 'Service created.');
                                          context.pop();
                                        }
                                      } else {
                                        await ref
                                            .read(serviceEditorProvider(serviceId).notifier)
                                            .updateService(
                                              name: name,
                                              defaultPrice: defaultPrice,
                                              globalStatus: globalStatus,
                                              assignAllBranches: assignAllBranches,
                                              selectedBranchIds: selectedBranchIds,
                                              allBranchIds: allBranchIds,
                                            );
                                        if (context.mounted) {
                                          AppToast.success(context, message: 'Service updated.');
                                        }
                                      }
                                    } on RpcFailure catch (error) {
                                      if (context.mounted) {
                                        AppToast.error(context, message: serviceCatalogMessageForRpc(error));
                                      }
                                    }
                                  },
                            ),
                            if (!isCreate && detail != null) ...[
                              const SizedBox(height: SpacingTokens.md),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: AppButton(
                                  label: detail.service.globalStatus == GlobalStatus.active
                                      ? 'Mark inactive'
                                      : 'Mark active',
                                  variant: AppButtonVariant.outline,
                                  expand: false,
                                  isLoading: editorState.isSaving,
                                  onPressed: editorState.isSaving
                                      ? null
                                      : () async {
                                          final nextStatus = detail.service.globalStatus == GlobalStatus.active
                                              ? GlobalStatus.inactive
                                              : GlobalStatus.active;
                                          try {
                                            await ref
                                                .read(serviceEditorProvider(serviceId).notifier)
                                                .setGlobalStatus(nextStatus);
                                            if (context.mounted) {
                                              AppToast.success(context, message: 'Global status updated.');
                                            }
                                          } on RpcFailure catch (error) {
                                            if (context.mounted) {
                                              AppToast.error(context, message: serviceCatalogMessageForRpc(error));
                                            }
                                          }
                                        },
                                ),
                              ),
                              const SizedBox(height: SpacingTokens.sm),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: AppButton(
                                  label: 'Delete service',
                                  variant: AppButtonVariant.destructive,
                                  expand: false,
                                  isLoading: editorState.isSaving,
                                  onPressed: editorState.isSaving
                                      ? null
                                      : () => _confirmDeleteService(context, ref, serviceId),
                                ),
                              ),
                              const SizedBox(height: SpacingTokens.xl),
                              BranchConfigurationMatrix(
                                branches: [
                                  for (final row in detail.branches)
                                    ServiceBranchConfig.fromRow(
                                      row,
                                      branchName:
                                          branches
                                              .where((branch) => branch.id == row.branchId)
                                              .map((branch) => branch.name)
                                              .firstOrNull ??
                                          row.branchId,
                                    ),
                                ],
                                defaultPrice: detail.service.defaultPrice,
                                isSaving: editorState.isSaving,
                                onConfigureBranch: ({required branch, required active, required priceOverride}) async {
                                  final updatedAt = branch.updatedAt;
                                  if (updatedAt == null) {
                                    throw StateError('Branch configuration timestamp is missing.');
                                  }
                                  try {
                                    await ref
                                        .read(serviceEditorProvider(serviceId).notifier)
                                        .configureServiceBranch(
                                          branchId: branch.branchId,
                                          expectedUpdatedAt: updatedAt,
                                          active: active,
                                          priceOverride: priceOverride,
                                        );
                                    if (context.mounted) {
                                      AppToast.success(context, message: 'Branch settings saved.');
                                    }
                                  } on RpcFailure catch (error) {
                                    if (context.mounted) {
                                      AppToast.error(context, message: serviceCatalogMessageForRpc(error));
                                    }
                                  }
                                },
                                onSetPromotion:
                                    ({required branch, required price, required startDate, required endDate}) async {
                                      final updatedAt = branch.updatedAt;
                                      if (updatedAt == null) {
                                        throw StateError('Branch configuration timestamp is missing.');
                                      }
                                      try {
                                        await ref
                                            .read(serviceEditorProvider(serviceId).notifier)
                                            .setServicePromotion(
                                              branchId: branch.branchId,
                                              expectedUpdatedAt: updatedAt,
                                              promotionPrice: price,
                                              startDate: startDate,
                                              endDate: endDate,
                                            );
                                        if (context.mounted) {
                                          AppToast.success(context, message: 'Promotion saved.');
                                        }
                                      } on RpcFailure catch (error) {
                                        if (context.mounted) {
                                          AppToast.error(context, message: serviceCatalogMessageForRpc(error));
                                        }
                                      }
                                    },
                                onClearPromotion: ({required branch}) async {
                                  final updatedAt = branch.updatedAt;
                                  if (updatedAt == null) {
                                    throw StateError('Branch configuration timestamp is missing.');
                                  }
                                  try {
                                    await ref
                                        .read(serviceEditorProvider(serviceId).notifier)
                                        .clearServicePromotion(branchId: branch.branchId, expectedUpdatedAt: updatedAt);
                                    if (context.mounted) {
                                      AppToast.success(context, message: 'Promotion cleared.');
                                    }
                                  } on RpcFailure catch (error) {
                                    if (context.mounted) {
                                      AppToast.error(context, message: serviceCatalogMessageForRpc(error));
                                    }
                                  }
                                },
                              ),
                            ],
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDeleteService(BuildContext context, WidgetRef ref, String? serviceId) async {
    await AppDialog.showConfirmation(
      context: context,
      title: 'Delete service',
      message:
          'This hides the service from the catalog and invoice selector. Historical invoice lines keep their snapshots.',
      confirmLabel: 'Delete',
      destructive: true,
      onConfirm: () async {
        try {
          await ref.read(serviceEditorProvider(serviceId).notifier).softDeleteService();
          if (!context.mounted) return;
          AppToast.success(context, message: 'Service deleted.');
          context.pop();
        } on RpcFailure catch (error) {
          if (!context.mounted) return;
          AppToast.error(context, message: serviceCatalogMessageForRpc(error));
        }
      },
    );
  }
}
