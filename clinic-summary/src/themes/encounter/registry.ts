import type { ComponentType } from "react";
import type { EncounterWorkspace } from "@/lib/encounter-types";
import { EncounterAiNativeTheme } from "./ai-native";
import { EncounterAppleInspiredTheme } from "./apple-inspired";
import { EncounterBentoTheme } from "./bento";
import { EncounterDataVisualizationTheme } from "./data-visualization";
import { EncounterFuturisticMinimalTheme } from "./futuristic-minimal";
import { EncounterGlassmorphismTheme } from "./glassmorphism";
import { EncounterHealthcareProfessionalTheme } from "./healthcare-professional";
import { EncounterMaterial3Theme } from "./material-3";
import { EncounterMinimalistTheme } from "./minimalist";
import { EncounterModernSaasTheme } from "./modern-saas";

export interface EncounterThemeEntry {
  slug: string;
  name: string;
  tagline: string;
  accent: string;
  component: ComponentType<{ encounter: EncounterWorkspace }>;
}

export const encounterThemes: EncounterThemeEntry[] = [
  {
    slug: "minimalist",
    name: "Minimalist",
    tagline: "Clinical prose, zero noise",
    accent: "#111111",
    component: EncounterMinimalistTheme,
  },
  {
    slug: "ai-native",
    name: "AI Native",
    tagline: "Structured record as telemetry",
    accent: "#8B5CF6",
    component: EncounterAiNativeTheme,
  },
  {
    slug: "glassmorphism",
    name: "Glassmorphism",
    tagline: "Layered record over depth",
    accent: "#38BDF8",
    component: EncounterGlassmorphismTheme,
  },
  {
    slug: "bento",
    name: "Bento",
    tagline: "Record blocks in a grid",
    accent: "#F97316",
    component: EncounterBentoTheme,
  },
  {
    slug: "apple-inspired",
    name: "Apple-inspired",
    tagline: "Calm chart, grouped sections",
    accent: "#007AFF",
    component: EncounterAppleInspiredTheme,
  },
  {
    slug: "material-3",
    name: "Material 3",
    tagline: "Tonal SOAP containers",
    accent: "#6750A4",
    component: EncounterMaterial3Theme,
  },
  {
    slug: "healthcare-professional",
    name: "Healthcare Professional",
    tagline: "Safety-first clinical workspace",
    accent: "#0891B2",
    component: EncounterHealthcareProfessionalTheme,
  },
  {
    slug: "data-visualization",
    name: "Data Visualization",
    tagline: "Vitals and labs as charts",
    accent: "#22C55E",
    component: EncounterDataVisualizationTheme,
  },
  {
    slug: "futuristic-minimal",
    name: "Futuristic Minimal",
    tagline: "Record on black glass",
    accent: "#00FFD1",
    component: EncounterFuturisticMinimalTheme,
  },
  {
    slug: "modern-saas",
    name: "Modern SaaS",
    tagline: "Phase-sequenced workspace",
    accent: "#0891B2",
    component: EncounterModernSaasTheme,
  },
];

export function getEncounterTheme(slug: string): EncounterThemeEntry | undefined {
  return encounterThemes.find((t) => t.slug === slug);
}
