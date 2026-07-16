import { motion } from 'motion/react'
import { FormField } from '@/components/ui/form-field/FormField'
import { Textarea } from '@/components/ui/textarea/Textarea'
import { motionPresets, resolveTransition, staggerChildren } from '@/lib/motion'
import { VitalSignsEditor } from '../components/VitalSignsEditor'
import type { VisitFormData } from '../types'

export type FindingsSectionProps = {
  form: VisitFormData
  onChange: (patch: Partial<VisitFormData>) => void
}

export function FindingsSection({ form, onChange }: FindingsSectionProps) {
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
          <h2 className="font-display text-h2 text-text-primary">Findings & diagnosis</h2>
          <p className="mt-1 text-body-sm text-text-secondary">
            Document physical examination, vital signs, and clinical assessment.
          </p>
        </header>
      </motion.div>

      <motion.div variants={preset.variants} transition={transition}>
        <FormField
          id="examination"
          label="Physical examination"
          hint="Objective findings from the clinical examination."
        >
          <Textarea
            id="examination"
            rows={4}
            autoGrow
            placeholder="General appearance, systems examined, notable findings…"
            value={form.examination}
            onChange={(e) => onChange({ examination: e.target.value })}
          />
        </FormField>
      </motion.div>

      <motion.div variants={preset.variants} transition={transition}>
        <FormField
          id="vital-signs"
          label="Vital signs"
          helperText="Add each measurement via the dialog; recorded values appear as cards below."
        >
          <VitalSignsEditor
            entries={form.vitalSigns}
            onChange={(vitalSigns) => onChange({ vitalSigns })}
          />
        </FormField>
      </motion.div>

      <motion.div variants={preset.variants} transition={transition}>
        <FormField
          id="diagnosis"
          label="Diagnosis"
          required
          hint="Primary and secondary diagnoses for this encounter."
        >
          <Textarea
            id="diagnosis"
            rows={3}
            autoGrow
            placeholder="e.g. Acute upper respiratory infection (J06.9)…"
            value={form.diagnosis}
            onChange={(e) => onChange({ diagnosis: e.target.value })}
          />
        </FormField>
      </motion.div>
    </motion.div>
  )
}
