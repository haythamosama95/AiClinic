import type { VisitStatus, InvestigationStatus } from "./encounter-types";

export const visitStatusLabels: Record<VisitStatus, string> = {
  in_progress: "In progress",
  completed: "Completed",
  scheduled: "Scheduled",
};

export const investigationStatusLabels: Record<InvestigationStatus, string> = {
  ordered: "Ordered",
  pending: "Pending",
  completed: "Completed",
};

export function deriveBmi(weightKg: number, heightCm: number): string | null {
  if (!weightKg || !heightCm) return null;
  const m = heightCm / 100;
  const bmi = weightKg / (m * m);
  return bmi.toFixed(1);
}

export function findVital(
  vitals: { type: string; value: string }[],
  type: string,
): string | null {
  const v = vitals.find((x) => x.type.toLowerCase() === type.toLowerCase());
  return v?.value ?? null;
}
