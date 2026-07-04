import type { ClinicSummary } from "@/lib/types";
import { formatDateLong, formatTimeRange, formatWait, formatTime, formatDuration } from "@/lib/format";
import { doctorAssignmentLabel, statusLabels, visitPhaseLabels, shiftStatusLabels } from "@/lib/labels";
import { getSummaryStats } from "@/lib/stats";
import { ThemeChrome } from "@/components/ThemeChrome";

function GlassCard({
  children,
  className = "",
}: {
  children: React.ReactNode;
  className?: string;
}) {
  return (
    <div
      className={`rounded-2xl border border-white/20 bg-white/10 p-5 shadow-[0_8px_32px_rgba(0,0,0,0.12)] backdrop-blur-xl ${className}`}
    >
      {children}
    </div>
  );
}

export function GlassmorphismTheme({ summary }: { summary: ClinicSummary }) {
  const stats = getSummaryStats(summary);

  return (
    <div className="relative min-h-screen font-[family-name:var(--font-jakarta)] text-white">
      <div
        className="fixed inset-0 bg-gradient-to-br from-indigo-600 via-purple-600 to-pink-500"
        aria-hidden
      />
      <div
        className="fixed inset-0 bg-[url('data:image/svg+xml;base64,PHN2ZyB3aWR0aD0iNjAiIGhlaWdodD0iNjAiIHZpZXdCb3g9IjAgMCA2MCA2MCIgeG1sbnM9Imh0dHA6Ly93d3cudzMub3JnLzIwMDAvc3ZnIj48ZyBmaWxsPSJub25lIiBmaWxsLXJ1bGU9ImV2ZW5vZGQiPjxwYXRoIGQ9Ik0zNiAxOGMtOS45NDEgMC0xOCA4LjA1OS0xOCAxOHM4LjA1OSAxOCAxOCAxOCAxOC04LjA1OSAxOC0xOC04LjA1OS0xOC0xOC0xOHptMCAzMmMtNy43MzIgMC0xNC02LjI2OC0xNC0xNCAwLTcuNzMyIDYuMjY4LTE0IDE0LTE0czE0IDYuMjY4IDE0IDE0LTYuMjY4IDE0LTE0IDE0eiIgZmlsbD0iI2ZmZiIgZmlsbC1vcGFjaXR5PSIuMDMiLz48L2c+PC9zdmc+')] opacity-60"
        aria-hidden
      />

      <div className="relative mx-auto max-w-6xl px-4 py-8 sm:px-6">
        <ThemeChrome themeName="Glassmorphism" className="mb-6 text-white/70" />

        <header className="mb-8">
          <GlassCard className="!bg-white/15">
            <p className="text-sm font-medium text-white/70">{formatDateLong(summary.date)}</p>
            <h1 className="mt-2 text-3xl font-bold tracking-tight">Clinic overview</h1>
            <div className="mt-6 grid grid-cols-2 gap-3 sm:grid-cols-4">
              {[
                ["Appointments", stats.appointmentCount],
                ["In progress", stats.inProgress],
                ["Waiting", stats.waiting],
                ["On shift", stats.onShift],
              ].map(([label, val]) => (
                <div
                  key={label as string}
                  className="rounded-xl bg-white/10 px-4 py-3 text-center backdrop-blur-sm"
                >
                  <p className="text-2xl font-bold">{val}</p>
                  <p className="text-xs text-white/60">{label}</p>
                </div>
              ))}
            </div>
          </GlassCard>
        </header>

        <div className="grid gap-6 lg:grid-cols-12">
          <section className="lg:col-span-7">
            <GlassCard>
              <h2 className="text-lg font-semibold">Appointments</h2>
              {summary.appointments.length === 0 ? (
                <p className="mt-6 text-center text-white/50">No appointments today</p>
              ) : (
                <ul className="mt-4 space-y-3">
                  {summary.appointments.map((a) => (
                    <li
                      key={a.id}
                      className="rounded-xl bg-white/5 p-4 ring-1 ring-white/10 transition hover:bg-white/10"
                    >
                      <div className="flex gap-3">
                        <time className="shrink-0 text-sm font-semibold text-cyan-200">
                          {formatTimeRange(a.startTime, a.endTime)}
                        </time>
                        <div>
                          <div className="flex flex-wrap gap-2">
                            <span className="rounded-full bg-white/20 px-2 py-0.5 text-xs">
                              {statusLabels[a.status]}
                            </span>
                            <span className="text-xs text-white/50">
                              {visitPhaseLabels[a.visitPhase]}
                            </span>
                          </div>
                          <p className="mt-1 font-semibold">{a.patientName}</p>
                          <p className="text-sm text-white/60">{a.appointmentType}</p>
                          <p className="mt-2 text-xs text-white/50">
                            {doctorAssignmentLabel(a.doctorName, a.doctorOnShift)}
                            {a.patientChoseDoctor && a.doctorName && " · Patient's choice"}
                          </p>
                          {a.waitMinutes !== undefined && (
                            <p className="mt-1 text-xs text-amber-200">
                              Waiting {formatWait(a.waitMinutes)}
                            </p>
                          )}
                        </div>
                      </div>
                    </li>
                  ))}
                </ul>
              )}
            </GlassCard>
          </section>

          <div className="flex flex-col gap-6 lg:col-span-5">
            <GlassCard>
              <h2 className="text-lg font-semibold">Doctors on shift</h2>
              {summary.doctors.length === 0 ? (
                <p className="mt-4 text-sm text-white/50">No doctors on shift</p>
              ) : (
                <ul className="mt-4 space-y-3">
                  {summary.doctors.map((d) => (
                    <li key={d.id} className="rounded-xl bg-white/5 p-3 ring-1 ring-white/10">
                      <p className="font-medium">{d.name}</p>
                      <p className="text-xs text-white/50">{shiftStatusLabels[d.shiftStatus]}</p>
                      <p className="mt-1 text-sm text-white/70">
                        {d.currentPatient ?? "Available · no patient in progress"}
                        {d.sessionMinutes !== undefined && ` · ${formatDuration(d.sessionMinutes)}`}
                      </p>
                    </li>
                  ))}
                </ul>
              )}
            </GlassCard>

            <GlassCard className="!border-cyan-300/30 !bg-cyan-500/10">
              <div className="flex items-center justify-between">
                <h2 className="text-lg font-semibold">Checked in</h2>
                <span className="rounded-full bg-white/25 px-3 py-1 text-sm font-bold">
                  {stats.waiting} waiting
                </span>
              </div>
              {summary.waitingRoom.length === 0 ? (
                <p className="mt-4 text-sm text-white/50">Waiting room is clear</p>
              ) : (
                <ul className="mt-4 space-y-3">
                  {summary.waitingRoom.map((w) => (
                    <li key={w.id} className="rounded-xl bg-white/5 p-3">
                      <div className="flex justify-between">
                        <p className="font-medium">{w.patientName}</p>
                        <span className="text-sm text-amber-200">{formatWait(w.waitMinutes)}</span>
                      </div>
                      <p className="mt-1 text-xs text-white/50">
                        {doctorAssignmentLabel(w.doctorName, true)} · Scheduled{" "}
                        {formatTime(w.scheduledTime)}
                      </p>
                    </li>
                  ))}
                </ul>
              )}
            </GlassCard>
          </div>
        </div>
      </div>
    </div>
  );
}
