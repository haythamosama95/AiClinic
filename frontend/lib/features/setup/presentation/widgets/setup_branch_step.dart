import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/settings/domain/branch_working_schedule.dart';
import 'package:ai_clinic/features/settings/presentation/widgets/branch_working_hours_sheet.dart';
import 'package:ai_clinic/features/setup/presentation/widgets/branch_form_fields.dart';
import 'package:ai_clinic/features/setup/presentation/widgets/setup_step_layout.dart';

class SetupBranchStep extends StatelessWidget {
  const SetupBranchStep({
    required this.formKey,
    required this.nameController,
    required this.codeController,
    required this.addressController,
    required this.phoneController,
    required this.mapsUrlController,
    required this.workingSchedule,
    required this.onWorkingScheduleChanged,
    required this.isBusy,
    super.key,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController nameController;
  final TextEditingController codeController;
  final TextEditingController addressController;
  final TextEditingController phoneController;
  final TextEditingController mapsUrlController;
  final BranchWorkingSchedule workingSchedule;
  final ValueChanged<BranchWorkingSchedule> onWorkingScheduleChanged;
  final bool isBusy;

  Future<void> _openWorkingHoursSheet(BuildContext context) async {
    await AppSheets.showModal<void>(
      context: context,
      side: AppSheetSide.right,
      width: 520,
      builder: (context) => BranchWorkingHoursSheet(
        initialSchedule: workingSchedule,
        startInEditMode: true,
        confirmLabel: 'Save',
        onUpdate: onWorkingScheduleChanged,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: formKey,
      child: SetupStepLayout(
        body: BranchFormFields(
          mode: BranchFormFieldsMode.create,
          nameController: nameController,
          codeController: codeController,
          addressController: addressController,
          phoneController: phoneController,
          mapsUrlController: mapsUrlController,
          enabled: !isBusy,
          workingHoursConfigured: workingSchedule.hasConfiguredWorkingHours,
          onWorkingHours: isBusy ? null : () => _openWorkingHoursSheet(context),
        ),
      ),
    );
  }
}
