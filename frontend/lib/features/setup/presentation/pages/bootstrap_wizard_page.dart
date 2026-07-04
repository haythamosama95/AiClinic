import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/ui/ui.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/setup/domain/bootstrap_field_options.dart';
import 'package:ai_clinic/features/setup/domain/branch_summary.dart';
import 'package:ai_clinic/features/setup/domain/setup_wizard_draft_ids.dart';
import 'package:ai_clinic/features/settings/domain/branch_working_schedule.dart';
import 'package:ai_clinic/features/setup/presentation/dev/setup_dev_widgets.dart';
import 'package:ai_clinic/features/setup/presentation/providers/setup_notifier.dart';
import 'package:ai_clinic/features/setup/presentation/widgets/bootstrap_staff_step_fields.dart';
import 'package:ai_clinic/features/setup/presentation/widgets/bootstrap_step_fields.dart';
import 'package:ai_clinic/features/setup/presentation/widgets/first_sign_in_warning_dialog.dart';

/// Clinic first-run setup wizard on `/bootstrap` (organization → branch → staff → complete).
class BootstrapWizardPage extends ConsumerStatefulWidget {
  const BootstrapWizardPage({super.key});

  @override
  ConsumerState<BootstrapWizardPage> createState() => _BootstrapWizardPageState();
}

class _BootstrapWizardPageState extends ConsumerState<BootstrapWizardPage> {
  final _orgNameController = TextEditingController();
  final _logoUrlController = TextEditingController();
  final _branchNameController = TextEditingController();
  final _branchCodeController = TextEditingController();
  final _branchAddressController = TextEditingController();
  final _branchPhoneController = TextEditingController();
  final _branchMapsController = TextEditingController();
  final _staffUsernameController = TextEditingController();
  final _staffFullNameController = TextEditingController();
  final _staffPhoneController = TextEditingController();
  final _staffPasswordController = TextEditingController();

  String? _currency = BootstrapCurrencyOptions.defaultCode;
  String? _timezone = BootstrapTimezoneOptions.defaultZone;
  BranchWorkingSchedule _branchWorkingSchedule = BranchWorkingSchedule.emptySchedule();
  final Map<String, String?> _fieldErrors = {};
  String? _staffStepError;
  ({String username, String password})? _staffAddedAcknowledgement;

  static const _steps = [
    AppStepperStep(id: 'organization', label: 'Organization'),
    AppStepperStep(id: 'branch', label: 'Branch'),
    AppStepperStep(id: 'staff', label: 'Staff'),
    AppStepperStep(id: 'complete', label: 'Complete'),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShowPasswordWarning());
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
    _staffPhoneController.dispose();
    _staffPasswordController.dispose();
    super.dispose();
  }

  void _maybeShowPasswordWarning() {
    final auth = ref.read(authSessionProvider).context;
    final setup = ref.read(setupNotifierProvider);
    if (auth == null || !auth.staffProfile.isBootstrapAdmin || setup.hasShownPasswordWarning) {
      return;
    }

    FirstSignInWarningDialog.show(
      context,
      onContinue: () => ref.read(setupNotifierProvider.notifier).markPasswordWarningShown(),
    );
  }

  int _stepIndex(SetupWizardStep step) => switch (step) {
    SetupWizardStep.organization => 0,
    SetupWizardStep.branch => 1,
    SetupWizardStep.staff => 2,
    SetupWizardStep.complete => 3,
  };

  String _stepSubtitle(SetupWizardStep step) => switch (step) {
    SetupWizardStep.organization => "Enter your clinic's organization details to get started.",
    SetupWizardStep.branch => 'Start with your main branch. Additional branches can be added later.',
    SetupWizardStep.staff =>
      'Create at least one staff account to finish setup. You can add more now or manage staff later in Settings.',
    SetupWizardStep.complete => 'Your clinic is ready to use.',
  };

  void _restoreDraftFromState(SetupUiState setup) {
    final orgDraft = setup.organizationDraft;
    if (orgDraft != null) {
      _orgNameController.text = orgDraft.name;
      _logoUrlController.text = orgDraft.logoUrl ?? '';
      _currency = orgDraft.currencyCode;
      _timezone = orgDraft.timezone;
    }

    final branchDraft = setup.branchDraft;
    if (branchDraft != null) {
      _branchNameController.text = branchDraft.name;
      _branchCodeController.text = branchDraft.code;
      _branchAddressController.text = branchDraft.address;
      _branchPhoneController.text = branchDraft.phone;
      _branchMapsController.text = branchDraft.mapsUrl;
      _branchWorkingSchedule = branchDraft.workingSchedule;
    }
  }

  void _clearFieldError(String field) {
    if (_fieldErrors.containsKey(field)) {
      setState(() => _fieldErrors.remove(field));
    }
  }

  Map<String, String?> _validateOrganizationFields() {
    return {
      'name': _orgNameController.text.trim().isEmpty ? 'Enter your clinic organization name.' : null,
      'currency': !BootstrapCurrencyOptions.isValid(_currency) ? 'Select a valid currency code from the list.' : null,
      'timezone': !BootstrapTimezoneOptions.isValid(_timezone) ? 'Select a valid timezone from the list.' : null,
    };
  }

  Future<bool> _validateCurrentStep(int stepIndex) async {
    final setup = ref.read(setupNotifierProvider);
    switch (setup.step) {
      case SetupWizardStep.organization:
        final errors = _validateOrganizationFields();
        setState(() => _fieldErrors.addAll(errors));
        return errors.values.every((error) => error == null);
      case SetupWizardStep.branch:
        final errors = BootstrapBranchStepFields.validate(
          branchName: _branchNameController.text,
          branchCode: _branchCodeController.text,
          address: _branchAddressController.text,
          phone: _branchPhoneController.text,
          mapsUrl: _branchMapsController.text,
          workingSchedule: _branchWorkingSchedule,
        );
        setState(() => _fieldErrors.addAll(errors));
        return errors.values.every((error) => error == null);
      case SetupWizardStep.staff:
        if (setup.staffDrafts.isEmpty) {
          setState(() => _staffStepError = 'Create at least one staff account to finish setup.');
          return false;
        }
        setState(() => _staffStepError = null);
        return true;
      case SetupWizardStep.complete:
        return true;
    }
  }

  void _handleNext() {
    final setup = ref.read(setupNotifierProvider);
    switch (setup.step) {
      case SetupWizardStep.organization:
        ref.read(setupNotifierProvider.notifier).continueToBranchStep(
              name: _orgNameController.text,
              logoUrl: _logoUrlController.text,
              currencyCode: _currency!,
              timezone: _timezone!,
            );
      case SetupWizardStep.branch:
        ref.read(setupNotifierProvider.notifier).continueToStaffStep(
              branchName: _branchNameController.text,
              branchCode: _branchCodeController.text,
              address: _branchAddressController.text,
              phone: _branchPhoneController.text,
              mapsUrl: _branchMapsController.text,
              workingSchedule: _branchWorkingSchedule,
            );
      case SetupWizardStep.staff:
      case SetupWizardStep.complete:
        break;
    }
  }

  Future<void> _handleFinish() async {
    setState(() => _staffAddedAcknowledgement = null);
    await ref.read(setupNotifierProvider.notifier).finishSetup();
  }

  Future<void> _addStaffDraft({
    required StaffRole role,
    required List<String> branchIds,
    String? primaryBranchId,
    String? phone,
  }) async {
    final added = ref.read(setupNotifierProvider.notifier).addStaffDraft(
          username: _staffUsernameController.text,
          fullName: _staffFullNameController.text,
          role: role,
          branchIds: branchIds,
          password: _staffPasswordController.text,
          primaryBranchId: primaryBranchId,
          phone: phone,
        );

    if (!mounted || !added) {
      return;
    }

    final username = _staffUsernameController.text.trim();
    final password = _staffPasswordController.text;
    _staffUsernameController.clear();
    _staffFullNameController.clear();
    _staffPhoneController.clear();
    _staffPasswordController.clear();
    setState(() {
      _fieldErrors.clear();
      _staffStepError = null;
      _staffAddedAcknowledgement = (username: username, password: password);
    });
  }

  BranchSummary? _wizardBranch(SetupBranchDraft? draft) {
    if (draft == null) {
      return null;
    }
    return BranchSummary(
      id: SetupWizardDraftIds.branch,
      name: draft.name,
      code: draft.code,
      address: draft.address,
      phone: draft.phone,
      mapsUrl: draft.mapsUrl,
    );
  }

  void _goHome() {
    if (mounted) {
      context.go(AppRoutes.home);
    }
  }

  @override
  Widget build(BuildContext context) {
    final setup = ref.watch(setupNotifierProvider);
    final isBusy = setup.isSubmitting;
    final currentStep = _stepIndex(setup.step);

    ref.listen<SetupUiState>(setupNotifierProvider, (previous, next) {
      if (previous?.step != next.step) {
        _restoreDraftFromState(next);
        if (next.step != SetupWizardStep.staff) {
          setState(() => _staffAddedAcknowledgement = null);
        }
      }
      if (next.step == SetupWizardStep.complete && previous?.step != SetupWizardStep.complete) {
        _goHome();
      }
    });

    return Scaffold(
      backgroundColor: context.colors.surfaceCanvas,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsetsDirectional.symmetric(
              horizontal: AppSpacing.s6,
              vertical: AppSpacing.s8,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 920),
              child: AppCard(
                padding: AppCardPadding.lg,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      "Let's get you started",
                      textAlign: TextAlign.center,
                      style: context.typography.title.copyWith(color: context.colors.textPrimary),
                    ),
                    const SizedBox(height: AppSpacing.s2),
                    Text(
                      _stepSubtitle(setup.step),
                      textAlign: TextAlign.center,
                      style: context.typography.body.copyWith(color: context.colors.textSecondary),
                    ),
                    const SizedBox(height: AppSpacing.s6),
                    if (setup.errorMessage != null) ...[
                      AppAlert(
                        variant: AppAlertVariant.danger,
                        title: setup.errorMessage!,
                        dismissible: true,
                        onDismiss: () => ref.read(setupNotifierProvider.notifier).clearError(),
                      ),
                      const SizedBox(height: AppSpacing.s4),
                    ],
                    if (_staffStepError != null && setup.step == SetupWizardStep.staff) ...[
                      AppAlert(variant: AppAlertVariant.warning, title: _staffStepError!),
                      const SizedBox(height: AppSpacing.s4),
                    ],
                    if (_staffAddedAcknowledgement != null && setup.step == SetupWizardStep.staff) ...[
                      AppAlert(
                        variant: AppAlertVariant.success,
                        title: 'Staff member added',
                        body:
                            'This account will be created when you finish setup.\n\n'
                            'Username: ${_staffAddedAcknowledgement!.username}\n'
                            'Password: ${_staffAddedAcknowledgement!.password}\n\n'
                            'Create another account below, or click Finish when you are done.',
                      ),
                      const SizedBox(height: AppSpacing.s4),
                    ],
                    WizardPattern(
                      steps: _steps,
                      currentStep: currentStep,
                      finishLabel: 'Finish',
                      onBack: setup.step == SetupWizardStep.branch
                          ? () => ref.read(setupNotifierProvider.notifier).goBackToOrganizationStep()
                          : setup.step == SetupWizardStep.staff
                          ? () => ref.read(setupNotifierProvider.notifier).goBackToBranchStep()
                          : null,
                      onNext: setup.step == SetupWizardStep.complete ? null : _handleNext,
                      onFinish: setup.step == SetupWizardStep.staff ? _handleFinish : null,
                      onValidateStep: _validateCurrentStep,
                      stepContent: _buildStepContent(setup, isBusy),
                    ),
                    SetupDevWidgets.panel(
                      isBusy: isBusy,
                      onFillDummy: () {},
                      onResetInstallation: () => ref.read(setupNotifierProvider.notifier).resetInstallationForDevelopment(),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStepContent(SetupUiState setup, bool isBusy) {
    return switch (setup.step) {
      SetupWizardStep.organization => BootstrapOrganizationStepFields(
        nameController: _orgNameController,
        logoUrlController: _logoUrlController,
        currency: _currency,
        timezone: _timezone,
        onCurrencyChanged: (value) => setState(() {
          _currency = value;
          _clearFieldError('currency');
        }),
        onTimezoneChanged: (value) => setState(() {
          _timezone = value;
          _clearFieldError('timezone');
        }),
        fieldErrors: _fieldErrors,
        onFieldBlur: (field) {
          if (field == 'name') {
            setState(() => _fieldErrors['name'] = _orgNameController.text.trim().isEmpty
                ? 'Enter your clinic organization name.'
                : null);
          }
        },
        disabled: isBusy,
      ),
      SetupWizardStep.branch => BootstrapBranchStepFields(
        nameController: _branchNameController,
        codeController: _branchCodeController,
        addressController: _branchAddressController,
        phoneController: _branchPhoneController,
        mapsUrlController: _branchMapsController,
        workingSchedule: _branchWorkingSchedule,
        onWorkingScheduleChanged: (schedule) => setState(() => _branchWorkingSchedule = schedule),
        fieldErrors: _fieldErrors,
        onFieldBlur: (field) {
          final errors = BootstrapBranchStepFields.validate(
            branchName: _branchNameController.text,
            branchCode: _branchCodeController.text,
            address: _branchAddressController.text,
            phone: _branchPhoneController.text,
            mapsUrl: _branchMapsController.text,
            workingSchedule: _branchWorkingSchedule,
          );
          if (errors.containsKey(field)) {
            setState(() => _fieldErrors[field] = errors[field]);
          }
        },
        disabled: isBusy,
      ),
      SetupWizardStep.staff => BootstrapStaffStepFields(
        usernameController: _staffUsernameController,
        fullNameController: _staffFullNameController,
        phoneController: _staffPhoneController,
        passwordController: _staffPasswordController,
        wizardBranch: _wizardBranch(setup.branchDraft),
        staffDrafts: setup.staffDrafts,
        fieldErrors: _fieldErrors,
        onFieldBlur: (_) {},
        onAddDraft: _addStaffDraft,
        disabled: isBusy,
      ),
      SetupWizardStep.complete => Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          AppIcon(icon: LucideIcons.circleCheck, size: AppIconSize.xl, color: context.colors.statusSuccessFg),
          const SizedBox(height: AppSpacing.s4),
          Text(
            'Clinic setup is complete',
            textAlign: TextAlign.center,
            style: context.typography.title.copyWith(color: context.colors.textPrimary),
          ),
          const SizedBox(height: AppSpacing.s2),
          Text(
            'Your organization, first branch, and staff account are ready. Open the clinic shell to get started.',
            textAlign: TextAlign.center,
            style: context.typography.body.copyWith(color: context.colors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.s6),
          AppButton(label: 'Go to clinic home', onPressed: _goHome),
        ],
      ),
    };
  }
}
