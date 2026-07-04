export type VisitStatus = "in_progress" | "completed" | "scheduled";

export interface PatientContext {
  name: string;
  age: number;
  sex: string;
  mrn: string;
  dateOfBirth: string;
  phone?: string;
}

export interface DoctorContext {
  name: string;
  specialty: string;
}

export interface VisitContext {
  id: string;
  dateTime: string;
  status: VisitStatus;
  type: string;
  branch: string;
}

export interface SafetyAllergy {
  substance: string;
  reaction: string;
}

export interface PatientSafety {
  allergies: SafetyAllergy[];
  currentMedications: string[];
  chronicConditions: string[];
  lastVitals: VitalSign[];
}

export interface ClinicalNote {
  complaint: string;
  history: string;
  examination: string;
  diagnosis: string;
  plan: string;
}

export interface VitalSign {
  type: string;
  value: string;
  unit: string;
  measuredAt: string;
}

export interface Treatment {
  id: string;
  medication: string;
  dose: string;
  frequency: string;
  duration: string;
  instructions?: string;
}

export type InvestigationStatus = "ordered" | "pending" | "completed";

export interface Investigation {
  id: string;
  name: string;
  status: InvestigationStatus;
  orderedAt: string;
  result?: string;
  resultRecordedAt?: string;
}

export interface Attachment {
  id: string;
  name: string;
  fileType: string;
  uploadedAt: string;
  sizeLabel: string;
}

export interface EncounterWorkspace {
  visit: VisitContext;
  patient: PatientContext;
  doctor: DoctorContext;
  safety: PatientSafety;
  note: ClinicalNote;
  vitals: VitalSign[];
  treatments: Treatment[];
  investigations: Investigation[];
  attachments: Attachment[];
}
