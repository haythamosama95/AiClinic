import type { EncounterWorkspace } from "@/lib/encounter-types";
import { formatDateLong, formatTime } from "@/lib/format";
import { visitStatusLabels, deriveBmi, findVital } from "@/lib/encounter-labels";
import { ThemeChrome } from "@/components/ThemeChrome";

export function EncounterHealthcareProfessionalTheme({
  encounter,
}: {
  encounter: EncounterWorkspace;
}) {
  const { visit, patient, doctor, safety, note, vitals, treatments, investigations, attachments } =
    encounter;

  const weight = findVital(vitals, "Weight");
  const height = findVital(vitals, "Height");
  const bmi =
    weight && height ? deriveBmi(parseFloat(weight), parseFloat(height)) : null;

  return (
    <div className="min-h-screen bg-[#ECFEFF] font-[family-name:var(--font-noto)] text-[#164E63]">
      <div className="border-b border-[#0891B2]/15 bg-white">
        <div className="mx-auto flex max-w-6xl items-center gap-3 px-4 py-3">
          <div className="flex h-9 w-9 items-center justify-center rounded-lg bg-[#0891B2] text-sm font-bold text-white">
            AC
          </div>
          <span className="font-[family-name:var(--font-figtree)] text-lg font-semibold">
            Encounter workspace
          </span>
        </div>
      </div>

      <div className="mx-auto max-w-6xl px-4 py-6">
        <ThemeChrome themeName="Healthcare Professional · Encounter" className="mb-6 text-[#64748B]" />

        <header className="rounded-xl border border-[#0891B2]/20 bg-white p-6 shadow-sm">
          <div className="flex flex-wrap justify-between gap-4">
            <div>
              <span className="rounded-full bg-[#ECFEFF] px-2.5 py-0.5 text-xs font-medium text-[#0891B2] ring-1 ring-[#0891B2]/20">
                {visitStatusLabels[visit.status]}
              </span>
              <h1 className="mt-2 font-[family-name:var(--font-figtree)] text-2xl font-semibold">
                {patient.name}
              </h1>
              <p className="text-sm text-[#64748B]">
                {patient.age}y · {patient.sex} · {patient.mrn} · DOB {patient.dateOfBirth}
              </p>
            </div>
            <div className="text-right text-sm">
              <p className="font-medium">{formatDateLong(visit.dateTime)}</p>
              <p className="text-[#64748B]">{formatTime(visit.dateTime)} · {visit.type}</p>
              <p className="mt-1">{doctor.name}</p>
              <p className="text-[#64748B]">{doctor.specialty} · {visit.branch}</p>
            </div>
          </div>
        </header>

        <aside className="mt-6 rounded-xl border border-rose-200 bg-rose-50 p-5">
          <h2 className="font-[family-name:var(--font-figtree)] text-sm font-semibold text-rose-900">
            Patient safety — always visible
          </h2>
          <div className="mt-4 grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
            <div>
              <p className="text-xs font-medium uppercase text-rose-700">Allergies</p>
              <ul className="mt-1 text-sm">
                {safety.allergies.map((a) => (
                  <li key={a.substance}>
                    <strong>{a.substance}</strong> — {a.reaction}
                  </li>
                ))}
              </ul>
            </div>
            <div>
              <p className="text-xs font-medium uppercase text-[#64748B]">Home medications</p>
              <ul className="mt-1 list-disc pl-4 text-sm">
                {safety.currentMedications.map((m) => (
                  <li key={m}>{m}</li>
                ))}
              </ul>
            </div>
            <div>
              <p className="text-xs font-medium uppercase text-[#64748B]">Chronic conditions</p>
              <p className="mt-1 text-sm">{safety.chronicConditions.join(", ")}</p>
            </div>
            <div>
              <p className="text-xs font-medium uppercase text-[#64748B]">Last vitals</p>
              <ul className="mt-1 text-sm">
                {safety.lastVitals.map((v) => (
                  <li key={v.type}>
                    {v.type}: {v.value} {v.unit}
                  </li>
                ))}
              </ul>
            </div>
          </div>
        </aside>

        <main className="mt-6 grid gap-6 lg:grid-cols-12">
          <section className="rounded-xl border border-[#E2E8F0] bg-white shadow-sm lg:col-span-8">
            <div className="border-b border-[#E2E8F0] px-5 py-4">
              <h2 className="font-[family-name:var(--font-figtree)] font-semibold">
                Clinical note
              </h2>
            </div>
            <div className="space-y-6 p-5">
              {(
                [
                  ["Complaint", note.complaint],
                  ["History", note.history],
                  ["Examination", note.examination],
                  ["Diagnosis", note.diagnosis],
                  ["Plan", note.plan],
                ] as const
              ).map(([label, text]) => (
                <div key={label}>
                  <h3 className="text-xs font-semibold uppercase tracking-wide text-[#0891B2]">
                    {label}
                  </h3>
                  <p className="mt-2 text-sm leading-relaxed">{text}</p>
                </div>
              ))}
            </div>
          </section>

          <div className="flex flex-col gap-6 lg:col-span-4">
            <section className="rounded-xl border border-[#E2E8F0] bg-white p-5 shadow-sm">
              <h2 className="font-[family-name:var(--font-figtree)] font-semibold">Vitals</h2>
              {bmi && (
                <p className="mt-2 text-sm text-[#059669]">
                  BMI (derived): <strong>{bmi}</strong>
                </p>
              )}
              <ul className="mt-3 space-y-2 text-sm">
                {vitals.map((v) => (
                  <li key={v.type} className="flex justify-between border-b border-[#F1F5F9] pb-2">
                    <span className="text-[#64748B]">{v.type}</span>
                    <span className="font-medium tabular-nums">
                      {v.value} {v.unit}
                    </span>
                  </li>
                ))}
              </ul>
            </section>

            <section className="rounded-xl border border-[#E2E8F0] bg-white p-5 shadow-sm">
              <h2 className="font-[family-name:var(--font-figtree)] font-semibold">Treatments</h2>
              <ul className="mt-3 space-y-3 text-sm">
                {treatments.map((t) => (
                  <li key={t.id} className="rounded-lg bg-[#F0FDFA] p-3 ring-1 ring-[#0891B2]/10">
                    <p className="font-semibold">{t.medication}</p>
                    <p className="text-[#64748B]">
                      {t.dose} · {t.frequency} · {t.duration}
                    </p>
                  </li>
                ))}
              </ul>
            </section>

            <section className="rounded-xl border border-[#E2E8F0] bg-white p-5 shadow-sm">
              <h2 className="font-[family-name:var(--font-figtree)] font-semibold">
                Investigations
              </h2>
              <ul className="mt-3 space-y-2 text-sm">
                {investigations.map((i) => (
                  <li key={i.id}>
                    <p className="font-medium">{i.name}</p>
                    {i.result && <p className="text-[#059669]">Result: {i.result}</p>}
                  </li>
                ))}
              </ul>
            </section>

            <section className="rounded-xl border border-[#E2E8F0] bg-white p-5 shadow-sm">
              <h2 className="font-[family-name:var(--font-figtree)] font-semibold">Attachments</h2>
              <ul className="mt-3 space-y-2 text-sm text-[#0891B2]">
                {attachments.map((a) => (
                  <li key={a.id}>
                    {a.name}
                    <span className="ml-1 text-[#64748B]">({a.sizeLabel})</span>
                  </li>
                ))}
              </ul>
            </section>
          </div>
        </main>
      </div>
    </div>
  );
}
