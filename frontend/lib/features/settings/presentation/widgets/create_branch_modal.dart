import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/core/ui/theme/shadow_tokens.dart';
import 'package:ai_clinic/core/ui/theme/theme.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/settings/application/settings_rpc_messages.dart';
import 'package:ai_clinic/features/settings/domain/branch_working_schedule.dart';
import 'package:ai_clinic/features/settings/domain/create_branch_input.dart';
import 'package:ai_clinic/features/settings/domain/usecases/settings_use_case_providers.dart';
import 'package:ai_clinic/features/settings/presentation/providers/clinic_setup_providers.dart';
import 'package:ai_clinic/features/setup/domain/setup_step_readiness.dart';
import 'package:ai_clinic/features/setup/presentation/widgets/setup_branch_step.dart';

abstract final class _CreateBranchModalPalette {
  static const modalRadius = 24.0;
  static const maxWidth = 720.0;
}

/// Blurred overlay with the bootstrap branch form for adding a branch from settings.
class CreateBranchModal extends ConsumerStatefulWidget {
  const CreateBranchModal({super.key});

  /// Presents the create-branch form over a blurred scrim.
  static Future<bool?> show(BuildContext context) {
    return showGeneralDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      barrierColor: Colors.transparent,
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        return UncontrolledProviderScope(
          container: ProviderScope.containerOf(context, listen: false),
          child: const _CreateBranchModalOverlay(),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(opacity: animation, child: child);
      },
    );
  }

  @override
  ConsumerState<CreateBranchModal> createState() => _CreateBranchModalState();
}

class _CreateBranchModalOverlay extends StatelessWidget {
  const _CreateBranchModalOverlay();

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
                  constraints: const BoxConstraints(maxWidth: _CreateBranchModalPalette.maxWidth),
                  child: const CreateBranchModal(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CreateBranchModalState extends ConsumerState<CreateBranchModal> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _codeController = TextEditingController();
  final _addressController = TextEditingController();
  final _phoneController = TextEditingController();
  final _mapsUrlController = TextEditingController();
  late final Listenable _formFieldsListenable;

  BranchWorkingSchedule _workingSchedule = BranchWorkingSchedule.emptySchedule();
  var _isSaving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _formFieldsListenable = Listenable.merge([
      _nameController,
      _codeController,
      _addressController,
      _phoneController,
      _mapsUrlController,
    ]);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _codeController.dispose();
    _addressController.dispose();
    _phoneController.dispose();
    _mapsUrlController.dispose();
    super.dispose();
  }

  bool get _isReady => isBranchStepReady(
    name: _nameController.text,
    code: _codeController.text,
    address: _addressController.text,
    phone: _phoneController.text,
    mapsUrl: _mapsUrlController.text,
    workingSchedule: _workingSchedule,
  );

  Future<void> _create() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      await ref.read(createBranchUseCaseProvider)(
        CreateBranchInput(
          name: _nameController.text,
          workingSchedule: _workingSchedule,
          code: _codeController.text,
          address: _addressController.text,
          phone: _phoneController.text,
          mapsUrl: _mapsUrlController.text,
        ),
      );

      ref.invalidate(clinicSetupBranchesProvider);

      if (!mounted) {
        return;
      }

      AppToast.success(context, message: 'Branch created.');
      Navigator.of(context).pop(true);
    } on RpcFailure catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isSaving = false;
        _errorMessage = branchMessageForRpc(error);
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isSaving = false;
        _errorMessage = 'Unable to create branch. Check connectivity and try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.semanticColors;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(_CreateBranchModalPalette.modalRadius),
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
                'Add branch',
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: SpacingTokens.sm),
              Text(
                'Start with your main branch. Additional branches can be added later.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(color: colors.mutedForeground),
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: SpacingTokens.lg),
                AppAlert(variant: AppAlertVariant.destructive, title: _errorMessage!),
              ],
              const SizedBox(height: SpacingTokens.xl),
              SetupBranchStep(
                formKey: _formKey,
                nameController: _nameController,
                codeController: _codeController,
                addressController: _addressController,
                phoneController: _phoneController,
                mapsUrlController: _mapsUrlController,
                workingSchedule: _workingSchedule,
                onWorkingScheduleChanged: (schedule) {
                  setState(() => _workingSchedule = schedule);
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    _formKey.currentState?.validate();
                  });
                },
                isBusy: _isSaving,
              ),
              const SizedBox(height: SpacingTokens.xl),
              ListenableBuilder(
                listenable: _formFieldsListenable,
                builder: (context, _) {
                  return Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      AppButton(
                        label: 'Cancel',
                        variant: AppButtonVariant.outline,
                        expand: false,
                        onPressed: _isSaving ? null : () => Navigator.of(context).pop(false),
                      ),
                      const SizedBox(width: SpacingTokens.sm),
                      AppButton(
                        label: 'Create branch',
                        expand: false,
                        isLoading: _isSaving,
                        onPressed: _isSaving || !_isReady ? null : _create,
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
