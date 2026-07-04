import type { EncounterWorkspace } from "@/lib/encounter-types";
import { formatDateLong, formatTime } from "@/lib/format";
import { visitStatusLabels } from "@/lib/encounter-labels";
import { ThemeChrome } from "@/components/ThemeChrome";

function Section({
  title,
  children,
}: {
  title: string;
  children: React.ReactNode;
}) {
  return (
    <section className="overflow-hidden rounded-3xl bg-white shadow-[0_2px_24px_rgba(0,0,0,0.06)]">
      <div className="border-b border-black/[0.06] px-6 py-4">
        <h2 className="text-xl font-semibold">{title}</h2>
      </div>
      <div className="px-6 py-5">{children}</div>
    </section>
  );
}

export function EncounterAppleInspiredTheme({ encounter }: { encounter: EncounterWorkspace }) {
  const { visit, patient, doctor, safety, note, vitals, treatments, investigations, attachments } =
    encounter;

  return (
    <div className="min-h-screen bg-[#F5F5F7] font-[family-name:var(--font-system)] text-[#1D1D1F]">
      <div className="mx-auto max-w-3xl px-5 py-10">
        <ThemeChrome themeName="Apple-inspired · Encounter" className="mb-10 text-[#86868B]" />

        <header className="mb-10 text-center">
          <p className="text-sm text-[#86868B]">{formatDateLong(visit.dateTime)}</p>
          <h1 className="mt-2 text-4xl font-semibold tracking-tight">{patient.name}</h1>
          <p className="mt-1 text-[#86868B]">
            {patient.age} years · {patient.sex} · {patient.mrn}
          </p>
          <div className="mx-auto mt-6 inline-flex flex-wrap justify-center gap-2 rounded-2xl bg-white/80 px-4 py-2 shadow-sm ring-1 ring-black/[0.04]">
            <span className="rounded-full bg-[#007AFF]/10 px-3 py-1 text-sm font-medium text-[#007AFF]">
              {visitStatusLabels[visit.status]}
            </span>
            <span className="rounded-full bg-[#F5F5F7] px-3 py-1 text-sm text-[#86868B]">
              {visit.type}
            </span>
            <span className="rounded-full bg-[#F5F5F7] px-3 py-1 text-sm text-[#86868B]">
              {doctor.name}
            </span>
            <span className="text-sm text-[#86868B]">{formatTime(visit.dateTime)}</span>
          </div>
        </header>

        <div className="mb-8 rounded-3xl border border-[#FF3B30]/20 bg-[#FF3B30]/5 p-5">
          <h2 className="text-sm font-semibold text-[#FF3B30]">Safety information</h2>
          <p className="mt-2 text-sm">
            <span className="font-medium">Allergies:</span>{" "}
            {safety.allergies.map((a) => `${a.substance} (${a.reaction})`).join("; ")}
          </p>
          <p className="mt-2 text-sm text-[#424245]">
            <span className="font-medium">Home meds:</span> {safety.currentMedications.join("; ")}
          </p>
        </div>

        <div className="space-y-8">
          <Section title="Clinical note">
            {(
              [
                ["Complaint", note.complaint],
                ["History", note.history],
                ["Examination", note.examination],
                ["Diagnosis", note.diagnosis],
                ["Plan", note.plan],
              ] as const
            ).map(([label, text]) => (
              <div key={label} className="mb-5 last:mb-0">
                <h3 className="text-xs font-semibold uppercase tracking-wide text-[#86868B]">
                  {label}
                </h3>
                <p className="mt-2 text-[17px] leading-relaxed">{text}</p>
              </div>
            ))}
          </Section>

          <Section title="Vitals">
            <div className="grid grid-cols-2 gap-3 sm:grid-cols-3">
              {vitals.map((v) => (
                <div key={v.type} className="rounded-2xl bg-[#F5F5F7] px-4 py-3 text-center">
                  <p className="text-2xl font-semibold tabular-nums">{v.value}</p>
                  <p className="text-xs text-[#86868B]">
                    {v.type} ({v.unit})
                  </p>
                </div>
              ))}
            </div>
          </Section>

          <Section title="Treatments">
            <ul className="divide-y divide-black/[0.06]">
              {treatments.map((t) => (
                <li key={t.id} className="py-3 first:pt-0">
                  <p className="font-semibold">{t.medication}</p>
                  <p className="text-sm text-[#86868B]">
                    {t.dose} · {t.frequency} · {t.duration}
                  </p>
                </li>
              ))}
            </ul>
          </Section>

          <Section title="Investigations & attachments">
            <h3 className="text-xs font-semibold uppercase text-[#86868B]">Labs & imaging</h3>
            <ul className="mt-2 space-y-2 text-sm">
              {investigations.map((i) => (
                <li key={i.id}>
                  {i.name}
                  {i.result && <span className="text-[#86868B]"> — {i.result}</span>}
                </li>
              ))}
            </ul>
            <h3 className="mt-6 text-xs font-semibold uppercase text-[#86868B]">Files</h3>
            <ul className="mt-2 space-y-2 text-sm text-[#007AFF]">
              {attachments.map((a) => (
                <li key={a.id}>{a.name}</li>
              ))}
            </ul>
          </Section>
        </div>
      </div>
    </div>
  );
}
