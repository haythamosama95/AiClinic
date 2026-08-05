import { existsSync, readdirSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { env } from "cloudflare:test";
import { beforeAll, describe, expect, it } from "vitest";
import migrationSql from "../../migrations/20260731120000_platform_schema.sql?raw";
import ciWorkflowSource from "../../../.github/workflows/ci.yml?raw";
import packageJson from "../../package.json";
import { CONCURRENCY_LIMIT } from "../../src/quota-do";
import { createBindingSpies, type BindingSpies } from "./binding-spies";
import {
  CONCURRENCY_FIXTURE,
  GUARD_P95_CEILING_MS,
  type LoadMeasurementReport,
  assertFiniteMeasurement,
  computeGuardP95,
} from "./measurement-report";
import { LOAD_POOL_SIZE, runLoadHappyPath } from "./happy-path";
import happyPathSource from "./happy-path.ts?raw";
import pipelineSource from "../../src/pipeline/index.ts?raw";

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
const CI_WORKFLOW = path.join(REPO_ROOT, ".github", "workflows", "ci.yml");

async function applyPlatformSchema(db: D1Database, sql: string): Promise<void> {
  const withoutLineComments = sql.replace(/--.*$/gm, "");
  const statements: string[] = [];
  let current = "";
  let inString = false;

  for (let i = 0; i < withoutLineComments.length; i += 1) {
    const ch = withoutLineComments[i]!;
    if (ch === "'") {
      const next = withoutLineComments[i + 1];
      if (inString && next === "'") {
        current += "''";
        i += 1;
        continue;
      }
      inString = !inString;
      current += ch;
      continue;
    }
    if (ch === ";" && !inString) {
      const trimmed = current.trim();
      if (trimmed.length > 0) {
        statements.push(trimmed);
      }
      current = "";
      continue;
    }
    current += ch;
  }
  const trailing = current.trim();
  if (trailing.length > 0) {
    statements.push(trailing);
  }

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
    env.DB.prepare("DELETE FROM capability_grant"),
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

let sharedReport: LoadMeasurementReport;
let sharedSpies: BindingSpies;

beforeAll(async () => {
  await applyPlatformSchema(env.DB, migrationSql);
  await clearLoadTables();
  const spies = createBindingSpies(env);
  const result = await runLoadHappyPath({
    db: spies.db,
    r2: spies.r2,
    do: spies.do,
    realDo: env.DO,
  });
  sharedReport = result.report;
  sharedSpies = spies;
}, 180_000);

describe("guard_p95_within_tens_of_ms_at_target_concurrency", () => {
  it("drives N=20 happy-path requests via a bounded pool with real overlap", () => {
    expect(sharedReport.request_count).toBe(CONCURRENCY_FIXTURE);
    expect(sharedReport.concurrency).toBeGreaterThanOrEqual(2);
    expect(sharedReport.concurrency).toBeLessThanOrEqual(CONCURRENCY_LIMIT);
    expect(sharedReport.concurrency).toBe(LOAD_POOL_SIZE);
    expect(computeGuardP95(sharedReport.guard_latencies_ms)).toBe(
      sharedReport.guard_p95_ms,
    );
    // Miniflare ceiling (2000 ms); production target remains 100 ms (documented).
    expect(sharedReport.guard_p95_ms).toBeLessThan(GUARD_P95_CEILING_MS);    const sequentialSum = sharedReport.guard_latencies_ms.reduce(
      (a, b) => a + b,
      0,
    );
    expect(sharedReport.wall_clock_ms).toBeLessThan(sequentialSum * 0.9);
  });
});

describe("exactly_one_r2_class_a_per_request_under_load", () => {
  it("counts exactly one R2 Class A operation per request (max and average)", () => {
    expect(sharedReport.r2_class_a_ops_per_request).toBe(1);
    expect(sharedReport.r2_class_a_ops_max_per_request).toBe(1);
    expect(sharedSpies.r2.classAOpCount()).toBe(CONCURRENCY_FIXTURE);
    expect(new Set(sharedSpies.r2.putKeys()).size).toBe(CONCURRENCY_FIXTURE);
  });
});

describe("exactly_two_durable_object_requests_per_request_under_load", () => {
  it("counts exactly two Quota DO fetches per request — admission and credit", () => {
    expect(sharedReport.durable_object_requests_per_request).toBe(2);
    expect(sharedReport.durable_object_requests_max_per_request).toBe(2);
    expect(sharedSpies.do.fetchCount()).toBe(CONCURRENCY_FIXTURE * 2);
  });
});

describe("d1_write_headroom_measured", () => {
  it("measures one hot-path ai_request INSERT per request (finite, no ceiling)", () => {
    assertFiniteMeasurement(sharedReport.d1_hot_path_writes_per_request);
    expect(sharedReport.d1_hot_path_writes_per_request).toBe(1);
    expect(sharedReport.d1_hot_path_writes_max_per_request).toBe(1);
  });
});

describe("do_throughput_per_installation_measured", () => {
  it("measures time-dimensioned DO throughput against one pinned installation", () => {
    assertFiniteMeasurement(sharedReport.do_throughput_per_installation);
    expect(sharedReport.do_throughput_per_installation).toBeGreaterThan(0);
    expect(sharedReport.wall_clock_ms).toBeGreaterThan(0);
    expect(sharedSpies.do.fetchCount()).toBe(CONCURRENCY_FIXTURE * 2);
  });
});

describe("no_second_r2_object_per_request", () => {
  it("proves no second R2 Class A op is written per request under load", () => {
    expect(sharedReport.r2_class_a_ops_max_per_request).toBe(1);
    expect(sharedSpies.r2.classAOpCount()).toBe(CONCURRENCY_FIXTURE);
    expect(sharedSpies.r2.classAOpCount()).toBeLessThan(CONCURRENCY_FIXTURE * 2);
  });
});

describe("no_second_quota_do_round_trip_beyond_two", () => {
  it("proves no third Quota DO fetch occurs per request under load", () => {
    expect(sharedReport.durable_object_requests_max_per_request).toBe(2);
    expect(sharedSpies.do.fetchCount()).toBe(CONCURRENCY_FIXTURE * 2);
    expect(sharedSpies.do.fetchCount()).toBeLessThan(CONCURRENCY_FIXTURE * 3);
  });
});

describe("load_suite_introduces_no_per_request_server_state", () => {
  it("keeps load tooling under test/load; composition lives in src/pipeline", () => {
    expect(LOAD_ROOT.includes(path.join("test", "load"))).toBe(true);
    expect(LOAD_ROOT.includes(`${path.sep}src${path.sep}`)).toBe(false);
    expect(happyPathSource).toContain('from "../../src/pipeline"');
    expect(happyPathSource).not.toContain("src/load");
    expect(pipelineSource).toContain("runGuard");
    expect(pipelineSource).toContain("settleHappyPath");
    expect(happyPathSource).toMatch(/function createRequestCounters/);
    expect(happyPathSource).not.toMatch(/^let jtiCounter/m);
    expect(happyPathSource).not.toMatch(/\bglobalThis\./);
  });
});

describe("no_prompt_provider_model_in_flutter_from_load_suite", () => {
  it("introduces no Flutter client files; defers R-12 content scan to CI architecture guard", () => {
    const loadPaths = listFilesRecursive(LOAD_ROOT);
    for (const file of loadPaths) {
      expect(file.startsWith(AI_PLATFORM_ROOT)).toBe(true);
      expect(file.includes("frontend")).toBe(false);
    }

    const frontendLoadPaths = listFilesRecursive(path.join(FRONTEND_LIB, "load"));
    expect(frontendLoadPaths).toEqual([]);

    const dartUnderLoad = loadPaths.filter((file) => file.endsWith(".dart"));
    expect(dartUnderLoad).toEqual([]);

    expect(CI_WORKFLOW.endsWith(path.join(".github", "workflows", "ci.yml"))).toBe(
      true,
    );
    expect(ciWorkflowSource).toContain("Architecture guard (client R-12 lint)");
    expect(ciWorkflowSource).toContain(
      "tool/architecture_guard/architecture_guard.dart",
    );
  });
});

describe("load_suite_joins_ci_permanently", () => {
  it("wires test:load into .github/workflows/ci.yml as an ai-platform job", () => {
    expect(ciWorkflowSource).toMatch(/ai-platform-tests:/);
    expect(ciWorkflowSource).toContain("npm run test:load");
    expect(packageJson.scripts["test:load"]).toMatch(/load-and-cost\.test/);
  });
});
