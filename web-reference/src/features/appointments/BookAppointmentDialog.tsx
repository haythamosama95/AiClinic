import { ArrowLeft, ArrowRight, CalendarPlus } from 'lucide-react'
import { Button } from '@/components/actions/Button'
import { Dialog } from '@/components/dialog/Dialog'
import { BookAppointmentStep1 } from './BookAppointmentStep1'
import { BookAppointmentStep2 } from './BookAppointmentStep2'
import { useBookAppointment, type UseBookAppointmentOptions } from './useBookAppointment'

export type BookAppointmentDialogProps = UseBookAppointmentOptions

export function BookAppointmentDialog(props: BookAppointmentDialogProps) {
  const booking = useBookAppointment(props)

  const stepDescriptions = [
    'Patient, branch, and optional doctor preference.',
    'Pick a day and choose an open time slot.',
  ]

  return (
    <Dialog
      open={props.open}
      onOpenChange={props.onOpenChange}
      title="Book appointment"
      description={stepDescriptions[booking.step]}
      size="lg"
      className="max-h-[min(92dvh,54rem)]"
      footer={
        <>
          {booking.step > 0 ? (
            <Button
              variant="secondary"
              onClick={booking.goBack}
              disabled={booking.submitting}
              leadingIcon={<ArrowLeft size={16} />}
            >
              Back
            </Button>
          ) : (
            <Button
              variant="secondary"
              onClick={() => props.onOpenChange(false)}
              disabled={booking.submitting}
            >
              Cancel
            </Button>
          )}

          {booking.step === 0 ? (
            <Button
              variant="primary"
              onClick={booking.goNext}
              trailingIcon={<ArrowRight size={16} />}
            >
              Choose time
            </Button>
          ) : (
            <Button
              variant="primary"
              onClick={booking.handleConfirm}
              loading={booking.submitting}
              leadingIcon={<CalendarPlus size={16} />}
            >
              Confirm booking
            </Button>
          )}
        </>
      }
    >
      {booking.step === 0 ? (
        <BookAppointmentStep1
          draft={booking.draft}
          errors={booking.errors}
          patientItems={booking.patientItems}
          selectedPatient={booking.selectedPatient}
          branchOptions={booking.branchOptions}
          doctorOptions={booking.doctorOptions}
          doctorCount={booking.doctorCount}
          onFieldChange={booking.updateDraft}
        />
      ) : (
        <BookAppointmentStep2
          branchName={booking.branch?.name ?? '—'}
          patientName={booking.selectedPatient?.label ?? '—'}
          preferredDoctorName={booking.preferredDoctor?.fullName ?? null}
          hasPreferredDoctor={booking.hasPreferredDoctor}
          dayOptions={booking.dayOptions}
          selectedDate={booking.draft.date}
          selectedTime={booking.draft.time}
          slots={booking.slots}
          errors={booking.errors}
          onDateChange={(date) => booking.updateDraft({ date })}
          onTimeChange={(time) => booking.updateDraft({ time })}
        />
      )}
    </Dialog>
  )
}
