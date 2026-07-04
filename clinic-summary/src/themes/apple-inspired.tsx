import type { ClinicSummary } from "@/lib/types";
import { formatDateLong, formatTimeRange, formatWait, formatTime, formatDuration } from "@/lib/format";
import { doctorAssignmentLabel, statusLabels, visitPhaseLabels, shiftStatusLabels } from "@/lib/labels";
import { getSummaryStats } from "@/lib/stats";
import { ThemeChrome } from "@/components/ThemeChrome";

export function AppleInspiredTheme({ summary }: { summary: ClinicSummary }) {
  const stats = getSummaryStats(summary);

  return (
    <div className="min-h-screen bg-[#F5F5F7] font-[family-name:var(--font-system)] text-[#1D1D1F] antialiased">
      <div className="mx-auto max-w-5xl px-5 py-10 sm:px-8">
        <ThemeChrome themeName="Apple-inspired" className="mb-10 text-[#86868B]" />

        <header className="mb-12 text-center">
          <p className="text-sm font-medium text-[#86868B]">{formatDateLong(summary.date)}</p>
          <h1 className="mt-2 text-[2.5rem] font-semibold leading-tight tracking-tight">
            Clinic Summary
          </h1>
          <div className="mx-auto mt-8 flex max-w-lg justify-center gap-2 rounded-2xl bg-white/80 p-1.5 shadow-sm ring-1 ring-black/[0.04] backdrop-blur-xl">
            {[
              ["Visits", stats.appointmentCount],
              ["Active", stats.inProgress],
              ["Waiting", stats.waiting],
              ["Staff", stats.onShift],
            ].map(([label, val]) => (
              <div key={label as string} className="flex-1 rounded-xl px-3 py-3">
                <p className="text-xl font-semibold tabular-nums">{val}</p>
                <p className="text-[11px] font-medium text-[#86868B]">{label}</p>
              </div>
            ))}
          </div>
        </header>

        <section className="mb-8 overflow-hidden rounded-3xl bg-white shadow-[0_2px_24px_rgba(0,0,0,0.06)]">
          <div className="border-b border-black/[0.06] px-6 py-4">
            <h2 className="text-xl font-semibold">Appointments</h2>
            <p className="text-sm text-[#86868B]">Scheduled for today</p>
          </div>
          {summary.appointments.length === 0 ? (
            <p className="px-6 py-16 text-center text-[#86868B]">No appointments today.</p>
          ) : (
            <ul className="divide-y divide-black/[0.06]">
              {summary.appointments.map((a) => (
                <li key={a.id} className="flex gap-5 px-6 py-5 transition hover:bg-[#F5F5F7]/50">
                  <time className="w-20 shrink-0 text-sm font-medium tabular-nums text-[#007AFF]">
                    {formatTimeRange(a.startTime, a.endTime)}
                  </time>
                  <div className="min-w-0 flex-1">
                    <p className="text-[17px] font-semibold leading-snug">{a.patientName}</p>
                    <p className="text-sm text-[#86868B]">{a.appointmentType}</p>
                    <div className="mt-2 flex flex-wrap gap-2">
                      <span className="rounded-full bg-[#007AFF]/10 px-2.5 py-0.5 text-xs font-medium text-[#007AFF]">
                        {statusLabels[a.status]}
                      </span>
                      <span className="rounded-full bg-[#F5F5F7] px-2.5 py-0.5 text-xs text-[#86868B]">
                        {visitPhaseLabels[a.visitPhase]}
                      </span>
                    </div>
                    <p className="mt-2 text-sm text-[#424245]">
                      {doctorAssignmentLabel(a.doctorName, a.doctorOnShift)}
                      {a.patientChoseDoctor && a.doctorName && (
                        <span className="text-[#86868B]"> · Patient&apos;s choice</span>
                      )}
                    </p>
                    {a.waitMinutes !== undefined && (
                      <p className="mt-1 text-xs font-medium text-[#FF9500]">
                        Waiting {formatWait(a.waitMinutes)}
                      </p>
                    )}
                  </div>
                </li>
              ))}
            </ul>
          )}
        </section>

        <div className="grid gap-8 sm:grid-cols-2">
          <section className="overflow-hidden rounded-3xl bg-white shadow-[0_2px_24px_rgba(0,0,0,0.06)]">
            <div className="border-b border-black/[0.06] px-6 py-4">
              <h2 className="text-xl font-semibold">Doctors on shift</h2>
            </div>
            {summary.doctors.length === 0 ? (
              <p className="px-6 py-12 text-center text-sm text-[#86868B]">No doctors on shift.</p>
            ) : (
              <ul className="divide-y divide-black/[0.06]">
                {summary.doctors.map((d) => (
                  <li key={d.id} className="px-6 py-4">
                    <p className="font-semibold">{d.name}</p>
                    <p className="text-xs text-[#86868B]">{shiftStatusLabels[d.shiftStatus]}</p>
                    <p className="mt-1 text-sm text-[#424245]">
                      {d.currentPatient ? (
                        <>
                          {d.currentPatient}
                          {d.sessionMinutes !== undefined && (
                            <span className="text-[#86868B]">
                              {" "}
                              · {formatDuration(d.sessionMinutes)}
                            </span>
                          )}
                        </>
                      ) : (
                        <span className="text-[#34C759]">Available</span>
                      )}
                    </p>
                  </li>
                ))}
              </ul>
            )}
          </section>

          <section className="overflow-hidden rounded-3xl bg-white shadow-[0_2px_24px_rgba(0,0,0,0.06)]">
            <div className="flex items-center justify-between border-b border-black/[0.06] px-6 py-4">
              <h2 className="text-xl font-semibold">Checked in</h2>
              <span className="rounded-full bg-[#FF9500]/15 px-2.5 py-0.5 text-sm font-semibold text-[#FF9500]">
                {stats.waiting}
              </span>
            </div>
            {summary.waitingRoom.length === 0 ? (
              <p className="px-6 py-12 text-center text-sm text-[#86868B]">
                Waiting room is clear.
              </p>
            ) : (
              <ul className="divide-y divide-black/[0.06]">
                {summary.waitingRoom.map((w) => (
                  <li key={w.id} className="px-6 py-4">
                    <div className="flex justify-between gap-2">
                      <p className="font-semibold">{w.patientName}</p>
                      <span className="text-sm font-medium tabular-nums text-[#FF9500]">
                        {formatWait(w.waitMinutes)}
                      </span>
                    </div>
                    <p className="mt-1 text-sm text-[#86868B]">
                      {doctorAssignmentLabel(w.doctorName, true)} · Scheduled{" "}
                      {formatTime(w.scheduledTime)}
                    </p>
                  </li>
                ))}
              </ul>
            )}
          </section>
        </div>
      </div>
    </div>
  );
}
