import { notFound } from "next/navigation";
import { clinicSummary } from "@/lib/mock-data";
import { getTheme, themes } from "@/themes/registry";

interface ThemePageProps {
  params: Promise<{ slug: string }>;
}

export function generateStaticParams() {
  return themes.map((theme) => ({ slug: theme.slug }));
}

export async function generateMetadata({ params }: ThemePageProps) {
  const { slug } = await params;
  const theme = getTheme(slug);
  if (!theme) return { title: "Theme not found" };
  return {
    title: `${theme.name} · Clinic summary`,
    description: theme.tagline,
  };
}

export default async function ThemePage({ params }: ThemePageProps) {
  const { slug } = await params;
  const theme = getTheme(slug);
  if (!theme) notFound();

  const ThemeView = theme.component;
  return <ThemeView summary={clinicSummary} />;
}
