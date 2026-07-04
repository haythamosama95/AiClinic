import type { ClinicSummary } from "@/lib/types";
import { formatDateLong, formatTimeRange, formatWait, formatTime, formatDuration } from "@/lib/format";
import { doctorAssignmentLabel, statusLabels, visitPhaseLabels, shiftStatusLabels } from "@/lib/labels";
import { getSummaryStats } from "@/lib/stats";
import { ThemeChrome } from "@/components/ThemeChrome";

function BentoCell({
  children,
  className = "",
}: {
  children: React.ReactNode;
  className?: string;
}) {
  return (
    <div className={`rounded-3xl p-5 ${className}`}>{children}</div>
  );
}

export function BentoTheme({ summary }: { summary: ClinicSummary }) {
  const stats = getSummaryStats(summary);

  return (
    <div className="min-h-screen bg-[#F5F0EB] font-[family-name:var(--font-sora)] text-stone-900">
      <div className="mx-auto max-w-6xl px-4 py-8 sm:px-6">
        <ThemeChrome themeName="Bento" className="mb-6 text-stone-500" />

        <div className="grid auto-rows-min gap-4 sm:grid-cols-6 lg:grid-cols-12">
          <BentoCell className="bg-stone-900 text-white sm:col-span-4 lg:col-span-5">
            <p className="text-sm text-stone-400">{formatDateLong(summary.date)}</p>
            <h1 className="mt-2 text-3xl font-bold tracking-tight">Today&apos;s clinic</h1>
            <p className="mt-2 text-stone-400">Summary stats at a glance</p>
          </BentoCell>

          <BentoCell className="bg-orange-500 text-white sm:col-span-2 lg:col-span-2">
            <p className="text-5xl font-bold">{stats.appointmentCount}</p>
            <p className="mt-1 text-sm text-orange-100">Appointments</p>
          </BentoCell>

          <BentoCell className="bg-violet-500 text-white sm:col-span-2 lg:col-span-2">
            <p className="text-5xl font-bold">{stats.inProgress}</p>
            <p className="mt-1 text-sm text-violet-100">In progress</p>
          </BentoCell>

          <BentoCell className="bg-amber-400 text-stone-900 sm:col-span-2 lg:col-span-3">
            <p className="text-5xl font-bold">{stats.waiting}</p>
            <p className="mt-1 text-sm text-stone-700">In waiting room</p>
          </BentoCell>

          <BentoCell className="bg-emerald-500 text-white lg:col-span-12 lg:row-span-1">
            <div className="flex flex-wrap items-center justify-between gap-4">
              <div>
                <p className="text-4xl font-bold">{stats.onShift}</p>
                <p className="text-sm text-emerald-100">Doctors on shift</p>
              </div>
              <p className="max-w-md text-sm text-emerald-50">
                {stats.completed} completed · {stats.checkedIn} checked in
              </p>
            </div>
          </BentoCell>

          <BentoCell className="bg-white sm:col-span-6 lg:col-span-7 lg:row-span-2">
            <h2 className="text-lg font-bold">Appointments</h2>
            {summary.appointments.length === 0 ? (
              <p className="mt-6 text-stone-400">No appointments today</p>
            ) : (
              <ul className="mt-4 max-h-[28rem] space-y-3 overflow-y-auto pr-1">
                {summary.appointments.map((a) => (
                  <li
                    key={a.id}
                    className="rounded-2xl bg-stone-50 p-4 transition hover:bg-stone-100"
                  >
                    <div className="flex gap-3">
                      <span className="shrink-0 rounded-xl bg-stone-900 px-2 py-1 text-xs font-semibold text-white">
                        {formatTimeRange(a.startTime, a.endTime)}
                      </span>
                      <div>
                        <p className="font-semibold">{a.patientName}</p>
                        <p className="text-sm text-stone-500">{a.appointmentType}</p>
                        <div className="mt-2 flex flex-wrap gap-1.5">
                          <span className="rounded-full bg-orange-100 px-2 py-0.5 text-xs text-orange-800">
                            {statusLabels[a.status]}
                          </span>
                          <span className="rounded-full bg-violet-100 px-2 py-0.5 text-xs text-violet-800">
                            {visitPhaseLabels[a.visitPhase]}
                          </span>
                        </div>
                        <p className="mt-2 text-xs text-stone-500">
                          {doctorAssignmentLabel(a.doctorName, a.doctorOnShift)}
                          {a.patientChoseDoctor && a.doctorName && " · Patient's choice"}
                        </p>
                        {a.waitMinutes !== undefined && (
                          <p className="mt-1 text-xs font-medium text-amber-700">
                            Wait {formatWait(a.waitMinutes)}
                          </p>
                        )}
                      </div>
                    </div>
                  </li>
                ))}
              </ul>
            )}
          </BentoCell>

          <BentoCell className="bg-sky-100 sm:col-span-3 lg:col-span-5">
            <h2 className="text-lg font-bold text-sky-950">Doctors</h2>
            {summary.doctors.length === 0 ? (
              <p className="mt-4 text-sm text-sky-800/60">No doctors on shift</p>
            ) : (
              <ul className="mt-4 space-y-3">
                {summary.doctors.map((d) => (
                  <li key={d.id} className="rounded-2xl bg-white/70 p-3">
                    <p className="font-semibold">{d.name}</p>
                    <p className="text-xs text-sky-700">{shiftStatusLabels[d.shiftStatus]}</p>
                    <p className="mt-1 text-sm text-stone-600">
                      {d.currentPatient ?? "Available"}
                      {d.sessionMinutes !== undefined && ` · ${formatDuration(d.sessionMinutes)}`}
                    </p>
                  </li>
                ))}
              </ul>
            )}
          </BentoCell>

          <BentoCell className="bg-rose-200 sm:col-span-3 lg:col-span-5">
            <div className="flex items-center justify-between">
              <h2 className="text-lg font-bold text-rose-950">Checked in</h2>
              <span className="rounded-full bg-rose-500 px-3 py-1 text-sm font-bold text-white">
                {stats.waiting}
              </span>
            </div>
            {summary.waitingRoom.length === 0 ? (
              <p className="mt-4 text-sm text-rose-900/60">Waiting room is clear</p>
            ) : (
              <ul className="mt-4 space-y-3">
                {summary.waitingRoom.map((w) => (
                  <li key={w.id} className="rounded-2xl bg-white/60 p-3">
                    <div className="flex justify-between gap-2">
                      <p className="font-semibold">{w.patientName}</p>
                      <span className="text-sm font-bold text-rose-700">
                        {formatWait(w.waitMinutes)}
                      </span>
                    </div>
                    <p className="mt-1 text-xs text-stone-600">
                      {doctorAssignmentLabel(w.doctorName, true)} · {formatTime(w.scheduledTime)}
                    </p>
                  </li>
                ))}
              </ul>
            )}
          </BentoCell>
        </div>
      </div>
    </div>
  );
}
