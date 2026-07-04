import type { ClinicSummary } from "@/lib/types";
import { formatDateLong, formatTimeRange, formatWait, formatTime, formatDuration } from "@/lib/format";
import { doctorAssignmentLabel, statusLabels, visitPhaseLabels, shiftStatusLabels } from "@/lib/labels";
import { getSummaryStats } from "@/lib/stats";
import { ThemeChrome } from "@/components/ThemeChrome";

const statusBarColor: Record<string, string> = {
  scheduled: "bg-slate-500",
  confirmed: "bg-blue-500",
  checked_in: "bg-amber-500",
  in_progress: "bg-violet-500",
  completed: "bg-emerald-500",
  no_show: "bg-rose-500",
  cancelled: "bg-slate-400",
};

function MetricBar({ label, value, max, color }: { label: string; value: number; max: number; color: string }) {
  const pct = max > 0 ? (value / max) * 100 : 0;
  return (
    <div>
      <div className="mb-1 flex justify-between font-mono text-xs">
        <span className="text-slate-400">{label}</span>
        <span className="tabular-nums text-slate-200">{value}</span>
      </div>
      <div className="h-2 overflow-hidden rounded-sm bg-slate-800">
        <div className={`h-full rounded-sm ${color} transition-all`} style={{ width: `${pct}%` }} />
      </div>
    </div>
  );
}

export function DataVisualizationTheme({ summary }: { summary: ClinicSummary }) {
  const stats = getSummaryStats(summary);
  const maxWait = Math.max(...summary.waitingRoom.map((w) => w.waitMinutes), 1);
  const statusCounts = summary.appointments.reduce(
    (acc, a) => {
      acc[a.status] = (acc[a.status] ?? 0) + 1;
      return acc;
    },
    {} as Record<string, number>,
  );

  return (
    <div className="min-h-screen bg-[#0B1120] font-[family-name:var(--font-archivo)] text-slate-200">
      <div className="mx-auto max-w-7xl px-4 py-6 sm:px-6">
        <ThemeChrome themeName="Data Visualization" className="mb-6 text-slate-500" />

        <header className="mb-8 grid gap-6 lg:grid-cols-12">
          <div className="lg:col-span-4">
            <p className="font-mono text-xs uppercase tracking-widest text-emerald-400">
              Dashboard
            </p>
            <h1 className="mt-2 text-3xl font-bold tracking-tight">Clinic metrics</h1>
            <p className="mt-1 font-mono text-sm text-slate-500">{formatDateLong(summary.date)}</p>
          </div>
          <div className="grid grid-cols-2 gap-3 sm:grid-cols-4 lg:col-span-8">
            {[
              { label: "TOTAL", val: stats.appointmentCount, color: "text-sky-400" },
              { label: "ACTIVE", val: stats.inProgress, color: "text-violet-400" },
              { label: "QUEUE", val: stats.waiting, color: "text-amber-400" },
              { label: "STAFF", val: stats.onShift, color: "text-emerald-400" },
            ].map((m) => (
              <div
                key={m.label}
                className="rounded-lg border border-slate-800 bg-slate-900/80 p-4"
              >
                <p className={`font-mono text-3xl font-bold tabular-nums ${m.color}`}>{m.val}</p>
                <p className="mt-1 font-mono text-[10px] tracking-widest text-slate-500">
                  {m.label}
                </p>
              </div>
            ))}
          </div>
        </header>

        <div className="mb-8 grid gap-6 lg:grid-cols-12">
          <section className="rounded-lg border border-slate-800 bg-slate-900/50 p-5 lg:col-span-4">
            <h2 className="font-mono text-xs uppercase tracking-widest text-slate-500">
              Status distribution
            </h2>
            <div className="mt-4 space-y-3">
              {Object.entries(statusCounts).map(([status, count]) => (
                <MetricBar
                  key={status}
                  label={statusLabels[status as keyof typeof statusLabels] ?? status}
                  value={count}
                  max={summary.appointments.length}
                  color={statusBarColor[status] ?? "bg-slate-500"}
                />
              ))}
            </div>
          </section>

          <section className="rounded-lg border border-slate-800 bg-slate-900/50 p-5 lg:col-span-8">
            <h2 className="font-mono text-xs uppercase tracking-widest text-slate-500">
              Wait time index
            </h2>
            {summary.waitingRoom.length === 0 ? (
              <p className="mt-8 text-center font-mono text-sm text-slate-600">Queue: 0</p>
            ) : (
              <ul className="mt-4 space-y-4">
                {summary.waitingRoom.map((w) => (
                  <li key={w.id}>
                    <div className="mb-1 flex justify-between text-sm">
                      <span>{w.patientName}</span>
                      <span className="font-mono tabular-nums text-amber-400">
                        {formatWait(w.waitMinutes)}
                      </span>
                    </div>
                    <div className="h-3 overflow-hidden rounded-sm bg-slate-800">
                      <div
                        className="h-full rounded-sm bg-gradient-to-r from-amber-600 to-amber-400"
                        style={{ width: `${(w.waitMinutes / maxWait) * 100}%` }}
                      />
                    </div>
                    <p className="mt-1 font-mono text-[10px] text-slate-600">
                      {doctorAssignmentLabel(w.doctorName, true)} · {formatTime(w.scheduledTime)}
                    </p>
                  </li>
                ))}
              </ul>
            )}
            <p className="mt-4 text-right font-mono text-xs text-slate-500">
              {stats.waiting} in waiting room
            </p>
          </section>
        </div>

        <div className="grid gap-6 lg:grid-cols-12">
          <section className="lg:col-span-8">
            <h2 className="mb-4 font-mono text-xs uppercase tracking-widest text-slate-500">
              Appointment timeline
            </h2>
            {summary.appointments.length === 0 ? (
              <p className="rounded-lg border border-dashed border-slate-800 p-12 text-center text-slate-600">
                No data points
              </p>
            ) : (
              <ul className="space-y-2">
                {summary.appointments.map((a) => (
                  <li
                    key={a.id}
                    className="grid grid-cols-[4px_5rem_1fr] gap-4 rounded-lg border border-slate-800 bg-slate-900/40 p-4 sm:grid-cols-[4px_6rem_1fr_auto]"
                  >
                    <div
                      className={`rounded-full ${statusBarColor[a.status] ?? "bg-slate-500"}`}
                      aria-hidden
                    />
                    <time className="font-mono text-xs tabular-nums text-sky-400/80">
                      {formatTimeRange(a.startTime, a.endTime)}
                    </time>
                    <div>
                      <p className="font-medium">{a.patientName}</p>
                      <p className="text-xs text-slate-500">{a.appointmentType}</p>
                      <div className="mt-1 flex flex-wrap gap-2 font-mono text-[10px] text-slate-500">
                        <span>{statusLabels[a.status]}</span>
                        <span>·</span>
                        <span>{visitPhaseLabels[a.visitPhase]}</span>
                        <span>·</span>
                        <span>
                          {doctorAssignmentLabel(a.doctorName, a.doctorOnShift)}
                          {a.patientChoseDoctor && a.doctorName && " (pref)"}
                        </span>
                      </div>
                      {a.waitMinutes !== undefined && (
                        <p className="mt-1 font-mono text-[10px] text-amber-500">
                          wait:{a.waitMinutes}m
                        </p>
                      )}
                    </div>
                  </li>
                ))}
              </ul>
            )}
          </section>

          <section className="lg:col-span-4">
            <h2 className="mb-4 font-mono text-xs uppercase tracking-widest text-slate-500">
              Provider load
            </h2>
            {summary.doctors.length === 0 ? (
              <p className="text-sm text-slate-600">No providers</p>
            ) : (
              <ul className="space-y-3">
                {summary.doctors.map((d) => {
                  const load = d.currentPatient ? 100 : 15;
                  return (
                    <li
                      key={d.id}
                      className="rounded-lg border border-slate-800 bg-slate-900/40 p-4"
                    >
                      <div className="flex justify-between text-sm">
                        <span className="font-medium">{d.name}</span>
                        <span className="font-mono text-xs text-slate-500">
                          {shiftStatusLabels[d.shiftStatus]}
                        </span>
                      </div>
                      <div className="mt-2 h-2 overflow-hidden rounded-sm bg-slate-800">
                        <div
                          className={`h-full rounded-sm ${d.currentPatient ? "bg-violet-500" : "bg-emerald-500"}`}
                          style={{ width: `${load}%` }}
                        />
                      </div>
                      <p className="mt-2 font-mono text-[10px] text-slate-500">
                        {d.currentPatient ?? "idle"}
                        {d.sessionMinutes !== undefined && ` · ${formatDuration(d.sessionMinutes)}`}
                      </p>
                    </li>
                  );
                })}
              </ul>
            )}
          </section>
        </div>
      </div>
    </div>
  );
}
