import type { ClinicSummary } from "@/lib/types";
import { formatDateLong, formatTimeRange, formatWait, formatTime, formatDuration } from "@/lib/format";
import { doctorAssignmentLabel, statusLabels, visitPhaseLabels, shiftStatusLabels } from "@/lib/labels";
import { getSummaryStats } from "@/lib/stats";
import { ThemeChrome } from "@/components/ThemeChrome";

const statusGlow: Record<string, string> = {
  in_progress: "shadow-[0_0_12px_rgba(139,92,246,0.6)] border-violet-400/50",
  checked_in: "shadow-[0_0_8px_rgba(56,189,248,0.4)] border-sky-400/40",
  completed: "border-emerald-500/30",
  no_show: "border-rose-500/30",
};

export function AiNativeTheme({ summary }: { summary: ClinicSummary }) {
  const stats = getSummaryStats(summary);

  return (
    <div className="relative min-h-screen overflow-hidden bg-[#0a0a0f] font-[family-name:var(--font-space)] text-zinc-100">
      <div
        className="pointer-events-none absolute inset-0 bg-[radial-gradient(ellipse_80%_50%_at_50%_-20%,rgba(139,92,246,0.25),transparent),radial-gradient(ellipse_60%_40%_at_100%_50%,rgba(56,189,248,0.12),transparent)]"
        aria-hidden
      />
      <div
        className="pointer-events-none absolute inset-0 opacity-[0.03]"
        style={{
          backgroundImage:
            "linear-gradient(rgba(255,255,255,0.5) 1px, transparent 1px), linear-gradient(90deg, rgba(255,255,255,0.5) 1px, transparent 1px)",
          backgroundSize: "48px 48px",
        }}
        aria-hidden
      />

      <div className="relative mx-auto max-w-6xl px-4 py-8 sm:px-6">
        <ThemeChrome themeName="AI Native" className="mb-8 text-zinc-500" />

        <header className="mb-10 rounded-2xl border border-violet-500/20 bg-zinc-900/60 p-6 backdrop-blur-sm">
          <div className="flex flex-wrap items-start justify-between gap-4">
            <div>
              <span className="inline-flex items-center gap-2 rounded-full border border-violet-500/30 bg-violet-500/10 px-3 py-1 text-xs text-violet-300">
                <span className="h-1.5 w-1.5 animate-pulse rounded-full bg-violet-400" />
                Live clinic feed
              </span>
              <h1 className="mt-4 font-[family-name:var(--font-space)] text-2xl font-semibold tracking-tight">
                Operations snapshot
              </h1>
              <p className="mt-1 font-mono text-xs text-zinc-500">{formatDateLong(summary.date)}</p>
            </div>
            <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
              {[
                ["appts", stats.appointmentCount],
                ["active", stats.inProgress],
                ["queue", stats.waiting],
                ["staff", stats.onShift],
              ].map(([k, v]) => (
                <div
                  key={k}
                  className="rounded-xl border border-zinc-800 bg-zinc-950/80 px-4 py-3 font-mono"
                >
                  <p className="text-[10px] uppercase tracking-widest text-zinc-600">{k}</p>
                  <p className="mt-1 text-xl font-semibold text-violet-300">{v}</p>
                </div>
              ))}
            </div>
          </div>
        </header>

        <div className="grid gap-6 lg:grid-cols-12">
          <section className="lg:col-span-7">
            <h2 className="mb-4 font-mono text-xs uppercase tracking-widest text-zinc-500">
              {"// appointments"}
            </h2>
            {summary.appointments.length === 0 ? (
              <p className="rounded-xl border border-dashed border-zinc-800 p-8 text-center text-zinc-600">
                No signals today
              </p>
            ) : (
              <ul className="space-y-3">
                {summary.appointments.map((a) => (
                  <li
                    key={a.id}
                    className={`rounded-xl border bg-zinc-900/50 p-4 transition-colors hover:bg-zinc-900/80 ${statusGlow[a.status] ?? "border-zinc-800"}`}
                  >
                    <div className="flex gap-4">
                      <time className="shrink-0 font-mono text-xs text-sky-400/80">
                        {formatTimeRange(a.startTime, a.endTime)}
                      </time>
                      <div className="min-w-0 flex-1">
                        <div className="flex flex-wrap gap-2 text-xs">
                          <span className="rounded bg-zinc-800 px-2 py-0.5 text-zinc-300">
                            {statusLabels[a.status]}
                          </span>
                          <span className="text-zinc-600">{visitPhaseLabels[a.visitPhase]}</span>
                        </div>
                        <p className="mt-2 font-medium">{a.patientName}</p>
                        <p className="text-sm text-zinc-500">{a.appointmentType}</p>
                        <p className="mt-2 text-xs text-zinc-400">
                          {doctorAssignmentLabel(a.doctorName, a.doctorOnShift)}
                          {a.patientChoseDoctor && a.doctorName && " · preferred"}
                        </p>
                        {a.waitMinutes !== undefined && (
                          <p className="mt-1 font-mono text-xs text-amber-400/90">
                            wait:{formatWait(a.waitMinutes)}
                          </p>
                        )}
                      </div>
                    </div>
                  </li>
                ))}
              </ul>
            )}
          </section>

          <div className="flex flex-col gap-6 lg:col-span-5">
            <section>
              <h2 className="mb-4 font-mono text-xs uppercase tracking-widest text-zinc-500">
                {"// doctors"}
              </h2>
              <ul className="space-y-3">
                {summary.doctors.length === 0 ? (
                  <li className="rounded-xl border border-dashed border-zinc-800 p-6 text-center text-sm text-zinc-600">
                    No staff online
                  </li>
                ) : (
                  summary.doctors.map((d) => (
                    <li
                      key={d.id}
                      className="rounded-xl border border-zinc-800 bg-gradient-to-br from-zinc-900/80 to-zinc-950 p-4"
                    >
                      <p className="font-medium">{d.name}</p>
                      <p className="text-xs text-violet-400/80">{shiftStatusLabels[d.shiftStatus]}</p>
                      <p className="mt-2 text-sm text-zinc-400">
                        {d.currentPatient ? (
                          <>
                            <span className="text-zinc-200">{d.currentPatient}</span>
                            {d.sessionMinutes !== undefined && (
                              <span className="ml-2 font-mono text-xs text-zinc-600">
                                {formatDuration(d.sessionMinutes)}
                              </span>
                            )}
                          </>
                        ) : (
                          "Available"
                        )}
                      </p>
                    </li>
                  ))
                )}
              </ul>
            </section>

            <section className="rounded-2xl border border-sky-500/20 bg-sky-950/20 p-4">
              <div className="mb-4 flex items-center justify-between">
                <h2 className="font-mono text-xs uppercase tracking-widest text-sky-400/70">
                  {"// waiting_room"}
                </h2>
                <span className="rounded-full bg-sky-500/20 px-2.5 py-0.5 font-mono text-sm text-sky-300">
                  {stats.waiting}
                </span>
              </div>
              {summary.waitingRoom.length === 0 ? (
                <p className="text-sm text-zinc-600">Queue empty</p>
              ) : (
                <ul className="space-y-3">
                  {summary.waitingRoom.map((w) => (
                    <li key={w.id} className="rounded-lg border border-zinc-800/80 bg-zinc-950/50 p-3">
                      <div className="flex justify-between gap-2">
                        <p className="text-sm font-medium">{w.patientName}</p>
                        <span className="font-mono text-xs text-amber-400">{formatWait(w.waitMinutes)}</span>
                      </div>
                      <p className="mt-1 text-xs text-zinc-500">
                        {doctorAssignmentLabel(w.doctorName, true)} · {formatTime(w.scheduledTime)}
                      </p>
                    </li>
                  ))}
                </ul>
              )}
            </section>
          </div>
        </div>
      </div>
    </div>
  );
}
