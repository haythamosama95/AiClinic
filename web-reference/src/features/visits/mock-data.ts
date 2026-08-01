import type { ComboboxItem } from '@/components/ui/combobox/Combobox'
import type { SelectOption } from '@/components/ui/select/Select'
import type { VitalSignDefinition } from './types'

export const VITAL_SIGN_CATALOG: VitalSignDefinition[] = [
  { id: 'bp', label: 'Blood pressure', unit: 'mmHg', placeholder: '120/80' },
  { id: 'hr', label: 'Heart rate', unit: 'bpm', placeholder: '72' },
  { id: 'temp', label: 'Temperature', unit: '°C', placeholder: '36.8' },
  { id: 'spo2', label: 'SpO₂', unit: '%', placeholder: '98' },
  { id: 'rr', label: 'Respiratory rate', unit: '/min', placeholder: '16' },
  { id: 'weight', label: 'Weight', unit: 'kg', placeholder: '68' },
  { id: 'height', label: 'Height', unit: 'cm', placeholder: '165' },
  { id: 'bmi', label: 'BMI', unit: 'kg/m²', placeholder: '24.2' },
]

export const CHRONIC_CONDITION_OPTIONS: ComboboxItem[] = [
  { id: 'dm2', label: 'Type 2 diabetes', meta: 'E11' },
  { id: 'htn', label: 'Hypertension', meta: 'I10' },
  { id: 'asthma', label: 'Asthma', meta: 'J45' },
  { id: 'ckd', label: 'Chronic kidney disease', meta: 'N18' },
  { id: 'cad', label: 'Coronary artery disease', meta: 'I25' },
  { id: 'hypothyroid', label: 'Hypothyroidism', meta: 'E03' },
  { id: 'copd', label: 'COPD', meta: 'J44' },
  { id: 'oa', label: 'Osteoarthritis', meta: 'M19' },
]

export const ALLERGY_OPTIONS: ComboboxItem[] = [
  { id: 'penicillin', label: 'Penicillin', meta: 'Drug' },
  { id: 'sulfa', label: 'Sulfonamides', meta: 'Drug' },
  { id: 'nsaid', label: 'NSAIDs', meta: 'Drug' },
  { id: 'latex', label: 'Latex', meta: 'Environmental' },
  { id: 'peanut', label: 'Peanuts', meta: 'Food' },
  { id: 'shellfish', label: 'Shellfish', meta: 'Food' },
  { id: 'dust', label: 'Dust mites', meta: 'Environmental' },
  { id: 'pollen', label: 'Pollen', meta: 'Environmental' },
]

export const MEDICATION_OPTIONS: ComboboxItem[] = [
  { id: 'metformin', label: 'Metformin', meta: '500 mg' },
  { id: 'amlodipine', label: 'Amlodipine', meta: '5 mg' },
  { id: 'lisinopril', label: 'Lisinopril', meta: '10 mg' },
  { id: 'atorvastatin', label: 'Atorvastatin', meta: '20 mg' },
  { id: 'omeprazole', label: 'Omeprazole', meta: '20 mg' },
  { id: 'levothyroxine', label: 'Levothyroxine', meta: '50 mcg' },
  { id: 'salbutamol', label: 'Salbutamol inhaler', meta: 'PRN' },
  { id: 'paracetamol', label: 'Paracetamol', meta: '500 mg' },
]

export const INVESTIGATION_OPTIONS: ComboboxItem[] = [
  { id: 'cbc', label: 'Complete blood count', meta: 'Lab' },
  { id: 'bmp', label: 'Basic metabolic panel', meta: 'Lab' },
  { id: 'lipid', label: 'Lipid profile', meta: 'Lab' },
  { id: 'hba1c', label: 'HbA1c', meta: 'Lab' },
  { id: 'ecg', label: 'ECG', meta: 'Imaging' },
  { id: 'cxr', label: 'Chest X-ray', meta: 'Imaging' },
  { id: 'ua', label: 'Urinalysis', meta: 'Lab' },
  { id: 'tsh', label: 'TSH', meta: 'Lab' },
  { id: 'us-abd', label: 'Abdominal ultrasound', meta: 'Imaging' },
  { id: 'mri', label: 'MRI', meta: 'Imaging' },
]

export const TREATMENT_MEDICATION_OPTIONS: ComboboxItem[] = [
  { id: 'amoxicillin', label: 'Amoxicillin', meta: 'Antibiotic' },
  { id: 'azithromycin', label: 'Azithromycin', meta: 'Antibiotic' },
  { id: 'ibuprofen', label: 'Ibuprofen', meta: 'NSAID' },
  { id: 'prednisone', label: 'Prednisone', meta: 'Corticosteroid' },
  { id: 'cetirizine', label: 'Cetirizine', meta: 'Antihistamine' },
  { id: 'omeprazole-rx', label: 'Omeprazole', meta: 'PPI' },
  { id: 'salbutamol-rx', label: 'Salbutamol inhaler', meta: 'Bronchodilator' },
  { id: 'metformin-rx', label: 'Metformin', meta: 'Antidiabetic' },
]

export const FREQUENCY_OPTIONS: SelectOption[] = [
  { value: 'od', label: 'Once daily' },
  { value: 'bd', label: 'Twice daily' },
  { value: 'tds', label: 'Three times daily' },
  { value: 'qid', label: 'Four times daily' },
  { value: 'q4h', label: 'Every 4 hours' },
  { value: 'q6h', label: 'Every 6 hours' },
  { value: 'q8h', label: 'Every 8 hours' },
  { value: 'prn', label: 'As needed' },
  { value: 'stat', label: 'Single dose' },
]

export const DURATION_OPTIONS: SelectOption[] = [
  { value: '3d', label: '3 days' },
  { value: '5d', label: '5 days' },
  { value: '7d', label: '7 days' },
  { value: '10d', label: '10 days' },
  { value: '14d', label: '14 days' },
  { value: '21d', label: '21 days' },
  { value: '30d', label: '30 days' },
  { value: 'ongoing', label: 'Ongoing' },
]

export function getVitalSignById(id: string): VitalSignDefinition | undefined {
  return VITAL_SIGN_CATALOG.find((v) => v.id === id)
}

<<<<<<< HEAD
=======
export function getChronicConditionById(id: string): ComboboxItem | undefined {
  return CHRONIC_CONDITION_OPTIONS.find((item) => item.id === id)
}

export function getAllergyById(id: string): ComboboxItem | undefined {
  return ALLERGY_OPTIONS.find((item) => item.id === id)
}

export function getCurrentMedicationById(id: string): ComboboxItem | undefined {
  return MEDICATION_OPTIONS.find((item) => item.id === id)
}

>>>>>>> master
export function getInvestigationById(id: string): ComboboxItem | undefined {
  return INVESTIGATION_OPTIONS.find((item) => item.id === id)
}

export function getInvestigationLabel(id: string): string {
  return getInvestigationById(id)?.label ?? id
}

export function getMedicationLabel(id: string): string {
  return TREATMENT_MEDICATION_OPTIONS.find((m) => m.id === id)?.label ?? id
}

export function getFrequencyLabel(value: string): string {
  return FREQUENCY_OPTIONS.find((f) => f.value === value)?.label ?? value
}

export function getDurationLabel(value: string): string {
  return DURATION_OPTIONS.find((d) => d.value === value)?.label ?? value
}
