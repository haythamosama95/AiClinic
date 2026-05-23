import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/core/widgets/app_form_field.dart';
import 'package:ai_clinic/core/widgets/app_searchable_dropdown_field.dart';
import 'package:ai_clinic/features/settings/presentation/widgets/branch_form_fields.dart';
import 'package:ai_clinic/features/auth/domain/bootstrap_field_options.dart';
import 'package:ai_clinic/features/auth/presentation/providers/bootstrap_notifier.dart';
import 'package:ai_clinic/features/auth/presentation/widgets/dev_fill_dummy_clinic_button.dart';
import 'package:ai_clinic/features/auth/presentation/widgets/dev_reset_clinic_button.dart';
import 'package:ai_clinic/features/auth/presentation/widgets/first_sign_in_warning_dialog.dart';
import 'package:ai_clinic/shared/providers/auth_session_provider.dart';

/// Two-step wizard: organization, then first branch (US5). Database writes occur on finish only.
class ClinicBootstrapPage extends ConsumerStatefulWidget {
  const ClinicBootstrapPage({super.key});

  @override
  ConsumerState<ClinicBootstrapPage> createState() => _ClinicBootstrapPageState();
}

class _ClinicBootstrapPageState extends ConsumerState<ClinicBootstrapPage> {
  final _orgFormKey = GlobalKey<FormState>();
  final _branchFormKey = GlobalKey<FormState>();
  final _orgNameController = TextEditingController();
  final _logoUrlController = TextEditingController();
  final _currencyController = TextEditingController();
  final _timezoneController = TextEditingController();
  final _branchNameController = TextEditingController();
  final _branchCodeController = TextEditingController();
  final _branchAddressController = TextEditingController();
  final _branchPhoneController = TextEditingController();
  final _branchMapsController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShowPasswordWarning());
  }

  @override
  void dispose() {
    _orgNameController.dispose();
    _logoUrlController.dispose();
    _currencyController.dispose();
    _timezoneController.dispose();
    _branchNameController.dispose();
    _branchCodeController.dispose();
    _branchAddressController.dispose();
    _branchPhoneController.dispose();
    _branchMapsController.dispose();
    super.dispose();
  }

  void _maybeShowPasswordWarning() {
    final auth = ref.read(authSessionProvider).context;
    final bootstrap = ref.read(bootstrapNotifierProvider);
    if (auth == null || !auth.staffProfile.isBootstrapAdmin || bootstrap.hasShownPasswordWarning) {
      return;
    }

    FirstSignInWarningDialog.show(
      context,
      onContinue: () {
        ref.read(bootstrapNotifierProvider.notifier).markPasswordWarningShown();
        Navigator.of(context).pop();
      },
    );
  }

  void _continueToBranch() {
    if (!(_orgFormKey.currentState?.validate() ?? false)) {
      return;
    }

    ref
        .read(bootstrapNotifierProvider.notifier)
        .continueToBranchStep(
          name: _orgNameController.text,
          logoUrl: _logoUrlController.text,
          currencyCode: _currencyController.text,
          timezone: _timezoneController.text,
        );
  }

  Future<void> _finishSetup() async {
    if (!(_branchFormKey.currentState?.validate() ?? false)) {
      return;
    }

    await ref
        .read(bootstrapNotifierProvider.notifier)
        .finishSetup(
          branchName: _branchNameController.text,
          branchCode: _branchCodeController.text,
          address: _branchAddressController.text,
          phone: _branchPhoneController.text,
          mapsUrl: _branchMapsController.text,
        );
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(authSessionProvider);
    final bootstrap = ref.watch(bootstrapNotifierProvider);
    final auth = session.context;
    final isBusy = bootstrap.isSubmitting;

    if (session.isAuthenticated && auth != null && !auth.setupRequired) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        context.go(AppRoutes.home);
      });
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Clinic setup'),
        automaticallyImplyLeading: false,
        actions: const [DevFillDummyClinicButton(), DevResetClinicButton()],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Set up your clinic', style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 8),
                Text(
                  auth == null
                      ? 'Loading your administrator session…'
                      : 'Signed in as ${auth.staffProfile.fullName}. '
                            'Enter organization and branch details, then save both together.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 8),
                _StepIndicator(current: bootstrap.step),
                if (bootstrap.errorMessage != null) ...[
                  const SizedBox(height: 16),
                  MaterialBanner(
                    content: Text(bootstrap.errorMessage!),
                    leading: const Icon(Icons.error_outline),
                    backgroundColor: Theme.of(context).colorScheme.errorContainer,
                    actions: [
                      TextButton(
                        onPressed: isBusy ? null : () => ref.read(bootstrapNotifierProvider.notifier).clearError(),
                        child: const Text('Dismiss'),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 24),
                switch (bootstrap.step) {
                  BootstrapWizardStep.organization => _OrganizationStep(
                    formKey: _orgFormKey,
                    nameController: _orgNameController,
                    logoController: _logoUrlController,
                    currencyController: _currencyController,
                    timezoneController: _timezoneController,
                    isBusy: isBusy,
                    onContinue: _continueToBranch,
                  ),
                  BootstrapWizardStep.branch => _BranchStep(
                    formKey: _branchFormKey,
                    nameController: _branchNameController,
                    codeController: _branchCodeController,
                    addressController: _branchAddressController,
                    phoneController: _branchPhoneController,
                    mapsController: _branchMapsController,
                    isBusy: isBusy,
                    onSubmit: _finishSetup,
                    onBack: isBusy
                        ? null
                        : () => ref.read(bootstrapNotifierProvider.notifier).goBackToOrganizationStep(),
                  ),
                  BootstrapWizardStep.complete => _CompleteStep(
                    organizationId: bootstrap.organizationId,
                    branchId: bootstrap.branchId,
                    onGoHome: () => context.go(AppRoutes.home),
                    onCreateStaff: () {
                      final setupRequired = ref.read(authSessionProvider).context?.setupRequired ?? true;
                      context.go(setupRequired ? AppRoutes.staffCreate : AppRoutes.settingsStaffNew);
                    },
                  ),
                },
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StepIndicator extends StatelessWidget {
  const _StepIndicator({required this.current});

  final BootstrapWizardStep current;

  static const _organizationStepHelp = 'Legal or trading name patients and staff will see on reports and receipts.';
  static const _branchStepHelp = 'Physical location for appointments, inventory, and branch-scoped permissions.';

  @override
  Widget build(BuildContext context) {
    final steps = BootstrapWizardStep.values.where((s) => s != BootstrapWizardStep.complete).toList();
    final index = steps.indexOf(current);

    return Row(
      children: [
        for (var i = 0; i < steps.length; i++) ...[
          if (i > 0) const Expanded(child: Divider()),
          _StepChip(
            label: i == 0 ? '1. Organization' : '2. Branch',
            isActive: i <= index,
            infoTooltip: i == 0 ? _organizationStepHelp : _branchStepHelp,
          ),
        ],
      ],
    );
  }
}

class _StepChip extends StatelessWidget {
  const _StepChip({required this.label, required this.isActive, this.infoTooltip});

  final String label;
  final bool isActive;
  final String? infoTooltip;

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: infoTooltip == null
          ? null
          : Tooltip(
              message: infoTooltip!,
              child: Icon(Icons.info_outline, size: 16, color: Theme.of(context).colorScheme.primary),
            ),
      label: Text(label),
      backgroundColor: isActive
          ? Theme.of(context).colorScheme.primaryContainer
          : Theme.of(context).colorScheme.surfaceContainerHighest,
    );
  }
}

class _OrganizationStep extends StatelessWidget {
  const _OrganizationStep({
    required this.formKey,
    required this.nameController,
    required this.logoController,
    required this.currencyController,
    required this.timezoneController,
    required this.isBusy,
    required this.onContinue,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController nameController;
  final TextEditingController logoController;
  final TextEditingController currencyController;
  final TextEditingController timezoneController;
  final bool isBusy;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    return Form(
      key: formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppFormField(
            label: 'Organization name',
            infoTooltip: 'Official clinic name shown on invoices, reports, and staff screens.',
            controller: nameController,
            enabled: !isBusy,
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Organization name is required';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),
          AppFormField(
            label: 'Logo URL',
            infoTooltip: 'HTTPS link to your clinic logo (PNG/SVG). Leave blank if you add a logo later.',
            controller: logoController,
            enabled: !isBusy,
            keyboardType: TextInputType.url,
          ),
          const SizedBox(height: 16),
          AppSearchableDropdownField(
            fieldKey: const ValueKey('bootstrap_currency'),
            label: 'Currency code',
            infoTooltip: 'ISO 4217 code for billing and receipts (e.g. EGP, USD). Type to filter the list.',
            controller: currencyController,
            enabled: !isBusy,
            hint: 'Type to search (e.g. EGP)',
            options: BootstrapCurrencyOptions.codes,
            filterOptions: BootstrapCurrencyOptions.filter,
            validator: (value) {
              if (!BootstrapCurrencyOptions.isValid(value)) {
                return 'Select a currency code from the list';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),
          AppSearchableDropdownField(
            fieldKey: const ValueKey('bootstrap_timezone'),
            label: 'Timezone',
            infoTooltip: 'IANA timezone for appointments and daily reports (e.g. Africa/Cairo). Type to filter.',
            controller: timezoneController,
            enabled: !isBusy,
            hint: 'Type to search (e.g. Africa/Cairo)',
            options: BootstrapTimezoneOptions.zones,
            filterOptions: BootstrapTimezoneOptions.filter,
            validator: (value) {
              if (!BootstrapTimezoneOptions.isValid(value)) {
                return 'Select a timezone from the list';
              }
              return null;
            },
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: isBusy ? null : onContinue,
            child: isBusy
                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Continue to branch'),
          ),
        ],
      ),
    );
  }
}

class _BranchStep extends StatelessWidget {
  const _BranchStep({
    required this.formKey,
    required this.nameController,
    required this.codeController,
    required this.addressController,
    required this.phoneController,
    required this.mapsController,
    required this.isBusy,
    required this.onSubmit,
    required this.onBack,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController nameController;
  final TextEditingController codeController;
  final TextEditingController addressController;
  final TextEditingController phoneController;
  final TextEditingController mapsController;
  final bool isBusy;
  final Future<void> Function() onSubmit;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return Form(
      key: formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BranchFormFields(
            mode: BranchFormFieldsMode.bootstrap,
            nameController: nameController,
            codeController: codeController,
            addressController: addressController,
            phoneController: phoneController,
            mapsUrlController: mapsController,
            enabled: !isBusy,
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              if (onBack != null) OutlinedButton(onPressed: onBack, child: const Text('Back')),
              const Spacer(),
              FilledButton(
                onPressed: isBusy ? null : onSubmit,
                child: isBusy
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Finish setup'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CompleteStep extends StatelessWidget {
  const _CompleteStep({
    required this.organizationId,
    required this.branchId,
    required this.onGoHome,
    required this.onCreateStaff,
  });

  final String? organizationId;
  final String? branchId;
  final VoidCallback onGoHome;
  final VoidCallback onCreateStaff;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(Icons.check_circle_outline, size: 48, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 16),
        Text('Clinic setup is complete', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(
          'Organization and first branch are saved. '
          'You can create staff accounts next or open the clinic shell.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        if (organizationId != null || branchId != null) ...[
          const SizedBox(height: 12),
          Text(
            [
              if (organizationId != null) 'Organization: $organizationId',
              if (branchId != null) 'Branch: $branchId',
            ].join('\n'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
        const SizedBox(height: 24),
        FilledButton(onPressed: onCreateStaff, child: const Text('Create staff accounts')),
        const SizedBox(height: 8),
        OutlinedButton(onPressed: onGoHome, child: const Text('Go to clinic home')),
      ],
    );
  }
}
