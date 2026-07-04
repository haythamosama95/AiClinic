import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/navigation/app_navigator.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/auth/auth_route_guard.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/core/ui/ui.dart';
import 'package:ai_clinic/features/settings/application/settings_rpc_messages.dart';
import 'package:ai_clinic/features/settings/domain/branch_working_schedule.dart';
import 'package:ai_clinic/features/settings/domain/create_branch_input.dart';
import 'package:ai_clinic/features/settings/domain/usecases/settings_use_case_providers.dart';
import 'package:ai_clinic/features/settings/presentation/providers/clinic_setup_providers.dart';
import 'package:ai_clinic/features/setup/presentation/widgets/bootstrap_step_fields.dart';

/// Create branch form on `/settings/branches/new`.
class BranchCreatePage extends ConsumerStatefulWidget {
  const BranchCreatePage({super.key});

  @override
  ConsumerState<BranchCreatePage> createState() => _BranchCreatePageState();
}

class _BranchCreatePageState extends ConsumerState<BranchCreatePage> {
  final _nameController = TextEditingController();
  final _codeController = TextEditingController();
  final _addressController = TextEditingController();
  final _phoneController = TextEditingController();
  final _mapsUrlController = TextEditingController();

  BranchWorkingSchedule _workingSchedule = BranchWorkingSchedule.emptySchedule();
  var _isSaving = false;
  String? _errorMessage;
  final Map<String, String?> _fieldErrors = {};

  @override
  void dispose() {
    _nameController.dispose();
    _codeController.dispose();
    _addressController.dispose();
    _phoneController.dispose();
    _mapsUrlController.dispose();
    super.dispose();
  }

  void _validateFields() {
    final errors = BootstrapBranchStepFields.validate(
      branchName: _nameController.text,
      branchCode: _codeController.text,
      address: _addressController.text,
      phone: _phoneController.text,
      mapsUrl: _mapsUrlController.text,
      workingSchedule: _workingSchedule,
    );
    setState(() => _fieldErrors.addAll(errors));
  }

  Future<void> _create() async {
    _validateFields();
    if (_fieldErrors.values.any((error) => error != null)) {
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

      ref.showAppToast(message: 'Branch created.', variant: AppToastVariant.success);
      context.nav.goSettingsBranches();
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
    final auth = ref.watch(authSessionProvider);
    final canManage = AuthRouteGuard.canAccessBranchManagement(auth);

    if (!canManage) {
      return ColoredBox(
        color: context.colors.surfaceCanvas,
        child: const Center(
          child: AppEmptyState(
            variant: AppEmptyStateVariant.noAccess,
            title: 'New branch',
            description: 'You do not have permission to manage branches.',
          ),
        ),
      );
    }

    return ColoredBox(
      color: context.colors.surfaceCanvas,
      child: EditorFormPattern(
        title: 'New branch',
        description: 'Add a clinic location with contact details and working hours.',
        breadcrumb: AppBreadcrumb(
          items: [
            AppBreadcrumbItem(label: 'Settings', onTap: () => context.nav.goSettings()),
            AppBreadcrumbItem(label: 'Branches', onTap: () => context.nav.goSettingsBranches()),
            const AppBreadcrumbItem(label: 'New branch'),
          ],
        ),
        summaryAlert: _errorMessage == null
            ? null
            : AppAlert(variant: AppAlertVariant.danger, title: _errorMessage!),
        sections: [
          EditorFormSection(
            title: 'Branch details',
            fields: [
              BootstrapBranchStepFields(
                nameController: _nameController,
                codeController: _codeController,
                addressController: _addressController,
                phoneController: _phoneController,
                mapsUrlController: _mapsUrlController,
                workingSchedule: _workingSchedule,
                onWorkingScheduleChanged: (schedule) => setState(() => _workingSchedule = schedule),
                fieldErrors: _fieldErrors,
                onFieldBlur: (_) {},
                disabled: _isSaving,
              ),
            ],
          ),
        ],
        footer: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppButton(
              label: 'Cancel',
              variant: AppButtonVariant.secondary,
              disabled: _isSaving,
              onPressed: () => context.nav.goSettingsBranches(),
            ),
            const SizedBox(width: AppSpacing.s3),
            AppButton(
              label: 'Create branch',
              loading: _isSaving,
              onPressed: _create,
            ),
          ],
        ),
      ),
    );
  }
}
