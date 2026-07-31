import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/clinic-management/presentation/components/working_hours_editor.dart';
import 'package:ai_clinic/features/clinic-management/presentation/models/branch_form_values.dart';
import 'package:ai_clinic/features/clinic-management/presentation/utils/working_schedule.dart';

/// Branch location fields in a responsive two-column grid (web `BranchFormFields`).
class BranchFormFields extends StatefulWidget {
  const BranchFormFields({
    required this.values,
    required this.onChanged,
    this.disabled = false,
    this.errors = const {},
    this.showWorkingHours = true,
    super.key,
  });

  final BranchFormValues values;
  final ValueChanged<BranchFormValues> onChanged;
  final bool disabled;
  final BranchFormErrors errors;
  final bool showWorkingHours;

  @override
  State<BranchFormFields> createState() => _BranchFormFieldsState();
}

class _BranchFormFieldsState extends State<BranchFormFields> {
  var _hoursOpen = false;

  @override
  Widget build(BuildContext context) {
    final hoursConfigured = hasConfiguredWorkingHours(widget.values.workingSchedule);

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 640;
        final columnCount = isWide ? 2 : 1;
        final fieldWidth = columnCount == 1
            ? constraints.maxWidth
            : (constraints.maxWidth - AppSpacing.space5) / 2;
        final fullWidth = constraints.maxWidth;

        Widget field(Widget child, {bool spanTwo = false}) {
          return SizedBox(
            width: spanTwo ? fullWidth : fieldWidth,
            child: child,
          );
        }

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: AppSpacing.space5,
              runSpacing: AppSpacing.space5,
              children: [
                field(
                  AppFormField(
                    id: 'branch-name',
                    label: 'Branch name',
                    requiredMark: true,
                    error: widget.errors['name'],
                    child: AppTextInput(
                      id: 'branch-name',
                      initialValue: widget.values.name,
                      placeholder: 'Enter branch name',
                      disabled: widget.disabled,
                      readOnly: widget.disabled,
                      invalid: widget.errors.containsKey('name'),
                      onChanged: (name) => widget.onChanged(widget.values.copyWith(name: name)),
                    ),
                  ),
                ),
                field(
                  AppFormField(
                    id: 'branch-code',
                    label: 'Branch code',
                    requiredMark: true,
                    error: widget.errors['code'],
                    child: AppTextInput(
                      id: 'branch-code',
                      initialValue: widget.values.code,
                      placeholder: 'e.g. MAIN',
                      disabled: widget.disabled,
                      readOnly: widget.disabled,
                      invalid: widget.errors.containsKey('code'),
                      onChanged: (code) => widget.onChanged(widget.values.copyWith(code: code)),
                    ),
                  ),
                ),
                field(
                  AppFormField(
                    id: 'branch-address',
                    label: 'Address',
                    requiredMark: true,
                    error: widget.errors['address'],
                    child: AppTextInput(
                      id: 'branch-address',
                      initialValue: widget.values.address,
                      placeholder: 'Street address',
                      disabled: widget.disabled,
                      readOnly: widget.disabled,
                      invalid: widget.errors.containsKey('address'),
                      onChanged: (address) =>
                          widget.onChanged(widget.values.copyWith(address: address)),
                    ),
                  ),
                  spanTwo: true,
                ),
                field(
                  AppFormField(
                    id: 'branch-phone',
                    label: 'Phone',
                    requiredMark: true,
                    error: widget.errors['phone'],
                    child: Directionality(
                      textDirection: TextDirection.ltr,
                      child: AppTextInput(
                        id: 'branch-phone',
                        initialValue: widget.values.phone,
                        placeholder: 'Numbers only',
                        keyboardType: TextInputType.phone,
                        disabled: widget.disabled,
                        readOnly: widget.disabled,
                        invalid: widget.errors.containsKey('phone'),
                        onChanged: (phone) => widget.onChanged(
                          widget.values.copyWith(
                            phone: phone.replaceAll(RegExp(r'\D'), ''),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                field(
                  AppFormField(
                    id: 'branch-maps',
                    label: 'Maps URL',
                    requiredMark: true,
                    error: widget.errors['mapsUrl'],
                    child: AppTextInput(
                      id: 'branch-maps',
                      initialValue: widget.values.mapsUrl,
                      placeholder: 'maps.google.com/... or www.example.com',
                      keyboardType: TextInputType.url,
                      disabled: widget.disabled,
                      readOnly: widget.disabled,
                      invalid: widget.errors.containsKey('mapsUrl'),
                      onChanged: (mapsUrl) =>
                          widget.onChanged(widget.values.copyWith(mapsUrl: mapsUrl)),
                    ),
                  ),
                ),
                if (widget.showWorkingHours)
                  field(
                    AppFormField(
                      id: 'branch-hours',
                      label: 'Working hours',
                      requiredMark: true,
                      error: widget.errors['workingSchedule'],
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: AppButton(
                          variant: AppButtonVariant.secondary,
                          disabled: widget.disabled,
                          leadingIcon: const Icon(Icons.event_available, size: 16),
                          onPressed: widget.disabled ? null : () => setState(() => _hoursOpen = true),
                          child: Text(
                            hoursConfigured ? 'Working hours configured' : 'Set working hours',
                          ),
                        ),
                      ),
                    ),
                    spanTwo: true,
                  ),
              ],
            ),
            if (widget.showWorkingHours)
              AppDialog(
                open: _hoursOpen,
                onOpenChange: (open) => setState(() => _hoursOpen = open),
                title: 'Working hours',
                description: 'Set open and close times for each day of the week.',
                size: AppDialogSize.lg,
                footer: AppButton(
                  onPressed: () => setState(() => _hoursOpen = false),
                  child: const Text('Done'),
                ),
                child: WorkingHoursEditor(
                  schedule: widget.values.workingSchedule,
                  disabled: widget.disabled,
                  onChange: (workingSchedule) =>
                      widget.onChanged(widget.values.copyWith(workingSchedule: workingSchedule)),
                ),
              ),
          ],
        );
      },
    );
  }
}
