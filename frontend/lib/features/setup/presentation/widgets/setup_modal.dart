import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/theme/theme.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/setup/presentation/providers/provisioning_notifier.dart';
import 'package:ai_clinic/features/setup/domain/bootstrap_field_options.dart';
import 'package:ai_clinic/features/setup/domain/setup_step_readiness.dart';
import 'package:ai_clinic/features/setup/presentation/providers/setup_notifier.dart';
import 'package:ai_clinic/features/setup/presentation/widgets/setup_branch_step.dart';
import 'package:ai_clinic/features/setup/presentation/widgets/setup_wizard_nav_bar.dart';
import 'package:ai_clinic/features/setup/presentation/widgets/setup_complete_step.dart';
import 'package:ai_clinic/features/setup/presentation/widgets/setup_organization_step.dart';
import 'package:ai_clinic/features/setup/presentation/widgets/setup_staff_step.dart';
import 'package:ai_clinic/features/setup/presentation/widgets/setup_step_indicator.dart';
import 'package:ai_clinic/features/setup/presentation/widgets/setup_step_layout.dart';
import 'package:ai_clinic/features/setup/presentation/widgets/setup_step_transition.dart';

abstract final class _SetupModalPalette {
  static const modalRadius = 24.0;
  static const maxWidth = 920.0;
}

/// Centered floating clinic setup wizard (Organization → Branch → Staff).
class SetupModal extends ConsumerStatefulWidget {
  const SetupModal({required this.onFinished, super.key});

  final VoidCallback onFinished;

  @override
  ConsumerState<SetupModal> createState() => _SetupModalState();
}

class _SetupModalState extends ConsumerState<SetupModal> {
  final _orgFormKey = GlobalKey<FormState>();
  final _branchFormKey = GlobalKey<FormState>();
  final _staffFormKey = GlobalKey<FormState>();

  final _orgNameController = TextEditingController();
  final _logoUrlController = TextEditingController();
  final _branchNameController = TextEditingController();
  final _branchCodeController = TextEditingController();
  final _branchAddressController = TextEditingController();
  final _branchPhoneController = TextEditingController();
  final _branchMapsController = TextEditingController();
  final _staffUsernameController = TextEditingController();
  final _staffFullNameController = TextEditingController();
  final _staffPasswordController = TextEditingController();

  String? _currency = BootstrapCurrencyOptions.defaultCode;
  String? _timezone = BootstrapTimezoneOptions.defaultZone;
  int _stepTransitionDirection = 1;
  late final List<TextEditingController> _fieldControllers;
  late final Listenable _formFieldsListenable;

  @override
  void initState() {
    super.initState();
    _fieldControllers = [
      _orgNameController,
      _logoUrlController,
      _branchNameController,
      _branchCodeController,
      _branchAddressController,
      _branchPhoneController,
      _branchMapsController,
      _staffUsernameController,
      _staffFullNameController,
      _staffPasswordController,
    ];
    _formFieldsListenable = Listenable.merge(_fieldControllers);
    _restoreDraftFromState();
  }

  @override
  void dispose() {
    _orgNameController.dispose();
    _logoUrlController.dispose();
    _branchNameController.dispose();
    _branchCodeController.dispose();
    _branchAddressController.dispose();
    _branchPhoneController.dispose();
    _branchMapsController.dispose();
    _staffUsernameController.dispose();
    _staffFullNameController.dispose();
    _staffPasswordController.dispose();
    super.dispose();
  }

  bool _isNextEnabled(SetupWizardStep step) {
    return switch (step) {
      SetupWizardStep.organization => isOrganizationStepReady(
        name: _orgNameController.text,
        currency: _currency,
        timezone: _timezone,
      ),
      SetupWizardStep.branch => isBranchStepReady(
        name: _branchNameController.text,
        code: _branchCodeController.text,
        address: _branchAddressController.text,
        phone: _branchPhoneController.text,
        mapsUrl: _branchMapsController.text,
      ),
      _ => false,
    };
  }

  void _onNextPressed() {
    switch (ref.read(setupNotifierProvider).step) {
      case SetupWizardStep.organization:
        _continueToBranch();
      case SetupWizardStep.branch:
        _finishBranchAndContinue();
      case SetupWizardStep.staff:
      case SetupWizardStep.complete:
        break;
    }
  }

  void _restoreDraftFromState() {
    final draft = ref.read(setupNotifierProvider).organizationDraft;
    if (draft == null) {
      return;
    }
    _orgNameController.text = draft.name;
    if (draft.logoUrl != null) {
      _logoUrlController.text = draft.logoUrl!;
    }
    _currency = draft.currencyCode;
    _timezone = draft.timezone;
  }

  void _continueToBranch() {
    if (!(_orgFormKey.currentState?.validate() ?? false)) {
      return;
    }

    final currency = _currency;
    final timezone = _timezone;
    if (currency == null || timezone == null) {
      return;
    }

    ref
        .read(setupNotifierProvider.notifier)
        .continueToBranchStep(
          name: _orgNameController.text,
          logoUrl: _logoUrlController.text,
          currencyCode: currency,
          timezone: timezone,
        );
  }

  Future<void> _finishBranchAndContinue() async {
    if (!(_branchFormKey.currentState?.validate() ?? false)) {
      return;
    }

    await ref
        .read(setupNotifierProvider.notifier)
        .finishSetup(
          branchName: _branchNameController.text,
          branchCode: _branchCodeController.text,
          address: _branchAddressController.text,
          phone: _branchPhoneController.text,
          mapsUrl: _branchMapsController.text,
        );
  }

  Future<void> _createStaffAccount({
    required StaffRole role,
    required List<String> branchIds,
    String? primaryBranchId,
  }) async {
    if (!(_staffFormKey.currentState?.validate() ?? false)) {
      return;
    }

    final result = await ref
        .read(provisioningNotifierProvider.notifier)
        .createStaffAccount(
          username: _staffUsernameController.text.trim(),
          fullName: _staffFullNameController.text.trim(),
          role: role,
          branchIds: branchIds,
          password: _staffPasswordController.text,
          primaryBranchId: primaryBranchId,
        );

    if (!mounted || result == null) {
      return;
    }

    final password = result.revealAssignedPassword();
    await AppDialog.show<void>(
      context: context,
      title: 'Staff account created',
      body: SelectableText(
        'Share these credentials with the staff member:\n\n'
        'Username: ${result.username}\n'
        'Password: ${password ?? '(already shown)'}',
      ),
      actions: [
        AppButton(
          label: 'Continue',
          onPressed: () {
            ref.read(provisioningNotifierProvider.notifier).clearLastCreated();
            Navigator.of(context).pop();
            ref.read(setupNotifierProvider.notifier).markSetupComplete();
          },
        ),
      ],
    );
  }

  void _skipStaff() {
    ref.read(setupNotifierProvider.notifier).markSetupComplete();
  }

  @override
  Widget build(BuildContext context) {
    final setup = ref.watch(setupNotifierProvider);
    final provisioning = ref.watch(provisioningNotifierProvider);
    final isBusy = setup.isSubmitting || provisioning.isSubmitting;
    final theme = Theme.of(context);
    final errorMessage = setup.errorMessage ?? provisioning.errorMessage;
    final compactViewport = MediaQuery.sizeOf(context).height < SetupLayoutBreakpoints.compactViewportHeight;

    ref.listen<SetupUiState>(setupNotifierProvider, (previous, next) {
      if (previous != null && previous.step != next.step) {
        setState(() {
          _stepTransitionDirection = next.step.index > previous.step.index ? 1 : -1;
        });
      }

      if (next.step == SetupWizardStep.organization && next.organizationDraft != null) {
        final draft = next.organizationDraft!;
        _orgNameController.text = draft.name;
        _logoUrlController.text = draft.logoUrl ?? '';
        setState(() {
          _currency = draft.currencyCode;
          _timezone = draft.timezone;
        });
      }
    });

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: _SetupModalPalette.maxWidth),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(_SetupModalPalette.modalRadius),
          boxShadow: ShadowTokens.shadowLg,
        ),
        child: Padding(
          padding: const EdgeInsets.all(SpacingTokens.xl),
          child: _wrapModalScroll(
            compactViewport: compactViewport,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                ListenableBuilder(
                  listenable: _formFieldsListenable,
                  builder: (context, _) => SetupWizardNavBar(
                    showBack: setup.step == SetupWizardStep.branch,
                    showNext: setup.step == SetupWizardStep.organization || setup.step == SetupWizardStep.branch,
                    nextEnabled: _isNextEnabled(setup.step),
                    isBusy: isBusy,
                    onBack: () => ref.read(setupNotifierProvider.notifier).goBackToOrganizationStep(),
                    onNext: _onNextPressed,
                  ),
                ),
                const SizedBox(height: SpacingTokens.md),
                Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(color: theme.colorScheme.primary, shape: BoxShape.circle),
                      child: Icon(Icons.local_hospital_outlined, color: theme.colorScheme.onPrimary, size: 20),
                    ),
                    const SizedBox(width: SpacingTokens.sm),
                    Text(
                      'AI Clinic',
                      style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.4),
                    ),
                  ],
                ),
                const SizedBox(height: SpacingTokens.xl),
                Text(
                  "Let's get you started",
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: SpacingTokens.sm),
                Text(
                  'Enter the details to get going',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: SpacingTokens.xl),
                SetupStepIndicator(current: setup.step),
                if (errorMessage != null) ...[
                  const SizedBox(height: SpacingTokens.lg),
                  AppAlert(variant: AppAlertVariant.destructive, title: errorMessage),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: isBusy
                          ? null
                          : () {
                              ref.read(setupNotifierProvider.notifier).clearError();
                              ref.read(provisioningNotifierProvider.notifier).clearError();
                            },
                      child: const Text('Dismiss'),
                    ),
                  ),
                ],
                const SizedBox(height: SpacingTokens.xl),
                SetupStepTransition(
                  step: setup.step,
                  direction: _stepTransitionDirection,
                  organizationStep: SetupOrganizationStep(
                    formKey: _orgFormKey,
                    nameController: _orgNameController,
                    logoUrlController: _logoUrlController,
                    currency: _currency,
                    timezone: _timezone,
                    onCurrencyChanged: (value) => setState(() => _currency = value),
                    onTimezoneChanged: (value) => setState(() => _timezone = value),
                    isBusy: isBusy,
                  ),
                  branchStep: SetupBranchStep(
                    formKey: _branchFormKey,
                    nameController: _branchNameController,
                    codeController: _branchCodeController,
                    addressController: _branchAddressController,
                    phoneController: _branchPhoneController,
                    mapsUrlController: _branchMapsController,
                    isBusy: isBusy,
                  ),
                  staffStep: SetupStaffStep(
                    formKey: _staffFormKey,
                    usernameController: _staffUsernameController,
                    fullNameController: _staffFullNameController,
                    passwordController: _staffPasswordController,
                    isBusy: isBusy,
                    onCreate: _createStaffAccount,
                    onSkip: _skipStaff,
                  ),
                  completeStep: SetupCompleteStep(onGoHome: widget.onFinished),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _wrapModalScroll({required bool compactViewport, required Widget child}) {
    if (compactViewport) {
      return SingleChildScrollView(child: child);
    }
    return child;
  }
}
