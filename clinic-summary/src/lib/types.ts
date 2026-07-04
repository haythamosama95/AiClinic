export type AppointmentStatus =
  | "scheduled"
  | "confirmed"
  | "checked_in"
  | "in_progress"
  | "completed"
  | "no_show"
  | "cancelled";

export type VisitPhase =
  | "not_started"
  | "consultation"
  | "in_consultation"
  | "completed_visit";

export type ShiftStatus = "on_shift" | "break" | "ending_soon";

export interface Appointment {
  id: string;
  startTime: string;
  endTime?: string;
  status: AppointmentStatus;
  patientName: string;
  appointmentType: string;
  doctorName: string | null;
  doctorOnShift: boolean;
  patientChoseDoctor: boolean;
  visitPhase: VisitPhase;
  waitMinutes?: number;
}

export interface DoctorOnShift {
  id: string;
  name: string;
  shiftStatus: ShiftStatus;
  currentPatient: string | null;
  sessionMinutes?: number;
}

export interface WaitingPatient {
  id: string;
  patientName: string;
  doctorName: string | null;
  patientChoseDoctor: boolean;
  scheduledTime: string;
  waitMinutes: number;
}

export interface ClinicSummary {
  date: string;
  appointments: Appointment[];
  doctors: DoctorOnShift[];
  waitingRoom: WaitingPatient[];
}
