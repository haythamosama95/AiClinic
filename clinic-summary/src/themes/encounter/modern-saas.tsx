"use client";

import { useState } from "react";
import type { EncounterWorkspace } from "@/lib/encounter-types";
import { formatDateLong, formatTime } from "@/lib/format";
import { visitStatusLabels, deriveBmi, findVital } from "@/lib/encounter-labels";
import { ThemeChrome } from "@/components/ThemeChrome";

const phases = [
  { id: "context", label: "Context" },
  { id: "subjective", label: "Subjective" },
  { id: "objective", label: "Objective" },
  { id: "assessment", label: "Assessment" },
  { id: "plan", label: "Plan" },
] as const;

type PhaseId = (typeof phases)[number]["id"];

export function EncounterModernSaasTheme({ encounter }: { encounter: EncounterWorkspace }) {
  const [active, setActive] = useState<PhaseId>("context");
  const { visit, patient, doctor, safety, note, vitals, treatments, investigations, attachments } =
    encounter;

  const weight = findVital(vitals, "Weight");
  const height = findVital(vitals, "Height");
  const bmi =
    weight && height ? deriveBmi(parseFloat(weight), parseFloat(height)) : null;

  return (
    <div className="min-h-screen bg-canvas font-sans text-ink">
      <div className="mx-auto max-w-7xl px-4 py-6 sm:px-6 lg:px-8">
        <ThemeChrome themeName="Modern SaaS · Encounter" className="mb-4 text-muted" />

        <header className="rounded-2xl border border-border bg-surface p-6 shadow-panel">
          <div className="flex flex-wrap justify-between gap-4">
            <div>
              <span className="inline-flex rounded-full bg-brand-soft px-2.5 py-0.5 text-xs font-medium text-brand ring-1 ring-brand/20">
                {visitStatusLabels[visit.status]}
              </span>
              <h1 className="mt-2 font-display text-2xl font-semibold">{patient.name}</h1>
              <p className="text-sm text-muted">
                {patient.age}y · {patient.sex} · {patient.mrn}
              </p>
            </div>
            <div className="text-right text-sm">
              <p className="font-medium">{formatDateLong(visit.dateTime)}</p>
              <p className="text-muted">
                {formatTime(visit.dateTime)} · {visit.type}
              </p>
              <p className="mt-1">{doctor.name}</p>
              <p className="text-muted">{doctor.specialty}</p>
            </div>
          </div>
        </header>

        <aside className="mt-6 rounded-2xl border border-rose-200 bg-rose-50/80 p-4">
          <h2 className="text-xs font-semibold uppercase tracking-wide text-rose-800">
            Safety surface
          </h2>
          <div className="mt-3 flex flex-wrap gap-x-6 gap-y-2 text-sm">
            <p>
              <span className="font-medium text-rose-900">Allergies:</span>{" "}
              {safety.allergies.map((a) => a.substance).join(", ")}
            </p>
            <p>
              <span className="font-medium text-rose-900">Home meds:</span>{" "}
              {safety.currentMedications.length} active
            </p>
            <p>
              <span className="font-medium text-rose-900">Conditions:</span>{" "}
              {safety.chronicConditions.join(", ")}
            </p>
          </div>
        </aside>

        <div className="mt-6 grid gap-6 lg:grid-cols-12">
          <nav className="lg:col-span-3">
            <ul className="flex gap-2 overflow-x-auto lg:flex-col lg:overflow-visible">
              {phases.map((p) => (
                <li key={p.id}>
                  <button
                    type="button"
                    onClick={() => setActive(p.id)}
                    className={`w-full rounded-xl px-4 py-3 text-left text-sm font-medium transition ${active === p.id
                        ? "bg-brand text-white shadow-sm"
                        : "bg-surface text-muted ring-1 ring-border hover:text-ink"
                      }`}
                  >
                    {p.label}
                  </button>
                </li>
              ))}
            </ul>
          </nav>

          <main className="rounded-2xl border border-border bg-surface p-6 shadow-panel lg:col-span-9">
            {active === "context" && (
              <div className="space-y-4 text-sm">
                <p>
                  <span className="font-medium">Visit:</span> {visit.id} · {visit.branch}
                </p>
                <p>
                  <span className="font-medium">Patient phone:</span> {patient.phone ?? "—"}
                </p>
                <p>
                  <span className="font-medium">Last vitals on file:</span>{" "}
                  {safety.lastVitals.map((v) => `${v.type} ${v.value}${v.unit}`).join("; ")}
                </p>
              </div>
            )}
            {active === "subjective" && (
              <div className="space-y-6">
                <div>
                  <h3 className="text-xs font-semibold uppercase text-brand">Complaint</h3>
                  <p className="mt-2 text-sm leading-relaxed">{note.complaint}</p>
                </div>
                <div>
                  <h3 className="text-xs font-semibold uppercase text-brand">History</h3>
                  <p className="mt-2 text-sm leading-relaxed">{note.history}</p>
                </div>
              </div>
            )}
            {active === "objective" && (
              <div className="space-y-6">
                <div>
                  <h3 className="text-xs font-semibold uppercase text-brand">Examination</h3>
                  <p className="mt-2 text-sm leading-relaxed">{note.examination}</p>
                </div>
                <div>
                  <h3 className="text-xs font-semibold uppercase text-brand">Vitals</h3>
                  {bmi && (
                    <p className="mt-2 text-sm text-accent">
                      BMI (derived): <strong>{bmi}</strong>
                    </p>
                  )}
                  <ul className="mt-3 grid gap-2 sm:grid-cols-2">
                    {vitals.map((v) => (
                      <li
                        key={v.type}
                        className="flex justify-between rounded-lg bg-canvas px-3 py-2 text-sm"
                      >
                        <span className="text-muted">{v.type}</span>
                        <span className="font-medium tabular-nums">
                          {v.value} {v.unit}
                        </span>
                      </li>
                    ))}
                  </ul>
                </div>
              </div>
            )}
            {active === "assessment" && (
              <div>
                <h3 className="text-xs font-semibold uppercase text-brand">Diagnosis</h3>
                <p className="mt-2 text-sm leading-relaxed">{note.diagnosis}</p>
              </div>
            )}
            {active === "plan" && (
              <div className="space-y-6">
                <div>
                  <h3 className="text-xs font-semibold uppercase text-brand">Plan</h3>
                  <p className="mt-2 text-sm leading-relaxed">{note.plan}</p>
                </div>
                <div>
                  <h3 className="text-xs font-semibold uppercase text-brand">Treatments</h3>
                  <ul className="mt-3 space-y-2 text-sm">
                    {treatments.map((t) => (
                      <li key={t.id} className="rounded-lg border border-border p-3">
                        <p className="font-medium">{t.medication}</p>
                        <p className="text-muted">
                          {t.dose} · {t.frequency} · {t.duration}
                        </p>
                      </li>
                    ))}
                  </ul>
                </div>
                <div>
                  <h3 className="text-xs font-semibold uppercase text-brand">Investigations</h3>
                  <ul className="mt-3 space-y-2 text-sm">
                    {investigations.map((i) => (
                      <li key={i.id}>
                        {i.name}
                        {i.result && <span className="text-accent"> — {i.result}</span>}
                      </li>
                    ))}
                  </ul>
                </div>
                <div>
                  <h3 className="text-xs font-semibold uppercase text-brand">Attachments</h3>
                  <ul className="mt-3 space-y-1 text-sm text-brand">
                    {attachments.map((a) => (
                      <li key={a.id}>{a.name}</li>
                    ))}
                  </ul>
                </div>
              </div>
            )}
          </main>
        </div>
      </div>
    </div>
  );
}
