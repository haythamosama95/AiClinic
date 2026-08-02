import { existsSync, readdirSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { env } from "cloudflare:test";
import { beforeAll, beforeEach, describe, expect, it } from "vitest";
import migrationSql from "../../migrations/20260731120000_platform_schema.sql?raw";
import { createBindingSpies, type BindingSpies } from "./binding-spies";
import {
  CONCURRENCY_FIXTURE,
  GUARD_P95_CEILING_MS,
  type LoadMeasurementReport,
  assertFiniteMeasurement,
  computeGuardP95,
} from "./measurement-report";
import { runLoadHappyPath } from "./happy-path";
import happyPathSource from "./happy-path.ts?raw";

declare module "cloudflare:test" {
  interface ProvidedEnv {
    DB: D1Database;
    R2: R2Bucket;
    DO: DurableObjectNamespace;
  }
}

const LOAD_ROOT = path.dirname(fileURLToPath(import.meta.url));
const AI_PLATFORM_ROOT = path.resolve(LOAD_ROOT, "..", "..");
const REPO_ROOT = path.resolve(AI_PLATFORM_ROOT, "..");
const FRONTEND_LIB = path.join(REPO_ROOT, "frontend", "lib");

async function applyPlatformSchema(db: D1Database, sql: string): Promise<void> {
  const statements = sql
    .replace(/--.*$/gm, "")
    .split(";")
    .map((statement) => statement.trim())
    .filter((statement) => statement.length > 0);

  for (const statement of statements) {
    await db.prepare(statement).run();
  }
}

async function clearLoadTables(): Promise<void> {
  await env.DB.batch([
    env.DB.prepare("DELETE FROM usage_event"),
    env.DB.prepare("DELETE FROM ai_attempt"),
    env.DB.prepare("DELETE FROM ai_request"),
    env.DB.prepare("DELETE FROM platform_counter"),
    env.DB.prepare("DELETE FROM entitlement"),
    env.DB.prepare("DELETE FROM installation"),
  ]);
}

function listFilesRecursive(dir: string): string[] {
  if (!existsSync(dir)) {
    return [];
  }
  const entries = readdirSync(dir, { withFileTypes: true });
  const files: string[] = [];
  for (const entry of entries) {
    const fullPath = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      files.push(...listFilesRecursive(fullPath));
    } else if (entry.isFile()) {
      files.push(fullPath);
    }
  }
  return files;
}

let lastReport: LoadMeasurementReport;
let lastSpies: BindingSpies;

async function exerciseLoad(): Promise<{ report: LoadMeasurementReport; spies: BindingSpies }> {
  const spies = createBindingSpies(env);
  const result = await runLoadHappyPath({
    db: spies.db,
    r2: spies.r2,
    do: spies.do,
    realDo: env.DO,
  });
  lastReport = result.report;
  lastSpies = spies;
  return { report: result.report, spies };
}

beforeAll(async () => {
  await applyPlatformSchema(env.DB, migrationSql);
});

beforeEach(async () => {
  await clearLoadTables();
});

describe("guard_p95_within_tens_of_ms_at_target_concurrency", () => {
  it("drives the full happy path at N=20 and asserts guard p95 is below 100 ms", async () => {
    const { report } = await exerciseLoad();
    expect(report.concurrency).toBe(CONCURRENCY_FIXTURE);
    expect(report.request_count).toBe(CONCURRENCY_FIXTURE);
    expect(report.guard_p95_ms).toBeLessThan(GUARD_P95_CEILING_MS);
    expect(computeGuardP95(report.guard_latencies_ms)).toBe(report.guard_p95_ms);
  });
});

describe("exactly_one_r2_class_a_per_request_under_load", () => {
  it("counts exactly one R2 Class A PutObject per request under load", async () => {
    const { report } = await exerciseLoad();
    expect(report.r2_class_a_ops_per_request).toBe(1);
    expect(lastSpies.r2.putCallCount()).toBe(CONCURRENCY_FIXTURE);
  });
});

describe("exactly_two_durable_object_requests_per_request_under_load", () => {
  it("counts exactly two Quota DO fetches per request — admission and credit", async () => {
    const { report } = await exerciseLoad();
    expect(report.durable_object_requests_per_request).toBe(2);
    expect(lastSpies.do.fetchCount()).toBe(CONCURRENCY_FIXTURE * 2);
  });
});

describe("d1_write_headroom_measured", () => {
  it("carries a finite d1_hot_path_writes_per_request with no invented ceiling", async () => {
    const { report } = await exerciseLoad();
    assertFiniteMeasurement(report.d1_hot_path_writes_per_request);
    expect(report.d1_hot_path_writes_per_request).toBeGreaterThan(0);
  });
});

describe("do_throughput_per_installation_measured", () => {
  it("carries a finite do_throughput_per_installation with no invented ceiling", async () => {
    const { report } = await exerciseLoad();
    assertFiniteMeasurement(report.do_throughput_per_installation);
    expect(report.do_throughput_per_installation).toBeGreaterThan(0);
  });
});

describe("no_second_r2_object_per_request", () => {
  it("proves no second R2 object is written per request under load", async () => {
    const { report } = await exerciseLoad();
    expect(report.r2_class_a_ops_per_request).toBe(1);
    expect(lastSpies.r2.putCallCount()).toBe(CONCURRENCY_FIXTURE);
    expect(lastSpies.r2.putCallCount()).toBeLessThan(CONCURRENCY_FIXTURE * 2);
  });
});

describe("no_second_quota_do_round_trip_beyond_two", () => {
  it("proves no third Quota DO fetch occurs per request under load", async () => {
    const { report } = await exerciseLoad();
    expect(report.durable_object_requests_per_request).toBe(2);
    expect(lastSpies.do.fetchCount()).toBe(CONCURRENCY_FIXTURE * 2);
    expect(lastSpies.do.fetchCount()).toBeLessThan(CONCURRENCY_FIXTURE * 3);
  });
});

describe("load_suite_introduces_no_per_request_server_state", () => {
  it("keeps load tooling under test/load with no src/load module or request-path store", () => {
    expect(LOAD_ROOT.includes(path.join("test", "load"))).toBe(true);
    expect(LOAD_ROOT.includes("src")).toBe(false);
    expect(happyPathSource.length).toBeGreaterThan(0);
    expect(happyPathSource).not.toContain("src/load");
    expect(happyPathSource).not.toMatch(/\bnew\s+Map\s*\(/);
    expect(happyPathSource).not.toMatch(/\bglobalThis\./);
  });
});

describe("no_prompt_provider_model_in_flutter_from_load_suite", () => {
  it("introduces no Flutter client files carrying prompt text, provider names, or model identifiers", () => {
    const loadPaths = listFilesRecursive(LOAD_ROOT);
    for (const file of loadPaths) {
      expect(file.startsWith(AI_PLATFORM_ROOT)).toBe(true);
      expect(file.includes("frontend")).toBe(false);
    }

    const frontendLoadPaths = listFilesRecursive(path.join(FRONTEND_LIB, "load"));
    expect(frontendLoadPaths).toEqual([]);

    const dartUnderLoad = loadPaths.filter((file) => file.endsWith(".dart"));
    expect(dartUnderLoad).toEqual([]);
  });
});
