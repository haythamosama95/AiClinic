import type { ClinicSummary } from "@/lib/types";
import { formatDateLong, formatTimeRange, formatWait, formatTime, formatDuration } from "@/lib/format";
import { doctorAssignmentLabel, statusLabels, visitPhaseLabels, shiftStatusLabels } from "@/lib/labels";
import { getSummaryStats } from "@/lib/stats";
import { ThemeChrome } from "@/components/ThemeChrome";

export function MinimalistTheme({ summary }: { summary: ClinicSummary }) {
  const stats = getSummaryStats(summary);

  return (
    <div className="min-h-screen bg-white font-[family-name:var(--font-inter)] text-neutral-900">
      <div className="mx-auto max-w-3xl px-6 py-16">
        <ThemeChrome themeName="Minimalist" className="mb-20 text-neutral-400" />

        <header className="border-b border-neutral-200 pb-10">
          <p className="text-[11px] font-medium uppercase tracking-[0.2em] text-neutral-400">
            {formatDateLong(summary.date)}
          </p>
          <h1 className="mt-3 text-4xl font-light tracking-tight">Clinic day</h1>
          <dl className="mt-8 flex gap-12 text-sm">
            {[
              ["Visits", stats.appointmentCount],
              ["Active", stats.inProgress],
              ["Waiting", stats.waiting],
              ["Staff", stats.onShift],
            ].map(([label, val]) => (
              <div key={label as string}>
                <dt className="text-neutral-400">{label}</dt>
                <dd className="mt-1 text-2xl font-light tabular-nums">{val}</dd>
              </div>
            ))}
          </dl>
        </header>

        <section className="mt-16">
          <h2 className="text-[11px] font-medium uppercase tracking-[0.2em] text-neutral-400">
            Appointments
          </h2>
          {summary.appointments.length === 0 ? (
            <p className="mt-8 text-neutral-400">Nothing scheduled.</p>
          ) : (
            <ul className="mt-6 divide-y divide-neutral-100">
              {summary.appointments.map((a) => (
                <li key={a.id} className="grid gap-4 py-6 sm:grid-cols-[5rem_1fr]">
                  <time className="text-sm tabular-nums text-neutral-500">
                    {formatTimeRange(a.startTime, a.endTime)}
                  </time>
                  <div>
                    <div className="flex flex-wrap items-baseline gap-x-3 gap-y-1">
                      <span className="text-base">{a.patientName}</span>
                      <span className="text-sm text-neutral-400">{statusLabels[a.status]}</span>
                    </div>
                    <p className="mt-1 text-sm text-neutral-500">{a.appointmentType}</p>
                    <p className="mt-2 text-sm text-neutral-600">
                      {doctorAssignmentLabel(a.doctorName, a.doctorOnShift)}
                      {a.patientChoseDoctor && a.doctorName && " · patient's choice"}
                    </p>
                    <p className="mt-1 text-xs text-neutral-400">{visitPhaseLabels[a.visitPhase]}</p>
                    {a.waitMinutes !== undefined && (
                      <p className="mt-1 text-xs text-neutral-500">Wait {formatWait(a.waitMinutes)}</p>
                    )}
                  </div>
                </li>
              ))}
            </ul>
          )}
        </section>

        <section className="mt-16 border-t border-neutral-200 pt-16">
          <h2 className="text-[11px] font-medium uppercase tracking-[0.2em] text-neutral-400">
            On shift
          </h2>
          {summary.doctors.length === 0 ? (
            <p className="mt-8 text-neutral-400">No one on shift.</p>
          ) : (
            <ul className="mt-6 space-y-8">
              {summary.doctors.map((d) => (
                <li key={d.id} className="flex justify-between gap-4 text-sm">
                  <div>
                    <p>{d.name}</p>
                    <p className="mt-1 text-neutral-400">{shiftStatusLabels[d.shiftStatus]}</p>
                  </div>
                  <p className="text-right text-neutral-600">
                    {d.currentPatient ?? (
                      <span className="text-neutral-400">Available</span>
                    )}
                    {d.sessionMinutes !== undefined && (
                      <span className="block text-xs text-neutral-400">
                        {formatDuration(d.sessionMinutes)}
                      </span>
                    )}
                  </p>
                </li>
              ))}
            </ul>
          )}
        </section>

        <section className="mt-16 border-t border-neutral-200 pt-16">
          <div className="flex items-baseline justify-between">
            <h2 className="text-[11px] font-medium uppercase tracking-[0.2em] text-neutral-400">
              Checked in
            </h2>
            <span className="text-sm tabular-nums text-neutral-400">{stats.waiting} waiting</span>
          </div>
          {summary.waitingRoom.length === 0 ? (
            <p className="mt-8 text-neutral-400">Waiting room is empty.</p>
          ) : (
            <ul className="mt-6 space-y-6">
              {summary.waitingRoom.map((w) => (
                <li key={w.id} className="flex justify-between gap-4 text-sm">
                  <div>
                    <p>{w.patientName}</p>
                    <p className="mt-1 text-neutral-500">
                      {doctorAssignmentLabel(w.doctorName, true)}
                      {w.patientChoseDoctor && w.doctorName && " · patient's choice"}
                    </p>
                    <p className="mt-1 text-xs text-neutral-400">
                      Scheduled {formatTime(w.scheduledTime)}
                    </p>
                  </div>
                  <span className="tabular-nums text-neutral-600">{formatWait(w.waitMinutes)}</span>
                </li>
              ))}
            </ul>
          )}
        </section>
      </div>
    </div>
  );
}
