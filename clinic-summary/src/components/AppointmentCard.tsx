import type { Appointment } from "@/lib/types";
import { formatTimeRange, formatWait } from "@/lib/format";
import {
  doctorAssignmentLabel,
  statusLabels,
  visitPhaseLabels,
} from "@/lib/labels";
import { StatusBadge, StatusDot } from "./StatusBadge";

interface AppointmentCardProps {
  appointment: Appointment;
}

export function AppointmentCard({ appointment }: AppointmentCardProps) {
  const doctorLabel = doctorAssignmentLabel(
    appointment.doctorName,
    appointment.doctorOnShift,
  );
  const isUnassigned =
    !appointment.doctorName || !appointment.doctorOnShift;

  return (
    <article className="group relative rounded-xl border border-border bg-surface p-4 transition-shadow hover:shadow-sm">
      <div className="flex gap-4">
        <div className="flex w-24 shrink-0 flex-col pt-0.5">
          <time
            className="font-mono text-sm font-medium tabular-nums text-ink"
            dateTime={appointment.startTime}
          >
            {formatTimeRange(appointment.startTime, appointment.endTime)}
          </time>
          {appointment.waitMinutes !== undefined && (
            <span className="mt-1 text-xs font-medium text-amber-700">
              Waiting {formatWait(appointment.waitMinutes)}
            </span>
          )}
        </div>

        <div className="min-w-0 flex-1">
          <div className="flex flex-wrap items-center gap-2">
            <StatusDot status={appointment.status} />
            <StatusBadge
              label={statusLabels[appointment.status]}
              variant="appointment"
              status={appointment.status}
            />
            <StatusBadge
              label={visitPhaseLabels[appointment.visitPhase]}
              variant="neutral"
            />
          </div>

          <h3 className="mt-2 font-display text-[15px] font-semibold text-ink">
            {appointment.patientName}
          </h3>
          <p className="mt-0.5 text-sm text-muted">
            {appointment.appointmentType}
          </p>

          <div className="mt-3 flex flex-wrap items-center gap-x-3 gap-y-1 text-sm">
            <span className={isUnassigned ? "text-muted italic" : "text-ink"}>
              {doctorLabel}
            </span>
            {appointment.patientChoseDoctor && appointment.doctorName && (
              <span className="inline-flex items-center gap-1 text-xs font-medium text-brand">
                <svg
                  className="h-3.5 w-3.5"
                  fill="currentColor"
                  viewBox="0 0 20 20"
                  aria-hidden
                >
                  <path
                    fillRule="evenodd"
                    d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.857-9.809a.75.75 0 00-1.214-.882l-3.483 4.79-1.88-1.88a.75.75 0 10-1.06 1.061l2.5 2.5a.75.75 0 001.137-.089l4-5.5z"
                    clipRule="evenodd"
                  />
                </svg>
                Patient&apos;s choice
              </span>
            )}
          </div>
        </div>
      </div>
    </article>
  );
}
