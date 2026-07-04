import type { WaitingPatient } from "@/lib/types";
import { formatTime, formatWait } from "@/lib/format";
import { doctorAssignmentLabel } from "@/lib/labels";

interface WaitingPatientCardProps {
  patient: WaitingPatient;
}

export function WaitingPatientCard({ patient }: WaitingPatientCardProps) {
  const doctorLabel = doctorAssignmentLabel(patient.doctorName, true);
  const isLongWait = patient.waitMinutes >= 20;

  return (
    <article className="rounded-xl border border-border bg-surface p-4">
      <div className="flex items-start justify-between gap-3">
        <div className="min-w-0">
          <h3 className="font-display text-[15px] font-semibold text-ink">
            {patient.patientName}
          </h3>
          <p className="mt-0.5 text-sm text-muted">
            Scheduled {formatTime(patient.scheduledTime)}
          </p>
        </div>
        <div
          className={`shrink-0 rounded-lg px-2.5 py-1 font-mono text-sm font-semibold tabular-nums ${isLongWait
              ? "bg-amber-50 text-amber-900 ring-1 ring-amber-200"
              : "bg-slate-50 text-slate-700 ring-1 ring-slate-200"
            }`}
        >
          {formatWait(patient.waitMinutes)}
        </div>
      </div>

      <div className="mt-3 flex flex-wrap items-center gap-x-2 gap-y-1 text-sm">
        <span className={!patient.doctorName ? "italic text-muted" : "text-ink"}>
          {doctorLabel}
        </span>
        {patient.patientChoseDoctor && patient.doctorName && (
          <span className="text-xs font-medium text-brand">
            · Patient&apos;s choice
          </span>
        )}
      </div>
    </article>
  );
}
