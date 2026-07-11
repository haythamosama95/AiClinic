import { useEffect, useState } from 'react'
import { Button } from '@/components/actions/Button'
import { Dialog } from '@/components/dialog/Dialog'
import {
  StaffFormFields,
  validateStaff,
} from '../forms/StaffFormFields'
import type { StaffFormValues } from '../types'
import type { BranchRecord } from '../types'

export type StaffFormDialogProps = {
  open: boolean
  onOpenChange: (open: boolean) => void
  mode: 'create' | 'edit'
  branches: BranchRecord[]
  initialValues: StaffFormValues
  onSubmit: (values: StaffFormValues) => void
}

export function StaffFormDialog({
  open,
  onOpenChange,
  mode,
  branches,
  initialValues,
  onSubmit,
}: StaffFormDialogProps) {
  const [values, setValues] = useState(initialValues)
  const [errors, setErrors] = useState<Partial<Record<keyof StaffFormValues, string>>>({})

  useEffect(() => {
    if (open) {
      setValues(initialValues)
      setErrors({})
    }
  }, [open, initialValues])

  const handleSubmit = () => {
    const nextErrors = validateStaff(values, mode)
    if (Object.keys(nextErrors).length > 0) {
      setErrors(nextErrors)
      return
    }
    onSubmit(values)
  }

  return (
    <Dialog
      open={open}
      onOpenChange={onOpenChange}
      title={mode === 'create' ? 'Add staff member' : 'Edit staff member'}
      description={
        mode === 'create'
          ? 'Create a sign-in account with a role and branch assignments.'
          : 'Update profile details, role, and branch access.'
      }
      size="lg"
      footer={
        <>
          <Button variant="secondary" onClick={() => onOpenChange(false)}>
            Cancel
          </Button>
          <Button onClick={handleSubmit}>
            {mode === 'create' ? 'Create account' : 'Save changes'}
          </Button>
        </>
      }
    >
      <StaffFormFields
        mode={mode}
        values={values}
        onChange={(patch) => setValues((prev) => ({ ...prev, ...patch }))}
        branches={branches}
        errors={errors}
      />
    </Dialog>
  )
}
