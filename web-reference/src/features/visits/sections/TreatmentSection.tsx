import { motion } from 'motion/react'
import { FormField } from '@/components/ui/form-field/FormField'
import { FileDropzone } from '@/components/ui/file-dropzone/FileDropzone'
import { Textarea } from '@/components/ui/textarea/Textarea'
import { motionPresets, resolveTransition, staggerChildren } from '@/lib/motion'
import { InvestigationsEditor } from '../components/InvestigationsEditor'
import { TreatmentPlanEditor } from '../components/TreatmentPlanEditor'
import type { VisitFormData } from '../types'

export type TreatmentSectionProps = {
  form: VisitFormData
  onChange: (patch: Partial<VisitFormData>) => void
}

export function TreatmentSection({ form, onChange }: TreatmentSectionProps) {
  const preset = motionPresets['slide-up']
  const transition = resolveTransition(preset)

  return (
    <motion.div
      variants={staggerChildren(40)}
      initial="hidden"
      animate="visible"
      className="space-y-6"
    >
      <motion.div variants={preset.variants} transition={transition}>
        <header className="mb-6">
          <h2 className="font-display text-h2 text-text-primary">Treatment</h2>
          <p className="mt-1 text-body-sm text-text-secondary">
            Plan investigations, prescribe treatments, and attach supporting documents.
          </p>
        </header>
      </motion.div>

      <motion.div variants={preset.variants} transition={transition}>
        <FormField
          id="treatment-notes"
          label="Treatment notes"
          hint="Clinical reasoning, patient education, and follow-up instructions."
        >
          <Textarea
            id="treatment-notes"
            rows={3}
            autoGrow
            placeholder="Rest, hydration, return if symptoms worsen…"
            value={form.treatmentNotes}
            onChange={(e) => onChange({ treatmentNotes: e.target.value })}
          />
        </FormField>
      </motion.div>

      <motion.div variants={preset.variants} transition={transition}>
        <FormField
          id="investigations"
          label="Investigations needed"
          helperText="Add each test via the dialog with any relevant clinical notes."
        >
          <InvestigationsEditor
            entries={form.investigationsNeeded}
            onChange={(investigationsNeeded) => onChange({ investigationsNeeded })}
          />
        </FormField>
      </motion.div>

      <motion.div variants={preset.variants} transition={transition}>
        <FormField
          id="treatment-plan"
          label="Treatment plan"
          helperText="Add each prescription via the dialog with dosage, frequency, and duration."
        >
          <TreatmentPlanEditor
            entries={form.treatmentPlan}
            onChange={(treatmentPlan) => onChange({ treatmentPlan })}
          />
        </FormField>
      </motion.div>

      <motion.div variants={preset.variants} transition={transition}>
        <FormField
          id="documents"
          label="Attachments"
          helperText="Upload lab results, referrals, or other visit documents (PDF, JPG, PNG — max 10 MB)."
        >
          <FileDropzone
            id="documents"
            files={form.documents}
            onFilesChange={(documents) => onChange({ documents })}
            onUpload={async () => {
              await new Promise((r) => setTimeout(r, 800))
            }}
          />
        </FormField>
      </motion.div>
    </motion.div>
  )
}
