import fs from "node:fs/promises";
import path from "node:path";

export type LocalSupabaseEnv = {
  supabaseUrl: string;
  anonKey: string;
};

const DEFAULT_SUPABASE_URL = "http://127.0.0.1:54321";

const DEFAULT_ANON_KEY =
  "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyAgCiAgICAicm9sZSI6ICJhbm9uIiwKICAgICJpc3MiOiAic3VwYWJhc2UtZGVtbyIsCiAgICAiaWF0IjogMTY0MTc2OTIwMCwKICAgICJleHAiOiAxNzk5NTM1NjAwCn0.dc_X5iR_VP_qT0zsiyj_I_OZ2BBNWN8Bu4GE";

export async function loadLocalSupabaseEnv(
  repoRoot: string,
): Promise<LocalSupabaseEnv> {
  const candidates = [
    path.join(repoRoot, "backend/local/.env"),
    path.join(repoRoot, "backend/local/.env.example"),
  ];

  const values: Record<string, string> = {};
  for (const filePath of candidates) {
    try {
      const raw = await fs.readFile(filePath, "utf8");
      Object.assign(values, parseDotEnv(raw));
    } catch {
      // try next candidate
    }
  }

  return {
    supabaseUrl:
      values.SUPABASE_PUBLIC_URL?.trim() ||
      values.SUPABASE_URL?.trim() ||
      DEFAULT_SUPABASE_URL,
    anonKey: values.SUPABASE_ANON_KEY?.trim() || DEFAULT_ANON_KEY,
  };
}

function parseDotEnv(raw: string): Record<string, string> {
  const out: Record<string, string> = {};
  for (const line of raw.split("\n")) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith("#")) {
      continue;
    }
    const eq = trimmed.indexOf("=");
    if (eq <= 0) {
      continue;
    }
    const key = trimmed.slice(0, eq).trim();
    let value = trimmed.slice(eq + 1).trim();
    if (
      (value.startsWith('"') && value.endsWith('"')) ||
      (value.startsWith("'") && value.endsWith("'"))
    ) {
      value = value.slice(1, -1);
    }
    out[key] = value;
  }
  return out;
}
