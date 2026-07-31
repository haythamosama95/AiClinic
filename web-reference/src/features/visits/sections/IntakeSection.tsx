import { motion } from 'motion/react'
import { FormField } from '@/components/ui/form-field/FormField'
import { Textarea } from '@/components/ui/textarea/Textarea'
import { motionPresets, resolveTransition, staggerChildren } from '@/lib/motion'
import { MedicalBackgroundEditor } from '../components/MedicalBackgroundEditor'
import {
  ALLERGY_OPTIONS,
  CHRONIC_CONDITION_OPTIONS,
  MEDICATION_OPTIONS,
} from '../mock-data'
import type { VisitFormData } from '../types'

export type IntakeSectionProps = {
  form: VisitFormData
  onChange: (patch: Partial<VisitFormData>) => void
}

export function IntakeSection({ form, onChange }: IntakeSectionProps) {
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
          <h2 className="font-display text-h2 text-text-primary">Patient intake</h2>
          <p className="mt-1 text-body-sm text-text-secondary">
            Record the presenting complaint and relevant medical background.
          </p>
        </header>
      </motion.div>

      <motion.div variants={preset.variants} transition={transition}>
        <FormField
          id="complaint"
          label="Chief complaint"
          required
          hint="The primary reason for today's visit, in the patient's own words."
        >
          <Textarea
            id="complaint"
            rows={3}
            autoGrow
            placeholder="e.g. Persistent cough for 5 days with mild fever…"
            value={form.complaint}
            onChange={(e) => onChange({ complaint: e.target.value })}
          />
        </FormField>
      </motion.div>

      <motion.div variants={preset.variants} transition={transition}>
        <FormField
          id="history"
          label="History of present illness"
          hint="Onset, duration, severity, aggravating and relieving factors."
        >
          <Textarea
            id="history"
            rows={4}
            autoGrow
            placeholder="Describe the timeline and progression of symptoms…"
            value={form.history}
            onChange={(e) => onChange({ history: e.target.value })}
          />
        </FormField>
      </motion.div>

      <motion.div variants={preset.variants} transition={transition}>
        <MedicalBackgroundEditor
          chronicConditions={form.chronicConditions}
          allergies={form.allergies}
          currentMedications={form.currentMedications}
          chronicConditionOptions={CHRONIC_CONDITION_OPTIONS}
          allergyOptions={ALLERGY_OPTIONS}
          medicationOptions={MEDICATION_OPTIONS}
          onChronicConditionsChange={(chronicConditions) => onChange({ chronicConditions })}
          onAllergiesChange={(allergies) => onChange({ allergies })}
          onCurrentMedicationsChange={(currentMedications) => onChange({ currentMedications })}
        />
      </motion.div>
    </motion.div>
  )
}
