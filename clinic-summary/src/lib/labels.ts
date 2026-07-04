import type {
  AppointmentStatus,
  ShiftStatus,
  VisitPhase,
} from "./types";

export const statusLabels: Record<AppointmentStatus, string> = {
  scheduled: "Scheduled",
  confirmed: "Confirmed",
  checked_in: "Checked in",
  in_progress: "In progress",
  completed: "Completed",
  no_show: "No-show",
  cancelled: "Cancelled",
};

export const visitPhaseLabels: Record<VisitPhase, string> = {
  not_started: "Not started",
  consultation: "Consultation",
  in_consultation: "In consultation",
  completed_visit: "Completed visit",
};

export const shiftStatusLabels: Record<ShiftStatus, string> = {
  on_shift: "On shift",
  break: "On break",
  ending_soon: "Ending soon",
};

export function doctorAssignmentLabel(
  doctorName: string | null,
  doctorOnShift: boolean,
): string {
  if (!doctorName) return "No preferred doctor";
  if (!doctorOnShift) return "No doctor on shift";
  return doctorName;
}
