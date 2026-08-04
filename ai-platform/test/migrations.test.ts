import { execFile } from "node:child_process";
import { readFile } from "node:fs/promises";
import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { promisify } from "node:util";
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import {
  generateRequestReference,
  type RequestReference,
} from "../src/reference";

const execFileAsync = promisify(execFile);

const ROOT = path.join(path.dirname(fileURLToPath(import.meta.url)), "..");
const CONFIG_PATH = path.join(ROOT, "wrangler.toml");
const SCHEMA_SNAPSHOT_PATH = path.join(ROOT, "schema.snap.sql");
const D1_DATABASE = "ai-platform-development";
const WRANGLER_ENV = "development";
const MIGRATIONS_TABLE = "d1_migrations";

/** §7.3 platform entities — every table the forward-only migration must create. */
export const PLATFORM_ENTITIES = [
  "installation",
  "installation_key",
  "entitlement",
  "capability_grant",
  "routing_policy",
  "ai_request",
  "ai_attempt",
  "usage_event",
  "usage_rollup",
  "platform_counter",
  "control_audit",
] as const;

export type PlatformEntity = (typeof PLATFORM_ENTITIES)[number];

const REQUEST_REFERENCE_PATTERN =
  /^[0-9A-HJKMNP-TV-Z]{4}-[0-9A-HJKMNP-TV-Z]{4}$/;

type SqlRow = Record<string, unknown>;

type WranglerExecuteResponse = Array<{
  results: SqlRow[];
  success: boolean;
}>;

let persistDir: string;

function wranglerArgs(command: string[]): string[] {
  return [
    "wrangler",
    ...command,
    "--config",
    CONFIG_PATH,
    "--env",
    WRANGLER_ENV,
    "--persist-to",
    persistDir,
  ];
}

async function runWrangler(command: string[]): Promise<{
  stdout: string;
  stderr: string;
}> {
  return execFileAsync("npx", wranglerArgs(command), {
    cwd: ROOT,
    env: { ...process.env, CI: "true" },
  });
}

/** Apply forward-only D1 migrations to a fresh local database (Clarification Q1). */
export async function applyMigrations(): Promise<{
  stdout: string;
  stderr: string;
}> {
  return runWrangler(["d1", "migrations", "apply", D1_DATABASE, "--local"]);
}

async function query<T extends SqlRow = SqlRow>(
  sql: string,
): Promise<T[]> {
  const { stdout } = await runWrangler([
    "d1",
    "execute",
    D1_DATABASE,
    "--local",
    "--json",
    "--command",
    sql,
  ]);

  const parsed = JSON.parse(stdout) as WranglerExecuteResponse;
  const batch = parsed.at(-1);
  if (!batch?.success) {
    throw new Error(`D1 query failed: ${sql}`);
  }
  return batch.results as T[];
}

async function tableNames(): Promise<Set<string>> {
  const rows = await query<{ name: string }>(
    "SELECT name FROM sqlite_master WHERE type = 'table'",
  );
  return new Set(rows.map((row) => row.name));
}

async function dumpCreateTableDdl(): Promise<string> {
  const rows = await query<{ name: string; sql: string }>(
    `SELECT name, sql
     FROM sqlite_master
     WHERE type = 'table'
       AND name NOT LIKE 'sqlite_%'
       AND name NOT LIKE 'd1_%'
       AND name NOT LIKE '_cf_%'
     ORDER BY name`,
  );

  return rows.map((row) => row.sql).join(";\n\n") + ";\n";
}

async function appliedMigrationCount(): Promise<number> {
  const tables = await tableNames();
  if (!tables.has(MIGRATIONS_TABLE)) {
    return 0;
  }

  const rows = await query<{ count: number }>(
    `SELECT COUNT(*) AS count FROM ${MIGRATIONS_TABLE}`,
  );
  return Number(rows[0]?.count ?? 0);
}

function assertRequestReferenceFormat(value: string): asserts value is RequestReference {
  expect(value).toMatch(REQUEST_REFERENCE_PATTERN);
  expect(value).toBe(value.toUpperCase());
}

beforeEach(async () => {
  persistDir = await mkdtemp(path.join(tmpdir(), "a5-d1-"));
});

afterEach(async () => {
  if (persistDir) {
    await rm(persistDir, { recursive: true, force: true });
  }
});

describe("T-A5-11 migrations_apply_cleanly_to_empty_db", () => {
  it("applies migrations to an empty D1 and creates every §7.3 entity", async () => {
    const { stderr } = await applyMigrations();
    expect(stderr).not.toMatch(/error/i);

    const tables = await tableNames();
    for (const entity of PLATFORM_ENTITIES) {
      expect(tables.has(entity)).toBe(true);
    }
  });
});

describe("T-A5-12 migrations_rerun_is_noop", () => {
  it("re-applying migrations is a no-op tracked by Wrangler's applied-migrations table", async () => {
    await applyMigrations();
    const countAfterFirstApply = await appliedMigrationCount();
    expect(countAfterFirstApply).toBeGreaterThan(0);

    const { stdout: secondStdout } = await applyMigrations();
    const countAfterSecondApply = await appliedMigrationCount();

    expect(countAfterSecondApply).toBe(countAfterFirstApply);
    expect(secondStdout).toMatch(/no migrations to apply|already applied/i);
  });
});

describe("T-A5-13 schema_snapshot_matches", () => {
  it("post-migration CREATE TABLE DDL equals ai-platform/schema.snap.sql", async () => {
    await applyMigrations();

    const actualDdl = await dumpCreateTableDdl();
    const expectedDdl = await readFile(SCHEMA_SNAPSHOT_PATH, "utf8");

    expect(actualDdl.trim()).toBe(expectedDdl.trim());
  });
});

describe("T-A5-14 entity_presence", () => {
  for (const entity of PLATFORM_ENTITIES) {
    it(`entity_presence_${entity}`, async () => {
      await applyMigrations();

      const tables = await tableNames();
      expect(tables.has(entity)).toBe(true);
    });
  }
});

describe("T-A5-15 request_reference_index_exists_and_unique", () => {
  it("ai_request request_reference index exists, is unique, and stores the A2 format", async () => {
    await applyMigrations();

    const indexes = await query<{ name: string; sql: string }>(
      `SELECT name, sql
       FROM sqlite_master
       WHERE type = 'index'
         AND tbl_name = 'ai_request'
         AND sql IS NOT NULL`,
    );

    const requestReferenceIndexes = indexes.filter((index) =>
      /request_reference/i.test(index.sql),
    );
    expect(requestReferenceIndexes.length).toBeGreaterThan(0);

    for (const index of requestReferenceIndexes) {
      expect(index.sql).toMatch(/UNIQUE/i);
    }

    const columns = await query<{ name: string; type: string }>(
      "PRAGMA table_info(ai_request)",
    );
    const requestReferenceColumn = columns.find(
      (column) => column.name === "request_reference",
    );
    expect(requestReferenceColumn).toBeDefined();

    const sample = generateRequestReference();
    assertRequestReferenceFormat(sample);

    await query(
      `INSERT INTO installation (
        installation_id, org_id, display_name, status, region, enrolled_at
      ) VALUES (
        'inst-a5-15', 'org-a5-15', 'A5 T15 Clinic', 'active', 'eeur',
        '2026-08-01T00:00:00.000Z'
      )`,
    );

    await query(
      `INSERT INTO ai_request (
        request_id, request_reference, installation_id, actor_id, branch_id,
        capability_id, capability_version, prompt_artifact_hash, idempotency_key,
        state, created_at, updated_at, completed_at, terminal_error_code,
        trace_id, payload_pointer, conversation_id, turn_ordinal
      ) VALUES (
        'req-a5-15', '${sample}', 'inst-a5-15', 'actor-a5-15', 'branch-a5-15',
        'clinic.visit_summary', '1.0.0', 'prompt/a5-15@v1', 'idem-a5-15',
        'Accepted', '2026-08-01T12:00:00.000Z', '2026-08-01T12:00:00.000Z', NULL, NULL,
        '01A5T15TRACEREFERENCE0001', NULL, NULL, NULL
      )`,
    );

    const stored = await query<{ request_reference: string }>(
      "SELECT request_reference FROM ai_request WHERE request_id = 'req-a5-15'",
    );
    expect(stored).toHaveLength(1);
    expect(stored[0]?.request_reference).toBe(sample);
    assertRequestReferenceFormat(stored[0]!.request_reference);
  });
});

describe("T-A5-15b idempotency_key_not_uniquely_indexed_on_d1", () => {
  it("has no unique index on (installation_id, idempotency_key) — C3 Quota DO owns idempotency (§4.3.3)", async () => {
    await applyMigrations();

    const indexes = await query<{ name: string; sql: string }>(
      `SELECT name, sql
       FROM sqlite_master
       WHERE type = 'index'
         AND tbl_name = 'ai_request'
         AND sql IS NOT NULL`,
    );

    const idempotencyUniqueIndexes = indexes.filter(
      (index) =>
        /idempotency/i.test(index.sql) && /UNIQUE/i.test(index.sql),
    );
    expect(idempotencyUniqueIndexes).toHaveLength(0);
  });
});

describe("T-A5-16 conversation_id_and_turn_ordinal_nullable", () => {
  it("ai_request conversation_id and turn_ordinal columns are nullable", async () => {
    await applyMigrations();

    const columns = await query<{
      name: string;
      notnull: number;
    }>("PRAGMA table_info(ai_request)");

    const conversationId = columns.find(
      (column) => column.name === "conversation_id",
    );
    const turnOrdinal = columns.find(
      (column) => column.name === "turn_ordinal",
    );

    expect(conversationId).toBeDefined();
    expect(conversationId?.notnull).toBe(0);

    expect(turnOrdinal).toBeDefined();
    expect(turnOrdinal?.notnull).toBe(0);
  });
});
