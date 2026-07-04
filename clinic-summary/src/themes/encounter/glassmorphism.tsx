import type { EncounterWorkspace } from "@/lib/encounter-types";
import { formatDateLong, formatTime } from "@/lib/format";
import { visitStatusLabels, investigationStatusLabels } from "@/lib/encounter-labels";
import { ThemeChrome } from "@/components/ThemeChrome";

function GlassPanel({
  children,
  className = "",
}: {
  children: React.ReactNode;
  className?: string;
}) {
  return (
    <div
      className={`rounded-2xl border border-white/20 bg-white/10 p-5 backdrop-blur-xl ${className}`}
    >
      {children}
    </div>
  );
}

export function EncounterGlassmorphismTheme({ encounter }: { encounter: EncounterWorkspace }) {
  const { visit, patient, doctor, safety, note, vitals, treatments, investigations, attachments } =
    encounter;

  return (
    <div className="relative min-h-screen font-[family-name:var(--font-jakarta)] text-white">
      <div className="fixed inset-0 bg-gradient-to-br from-violet-700 via-fuchsia-600 to-cyan-500" aria-hidden />
      <div className="relative mx-auto max-w-6xl px-4 py-8 sm:px-6">
        <ThemeChrome themeName="Glassmorphism · Encounter" className="mb-6 text-white/70" />

        <GlassPanel className="mb-6">
          <div className="flex flex-wrap justify-between gap-4">
            <div>
              <span className="rounded-full bg-white/20 px-3 py-1 text-xs">
                {visitStatusLabels[visit.status]}
              </span>
              <h1 className="mt-3 text-3xl font-bold">{patient.name}</h1>
              <p className="text-white/70">
                {patient.age}y · {patient.sex} · {patient.mrn}
              </p>
            </div>
            <div className="text-right text-sm text-white/80">
              <p>{formatDateLong(visit.dateTime)}</p>
              <p>{formatTime(visit.dateTime)} · {visit.type}</p>
              <p className="mt-1">{doctor.name}</p>
              <p className="text-white/60">{doctor.specialty}</p>
            </div>
          </div>
        </GlassPanel>

        <GlassPanel className="mb-6 !border-rose-300/30 !bg-rose-500/15">
          <h2 className="text-sm font-semibold text-rose-100">Patient safety</h2>
          <div className="mt-3 grid gap-4 sm:grid-cols-2">
            <div>
              <p className="text-xs text-white/50">Allergies</p>
              <ul className="mt-1 text-sm">
                {safety.allergies.map((a) => (
                  <li key={a.substance}>
                    {a.substance} — {a.reaction}
                  </li>
                ))}
              </ul>
            </div>
            <div>
              <p className="text-xs text-white/50">Home medications</p>
              <ul className="mt-1 text-sm text-white/80">
                {safety.currentMedications.map((m) => (
                  <li key={m}>{m}</li>
                ))}
              </ul>
            </div>
          </div>
        </GlassPanel>

        <div className="grid gap-6 lg:grid-cols-2">
          {(
            [
              ["Complaint", note.complaint],
              ["History", note.history],
              ["Examination", note.examination],
              ["Diagnosis", note.diagnosis],
              ["Plan", note.plan],
            ] as const
          ).map(([label, text]) => (
            <GlassPanel key={label}>
              <h2 className="text-sm font-semibold text-white/90">{label}</h2>
              <p className="mt-2 text-sm leading-relaxed text-white/75">{text}</p>
            </GlassPanel>
          ))}

          <GlassPanel>
            <h2 className="text-sm font-semibold">Vitals this visit</h2>
            <div className="mt-3 grid grid-cols-2 gap-2">
              {vitals.map((v) => (
                <div key={v.type} className="rounded-xl bg-white/10 px-3 py-2 text-center">
                  <p className="text-lg font-bold">{v.value}</p>
                  <p className="text-[10px] text-white/50">
                    {v.type} ({v.unit})
                  </p>
                </div>
              ))}
            </div>
          </GlassPanel>

          <GlassPanel>
            <h2 className="text-sm font-semibold">Treatments</h2>
            <ul className="mt-3 space-y-3">
              {treatments.map((t) => (
                <li key={t.id} className="rounded-xl bg-white/10 p-3 text-sm">
                  <p className="font-medium">{t.medication}</p>
                  <p className="text-white/60">
                    {t.dose} · {t.frequency} · {t.duration}
                  </p>
                </li>
              ))}
            </ul>
          </GlassPanel>

          <GlassPanel>
            <h2 className="text-sm font-semibold">Investigations</h2>
            <ul className="mt-3 space-y-2 text-sm">
              {investigations.map((i) => (
                <li key={i.id} className="flex justify-between gap-2">
                  <span>{i.name}</span>
                  <span className="text-white/50">
                    {investigationStatusLabels[i.status]}
                    {i.result ? ` · ${i.result}` : ""}
                  </span>
                </li>
              ))}
            </ul>
          </GlassPanel>

          <GlassPanel>
            <h2 className="text-sm font-semibold">Attachments</h2>
            <ul className="mt-3 space-y-2 text-sm text-white/80">
              {attachments.map((a) => (
                <li key={a.id} className="rounded-lg bg-white/10 px-3 py-2">
                  {a.name}
                  <span className="ml-2 text-xs text-white/40">{a.sizeLabel}</span>
                </li>
              ))}
            </ul>
          </GlassPanel>
        </div>
      </div>
    </div>
  );
}
