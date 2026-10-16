const HARNESS_CLOCK_ROW_ID = "default";

export type ClockEnv = {
  DB?: D1Database;
  TEST_CLOCK?: string;
};

async function harnessClockMs(env: ClockEnv): Promise<number | null> {
  if (env.TEST_CLOCK !== "1" || env.DB === undefined) {
    return null;
  }
  let row: { now_iso: string } | null;
  try {
    row = await env.DB.prepare(
      "SELECT now_iso FROM harness_test_clock WHERE id = ?",
    )
      .bind(HARNESS_CLOCK_ROW_ID)
      .first<{ now_iso: string }>();
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    if (/no such table/i.test(message)) {
      return null;
    }
    throw error;
  }
  if (row?.now_iso === undefined || row.now_iso.length === 0) {
    return null;
  }
  const parsed = Date.parse(row.now_iso);
  return Number.isNaN(parsed) ? null : parsed;
}

export async function clockNowMs(env: ClockEnv): Promise<number> {
  const harnessMs = await harnessClockMs(env);
  return harnessMs ?? Date.now();
}

export async function clockNowIso(env: ClockEnv): Promise<string> {
  return new Date(await clockNowMs(env)).toISOString();
}

export async function clockNowSeconds(env: ClockEnv): Promise<number> {
  return Math.floor((await clockNowMs(env)) / 1000);
}
