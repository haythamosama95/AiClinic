import { UserPlus } from 'lucide-react'
import { Button } from '@/components/actions/Button'
import { Dialog } from '@/components/dialog/Dialog'
import { AddPatientFormFields } from './AddPatientFormFields'
import { DuplicatePatientDialog } from './DuplicatePatientDialog'
import { useAddPatientRegistration } from './useAddPatientRegistration'

export type AddPatientDialogProps = {
  open: boolean
  onOpenChange: (open: boolean) => void
  onSuccess?: (patientId: string) => void
}

export function AddPatientDialog({ open, onOpenChange, onSuccess }: AddPatientDialogProps) {
  const registration = useAddPatientRegistration({ open, onOpenChange, onSuccess })

  return (
    <>
      <Dialog
        open={open}
        onOpenChange={onOpenChange}
        title="Add patient"
        description="Register a new patient at your active branch."
        size="lg"
        className="max-h-[min(90dvh,52rem)]"
        footer={
          <>
            <Button
              variant="secondary"
              onClick={() => onOpenChange(false)}
              disabled={registration.submitting}
            >
              Cancel
            </Button>
            <Button
              type="submit"
              form={registration.formId}
              variant="primary"
              loading={registration.submitting}
              leadingIcon={<UserPlus size={16} />}
            >
              Register patient
            </Button>
          </>
        }
      >
        <AddPatientFormFields
          formId={registration.formId}
          values={registration.values}
          errors={registration.errors}
          trimmedName={registration.trimmedName}
          showPreview={registration.showPreview}
          reducedMotion={registration.reducedMotion}
          autoFocus
          onSubmit={registration.handleSubmit}
          onFieldChange={registration.updateField}
        />
      </Dialog>

      <DuplicatePatientDialog
        open={registration.duplicateOpen}
        onOpenChange={registration.setDuplicateOpen}
        candidates={registration.duplicateCandidates}
        loading={registration.submitting}
        onRegisterAnyway={registration.handleRegisterAnyway}
        onOpenPatient={registration.handleOpenExistingPatient}
      />
    </>
  )
}
