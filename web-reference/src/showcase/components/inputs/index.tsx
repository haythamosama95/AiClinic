import type { ShowcaseSectionDef } from '../../registry'
import {
  CheckboxShowcase,
  RadioGroupShowcase,
  SwitchShowcase,
} from './ChoiceControlsShowcase'
import { ComboboxShowcase } from './ComboboxShowcase'
import {
  DatePickerShowcase,
  DateRangePickerShowcase,
  TimePickerShowcase,
} from './DateTimeShowcase'
import { FileDropzoneShowcase } from './FileDropzoneShowcase'
import { FormFieldShowcase } from './FormFieldShowcase'
import { MoneyFieldShowcase } from './MoneyFieldShowcase'
import { MultiSelectShowcase } from './MultiSelectShowcase'
import { NumberInputShowcase } from './NumberInputShowcase'
import { PasswordInputShowcase } from './PasswordInputShowcase'
import { PhoneInputShowcase } from './PhoneInputShowcase'
import { SearchInputShowcase } from './SearchInputShowcase'
import { SelectShowcase } from './SelectShowcase'
import { SliderShowcase } from './SliderShowcase'
import { TextInputShowcase } from './TextInputShowcase'
import { TextareaShowcase } from './TextareaShowcase'

export const inputsSections: ShowcaseSectionDef[] = [
  {
    id: 'form-field',
    title: 'Form field',
    description: 'Label, hint, error, and required wrapper for controls.',
    group: 'inputs',
    component: FormFieldShowcase,
    status: 'ready',
  },
  {
    id: 'text-input',
    title: 'Text input',
    group: 'inputs',
    component: TextInputShowcase,
    status: 'ready',
  },
  {
    id: 'textarea',
    title: 'Textarea',
    group: 'inputs',
    component: TextareaShowcase,
    status: 'ready',
  },
  {
    id: 'search-input',
    title: 'Search input',
    group: 'inputs',
    component: SearchInputShowcase,
    status: 'ready',
  },
  {
    id: 'password-input',
    title: 'Password input',
    group: 'inputs',
    component: PasswordInputShowcase,
    status: 'ready',
  },
  {
    id: 'number-input',
    title: 'Number input',
    group: 'inputs',
    component: NumberInputShowcase,
    status: 'ready',
  },
  {
    id: 'money-field',
    title: 'Money field',
    group: 'inputs',
    component: MoneyFieldShowcase,
    status: 'ready',
  },
  {
    id: 'phone-input',
    title: 'Phone input',
    group: 'inputs',
    component: PhoneInputShowcase,
    status: 'ready',
  },
  {
    id: 'select',
    title: 'Select',
    group: 'inputs',
    component: SelectShowcase,
    status: 'ready',
  },
  {
    id: 'combobox',
    title: 'Combobox / Autocomplete',
    description: 'Async loading, empty, and ineligible-with-reason states.',
    group: 'inputs',
    component: ComboboxShowcase,
    status: 'ready',
  },
  {
    id: 'multi-select',
    title: 'Multi-select / Token',
    group: 'inputs',
    component: MultiSelectShowcase,
    status: 'ready',
  },
  {
    id: 'checkbox',
    title: 'Checkbox',
    group: 'inputs',
    component: CheckboxShowcase,
    status: 'ready',
  },
  {
    id: 'radio-group',
    title: 'Radio group',
    group: 'inputs',
    component: RadioGroupShowcase,
    status: 'ready',
  },
  {
    id: 'switch',
    title: 'Switch',
    group: 'inputs',
    component: SwitchShowcase,
    status: 'ready',
  },
  {
    id: 'date-picker',
    title: 'Date picker',
    group: 'inputs',
    component: DatePickerShowcase,
    status: 'ready',
  },
  {
    id: 'time-picker',
    title: 'Time picker',
    group: 'inputs',
    component: TimePickerShowcase,
    status: 'ready',
  },
  {
    id: 'date-range-picker',
    title: 'Date range picker',
    group: 'inputs',
    component: DateRangePickerShowcase,
    status: 'ready',
  },
  {
    id: 'file-dropzone',
    title: 'File dropzone',
    group: 'inputs',
    component: FileDropzoneShowcase,
    status: 'ready',
  },
  {
    id: 'slider',
    title: 'Slider',
    group: 'inputs',
    component: SliderShowcase,
    status: 'ready',
  },
]
