import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/theme/theme.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/setup/domain/branch_summary.dart';
import 'package:ai_clinic/features/setup/domain/setup_wizard_draft_ids.dart';
import 'package:ai_clinic/features/setup/domain/bootstrap_field_options.dart';
import 'package:ai_clinic/features/setup/domain/setup_step_readiness.dart';
import 'package:ai_clinic/features/setup/presentation/providers/setup_notifier.dart';
import 'package:ai_clinic/features/settings/domain/branch_working_schedule.dart';
import 'package:ai_clinic/features/setup/presentation/widgets/setup_branch_step.dart';
import 'package:ai_clinic/features/setup/presentation/widgets/setup_wizard_nav_bar.dart';
import 'package:ai_clinic/features/setup/presentation/widgets/setup_complete_step.dart';
import 'package:ai_clinic/features/setup/presentation/widgets/setup_organization_step.dart';
import 'package:ai_clinic/features/setup/presentation/widgets/setup_staff_step.dart';
import 'package:ai_clinic/features/setup/presentation/widgets/setup_step_indicator.dart';
import 'package:ai_clinic/features/setup/presentation/widgets/setup_step_transition.dart';

abstract final class _SetupModalPalette {
  static const modalRadius = 24.0;
  static const maxWidth = 920.0;
}

String _setupStepSubtitle(SetupWizardStep step) => switch (step) {
  SetupWizardStep.organization => "Enter your clinic's organization details to get started.",
  SetupWizardStep.branch => 'Start with your main branch. Additional branches can be added later.',
  SetupWizardStep.staff =>
    'Create at least one staff account to finish setup. You can add more now or manage staff later in Settings.',
  SetupWizardStep.complete => 'Your clinic is ready to use.',
};

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
  final _staffPhoneController = TextEditingController();
  final _staffPasswordController = TextEditingController();

  BranchWorkingSchedule _branchWorkingSchedule = BranchWorkingSchedule.emptySchedule();
  String? _currency = BootstrapCurrencyOptions.defaultCode;
  String? _timezone = BootstrapTimezoneOptions.defaultZone;
  int _stepTransitionDirection = 1;
  ({String username, String password})? _staffCreatedAcknowledgement;
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
      _staffPhoneController,
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
    _staffPhoneController.dispose();
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
        workingSchedule: _branchWorkingSchedule,
      ),
      SetupWizardStep.staff => ref.read(setupNotifierProvider).staffDrafts.isNotEmpty,
      _ => false,
    };
  }

  String _nextLabel(SetupWizardStep step) => step == SetupWizardStep.staff ? 'Finish' : 'Next';

  String _nextDisabledTooltip(SetupWizardStep step) {
    if (step == SetupWizardStep.staff) {
      return 'Create at least one staff account to finish setup';
    }
    return 'One or more mandatory fields are empty';
  }

  void _onBackPressed(SetupWizardStep step) {
    switch (step) {
      case SetupWizardStep.branch:
        ref.read(setupNotifierProvider.notifier).goBackToOrganizationStep();
      case SetupWizardStep.staff:
        ref.read(setupNotifierProvider.notifier).goBackToBranchStep();
      case SetupWizardStep.organization:
      case SetupWizardStep.complete:
        break;
    }
  }

  void _onNextPressed() {
    switch (ref.read(setupNotifierProvider).step) {
      case SetupWizardStep.organization:
        _continueToBranch();
      case SetupWizardStep.branch:
        _continueToStaff();
      case SetupWizardStep.staff:
        _finishSetup();
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

  void _continueToStaff() {
    if (!(_branchFormKey.currentState?.validate() ?? false)) {
      return;
    }

    ref
        .read(setupNotifierProvider.notifier)
        .continueToStaffStep(
          branchName: _branchNameController.text,
          branchCode: _branchCodeController.text,
          address: _branchAddressController.text,
          phone: _branchPhoneController.text,
          mapsUrl: _branchMapsController.text,
          workingSchedule: _branchWorkingSchedule,
        );
  }

  Future<void> _finishSetup() async {
    final setup = ref.read(setupNotifierProvider);
    if (setup.staffDrafts.isEmpty) {
      return;
    }

    // Saved drafts are submitted on Finish; do not validate the cleared create form.
    _staffFormKey.currentState?.reset();
    _staffCreatedAcknowledgement = null;

    await ref.read(setupNotifierProvider.notifier).finishSetup();
  }

  Future<bool> _addStaffDraft({
    required StaffRole role,
    required List<String> branchIds,
    String? primaryBranchId,
    String? phone,
  }) async {
    if (!(_staffFormKey.currentState?.validate() ?? false)) {
      return false;
    }

    final username = _staffUsernameController.text.trim();
    final password = _staffPasswordController.text;
    final added = ref
        .read(setupNotifierProvider.notifier)
        .addStaffDraft(
          username: username,
          fullName: _staffFullNameController.text.trim(),
          role: role,
          branchIds: branchIds,
          password: password,
          primaryBranchId: primaryBranchId,
          phone: phone,
        );

    if (!mounted || !added) {
      return false;
    }

    _staffUsernameController.clear();
    _staffFullNameController.clear();
    _staffPhoneController.clear();
    _staffPasswordController.clear();

    setState(() => _staffCreatedAcknowledgement = (username: username, password: password));

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _staffFormKey.currentState?.reset();
    });

    return true;
  }

  @override
  Widget build(BuildContext context) {
    final setup = ref.watch(setupNotifierProvider);
    final isBusy = setup.isSubmitting;
    final theme = Theme.of(context);
    final errorMessage = setup.errorMessage;
    ref.listen<SetupUiState>(setupNotifierProvider, (previous, next) {
      if (previous != null && previous.step != next.step) {
        setState(() {
          _stepTransitionDirection = next.step.index > previous.step.index ? 1 : -1;
          if (next.step != SetupWizardStep.staff) {
            _staffCreatedAcknowledgement = null;
          }
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

      if (next.step == SetupWizardStep.branch && next.branchDraft != null) {
        final draft = next.branchDraft!;
        _branchNameController.text = draft.name;
        _branchCodeController.text = draft.code;
        _branchAddressController.text = draft.address;
        _branchPhoneController.text = draft.phone;
        _branchMapsController.text = draft.mapsUrl;
        _branchWorkingSchedule = draft.workingSchedule;
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
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
                    const Spacer(),
                    ListenableBuilder(
                      listenable: _formFieldsListenable,
                      builder: (context, _) => SetupWizardNavBar(
                        embedded: true,
                        showBack: setup.step == SetupWizardStep.branch || setup.step == SetupWizardStep.staff,
                        showNext:
                            setup.step == SetupWizardStep.organization ||
                            setup.step == SetupWizardStep.branch ||
                            setup.step == SetupWizardStep.staff,
                        nextLabel: _nextLabel(setup.step),
                        nextEnabled: setup.step == SetupWizardStep.staff
                            ? setup.staffDrafts.isNotEmpty
                            : _isNextEnabled(setup.step),
                        nextDisabledTooltip: _nextDisabledTooltip(setup.step),
                        isBusy: isBusy,
                        onBack: () => _onBackPressed(setup.step),
                        onNext: _onNextPressed,
                      ),
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
                  _setupStepSubtitle(setup.step),
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
                      onPressed: isBusy ? null : () => ref.read(setupNotifierProvider.notifier).clearError(),
                      child: const Text('Dismiss'),
                    ),
                  ),
                ],
                if (setup.step == SetupWizardStep.staff)
                  AppFadeInOutPanel(
                    key: const ValueKey('setup-staff-created-panel'),
                    visible: _staffCreatedAcknowledgement != null,
                    child: _staffCreatedAcknowledgement == null
                        ? const SizedBox.shrink()
                        : Padding(
                            padding: const EdgeInsets.only(top: SpacingTokens.lg),
                            child: AppAlert(
                              title: 'Staff member added',
                              subtitle:
                                  'This account will be created when you finish setup.\n\n'
                                  'Username: ${_staffCreatedAcknowledgement!.username}\n'
                                  'Password: ${_staffCreatedAcknowledgement!.password}\n\n'
                                  'Create another account below, or click Finish when you are done.',
                            ),
                          ),
                  ),
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
                    workingSchedule: _branchWorkingSchedule,
                    onWorkingScheduleChanged: (schedule) {
                      setState(() => _branchWorkingSchedule = schedule);
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        _branchFormKey.currentState?.validate();
                      });
                    },
                    isBusy: isBusy,
                  ),
                  staffStep: SetupStaffStep(
                    formKey: _staffFormKey,
                    usernameController: _staffUsernameController,
                    fullNameController: _staffFullNameController,
                    phoneController: _staffPhoneController,
                    passwordController: _staffPasswordController,
                    isBusy: isBusy,
                    onCreate: _addStaffDraft,
                    wizardBranches: _wizardBranches(setup.branchDraft),
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

  List<BranchSummary> _wizardBranches(SetupBranchDraft? draft) {
    if (draft == null) {
      return const [];
    }

    return [
      BranchSummary(
        id: SetupWizardDraftIds.branch,
        name: draft.name,
        code: draft.code,
        address: draft.address,
        phone: draft.phone,
        mapsUrl: draft.mapsUrl,
      ),
    ];
  }

  Widget _wrapModalScroll({required Widget child}) {
    return SingleChildScrollView(child: child);
  }
}
