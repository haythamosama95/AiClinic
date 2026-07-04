import type { EncounterWorkspace } from "@/lib/encounter-types";
import { formatDateLong, formatTime } from "@/lib/format";
import { visitStatusLabels } from "@/lib/encounter-labels";
import { ThemeChrome } from "@/components/ThemeChrome";

function VitalBar({ label, value, max, unit, color }: {
  label: string; value: number; max: number; unit: string; color: string;
}) {
  return (
    <div>
      <div className="mb-1 flex justify-between font-mono text-xs">
        <span className="text-slate-500">{label}</span>
        <span className="text-slate-300">{value}{unit}</span>
      </div>
      <div className="h-3 overflow-hidden rounded-sm bg-slate-800">
        <div className={`h-full ${color}`} style={{ width: `${Math.min((value / max) * 100, 100)}%` }} />
      </div>
    </div>
  );
}

export function EncounterDataVisualizationTheme({ encounter }: { encounter: EncounterWorkspace }) {
  const { visit, patient, doctor, safety, note, vitals, treatments, investigations, attachments } =
    encounter;

  const hr = parseFloat(vitals.find((v) => v.type === "Heart rate")?.value ?? "0");
  const spo2 = parseFloat(vitals.find((v) => v.type === "SpO₂")?.value ?? "0");
  const temp = parseFloat(vitals.find((v) => v.type === "Temperature")?.value ?? "0");
  const weight = parseFloat(vitals.find((v) => v.type === "Weight")?.value ?? "0");

  return (
    <div className="min-h-screen bg-[#0B1120] font-[family-name:var(--font-archivo)] text-slate-200">
      <div className="mx-auto max-w-7xl px-4 py-6">
        <ThemeChrome themeName="Data Visualization · Encounter" className="mb-6 text-slate-600" />

        <header className="mb-8 grid gap-6 border-b border-slate-800 pb-8 lg:grid-cols-12">
          <div className="lg:col-span-5">
            <p className="font-mono text-xs uppercase tracking-widest text-emerald-400">
              Encounter record
            </p>
            <h1 className="mt-2 text-3xl font-bold">{patient.name}</h1>
            <p className="font-mono text-sm text-slate-500">
              {patient.mrn} · {visitStatusLabels[visit.status]}
            </p>
            <p className="mt-2 text-sm text-slate-400">
              {doctor.name} · {formatDateLong(visit.dateTime)} {formatTime(visit.dateTime)}
            </p>
          </div>
          <div className="grid grid-cols-2 gap-3 sm:grid-cols-4 lg:col-span-7">
            {[
              { l: "ALLERGIES", v: safety.allergies.length, c: "text-rose-400" },
              { l: "HOME MEDS", v: safety.currentMedications.length, c: "text-amber-400" },
              { l: "TREATMENTS", v: treatments.length, c: "text-violet-400" },
              { l: "FILES", v: attachments.length, c: "text-sky-400" },
            ].map((m) => (
              <div key={m.l} className="rounded-lg border border-slate-800 bg-slate-900/80 p-4">
                <p className={`font-mono text-2xl font-bold ${m.c}`}>{m.v}</p>
                <p className="font-mono text-[10px] text-slate-600">{m.l}</p>
              </div>
            ))}
          </div>
        </header>

        <div className="mb-8 grid gap-6 lg:grid-cols-2">
          <section className="rounded-lg border border-slate-800 bg-slate-900/50 p-5">
            <h2 className="font-mono text-xs uppercase tracking-widest text-slate-500">
              Vital signs — this visit
            </h2>
            <div className="mt-4 space-y-4">
              <VitalBar label="Heart rate" value={hr} max={120} unit=" bpm" color="bg-rose-500" />
              <VitalBar label="SpO₂" value={spo2} max={100} unit="%" color="bg-sky-500" />
              <VitalBar label="Temperature" value={temp} max={40} unit="°C" color="bg-amber-500" />
              <VitalBar label="Weight" value={weight} max={120} unit=" kg" color="bg-emerald-500" />
            </div>
          </section>

          <section className="rounded-lg border border-slate-800 bg-slate-900/50 p-5">
            <h2 className="font-mono text-xs uppercase tracking-widest text-slate-500">
              Investigation pipeline
            </h2>
            <ul className="mt-4 space-y-3">
              {investigations.map((i) => (
                <li key={i.id}>
                  <div className="mb-1 flex justify-between text-sm">
                    <span>{i.name}</span>
                    <span className="font-mono text-xs text-slate-500">{i.status}</span>
                  </div>
                  <div className="h-2 overflow-hidden rounded-sm bg-slate-800">
                    <div
                      className={`h-full ${i.status === "completed" ? "w-full bg-emerald-500" : i.status === "pending" ? "w-2/3 bg-amber-500" : "w-1/3 bg-slate-600"}`}
                    />
                  </div>
                  {i.result && (
                    <p className="mt-1 font-mono text-xs text-emerald-400">{i.result}</p>
                  )}
                </li>
              ))}
            </ul>
          </section>
        </div>

        <section className="mb-8 rounded-lg border border-rose-900/50 bg-rose-950/20 p-5">
          <h2 className="font-mono text-xs uppercase tracking-widest text-rose-400">Safety flags</h2>
          <p className="mt-2 text-sm">
            {safety.allergies.map((a) => `${a.substance} (${a.reaction})`).join(" · ")}
          </p>
        </section>

        <div className="grid gap-6 lg:grid-cols-12">
          <section className="lg:col-span-7">
            <h2 className="mb-4 font-mono text-xs uppercase tracking-widest text-slate-500">
              Clinical narrative
            </h2>
            <div className="space-y-3">
              {(
                [
                  ["S", note.complaint + " " + note.history],
                  ["O", note.examination],
                  ["A", note.diagnosis],
                  ["P", note.plan],
                ] as const
              ).map(([tag, text]) => (
                <div key={tag} className="grid grid-cols-[2rem_1fr] gap-3 rounded-lg border border-slate-800 bg-slate-900/40 p-4">
                  <span className="font-mono text-lg font-bold text-emerald-500">{tag}</span>
                  <p className="text-sm leading-relaxed text-slate-300">{text}</p>
                </div>
              ))}
            </div>
          </section>

          <div className="flex flex-col gap-6 lg:col-span-5">
            <section className="rounded-lg border border-slate-800 bg-slate-900/40 p-4">
              <h2 className="font-mono text-xs uppercase tracking-widest text-violet-400">
                Prescriptions
              </h2>
              <ul className="mt-3 space-y-2 text-sm">
                {treatments.map((t) => (
                  <li key={t.id} className="flex justify-between border-b border-slate-800 pb-2">
                    <span>{t.medication}</span>
                    <span className="font-mono text-xs text-slate-500">{t.dose}</span>
                  </li>
                ))}
              </ul>
            </section>
            <section className="rounded-lg border border-slate-800 bg-slate-900/40 p-4">
              <h2 className="font-mono text-xs uppercase tracking-widest text-slate-500">
                Attachments
              </h2>
              <ul className="mt-3 space-y-1 font-mono text-xs text-slate-500">
                {attachments.map((a) => (
                  <li key={a.id}>{a.name}</li>
                ))}
              </ul>
            </section>
          </div>
        </div>
      </div>
    </div>
  );
}
