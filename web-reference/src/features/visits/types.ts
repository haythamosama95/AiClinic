import type { ComboboxItem } from '@/components/ui/combobox/Combobox'
import type { FileItem } from '@/components/ui/file-dropzone/FileDropzone'

export type VisitPhase = 'intake' | 'findings' | 'treatment' | 'summary' | 'billing' | 'completed'

export type VitalSignDefinition = {
  id: string
  label: string
  unit: string
  placeholder: string
}

export type VitalSignEntry = {
  id: string
  vitalSignId: string
  value: string
}

export type TreatmentPlanEntry = {
  id: string
  medicationId: string
  dosage: string
  frequency: string
  duration: string
}

export type InvestigationEntry = {
  id: string
  investigationId: string
  note: string
}

export type VisitFormData = {
  complaint: string
  history: string
  chronicConditions: ComboboxItem[]
  allergies: ComboboxItem[]
  currentMedications: ComboboxItem[]
  examination: string
  diagnosis: string
  vitalSigns: VitalSignEntry[]
  treatmentNotes: string
  investigationsNeeded: InvestigationEntry[]
  treatmentPlan: TreatmentPlanEntry[]
  documents: FileItem[]
}

export const EMPTY_VISIT_FORM: VisitFormData = {
  complaint: '',
  history: '',
  chronicConditions: [],
  allergies: [],
  currentMedications: [],
  examination: '',
  diagnosis: '',
  vitalSigns: [],
  treatmentNotes: '',
  investigationsNeeded: [],
  treatmentPlan: [],
  documents: [],
}
