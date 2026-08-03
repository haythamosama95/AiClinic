import { ExternalLink } from 'lucide-react'
import { Button } from '@/components/actions/Button'
import { Avatar } from '@/components/avatar/Avatar'
import { Dialog } from '@/components/dialog/Dialog'
import { List, ListItem } from '@/components/list/List'
import { formatDate, patientFullName, type Patient } from '@/data/patients'

export type DuplicatePatientDialogProps = {
  open: boolean
  onOpenChange: (open: boolean) => void
  candidates: Patient[]
  onRegisterAnyway: () => void
  onOpenPatient: (patientId: string) => void
  loading?: boolean
}

export function DuplicatePatientDialog({
  open,
  onOpenChange,
  candidates,
  onRegisterAnyway,
  onOpenPatient,
  loading,
}: DuplicatePatientDialogProps) {
  return (
    <Dialog
      open={open}
      onOpenChange={onOpenChange}
      title="Possible duplicate found"
      description="A patient with similar details already exists. Review the matches below before creating a new record."
      size="md"
      footer={
        <>
          <Button variant="secondary" onClick={() => onOpenChange(false)} disabled={loading}>
            Go back
          </Button>
          <Button variant="primary" loading={loading} onClick={onRegisterAnyway}>
            Register anyway
          </Button>
        </>
      }
    >
      <div className="space-y-4">
        <p className="text-body-sm text-text-secondary">
          {candidates.length === 1
            ? '1 existing patient matches the details you entered.'
            : `${candidates.length} existing patients match the details you entered.`}
        </p>

        <List className="overflow-hidden rounded-lg border border-border-default">
          {candidates.map((patient) => (
            <ListItem
              key={patient.id}
              leading={<Avatar name={patientFullName(patient)} size="sm" />}
              primary={patientFullName(patient)}
              secondary={`${patient.mrn} · ${patient.phone}${patient.dateOfBirth ? ` · DOB ${formatDate(patient.dateOfBirth)}` : ''}`}
              trailing={
                <Button
                  variant="ghost"
                  size="sm"
                  leadingIcon={<ExternalLink size={14} />}
                  onClick={() => onOpenPatient(patient.id)}
                >
                  Open
                </Button>
              }
            />
          ))}
        </List>
      </div>
    </Dialog>
  )
}
