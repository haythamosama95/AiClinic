import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/core/ui/theme/theme.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/core/utils/user_error_mapper.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_list_item.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/appointment_doctor_selector.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/settings/domain/staff_list_filter.dart';
import 'package:ai_clinic/features/settings/domain/staff_list_item.dart';
import 'package:ai_clinic/features/settings/domain/usecases/settings_use_case_providers.dart';
import 'package:ai_clinic/features/visits/application/visit_rpc_messages.dart';
import 'package:ai_clinic/features/visits/data/visit_repository.dart';

/// Starts a visit from an eligible appointment; prompts for doctor when missing (V1-5 US1).
class VisitCreateDialog extends ConsumerStatefulWidget {
  const VisitCreateDialog({
    required this.item,
    required this.branchId,
    required this.dialogStyle,
    required this.animation,
    super.key,
  });

  final AppointmentListItem item;
  final String branchId;
  final FDialogStyle dialogStyle;
  final Animation<double> animation;

  static Future<CreateVisitResult?> show(
    BuildContext context, {
    required AppointmentListItem item,
    required String branchId,
  }) {
    final fTheme = context.theme;

    return showFDialog<CreateVisitResult?>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      builder: (dialogContext, style, animation) {
        return FTheme(
          data: fTheme,
          child: VisitCreateDialog(item: item, branchId: branchId, dialogStyle: style, animation: animation),
        );
      },
    );
  }

  @override
  ConsumerState<VisitCreateDialog> createState() => _VisitCreateDialogState();
}

class _VisitCreateDialogState extends ConsumerState<VisitCreateDialog> {
  String? _selectedDoctorId;
  var _isSaving = false;
  String? _formError;
  var _doctorsLoading = true;
  List<StaffListItem> _doctors = const [];

  AppointmentListItem get _item => widget.item;

  bool get _needsDoctorPicker => _item.doctorId == null || _item.doctorId!.trim().isEmpty;

  @override
  void initState() {
    super.initState();
    _selectedDoctorId = _item.doctorId;
    _loadDoctors();
  }

  Future<void> _loadDoctors() async {
    try {
      final staff = await ref.read(listStaffUseCaseProvider)(filter: StaffListFilter.active);
      if (!mounted) {
        return;
      }
      setState(() {
        _doctors = staff.where((entry) => entry.role == StaffRole.doctor).toList(growable: false);
        _doctorsLoading = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() => _doctorsLoading = false);
    }
  }

  Future<void> _create() async {
    if (_needsDoctorPicker && (_selectedDoctorId == null || _selectedDoctorId!.trim().isEmpty)) {
      setState(() => _formError = 'Select a doctor before starting this visit.');
      return;
    }

    setState(() {
      _isSaving = true;
      _formError = null;
    });

    try {
      final result = await ref
          .read(visitRepositoryProvider)
          .createVisit(appointmentId: _item.id, doctorId: _needsDoctorPicker ? _selectedDoctorId : null);

      if (!mounted) {
        return;
      }
      Navigator.of(context, rootNavigator: true).pop(result);
    } on RpcFailure catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isSaving = false;
        _formError = visitMessageForRpc(error);
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isSaving = false;
        _formError = UserErrorMapper.mapToUserMessage(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.semanticColors;

    return FDialog(
      key: const Key('visit_create_dialog'),
      style: widget.dialogStyle,
      animation: widget.animation,
      direction: Axis.horizontal,
      title: Text('Start visit', style: theme.textTheme.titleLarge),
      body: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Patient: ${_item.patientName}', style: theme.textTheme.bodyMedium),
            const SizedBox(height: SpacingTokens.md),
            if (_needsDoctorPicker) ...[
              Text(
                'This appointment has no doctor assigned. Select one to continue.',
                style: theme.textTheme.bodySmall?.copyWith(color: colors.mutedForeground),
              ),
              const SizedBox(height: SpacingTokens.sm),
              if (_doctorsLoading)
                const Center(child: Padding(padding: EdgeInsets.all(SpacingTokens.md), child: AppCircularProgress()))
              else if (_doctors.isEmpty)
                Text(
                  'No active doctors are configured.',
                  style: theme.textTheme.bodySmall?.copyWith(color: colors.destructive),
                )
              else
                AppointmentDoctorSelector(
                  key: const Key('visit_create_doctor_selector'),
                  branchId: widget.branchId,
                  doctors: _doctors,
                  value: _selectedDoctorId,
                  enabled: !_isSaving,
                  onChanged: (value) => setState(() {
                    _selectedDoctorId = value;
                    _formError = null;
                  }),
                ),
            ] else
              Text('Doctor: ${_item.doctorDisplayName}', style: theme.textTheme.bodyMedium),
            if (_formError != null) ...[
              const SizedBox(height: SpacingTokens.sm),
              Text(
                _formError!,
                key: const Key('visit_create_error'),
                style: theme.textTheme.bodySmall?.copyWith(color: colors.destructive),
              ),
            ],
          ],
        ),
      ),
      actions: [
        AppButton(
          key: const Key('visit_create_cancel'),
          label: 'Cancel',
          variant: AppButtonVariant.outline,
          expand: false,
          onPressed: _isSaving ? null : () => Navigator.of(context, rootNavigator: true).pop(),
        ),
        AppButton(
          key: const Key('visit_create_confirm'),
          label: 'Start visit',
          expand: false,
          isLoading: _isSaving,
          onPressed: _isSaving ? null : _create,
        ),
      ],
    );
  }
}
