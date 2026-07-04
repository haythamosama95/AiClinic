import { notFound } from "next/navigation";
import { encounterWorkspace } from "@/lib/encounter-mock-data";
import { encounterThemes, getEncounterTheme } from "@/themes/encounter/registry";

interface EncounterPageProps {
  params: Promise<{ slug: string }>;
}

export function generateStaticParams() {
  return encounterThemes.map((theme) => ({ slug: theme.slug }));
}

export async function generateMetadata({ params }: EncounterPageProps) {
  const { slug } = await params;
  const theme = getEncounterTheme(slug);
  if (!theme) return { title: "Theme not found" };
  return {
    title: `${theme.name} · Encounter workspace`,
    description: theme.tagline,
  };
}

export default async function EncounterThemePage({ params }: EncounterPageProps) {
  const { slug } = await params;
  const theme = getEncounterTheme(slug);
  if (!theme) notFound();

  const ThemeView = theme.component;
  return <ThemeView encounter={encounterWorkspace} />;
}
