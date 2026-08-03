import { useId } from 'react'
import { DatePicker, DateRangePicker, FormField, TimePicker } from '@/components/ui'
import { ShowcaseSection } from '../../ShowcasePrimitives'

export function DatePickerShowcase() {
  const id = useId()
  return (
    <ShowcaseSection
      id="date-picker"
      title="Date picker"
      componentName="DatePicker"
      description="Calendar popover with keyboard entry, min/max, RTL calendar mirror."
    >
      <FormField id={id} label="Promotion start date">
        <DatePicker id={id} className="max-w-xs" />
      </FormField>
    </ShowcaseSection>
  )
}

export function TimePickerShowcase() {
  const id = useId()
  return (
    <ShowcaseSection
      id="time-picker"
      title="Time picker"
      componentName="TimePicker"
      description="Appointment times with 15-minute step granularity."
    >
      <FormField id={id} label="Appointment time">
        <TimePicker id={id} className="max-w-xs" />
      </FormField>
    </ShowcaseSection>
  )
}

export function DateRangePickerShowcase() {
  const id = useId()
  return (
    <ShowcaseSection
      id="date-range-picker"
      title="Date range picker"
      componentName="DateRangePicker"
      description="Dual-month popover with presets and inclusive-range messaging."
    >
      <FormField id={id} label="Report period">
        <DateRangePicker id={id} className="max-w-xs" />
      </FormField>
    </ShowcaseSection>
  )
}
