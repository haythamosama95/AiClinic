import type { EncounterWorkspace } from "@/lib/encounter-types";
import { formatDateLong, formatTime } from "@/lib/format";
import { visitStatusLabels } from "@/lib/encounter-labels";
import { ThemeChrome } from "@/components/ThemeChrome";

export function EncounterBentoTheme({ encounter }: { encounter: EncounterWorkspace }) {
  const { visit, patient, doctor, safety, note, vitals, treatments, investigations, attachments } =
    encounter;

  return (
    <div className="min-h-screen bg-[#F0EBE3] font-[family-name:var(--font-sora)] text-stone-900">
      <div className="mx-auto max-w-6xl px-4 py-8">
        <ThemeChrome themeName="Bento · Encounter" className="mb-6 text-stone-500" />

        <div className="grid auto-rows-min gap-4 sm:grid-cols-6 lg:grid-cols-12">
          <div className="rounded-3xl bg-stone-900 p-6 text-white sm:col-span-4 lg:col-span-5">
            <p className="text-sm text-stone-400">{visitStatusLabels[visit.status]}</p>
            <h1 className="mt-2 text-3xl font-bold">{patient.name}</h1>
            <p className="mt-1 text-stone-400">
              {patient.age}y · {patient.mrn}
            </p>
            <p className="mt-4 text-sm">{formatDateLong(visit.dateTime)}</p>
            <p className="text-sm text-stone-400">{visit.type}</p>
          </div>

          <div className="rounded-3xl bg-blue-500 p-6 text-white sm:col-span-2 lg:col-span-3">
            <p className="text-sm text-blue-100">Attending</p>
            <p className="mt-2 text-xl font-bold">{doctor.name}</p>
            <p className="text-sm text-blue-100">{doctor.specialty}</p>
            <p className="mt-2 text-xs">{formatTime(visit.dateTime)}</p>
          </div>

          <div className="rounded-3xl bg-rose-400 p-6 text-rose-950 sm:col-span-6 lg:col-span-4">
            <h2 className="font-bold">Allergies</h2>
            <ul className="mt-2 space-y-1 text-sm">
              {safety.allergies.map((a) => (
                <li key={a.substance}>
                  {a.substance} — {a.reaction}
                </li>
              ))}
            </ul>
          </div>

          <div className="rounded-3xl bg-white p-5 sm:col-span-3 lg:col-span-4">
            <h2 className="font-bold text-violet-700">Subjective</h2>
            <p className="mt-2 text-xs font-semibold uppercase text-stone-400">Complaint</p>
            <p className="mt-1 text-sm">{note.complaint}</p>
            <p className="mt-3 text-xs font-semibold uppercase text-stone-400">History</p>
            <p className="mt-1 text-sm">{note.history}</p>
          </div>

          <div className="rounded-3xl bg-emerald-100 p-5 sm:col-span-3 lg:col-span-4">
            <h2 className="font-bold text-emerald-900">Objective</h2>
            <p className="mt-2 text-sm">{note.examination}</p>
            <div className="mt-4 grid grid-cols-3 gap-2">
              {vitals.slice(0, 6).map((v) => (
                <div key={v.type} className="rounded-xl bg-white/80 p-2 text-center">
                  <p className="text-sm font-bold">{v.value}</p>
                  <p className="text-[9px] text-stone-500">{v.type}</p>
                </div>
              ))}
            </div>
          </div>

          <div className="rounded-3xl bg-amber-200 p-5 sm:col-span-6 lg:col-span-4">
            <h2 className="font-bold">Assessment</h2>
            <p className="mt-2 text-sm">{note.diagnosis}</p>
            <p className="mt-3 text-xs text-stone-600">
              {safety.chronicConditions.join(" · ")}
            </p>
          </div>

          <div className="rounded-3xl bg-orange-500 p-5 text-white lg:col-span-8">
            <h2 className="text-lg font-bold">Plan</h2>
            <p className="mt-2 text-sm text-orange-50">{note.plan}</p>
            <div className="mt-4 grid gap-3 sm:grid-cols-2">
              {treatments.map((t) => (
                <div key={t.id} className="rounded-2xl bg-white/20 p-3 text-sm">
                  <p className="font-semibold">{t.medication}</p>
                  <p className="text-orange-100">
                    {t.dose} · {t.frequency}
                  </p>
                </div>
              ))}
            </div>
          </div>

          <div className="rounded-3xl bg-sky-200 p-5 sm:col-span-3 lg:col-span-4">
            <h2 className="font-bold text-sky-900">Investigations</h2>
            <ul className="mt-3 space-y-2 text-sm">
              {investigations.map((i) => (
                <li key={i.id} className="rounded-xl bg-white/60 p-2">
                  {i.name}
                  {i.result && <span className="block text-xs text-sky-800">{i.result}</span>}
                </li>
              ))}
            </ul>
          </div>

          <div className="rounded-3xl bg-stone-300 p-5 sm:col-span-3 lg:col-span-4">
            <h2 className="font-bold">Attachments</h2>
            <ul className="mt-3 space-y-2 text-sm">
              {attachments.map((a) => (
                <li key={a.id} className="truncate rounded-lg bg-white/50 px-2 py-1">
                  {a.name}
                </li>
              ))}
            </ul>
          </div>
        </div>
      </div>
    </div>
  );
}
