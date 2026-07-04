import type { EncounterWorkspace } from "@/lib/encounter-types";
import { formatDateLong, formatTime } from "@/lib/format";
import { visitStatusLabels } from "@/lib/encounter-labels";
import { ThemeChrome } from "@/components/ThemeChrome";

export function EncounterFuturisticMinimalTheme({ encounter }: { encounter: EncounterWorkspace }) {
  const { visit, patient, doctor, safety, note, vitals, treatments, investigations, attachments } =
    encounter;

  return (
    <div className="min-h-screen bg-black font-[family-name:var(--font-syne)] text-white">
      <div className="mx-auto max-w-3xl px-6 py-12">
        <ThemeChrome themeName="Futuristic Minimal · Encounter" className="mb-16 text-white/30" />

        <header className="border-l-2 border-[#00FFD1] pl-6">
          <p className="text-[10px] uppercase tracking-[0.35em] text-[#00FFD1]/60">
            {visitStatusLabels[visit.status]}
          </p>
          <h1 className="mt-4 text-3xl font-light uppercase tracking-[0.12em]">{patient.name}</h1>
          <p className="mt-2 font-mono text-xs text-white/40">
            {patient.mrn} · {formatDateLong(visit.dateTime)} · {formatTime(visit.dateTime)}
          </p>
          <p className="mt-1 font-mono text-xs text-white/30">
            {doctor.name} / {visit.type}
          </p>
        </header>

        <section className="mt-16 border border-[#00FFD1]/20 p-5">
          <h2 className="text-[10px] uppercase tracking-[0.35em] text-[#00FFD1]/50">Safety</h2>
          <p className="mt-4 font-mono text-xs leading-relaxed text-white/50">
            ALG: {safety.allergies.map((a) => a.substance).join(" | ")}
          </p>
          <p className="mt-2 font-mono text-xs text-white/40">
            CHR: {safety.chronicConditions.join(" | ")}
          </p>
        </section>

        {(
          [
            ["01 — Subjective", note.complaint + "\n\n" + note.history],
            ["02 — Objective", note.examination],
            ["03 — Assessment", note.diagnosis],
            ["04 — Plan", note.plan],
          ] as const
        ).map(([title, text]) => (
          <section key={title} className="mt-12">
            <h2 className="text-[10px] uppercase tracking-[0.35em] text-white/30">{title}</h2>
            <p className="mt-4 whitespace-pre-line text-sm font-light leading-relaxed text-white/70">
              {text}
            </p>
          </section>
        ))}

        <section className="mt-16">
          <h2 className="text-[10px] uppercase tracking-[0.35em] text-white/30">05 — Vitals</h2>
          <div className="mt-6 grid grid-cols-3 gap-px bg-white/10">
            {vitals.map((v) => (
              <div key={v.type} className="bg-black p-4 text-center">
                <p className="font-mono text-lg text-[#00FFD1]">{v.value}</p>
                <p className="mt-1 text-[9px] uppercase tracking-wider text-white/30">{v.type}</p>
              </div>
            ))}
          </div>
        </section>

        <section className="mt-16">
          <h2 className="text-[10px] uppercase tracking-[0.35em] text-white/30">06 — Meds</h2>
          <ul className="mt-6 divide-y divide-white/10">
            {treatments.map((t) => (
              <li key={t.id} className="py-4 font-mono text-xs text-white/60">
                {t.medication} — {t.dose} — {t.frequency}
              </li>
            ))}
          </ul>
        </section>

        <section className="mt-16">
          <h2 className="text-[10px] uppercase tracking-[0.35em] text-white/30">
            07 — Labs & files
          </h2>
          <ul className="mt-6 space-y-2 font-mono text-xs text-white/40">
            {investigations.map((i) => (
              <li key={i.id}>
                {i.name}
                {i.result ? ` :: ${i.result}` : ""}
              </li>
            ))}
            {attachments.map((a) => (
              <li key={a.id} className="text-white/25">
                FILE: {a.name}
              </li>
            ))}
          </ul>
        </section>
      </div>
    </div>
  );
}
