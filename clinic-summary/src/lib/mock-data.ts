import type { ClinicSummary } from "./types";

const today = new Date();
today.setHours(0, 0, 0, 0);

function at(hour: number, minute = 0): string {
  const d = new Date(today);
  d.setHours(hour, minute, 0, 0);
  return d.toISOString();
}

export const clinicSummary: ClinicSummary = {
  date: today.toISOString(),
  appointments: [
    {
      id: "a1",
      startTime: at(8, 30),
      endTime: at(9, 5),
      status: "completed",
      patientName: "Layla Hassan",
      appointmentType: "Follow-up",
      doctorName: "Dr. Omar Khalil",
      doctorOnShift: true,
      patientChoseDoctor: true,
      visitPhase: "completed_visit",
    },
    {
      id: "a2",
      startTime: at(9, 15),
      status: "in_progress",
      patientName: "Youssef Nader",
      appointmentType: "General consultation",
      doctorName: "Dr. Sara Mansour",
      doctorOnShift: true,
      patientChoseDoctor: false,
      visitPhase: "in_consultation",
    },
    {
      id: "a3",
      startTime: at(9, 45),
      status: "checked_in",
      patientName: "Nadia Farouk",
      appointmentType: "New patient",
      doctorName: "Dr. Omar Khalil",
      doctorOnShift: true,
      patientChoseDoctor: true,
      visitPhase: "consultation",
      waitMinutes: 12,
    },
    {
      id: "a4",
      startTime: at(10, 0),
      status: "confirmed",
      patientName: "Karim El-Sayed",
      appointmentType: "Lab review",
      doctorName: null,
      doctorOnShift: false,
      patientChoseDoctor: false,
      visitPhase: "not_started",
    },
    {
      id: "a5",
      startTime: at(10, 30),
      status: "scheduled",
      patientName: "Hana Ibrahim",
      appointmentType: "Vaccination",
      doctorName: "Dr. Sara Mansour",
      doctorOnShift: true,
      patientChoseDoctor: true,
      visitPhase: "not_started",
    },
    {
      id: "a6",
      startTime: at(11, 0),
      status: "no_show",
      patientName: "Tariq Mahmoud",
      appointmentType: "General consultation",
      doctorName: "Dr. Omar Khalil",
      doctorOnShift: true,
      patientChoseDoctor: false,
      visitPhase: "not_started",
    },
  ],
  doctors: [
    {
      id: "d1",
      name: "Dr. Omar Khalil",
      shiftStatus: "on_shift",
      currentPatient: null,
      sessionMinutes: undefined,
    },
    {
      id: "d2",
      name: "Dr. Sara Mansour",
      shiftStatus: "on_shift",
      currentPatient: "Youssef Nader",
      sessionMinutes: 18,
    },
    {
      id: "d3",
      name: "Dr. Amira Fahmy",
      shiftStatus: "break",
      currentPatient: null,
    },
  ],
  waitingRoom: [
    {
      id: "w1",
      patientName: "Nadia Farouk",
      doctorName: "Dr. Omar Khalil",
      patientChoseDoctor: true,
      scheduledTime: at(9, 45),
      waitMinutes: 12,
    },
    {
      id: "w2",
      patientName: "Rami Saleh",
      doctorName: null,
      patientChoseDoctor: false,
      scheduledTime: at(9, 30),
      waitMinutes: 27,
    },
  ],
};

export const emptyClinicSummary: ClinicSummary = {
  date: today.toISOString(),
  appointments: [],
  doctors: [],
  waitingRoom: [],
};
