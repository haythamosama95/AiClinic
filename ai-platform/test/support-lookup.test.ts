import { env } from "cloudflare:test";
import { beforeAll, beforeEach, describe, expect, it } from "vitest";
import migrationSql from "../migrations/20260731120000_platform_schema.sql?raw";
import { supportLookup } from "../src/support";
import type { Envelope } from "../src/journal";

declare module "cloudflare:test" {
  interface ProvidedEnv {
    DB: D1Database;
    R2: R2Bucket;
  }
}

type OperatorAuth = {
  resolve(_request: Request): { operatorId: string } | null;
};

function createFakeOperatorAuth(
  principal: { operatorId: string } | null = { operatorId: "operator-test" },
): OperatorAuth {
  return { resolve: () => principal };
}

declare module "cloudflare:test" {
  interface ProvidedEnv {
    DB: D1Database;
    R2: R2Bucket;
  }
}

const FIXTURE_INSTALLATION_ID = "inst-support-001";
const FIXTURE_ORG_ID = "org-support-001";
const FIXTURE_NOW = new Date("2026-08-02T12:00:00.000Z");
const FIXTURE_REFERENCE = "7QK4-2B9F";
const FIXTURE_REQUEST_ID = "01SUPPORTREQ00000000001";

type D1Spy = D1Database & {
  requestReferenceQueryCount: () => number;
  resetCounts: () => void;
};

type R2Spy = R2Bucket & {
  getCallCount: () => number;
  resetCounts: () => void;
};

function normalizeSql(sql: string): string {
  return sql.replace(/\s+/g, " ").trim().toLowerCase();
}

function createD1Spy(realDb: D1Database): D1Spy {
  let requestReferenceQueries = 0;
  const spy: D1Spy = {
    ...realDb,
    prepare(query: string) {
      const normalized = normalizeSql(query);
      if (
        normalized.includes("from ai_request") &&
        normalized.includes("request_reference")
      ) {
        requestReferenceQueries += 1;
      }
      return realDb.prepare(query);
    },
    requestReferenceQueryCount() {
      return requestReferenceQueries;
    },
    resetCounts() {
      requestReferenceQueries = 0;
    },
  };
  return spy;
}

function createR2Spy(realR2: R2Bucket): R2Spy {
  let getCalls = 0;
  const spy: R2Spy = {
    ...realR2,
    async get(key: string, options?: R2GetOptions) {
      getCalls += 1;
      return realR2.get(key, options);
    },
    getCallCount() {
      return getCalls;
    },
    resetCounts() {
      getCalls = 0;
    },
  };
  return spy;
}

async function applyPlatformSchema(db: D1Database, sql: string): Promise<void> {
  const statements = sql
    .replace(/--.*$/gm, "")
    .split(";")
    .map((s) => s.trim())
    .filter((s) => s.length > 0);
  for (const statement of statements) {
    await db.prepare(statement).run();
  }
}

async function seedInstallation(): Promise<void> {
  await env.DB.prepare(
    `INSERT INTO installation (installation_id, org_id, display_name, status, region, enrolled_at)
     VALUES (?, ?, ?, ?, ?, ?)`,
  )
    .bind(
      FIXTURE_INSTALLATION_ID,
      FIXTURE_ORG_ID,
      "Support Clinic",
      "active",
      "us-east-1",
      FIXTURE_NOW.toISOString(),
    )
    .run();
}

async function seedRequest(
  overrides: {
    reference?: string;
    requestId?: string;
    createdAt?: string;
    completedAt?: string;
    capabilityId?: string;
    withEnvelope?: boolean;
  } = {},
): Promise<void> {
  const requestId = overrides.requestId ?? FIXTURE_REQUEST_ID;
  const reference = overrides.reference ?? FIXTURE_REFERENCE;
  const createdAt =
    overrides.createdAt ?? "2026-08-01T12:00:00.000Z";
  const completedAt = overrides.completedAt ?? "2026-08-01T12:05:00.000Z";
  const capabilityId = overrides.capabilityId ?? "clinic.support-test";

  await env.DB.prepare(
    `INSERT INTO ai_request (
      request_id, request_reference, installation_id, actor_id, branch_id,
      capability_id, capability_version, prompt_artifact_hash, idempotency_key,
      trace_id, state, created_at, updated_at, completed_at, terminal_error_code,
      payload_pointer, conversation_id, turn_ordinal
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULL, ?, NULL, NULL)`,
  )
    .bind(
      requestId,
      reference,
      FIXTURE_INSTALLATION_ID,
      "actor-001",
      "branch-001",
      capabilityId,
      "1.0.0",
      "prompt/support@v1",
      "idem-support-001",
      "01SUPPORTTRACE0000000001",
      "Completed",
      createdAt,
      completedAt,
      completedAt,
      `request/${requestId}/envelope`,
    )
    .run();

  await env.DB.prepare(
    `INSERT INTO ai_attempt (
      attempt_id, request_id, attempt_no, provider, model, outcome,
      latency_ms, tokens_in, tokens_out, cost, provider_request_id, error_code
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULL)`,
  )
    .bind(
      "attempt-support-001",
      requestId,
      1,
      "deepseek",
      "support-fixture",
      "success",
      150,
      100,
      50,
      0.001,
      "prov-support-001",
    )
    .run();

  if (overrides.withEnvelope !== false) {
    const envelope: Envelope = {
      context: { note: "support fixture" },
      prompt: { system: "test" },
      attempts: [{ raw: "response" }],
      result: {
        "final content": { text: "ok" },
        "usage counters": { input: 100, output: 50, cached: 0 },
        "provider+model actually used": {
          provider: "deepseek",
          model: "support-fixture",
        },
        "finish reason": "stop",
        "provider request id": "prov-support-001",
        "timing breakdown": { queue_ms: 1, provider_ms: 149, total_ms: 150 },
      },
    };
    await env.R2.put(`request/${requestId}/envelope`, JSON.stringify(envelope));
  }
}

async function clearTables(): Promise<void> {
  await env.DB.batch([
    env.DB.prepare("DELETE FROM ai_attempt"),
    env.DB.prepare("DELETE FROM ai_request"),
    env.DB.prepare("DELETE FROM installation"),
  ]);
}

async function loadControlHandlers(): Promise<{
  handleSupportLookup: (
    request: Request,
    bindings: { DB: D1Database; R2: R2Bucket },
    operatorAuth: OperatorAuth,
  ) => Promise<Response>;
}> {
  return import("../src/control") as Promise<{
    handleSupportLookup: (
      request: Request,
      bindings: { DB: D1Database; R2: R2Bucket },
      operatorAuth: OperatorAuth,
    ) => Promise<Response>;
  }>;
}

beforeAll(async () => {
  await applyPlatformSchema(env.DB, migrationSql);
});

beforeEach(async () => {
  await clearTables();
  await seedInstallation();
});

describe("support_lookup_one_d1_one_getobject", () => {
  it("resolves trace + envelope in exactly one D1 query and one GetObject", async () => {
    await seedRequest();
    const dbSpy = createD1Spy(env.DB);
    const r2Spy = createR2Spy(env.R2);

    const result = await supportLookup(FIXTURE_REFERENCE, {
      db: dbSpy,
      r2: r2Spy,
      now: () => FIXTURE_NOW,
      resolveRetentionClass: () => "diagnostic_30d",
    });

    expect(result.found).toBe(true);
    if (result.found) {
      expect(result.request.requestReference).toBe(FIXTURE_REFERENCE);
      expect(result.attempts).toHaveLength(1);
      expect(result.envelope).not.toBeNull();
    }
    expect(dbSpy.requestReferenceQueryCount()).toBe(1);
    expect(r2Spy.getCallCount()).toBe(1);
  });
});

describe("support_lookup_expired_envelope_metadata", () => {
  it("returns metadata without envelope body when outside diagnostic retention", async () => {
    await seedRequest({
      createdAt: "2026-06-01T12:00:00.000Z",
      completedAt: "2026-06-01T12:05:00.000Z",
    });

    const result = await supportLookup(FIXTURE_REFERENCE, {
      db: env.DB,
      r2: env.R2,
      now: () => FIXTURE_NOW,
      resolveRetentionClass: () => "diagnostic_7d",
    });

    expect(result.found).toBe(true);
    if (result.found) {
      expect(result.request.requestId).toBe(FIXTURE_REQUEST_ID);
      expect(result.attempts).toHaveLength(1);
      expect(result.envelope).toBeNull();
    }
  });
});

describe("support_lookup_non_operator_denied", () => {
  it("denies clinic/non-operator credentials on the control-plane route", async () => {
    await seedRequest();
    const { handleSupportLookup } = await loadControlHandlers();
    const rejectAuth = createFakeOperatorAuth(null);

    const response = await handleSupportLookup(
      new Request(
        `https://gateway.test/control/support/lookup?reference=${FIXTURE_REFERENCE}`,
        {
          method: "POST",
          headers: { authorization: "Bearer clinic-token" },
        },
      ),
      { DB: env.DB, R2: env.R2 },
      rejectAuth,
    );

    expect(response.status).toBe(401);
  });
});
