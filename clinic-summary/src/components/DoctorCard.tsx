import type { DoctorOnShift } from "@/lib/types";
import { formatDuration } from "@/lib/format";
import { shiftStatusLabels } from "@/lib/labels";
import { StatusBadge } from "./StatusBadge";

interface DoctorCardProps {
  doctor: DoctorOnShift;
}

export function DoctorCard({ doctor }: DoctorCardProps) {
  const isBusy = Boolean(doctor.currentPatient);

  return (
    <article className="rounded-xl border border-border bg-surface p-4">
      <div className="flex items-start justify-between gap-3">
        <div className="min-w-0">
          <h3 className="font-display text-[15px] font-semibold text-ink">
            {doctor.name}
          </h3>
          <StatusBadge
            label={shiftStatusLabels[doctor.shiftStatus]}
            variant="shift"
            status={doctor.shiftStatus}
          />
        </div>
        <div
          className={`flex h-9 w-9 shrink-0 items-center justify-center rounded-full text-xs font-semibold ${isBusy
              ? "bg-brand-soft text-brand ring-2 ring-brand/20"
              : "bg-emerald-50 text-emerald-700 ring-2 ring-emerald-100"
            }`}
          aria-hidden
        >
          {isBusy ? "●" : "○"}
        </div>
      </div>

      <div className="mt-3 border-t border-border pt-3">
        {isBusy ? (
          <>
            <p className="text-xs font-medium uppercase tracking-wide text-muted">
              Current patient
            </p>
            <p className="mt-0.5 text-sm font-medium text-ink">
              {doctor.currentPatient}
            </p>
            {doctor.sessionMinutes !== undefined && (
              <p className="mt-1 font-mono text-xs tabular-nums text-muted">
                Session · {formatDuration(doctor.sessionMinutes)}
              </p>
            )}
          </>
        ) : (
          <p className="text-sm text-muted">
            <span className="font-medium text-emerald-700">Available</span>
            <span className="mx-1.5 text-border">·</span>
            No patient in progress
          </p>
        )}
      </div>
    </article>
  );
}
