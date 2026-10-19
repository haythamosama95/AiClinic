import { env } from "cloudflare:test";
import { beforeAll, beforeEach, describe, expect, it } from "vitest";
import migrationSql from "../migrations/20260731120000_platform_schema.sql?raw";
import { MS_PER_DAY } from "../src/retention";
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
        finalContent: { text: "ok" },
        usage: { input: 100, output: 50, cached: 0 },
        providerModel: {
          provider: "deepseek",
          model: "support-fixture",
        },
        finishReason: "stop",
        providerRequestId: "prov-support-001",
        timing: { queue_ms: 1, provider_ms: 149, total_ms: 150 },
      },
    };
    await env.R2.put(`request/${requestId}/envelope`, JSON.stringify(envelope));
  }
}

async function clearTables(): Promise<void> {
  await env.DB.batch([
    env.DB.prepare("DELETE FROM ai_attempt"),
    env.DB.prepare("DELETE FROM ai_request"),
    env.DB.prepare("DELETE FROM tenant_binding"),
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
  await env.DB.prepare(
    `CREATE TABLE IF NOT EXISTS tenant_binding (
      org_id TEXT NOT NULL,
      installation_id TEXT NOT NULL,
      epoch INTEGER NOT NULL,
      status TEXT NOT NULL,
      retired_at TEXT,
      reason TEXT,
      created_at TEXT NOT NULL,
      PRIMARY KEY (org_id, epoch),
      FOREIGN KEY (installation_id) REFERENCES installation (installation_id)
    )`,
  ).run();
});

beforeEach(async () => {
  await clearTables();
  await seedInstallation();
  await env.DB.prepare(
    `INSERT INTO tenant_binding (
      org_id, installation_id, epoch, status, retired_at, reason, created_at
    ) VALUES (?, ?, 1, 'active', NULL, NULL, ?)`,
  )
    .bind(FIXTURE_ORG_ID, FIXTURE_INSTALLATION_ID, FIXTURE_NOW.toISOString())
    .run();
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
    const r2Spy = createR2Spy(env.R2);

    const result = await supportLookup(FIXTURE_REFERENCE, {
      db: env.DB,
      r2: r2Spy,
      now: () => FIXTURE_NOW,
      resolveRetentionClass: () => "diagnostic_7d",
    });

    expect(result.found).toBe(true);
    if (result.found) {
      expect(result.request.requestId).toBe(FIXTURE_REQUEST_ID);
      expect(result.attempts).toHaveLength(1);
      expect(result.envelope).toBeNull();
    }
    expect(r2Spy.getCallCount()).toBe(0);
  });
});

describe("support_lookup_in_horizon_missing_r2", () => {
  it("returns found with null envelope and exactly one GetObject when R2 object is absent", async () => {
    await seedRequest({ withEnvelope: false });
    const r2Spy = createR2Spy(env.R2);

    const result = await supportLookup(FIXTURE_REFERENCE, {
      db: env.DB,
      r2: r2Spy,
      now: () => FIXTURE_NOW,
      resolveRetentionClass: () => "diagnostic_30d",
    });

    expect(result.found).toBe(true);
    if (result.found) {
      expect(result.request.requestId).toBe(FIXTURE_REQUEST_ID);
      expect(result.attempts).toHaveLength(1);
      expect(result.envelope).toBeNull();
    }
    expect(r2Spy.getCallCount()).toBe(1);
  });
});

describe("support_lookup_reference_input", () => {
  it("resolves lowercase input to the stored reference", async () => {
    await seedRequest();
    const result = await supportLookup("7qk4-2b9f", {
      db: env.DB,
      r2: env.R2,
      now: () => FIXTURE_NOW,
      resolveRetentionClass: () => "diagnostic_30d",
    });
    expect(result.found).toBe(true);
    if (result.found) {
      expect(result.request.requestReference).toBe(FIXTURE_REFERENCE);
    }
  });

  it("resolves I/L/O-confused input to the seeded normalised reference", async () => {
    await seedRequest({ reference: "71K4-209F" });
    const result = await supportLookup("7IK4-2O9F", {
      db: env.DB,
      r2: env.R2,
      now: () => FIXTURE_NOW,
      resolveRetentionClass: () => "diagnostic_30d",
    });
    expect(result.found).toBe(true);
    if (result.found) {
      expect(result.request.requestReference).toBe("71K4-209F");
    }
  });

  it("trims surrounding whitespace on the control-plane route", async () => {
    await seedRequest();
    const { handleSupportLookup } = await loadControlHandlers();
    const response = await handleSupportLookup(
      new Request(
        `https://gateway.test/control/support/lookup?reference=${encodeURIComponent(" 7QK4-2B9F ")}`,
        { method: "GET" },
      ),
      { DB: env.DB, R2: env.R2 },
      createFakeOperatorAuth(),
    );
    expect(response.status).toBe(200);
    const body = (await response.json()) as {
      request: { requestReference: string };
    };
    expect(body.request.requestReference).toBe(FIXTURE_REFERENCE);
  });

  it("rejects malformed-after-normalise references with 400 invalid_reference", async () => {
    const { handleSupportLookup } = await loadControlHandlers();
    for (const bad of ["7QK4 2B9F", "SHORT"]) {
      const response = await handleSupportLookup(
        new Request(
          `https://gateway.test/control/support/lookup?reference=${encodeURIComponent(bad)}`,
          { method: "GET" },
        ),
        { DB: env.DB, R2: env.R2 },
        createFakeOperatorAuth(),
      );
      expect(response.status).toBe(400);
      expect(await response.json()).toEqual({ error: "invalid_reference" });
    }
  });

  it("returns 404 not_found for unknown but format-valid references", async () => {
    const { handleSupportLookup } = await loadControlHandlers();
    const response = await handleSupportLookup(
      new Request(
        "https://gateway.test/control/support/lookup?reference=AAAA-BBBB",
        { method: "GET" },
      ),
      { DB: env.DB, R2: env.R2 },
      createFakeOperatorAuth(),
    );
    expect(response.status).toBe(404);
    expect(await response.json()).toEqual({ error: "not_found" });
  });

  it("returns 400 missing_reference for blank or whitespace-only input", async () => {
    const { handleSupportLookup } = await loadControlHandlers();
    for (const query of ["", "reference=", "reference=%20%20"]) {
      const response = await handleSupportLookup(
        new Request(
          `https://gateway.test/control/support/lookup?${query}`,
          { method: "GET" },
        ),
        { DB: env.DB, R2: env.R2 },
        createFakeOperatorAuth(),
      );
      expect(response.status).toBe(400);
      expect(await response.json()).toEqual({ error: "missing_reference" });
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

describe("R8-SUPPORT1 bounded_support_history_pages", () => {
  it("pages request IDs before attempts, breaks timestamp ties, and never gets list envelopes", async () => {
    for (const [index, requestId] of [
      "01SUPPORTPAGE00000001",
      "01SUPPORTPAGE00000002",
      "01SUPPORTPAGE00000003",
    ].entries()) {
      await env.DB.prepare(
        `INSERT INTO ai_request (
          request_id, request_reference, installation_id, actor_id, branch_id,
          capability_id, capability_version, prompt_artifact_hash, idempotency_key,
          state, created_at, updated_at, completed_at, terminal_error_code,
          trace_id, payload_pointer, conversation_id, turn_ordinal
        ) VALUES (?, ?, ?, 'actor-001', NULL, 'clinic.support-test', '1.0.0',
          'prompt/support@v1', ?, 'Completed', ?, ?, ?, NULL, ?, NULL, NULL, NULL)`,
      )
        .bind(
          requestId,
          `7SF1-0${index}AA`,
          FIXTURE_INSTALLATION_ID,
          `support-page-${index}`,
          "2026-08-01T12:00:00.000Z",
          "2026-08-01T12:00:00.000Z",
          "2026-08-01T12:00:00.000Z",
          `trace-${requestId}`,
        )
        .run();
    }

    const r2Spy = createR2Spy(env.R2);
    const references: string[] = [];
    let cursor: string | undefined;
    do {
      const result = await supportLookup(
        { org_id: FIXTURE_ORG_ID, limit: 1, ...(cursor ? { cursor } : {}) },
        { db: env.DB, r2: r2Spy },
      );
      expect(result.found).toBe(true);
      if (!result.found || !("requests" in result)) {
        throw new Error("Expected support list result");
      }
      expect(result.requests).toHaveLength(1);
      expect(result.requests[0]?.envelope).toBeNull();
      references.push(result.requests[0]!.request.requestReference);
      cursor = result.next_after ?? undefined;
      if (!result.has_more) {
        break;
      }
    } while (cursor !== undefined);

    expect(references).toEqual(["7SF1-02AA", "7SF1-01AA", "7SF1-00AA"]);
    expect(new Set(references).size).toBe(3);
    expect(r2Spy.getCallCount()).toBe(0);
  });
});

describe("support_lookup_manifest_retention_wiring", () => {
  it("uses published visit_summary 30d horizon via handleSupportLookup factory wiring", async () => {
    const now = new Date();
    const day15 = new Date(now.getTime() - 15 * MS_PER_DAY).toISOString();
    const reference = "7QK4-30DY";
    const requestId = "01SUPPORTREQ00000000030";

    await seedRequest({
      reference,
      requestId,
      createdAt: day15,
      completedAt: day15,
      capabilityId: "clinic.visit_summary",
    });

    const { handleSupportLookup } = await loadControlHandlers();
    const operatorAuth = createFakeOperatorAuth({ operatorId: "operator-test" });

    const response = await handleSupportLookup(
      new Request(
        `https://gateway.test/control/support/lookup?reference=${reference}`,
        {
          method: "POST",
          headers: { authorization: "Bearer operator-test" },
        },
      ),
      { DB: env.DB, R2: env.R2 },
      operatorAuth,
    );

    expect(response.status).toBe(200);
    const body = (await response.json()) as {
      envelope: Envelope | null;
      request: { capabilityId: string };
    };
    expect(body.request.capabilityId).toBe("clinic.visit_summary");
    expect(body.envelope).not.toBeNull();
  });
});
