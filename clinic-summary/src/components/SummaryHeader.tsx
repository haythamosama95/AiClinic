import type { ClinicSummary } from "@/lib/types";
import { formatDateLong } from "@/lib/format";

interface SummaryHeaderProps {
  summary: ClinicSummary;
}

export function SummaryHeader({ summary }: SummaryHeaderProps) {
  const inProgress = summary.appointments.filter(
    (a) => a.status === "in_progress",
  ).length;
  const waiting = summary.waitingRoom.length;
  const onShift = summary.doctors.filter(
    (d) => d.shiftStatus === "on_shift",
  ).length;

  const stats = [
    { label: "Appointments today", value: summary.appointments.length },
    { label: "In progress", value: inProgress },
    { label: "Waiting", value: waiting },
    { label: "Doctors on shift", value: onShift },
  ];

  return (
    <header className="relative overflow-hidden rounded-2xl border border-border bg-surface shadow-panel">
      <div
        className="pointer-events-none absolute inset-0 bg-[radial-gradient(ellipse_at_top_right,_var(--color-brand-soft)_0%,_transparent_55%)]"
        aria-hidden
      />
      <div className="relative px-6 py-6 sm:px-8 sm:py-7">
        <div className="flex flex-col gap-6 lg:flex-row lg:items-end lg:justify-between">
          <div>
            <p className="text-xs font-semibold uppercase tracking-[0.14em] text-brand">
              Summary stats
            </p>
            <h1 className="mt-1 font-display text-2xl font-semibold tracking-tight text-ink sm:text-3xl">
              Today&apos;s clinic
            </h1>
            <p className="mt-1 text-sm text-muted">
              {formatDateLong(summary.date)}
            </p>
          </div>

          <dl className="grid grid-cols-2 gap-3 sm:grid-cols-4 sm:gap-4">
            {stats.map((stat) => (
              <div
                key={stat.label}
                className="rounded-xl border border-border/80 bg-canvas/80 px-4 py-3 backdrop-blur-sm"
              >
                <dt className="text-xs font-medium text-muted">{stat.label}</dt>
                <dd className="mt-0.5 font-display text-2xl font-semibold tabular-nums text-ink">
                  {stat.value}
                </dd>
              </div>
            ))}
          </dl>
        </div>

        <DayPulse appointments={summary.appointments} />
      </div>
    </header>
  );
}

function DayPulse({
  appointments,
}: {
  appointments: ClinicSummary["appointments"];
}) {
  if (appointments.length === 0) return null;

  const dayStart = 8 * 60;
  const dayEnd = 17 * 60;
  const span = dayEnd - dayStart;

  return (
    <div className="mt-6 hidden sm:block" aria-hidden>
      <div className="mb-2 flex justify-between text-[10px] font-medium uppercase tracking-wider text-muted">
        <span>8:00</span>
        <span>Clinic day</span>
        <span>17:00</span>
      </div>
      <div className="relative h-2 overflow-hidden rounded-full bg-slate-100">
        {appointments.map((appt) => {
          const start = new Date(appt.startTime);
          const minutes = start.getHours() * 60 + start.getMinutes();
          const left = ((minutes - dayStart) / span) * 100;
          if (left < 0 || left > 100) return null;

          const color =
            appt.status === "completed"
              ? "bg-emerald-400"
              : appt.status === "in_progress"
                ? "bg-brand"
                : appt.status === "checked_in"
                  ? "bg-amber-400"
                  : appt.status === "no_show"
                    ? "bg-rose-300"
                    : "bg-slate-300";

          return (
            <span
              key={appt.id}
              className={`absolute top-0 h-full w-1.5 -translate-x-1/2 rounded-full ${color}`}
              style={{ left: `${left}%` }}
            />
          );
        })}
        <span
          className="absolute top-0 h-full w-0.5 bg-ink/30"
          style={{ left: "42%" }}
          title="Current time (demo)"
        />
      </div>
    </div>
  );
}
