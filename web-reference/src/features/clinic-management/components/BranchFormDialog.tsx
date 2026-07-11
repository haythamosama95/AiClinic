import { useEffect, useState } from 'react'
import { Button } from '@/components/actions/Button'
import { Dialog } from '@/components/dialog/Dialog'
import {
  BranchFormFields,
  validateBranch,
} from '../forms/BranchFormFields'
import type { BranchFormValues } from '../types'

export type BranchFormDialogProps = {
  open: boolean
  onOpenChange: (open: boolean) => void
  mode: 'create' | 'edit'
  initialValues: BranchFormValues
  onSubmit: (values: BranchFormValues) => void
}

export function BranchFormDialog({
  open,
  onOpenChange,
  mode,
  initialValues,
  onSubmit,
}: BranchFormDialogProps) {
  const [values, setValues] = useState(initialValues)
  const [errors, setErrors] = useState<Partial<Record<keyof BranchFormValues, string>>>({})

  useEffect(() => {
    if (open) {
      setValues(initialValues)
      setErrors({})
    }
  }, [open, initialValues])

  const handleSubmit = () => {
    const nextErrors = validateBranch(values, mode === 'create')
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
      title={mode === 'create' ? 'Add branch' : 'Edit branch'}
      description={
        mode === 'create'
          ? 'Start with your main branch. Additional branches can be added later.'
          : 'Update location details and working hours for this branch.'
      }
      size="lg"
      footer={
        <>
          <Button variant="secondary" onClick={() => onOpenChange(false)}>
            Cancel
          </Button>
          <Button onClick={handleSubmit}>
            {mode === 'create' ? 'Create branch' : 'Save changes'}
          </Button>
        </>
      }
    >
      <BranchFormFields
        values={values}
        onChange={(patch) => setValues((prev) => ({ ...prev, ...patch }))}
        errors={errors}
      />
    </Dialog>
  )
}
