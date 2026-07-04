import type { ClinicSummary } from "./types";

export function getSummaryStats(summary: ClinicSummary) {
  return {
    appointmentCount: summary.appointments.length,
    inProgress: summary.appointments.filter((a) => a.status === "in_progress")
      .length,
    waiting: summary.waitingRoom.length,
    onShift: summary.doctors.filter((d) => d.shiftStatus === "on_shift").length,
    completed: summary.appointments.filter((a) => a.status === "completed")
      .length,
    checkedIn: summary.appointments.filter((a) => a.status === "checked_in")
      .length,
  };
}
