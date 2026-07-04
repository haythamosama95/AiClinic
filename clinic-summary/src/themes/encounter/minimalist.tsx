import type { EncounterWorkspace } from "@/lib/encounter-types";
import { formatDateLong, formatTime } from "@/lib/format";
import { visitStatusLabels } from "@/lib/encounter-labels";
import { ThemeChrome } from "@/components/ThemeChrome";

function NoteBlock({ label, text }: { label: string; text: string }) {
  if (!text) return null;
  return (
    <div className="py-6">
      <h3 className="text-[11px] font-medium uppercase tracking-[0.2em] text-neutral-400">
        {label}
      </h3>
      <p className="mt-3 text-sm leading-relaxed text-neutral-800">{text}</p>
    </div>
  );
}

export function EncounterMinimalistTheme({ encounter }: { encounter: EncounterWorkspace }) {
  const { visit, patient, doctor, safety, note, vitals, treatments, investigations, attachments } =
    encounter;

  return (
    <div className="min-h-screen bg-white font-[family-name:var(--font-inter)] text-neutral-900">
      <div className="mx-auto max-w-2xl px-6 py-16">
        <ThemeChrome themeName="Minimalist · Encounter" className="mb-16 text-neutral-400" />

        <header className="border-b border-neutral-200 pb-10">
          <p className="text-[11px] uppercase tracking-[0.2em] text-neutral-400">
            {visitStatusLabels[visit.status]} · {visit.type}
          </p>
          <h1 className="mt-3 text-3xl font-light">{patient.name}</h1>
          <p className="mt-2 text-sm text-neutral-500">
            {patient.age}y · {patient.sex} · {patient.mrn}
          </p>
          <p className="mt-4 text-sm text-neutral-600">
            {formatDateLong(visit.dateTime)} at {formatTime(visit.dateTime)}
          </p>
          <p className="text-sm text-neutral-500">
            {doctor.name} · {doctor.specialty} · {visit.branch}
          </p>
        </header>

        <section className="border-b border-neutral-200 py-8">
          <h2 className="text-[11px] font-medium uppercase tracking-[0.2em] text-neutral-400">
            Safety
          </h2>
          {safety.allergies.length > 0 && (
            <div className="mt-4">
              <p className="text-xs text-neutral-500">Allergies</p>
              <ul className="mt-1 space-y-1 text-sm">
                {safety.allergies.map((a) => (
                  <li key={a.substance}>
                    {a.substance} — {a.reaction}
                  </li>
                ))}
              </ul>
            </div>
          )}
          {safety.currentMedications.length > 0 && (
            <div className="mt-4">
              <p className="text-xs text-neutral-500">Current medications</p>
              <ul className="mt-1 list-inside list-disc text-sm text-neutral-700">
                {safety.currentMedications.map((m) => (
                  <li key={m}>{m}</li>
                ))}
              </ul>
            </div>
          )}
          {safety.chronicConditions.length > 0 && (
            <p className="mt-4 text-sm text-neutral-600">
              {safety.chronicConditions.join(" · ")}
            </p>
          )}
        </section>

        <section className="divide-y divide-neutral-100">
          <NoteBlock label="Complaint" text={note.complaint} />
          <NoteBlock label="History" text={note.history} />
          <NoteBlock label="Examination" text={note.examination} />
          <NoteBlock label="Diagnosis" text={note.diagnosis} />
          <NoteBlock label="Plan" text={note.plan} />
        </section>

        <section className="mt-12 border-t border-neutral-200 pt-10">
          <h2 className="text-[11px] font-medium uppercase tracking-[0.2em] text-neutral-400">
            Vitals
          </h2>
          <ul className="mt-4 space-y-2 text-sm">
            {vitals.map((v) => (
              <li key={v.type} className="flex justify-between">
                <span className="text-neutral-500">{v.type}</span>
                <span className="tabular-nums">
                  {v.value} {v.unit}
                </span>
              </li>
            ))}
          </ul>
        </section>

        <section className="mt-12 border-t border-neutral-200 pt-10">
          <h2 className="text-[11px] font-medium uppercase tracking-[0.2em] text-neutral-400">
            Prescribed
          </h2>
          <ul className="mt-4 space-y-4 text-sm">
            {treatments.map((t) => (
              <li key={t.id}>
                <p className="font-medium">{t.medication}</p>
                <p className="text-neutral-500">
                  {t.dose} · {t.frequency} · {t.duration}
                </p>
              </li>
            ))}
          </ul>
        </section>

        <section className="mt-12 border-t border-neutral-200 pt-10">
          <h2 className="text-[11px] font-medium uppercase tracking-[0.2em] text-neutral-400">
            Investigations
          </h2>
          <ul className="mt-4 space-y-3 text-sm">
            {investigations.map((i) => (
              <li key={i.id}>
                <p>{i.name}</p>
                {i.result && <p className="text-neutral-500">Result: {i.result}</p>}
              </li>
            ))}
          </ul>
        </section>

        <section className="mt-12 border-t border-neutral-200 pt-10">
          <h2 className="text-[11px] font-medium uppercase tracking-[0.2em] text-neutral-400">
            Attachments
          </h2>
          <ul className="mt-4 space-y-2 text-sm text-neutral-600">
            {attachments.map((a) => (
              <li key={a.id}>{a.name}</li>
            ))}
          </ul>
        </section>
      </div>
    </div>
  );
}
