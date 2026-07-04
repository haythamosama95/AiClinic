import type { EncounterWorkspace } from "@/lib/encounter-types";
import { formatDateLong, formatTime } from "@/lib/format";
import { visitStatusLabels, investigationStatusLabels } from "@/lib/encounter-labels";
import { ThemeChrome } from "@/components/ThemeChrome";

export function EncounterAiNativeTheme({ encounter }: { encounter: EncounterWorkspace }) {
  const { visit, patient, doctor, safety, note, vitals, treatments, investigations, attachments } =
    encounter;

  return (
    <div className="relative min-h-screen overflow-hidden bg-[#07070d] font-[family-name:var(--font-space)] text-zinc-100">
      <div className="pointer-events-none absolute inset-0 bg-[radial-gradient(ellipse_at_30%_0%,rgba(139,92,246,0.2),transparent_50%)]" aria-hidden />
      <div className="relative mx-auto max-w-6xl px-4 py-8">
        <ThemeChrome themeName="AI Native · Encounter" className="mb-8 text-zinc-600" />

        <header className="mb-8 rounded-xl border border-violet-500/25 bg-zinc-900/70 p-6">
          <div className="flex flex-wrap justify-between gap-4">
            <div>
              <p className="font-mono text-[10px] uppercase tracking-widest text-violet-400">
                encounter_ctx
              </p>
              <h1 className="mt-2 text-2xl font-semibold">{patient.name}</h1>
              <p className="font-mono text-xs text-zinc-500">
                {patient.mrn} · {patient.age}y · {patient.sex}
              </p>
            </div>
            <div className="text-right font-mono text-xs text-zinc-500">
              <p>status:{visitStatusLabels[visit.status].toLowerCase().replace(" ", "_")}</p>
              <p>ts:{formatDateLong(visit.dateTime)} {formatTime(visit.dateTime)}</p>
              <p>provider:{doctor.name}</p>
              <p>type:{visit.type}</p>
            </div>
          </div>
        </header>

        <section className="mb-8 rounded-xl border border-rose-500/30 bg-rose-950/30 p-5">
          <h2 className="font-mono text-[10px] uppercase tracking-widest text-rose-400">
            {"// safety_surface"}
          </h2>
          <div className="mt-4 grid gap-4 font-mono text-xs sm:grid-cols-3">
            <div>
              <p className="text-zinc-600">allergies[]</p>
              {safety.allergies.map((a) => (
                <p key={a.substance} className="mt-1 text-rose-300">
                  {a.substance}:{a.reaction}
                </p>
              ))}
            </div>
            <div>
              <p className="text-zinc-600">home_meds[]</p>
              {safety.currentMedications.map((m) => (
                <p key={m} className="mt-1 text-zinc-400">
                  {m}
                </p>
              ))}
            </div>
            <div>
              <p className="text-zinc-600">conditions[]</p>
              <p className="mt-1 text-zinc-400">{safety.chronicConditions.join(" | ")}</p>
            </div>
          </div>
        </section>

        <div className="grid gap-6 lg:grid-cols-12">
          <section className="lg:col-span-7">
            <h2 className="mb-4 font-mono text-[10px] uppercase tracking-widest text-zinc-600">
              {"// clinical_note"}
            </h2>
            <div className="space-y-3">
              {(
                [
                  ["complaint", note.complaint],
                  ["history", note.history],
                  ["examination", note.examination],
                  ["diagnosis", note.diagnosis],
                  ["plan", note.plan],
                ] as const
              ).map(([key, val]) => (
                <div
                  key={key}
                  className="rounded-lg border border-zinc-800 bg-zinc-900/50 p-4"
                >
                  <p className="font-mono text-[10px] text-violet-400">{key}</p>
                  <p className="mt-2 text-sm leading-relaxed text-zinc-300">{val}</p>
                </div>
              ))}
            </div>
          </section>

          <div className="flex flex-col gap-6 lg:col-span-5">
            <section className="rounded-xl border border-zinc-800 bg-zinc-900/50 p-4">
              <h2 className="font-mono text-[10px] uppercase tracking-widest text-sky-400">
                {"// vitals"}
              </h2>
              <ul className="mt-3 space-y-2 font-mono text-xs">
                {vitals.map((v) => (
                  <li key={v.type} className="flex justify-between text-zinc-400">
                    <span>{v.type}</span>
                    <span className="text-sky-300">
                      {v.value}
                      {v.unit}
                    </span>
                  </li>
                ))}
              </ul>
            </section>

            <section className="rounded-xl border border-zinc-800 bg-zinc-900/50 p-4">
              <h2 className="font-mono text-[10px] uppercase tracking-widest text-emerald-400">
                {"// treatments"}
              </h2>
              <ul className="mt-3 space-y-3 text-sm">
                {treatments.map((t) => (
                  <li key={t.id} className="border-l-2 border-emerald-500/40 pl-3">
                    <p>{t.medication}</p>
                    <p className="font-mono text-[10px] text-zinc-600">
                      {t.dose}|{t.frequency}|{t.duration}
                    </p>
                  </li>
                ))}
              </ul>
            </section>

            <section className="rounded-xl border border-zinc-800 bg-zinc-900/50 p-4">
              <h2 className="font-mono text-[10px] uppercase tracking-widest text-amber-400">
                {"// investigations"}
              </h2>
              <ul className="mt-3 space-y-2 text-sm">
                {investigations.map((i) => (
                  <li key={i.id}>
                    <span>{i.name}</span>
                    <span className="ml-2 font-mono text-[10px] text-zinc-600">
                      [{investigationStatusLabels[i.status]}]
                      {i.result ? ` → ${i.result}` : ""}
                    </span>
                  </li>
                ))}
              </ul>
            </section>

            <section className="rounded-xl border border-zinc-800 bg-zinc-900/50 p-4">
              <h2 className="font-mono text-[10px] uppercase tracking-widest text-zinc-600">
                {"// attachments"}
              </h2>
              <ul className="mt-3 space-y-1 font-mono text-[10px] text-zinc-500">
                {attachments.map((a) => (
                  <li key={a.id}>
                    {a.name} ({a.sizeLabel})
                  </li>
                ))}
              </ul>
            </section>
          </div>
        </div>
      </div>
    </div>
  );
}
