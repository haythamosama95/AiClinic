import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/showcase/showcase_primitives.dart';
import 'package:ai_clinic/core/ui/ui.dart';

class InputsShowcase extends StatefulWidget {
  const InputsShowcase({super.key});

  @override
  State<InputsShowcase> createState() => _InputsShowcaseState();
}

class _InputsShowcaseState extends State<InputsShowcase> {
  String _text = '';
  bool _checked = true;
  bool _switchOn = true;
  double _slider = 40;
  String? _select;
  DateTime? _date;
  DateRange _range = const DateRange();
  List<AppFileItem> _files = [];
  List<AppComboboxItem> _multi = [
    const AppComboboxItem(id: 'a', label: 'Cardiology'),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ShowcaseSection(
          title: 'Form field',
          child: AppFormField(
            id: 'patient-name',
            label: 'Patient name',
            required: true,
            description: 'Legal name as on ID.',
            error: _text.isEmpty ? 'Required' : null,
            child: AppTextInput(
              hintText: 'Full name',
              invalid: _text.isEmpty,
              onChanged: (v) => setState(() => _text = v),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.s10),
        ShowcaseSection(
          title: 'Text inputs',
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth > 600
                  ? 320.0
                  : constraints.maxWidth;
              return Wrap(
                spacing: AppSpacing.s4,
                runSpacing: AppSpacing.s4,
                children: [
                  SizedBox(
                    width: width,
                    child: const AppTextInput(hintText: 'Text input'),
                  ),
                  SizedBox(
                    width: width,
                    child: AppSearchInput(onValueChange: (_) {}),
                  ),
                  SizedBox(width: width, child: const AppPasswordInput()),
                  SizedBox(
                    width: width,
                    child: const AppTextarea(hintText: 'Notes…'),
                  ),
                ],
              );
            },
          ),
        ),
        const SizedBox(height: AppSpacing.s10),
        ShowcaseSection(
          title: 'Numeric & money',
          child: Wrap(
            spacing: AppSpacing.s4,
            runSpacing: AppSpacing.s4,
            children: [
              SizedBox(
                width: 200,
                child: AppNumberInput(onValueChange: (_) {}),
              ),
              SizedBox(width: 220, child: AppMoneyField(hintText: '0.00')),
              SizedBox(width: 280, child: AppPhoneInput(onChanged: (_) {})),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.s10),
        ShowcaseSection(
          title: 'Select & combobox',
          child: Wrap(
            spacing: AppSpacing.s4,
            runSpacing: AppSpacing.s4,
            children: [
              SizedBox(
                width: 240,
                child: AppSelect(
                  options: const [
                    AppSelectOption(value: 'a', label: 'Option A'),
                    AppSelectOption(value: 'b', label: 'Option B'),
                  ],
                  value: _select,
                  onValueChange: (v) => setState(() => _select = v),
                ),
              ),
              SizedBox(
                width: 240,
                child: AppCombobox(
                  items: const [
                    AppComboboxItem(id: 'x', label: 'Amoxicillin'),
                    AppComboboxItem(id: 'y', label: 'Ibuprofen'),
                  ],
                  onValueChange: (_) {},
                ),
              ),
              SizedBox(
                width: 280,
                child: AppMultiSelect(
                  options: const [
                    AppComboboxItem(id: 'a', label: 'Cardiology'),
                    AppComboboxItem(id: 'b', label: 'Dermatology'),
                  ],
                  value: _multi,
                  onValueChange: (v) => setState(() => _multi = v),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.s10),
        ShowcaseSection(
          title: 'Choice controls',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppCheckbox(
                label: 'Accept terms',
                value: _checked
                    ? AppCheckboxState.checked
                    : AppCheckboxState.unchecked,
                onChanged: (v) =>
                    setState(() => _checked = v == AppCheckboxState.checked),
              ),
              AppRadioGroup(
                value: 'a',
                onValueChange: (_) {},
                options: const [
                  AppRadioOption(value: 'a', label: 'In-person'),
                  AppRadioOption(value: 'b', label: 'Telehealth'),
                ],
              ),
              AppSwitch(
                label: 'Notifications',
                value: _switchOn,
                onChanged: (v) => setState(() => _switchOn = v),
              ),
              SizedBox(
                width: 280,
                child: AppSlider(
                  value: _slider,
                  onChanged: (v) => setState(() => _slider = v),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.s10),
        ShowcaseSection(
          title: 'Date & time',
          child: Wrap(
            spacing: AppSpacing.s4,
            runSpacing: AppSpacing.s4,
            children: [
              SizedBox(
                width: 220,
                child: AppDatePicker(
                  value: _date,
                  onValueChange: (d) => setState(() => _date = d),
                ),
              ),
              SizedBox(width: 220, child: AppTimePicker(onValueChange: (_) {})),
              SizedBox(
                width: 280,
                child: AppDateRangePicker(
                  value: _range,
                  onValueChange: (r) => setState(() => _range = r),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.s10),
        ShowcaseSection(
          title: 'File dropzone',
          child: AppFileDropzone(
            files: _files,
            onFilesChange: (f) => setState(() => _files = f),
          ),
        ),
        const SizedBox(height: AppSpacing.s10),
        ShowcaseSection(
          title: 'Spinner',
          child: Wrap(
            spacing: AppSpacing.s4,
            children: AppSpinnerSize.values
                .map(
                  (s) => ShowcaseDemo(
                    label: s.name,
                    child: AppSpinner(size: s),
                  ),
                )
                .toList(),
          ),
        ),
      ],
    );
  }
}
