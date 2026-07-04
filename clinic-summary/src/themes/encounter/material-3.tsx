import type { EncounterWorkspace } from "@/lib/encounter-types";
import { formatDateLong, formatTime } from "@/lib/format";
import { visitStatusLabels } from "@/lib/encounter-labels";
import { ThemeChrome } from "@/components/ThemeChrome";

export function EncounterMaterial3Theme({ encounter }: { encounter: EncounterWorkspace }) {
  const { visit, patient, doctor, safety, note, vitals, treatments, investigations, attachments } =
    encounter;

  const phases = [
    {
      title: "Subjective", bg: "bg-[#E8DEF8]", text: "text-[#1D192B]", fields: [
        { label: "Complaint", value: note.complaint },
        { label: "History", value: note.history },
      ]
    },
    {
      title: "Objective", bg: "bg-[#D0E8D0]", text: "text-[#1B3A1B]", fields: [
        { label: "Examination", value: note.examination },
      ]
    },
    {
      title: "Assessment", bg: "bg-[#FFD8E4]", text: "text-[#31111D]", fields: [
        { label: "Diagnosis", value: note.diagnosis },
      ]
    },
    {
      title: "Plan", bg: "bg-[#EADDFF]", text: "text-[#21005D]", fields: [
        { label: "Plan", value: note.plan },
      ]
    },
  ];

  return (
    <div className="min-h-screen bg-[#FFFBFE] font-[family-name:var(--font-roboto)] text-[#1C1B1F]">
      <div className="mx-auto max-w-5xl px-4 py-6">
        <ThemeChrome themeName="Material 3 · Encounter" className="mb-6 text-[#79747E]" />

        <header className="mb-6 rounded-[28px] bg-[#6750A4] px-6 py-8 text-white">
          <p className="text-sm opacity-80">{formatDateLong(visit.dateTime)} · {formatTime(visit.dateTime)}</p>
          <h1 className="mt-2 text-3xl font-normal">{patient.name}</h1>
          <p className="mt-1 opacity-80">{patient.age}y · {patient.sex} · {patient.mrn}</p>
          <div className="mt-4 flex flex-wrap gap-2">
            <span className="rounded-lg bg-white/20 px-3 py-1 text-sm">{visitStatusLabels[visit.status]}</span>
            <span className="rounded-lg bg-white/20 px-3 py-1 text-sm">{visit.type}</span>
            <span className="rounded-lg bg-white/20 px-3 py-1 text-sm">{doctor.name}</span>
          </div>
        </header>

        <section className="mb-6 rounded-[28px] bg-[#F9DEDC] p-6">
          <h2 className="text-lg text-[#410E0B]">Patient safety</h2>
          <p className="mt-2 text-sm text-[#601410]">
            Allergies: {safety.allergies.map((a) => a.substance).join(", ")}
          </p>
          <p className="mt-1 text-sm text-[#601410]">
            Conditions: {safety.chronicConditions.join(", ")}
          </p>
        </section>

        <div className="grid gap-4 sm:grid-cols-2">
          {phases.map((phase) => (
            <section key={phase.title} className={`rounded-[28px] ${phase.bg} p-6`}>
              <h2 className={`text-xl font-normal ${phase.text}`}>{phase.title}</h2>
              {phase.fields.map((f) => (
                <div key={f.label} className="mt-4 rounded-2xl bg-[#FFFBFE] p-4 shadow-sm">
                  <p className="text-xs font-medium text-[#49454F]">{f.label}</p>
                  <p className="mt-2 text-sm leading-relaxed">{f.value}</p>
                </div>
              ))}
            </section>
          ))}
        </div>

        <section className="mt-6 rounded-[28px] bg-[#E7E0EC] p-6">
          <h2 className="text-xl">Vitals</h2>
          <div className="mt-4 flex flex-wrap gap-2">
            {vitals.map((v) => (
              <span key={v.type} className="rounded-xl bg-[#FFFBFE] px-4 py-2 text-sm shadow-sm">
                <strong>{v.value}</strong> {v.unit} — {v.type}
              </span>
            ))}
          </div>
        </section>

        <div className="mt-6 grid gap-4 sm:grid-cols-3">
          <section className="rounded-[28px] bg-[#E8DEF8] p-5">
            <h2 className="text-lg">Treatments</h2>
            <ul className="mt-3 space-y-2 text-sm">
              {treatments.map((t) => (
                <li key={t.id} className="rounded-xl bg-white p-3">{t.medication} — {t.dose}</li>
              ))}
            </ul>
          </section>
          <section className="rounded-[28px] bg-[#FFD8E4] p-5">
            <h2 className="text-lg">Investigations</h2>
            <ul className="mt-3 space-y-2 text-sm">
              {investigations.map((i) => (
                <li key={i.id} className="rounded-xl bg-white p-3">{i.name}</li>
              ))}
            </ul>
          </section>
          <section className="rounded-[28px] bg-[#D0BCFF] p-5">
            <h2 className="text-lg">Attachments</h2>
            <ul className="mt-3 space-y-2 text-sm">
              {attachments.map((a) => (
                <li key={a.id} className="truncate rounded-xl bg-white p-3">{a.name}</li>
              ))}
            </ul>
          </section>
        </div>
      </div>
    </div>
  );
}
