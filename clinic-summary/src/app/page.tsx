import Link from "next/link";
import { encounterThemes } from "@/themes/encounter/registry";
import { themes } from "@/themes/registry";

function ThemeGrid({
  items,
  basePath,
}: {
  items: { slug: string; name: string; tagline: string; accent: string }[];
  basePath: string;
}) {
  return (
    <ul className="grid gap-5 sm:grid-cols-2 lg:grid-cols-3">
      {items.map((theme, index) => (
        <li key={theme.slug}>
          <Link
            href={`${basePath}/${theme.slug}`}
            className="group block overflow-hidden rounded-2xl border border-slate-800 bg-slate-900/60 transition hover:border-slate-600 hover:bg-slate-900"
          >
            <div
              className="flex h-28 items-end p-5"
              style={{
                background: `linear-gradient(135deg, ${theme.accent}22 0%, transparent 60%), linear-gradient(180deg, #1e293b 0%, #0f172a 100%)`,
              }}
            >
              <span
                className="h-3 w-3 rounded-full ring-4 ring-white/10"
                style={{ backgroundColor: theme.accent }}
                aria-hidden
              />
            </div>
            <div className="border-t border-slate-800 p-5">
              <div className="flex items-baseline gap-2">
                <span className="font-mono text-xs text-slate-600">
                  {String(index + 1).padStart(2, "0")}
                </span>
                <h2 className="text-lg font-semibold group-hover:text-cyan-300">
                  {theme.name}
                </h2>
              </div>
              <p className="mt-1 text-sm text-slate-500">{theme.tagline}</p>
              <p className="mt-3 text-xs font-medium text-cyan-500/80 opacity-0 transition group-hover:opacity-100">
                View theme →
              </p>
            </div>
          </Link>
        </li>
      ))}
    </ul>
  );
}

export default function GalleryPage() {
  return (
    <div className="min-h-screen bg-[#0F172A] font-[family-name:var(--font-outfit)] text-white">
      <div
        className="pointer-events-none fixed inset-0 bg-[radial-gradient(ellipse_at_top,_rgba(8,145,178,0.15),_transparent_50%)]"
        aria-hidden
      />

      <div className="relative mx-auto max-w-6xl px-4 py-16 sm:px-6">
        <header className="mb-16 text-center">
          <p className="text-xs font-semibold uppercase tracking-[0.2em] text-cyan-400">
            AiClinic design lab
          </p>
          <h1 className="mt-3 text-4xl font-semibold tracking-tight sm:text-5xl">
            Clinical UI themes
          </h1>
          <p className="mx-auto mt-4 max-w-xl text-slate-400">
            Two pages, ten visual identities each. Pick a page below, then explore how the
            same data reads in every theme.
          </p>
        </header>

        <section className="mb-20">
          <div className="mb-8 flex flex-wrap items-end justify-between gap-4 border-b border-slate-800 pb-4">
            <div>
              <h2 className="text-2xl font-semibold">Clinic summary</h2>
              <p className="mt-1 text-sm text-slate-500">
                Appointments, doctors on shift, waiting room
              </p>
            </div>
            <span className="rounded-full bg-slate-800 px-3 py-1 text-xs text-slate-400">
              10 themes
            </span>
          </div>
          <ThemeGrid items={themes} basePath="/themes" />
        </section>

        <section>
          <div className="mb-8 flex flex-wrap items-end justify-between gap-4 border-b border-slate-800 pb-4">
            <div>
              <h2 className="text-2xl font-semibold">Encounter workspace</h2>
              <p className="mt-1 text-sm text-slate-500">
                Patient & doctor context, clinical note, vitals, meds, investigations,
                attachments
              </p>
            </div>
            <span className="rounded-full bg-slate-800 px-3 py-1 text-xs text-slate-400">
              10 themes
            </span>
          </div>
          <ThemeGrid items={encounterThemes} basePath="/encounter" />
        </section>
      </div>
    </div>
  );
}
