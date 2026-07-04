import type { ComponentType } from "react";
import type { ClinicSummary } from "@/lib/types";
import { AiNativeTheme } from "./ai-native";
import { AppleInspiredTheme } from "./apple-inspired";
import { BentoTheme } from "./bento";
import { DataVisualizationTheme } from "./data-visualization";
import { FuturisticMinimalTheme } from "./futuristic-minimal";
import { GlassmorphismTheme } from "./glassmorphism";
import { HealthcareProfessionalTheme } from "./healthcare-professional";
import { Material3Theme } from "./material-3";
import { MinimalistTheme } from "./minimalist";
import { ModernSaasTheme } from "./modern-saas";

export interface ThemeEntry {
  slug: string;
  name: string;
  tagline: string;
  accent: string;
  component: ComponentType<{ summary: ClinicSummary }>;
}

export const themes: ThemeEntry[] = [
  {
    slug: "minimalist",
    name: "Minimalist",
    tagline: "Whitespace, hairlines, one accent",
    accent: "#111111",
    component: MinimalistTheme,
  },
  {
    slug: "ai-native",
    name: "AI Native",
    tagline: "Dark mesh, monospace telemetry",
    accent: "#8B5CF6",
    component: AiNativeTheme,
  },
  {
    slug: "glassmorphism",
    name: "Glassmorphism",
    tagline: "Frosted layers over vivid depth",
    accent: "#38BDF8",
    component: GlassmorphismTheme,
  },
  {
    slug: "bento",
    name: "Bento",
    tagline: "Modular cells, playful grid",
    accent: "#F97316",
    component: BentoTheme,
  },
  {
    slug: "apple-inspired",
    name: "Apple-inspired",
    tagline: "Calm hierarchy, tactile depth",
    accent: "#007AFF",
    component: AppleInspiredTheme,
  },
  {
    slug: "material-3",
    name: "Material 3",
    tagline: "Tonal surfaces, expressive chips",
    accent: "#6750A4",
    component: Material3Theme,
  },
  {
    slug: "healthcare-professional",
    name: "Healthcare Professional",
    tagline: "Clinical trust, calm cyan",
    accent: "#0891B2",
    component: HealthcareProfessionalTheme,
  },
  {
    slug: "data-visualization",
    name: "Data Visualization",
    tagline: "Metrics as the interface",
    accent: "#22C55E",
    component: DataVisualizationTheme,
  },
  {
    slug: "futuristic-minimal",
    name: "Futuristic Minimal",
    tagline: "Neon signal on void black",
    accent: "#00FFD1",
    component: FuturisticMinimalTheme,
  },
  {
    slug: "modern-saas",
    name: "Modern SaaS",
    tagline: "Operational clarity at scale",
    accent: "#0891B2",
    component: ModernSaasTheme,
  },
];

export function getTheme(slug: string): ThemeEntry | undefined {
  return themes.find((t) => t.slug === slug);
}
