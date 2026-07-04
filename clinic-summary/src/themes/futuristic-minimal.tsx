import type { ClinicSummary } from "@/lib/types";
import { formatDateLong, formatTimeRange, formatWait, formatTime, formatDuration } from "@/lib/format";
import { doctorAssignmentLabel, statusLabels, visitPhaseLabels, shiftStatusLabels } from "@/lib/labels";
import { getSummaryStats } from "@/lib/stats";
import { ThemeChrome } from "@/components/ThemeChrome";

export function FuturisticMinimalTheme({ summary }: { summary: ClinicSummary }) {
  const stats = getSummaryStats(summary);

  return (
    <div className="min-h-screen bg-black font-[family-name:var(--font-syne)] text-white">
      <div className="pointer-events-none fixed inset-0 bg-[linear-gradient(180deg,transparent_0%,rgba(0,255,209,0.03)_50%,transparent_100%)]" aria-hidden />

      <div className="relative mx-auto max-w-4xl px-6 py-12">
        <ThemeChrome themeName="Futuristic Minimal" className="mb-16 text-white/30" />

        <header className="border-l-2 border-[#00FFD1] pl-6">
          <p className="text-[10px] font-medium uppercase tracking-[0.35em] text-[#00FFD1]/70">
            {formatDateLong(summary.date)}
          </p>
          <h1 className="mt-4 text-4xl font-light uppercase tracking-[0.08em]">
            Clinic
            <span className="block text-white/40">Summary</span>
          </h1>
          <dl className="mt-10 grid grid-cols-4 gap-6 border-t border-white/10 pt-8">
            {[
              ["APT", stats.appointmentCount],
              ["ACT", stats.inProgress],
              ["QUE", stats.waiting],
              ["DOC", stats.onShift],
            ].map(([k, v]) => (
              <div key={k as string}>
                <dt className="text-[9px] tracking-[0.3em] text-white/30">{k}</dt>
                <dd className="mt-2 font-mono text-2xl font-light tabular-nums text-[#00FFD1]">
                  {v}
                </dd>
              </div>
            ))}
          </dl>
        </header>

        <section className="mt-20">
          <h2 className="text-[10px] font-medium uppercase tracking-[0.35em] text-white/30">
            01 — Appointments
          </h2>
          {summary.appointments.length === 0 ? (
            <p className="mt-8 text-sm text-white/30">Null set</p>
          ) : (
            <ul className="mt-8 space-y-0 divide-y divide-white/10">
              {summary.appointments.map((a) => (
                <li key={a.id} className="grid gap-4 py-6 sm:grid-cols-[6rem_1fr]">
                  <time className="font-mono text-xs tabular-nums text-[#00FFD1]/60">
                    {formatTimeRange(a.startTime, a.endTime)}
                  </time>
                  <div>
                    <p className="text-sm font-light uppercase tracking-widest">{a.patientName}</p>
                    <p className="mt-1 text-xs text-white/40">{a.appointmentType}</p>
                    <p className="mt-3 font-mono text-[10px] uppercase tracking-wider text-white/50">
                      {statusLabels[a.status]} / {visitPhaseLabels[a.visitPhase]}
                    </p>
                    <p className="mt-1 text-xs text-white/30">
                      {doctorAssignmentLabel(a.doctorName, a.doctorOnShift)}
                      {a.patientChoseDoctor && a.doctorName && " · CHOICE"}
                    </p>
                    {a.waitMinutes !== undefined && (
                      <p className="mt-2 font-mono text-[10px] text-[#00FFD1]/80">
                        +{a.waitMinutes}m
                      </p>
                    )}
                  </div>
                </li>
              ))}
            </ul>
          )}
        </section>

        <div className="mt-20 grid gap-16 sm:grid-cols-2">
          <section>
            <h2 className="text-[10px] font-medium uppercase tracking-[0.35em] text-white/30">
              02 — On shift
            </h2>
            {summary.doctors.length === 0 ? (
              <p className="mt-8 text-sm text-white/30">None</p>
            ) : (
              <ul className="mt-8 space-y-6">
                {summary.doctors.map((d) => (
                  <li key={d.id} className="border-l border-white/20 pl-4">
                    <p className="text-sm uppercase tracking-wider">{d.name}</p>
                    <p className="mt-1 font-mono text-[10px] text-white/40">
                      {shiftStatusLabels[d.shiftStatus]}
                    </p>
                    <p className="mt-2 text-xs text-white/50">
                      {d.currentPatient ?? "AVAILABLE"}
                      {d.sessionMinutes !== undefined && (
                        <span className="font-mono text-[#00FFD1]/60">
                          {" "}
                          · {formatDuration(d.sessionMinutes)}
                        </span>
                      )}
                    </p>
                  </li>
                ))}
              </ul>
            )}
          </section>

          <section>
            <div className="flex items-center gap-4">
              <h2 className="text-[10px] font-medium uppercase tracking-[0.35em] text-white/30">
                03 — Checked in
              </h2>
              <span className="font-mono text-sm text-[#00FFD1]">{stats.waiting}</span>
            </div>
            {summary.waitingRoom.length === 0 ? (
              <p className="mt-8 text-sm text-white/30">Clear</p>
            ) : (
              <ul className="mt-8 space-y-6">
                {summary.waitingRoom.map((w) => (
                  <li key={w.id} className="flex justify-between gap-4 border-l border-[#00FFD1]/30 pl-4">
                    <div>
                      <p className="text-sm uppercase tracking-wider">{w.patientName}</p>
                      <p className="mt-1 text-xs text-white/40">
                        {doctorAssignmentLabel(w.doctorName, true)} · {formatTime(w.scheduledTime)}
                      </p>
                    </div>
                    <span className="font-mono text-sm tabular-nums text-[#00FFD1]">
                      {formatWait(w.waitMinutes)}
                    </span>
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
