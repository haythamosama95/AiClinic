import { env } from "cloudflare:test";
import { beforeAll, beforeEach, describe, expect, it } from "vitest";
import migrationSql from "../migrations/20260731120000_platform_schema.sql?raw";
import uniqueEntitlementSql from "../migrations/20260821130000_entitlement_installation_unique.sql?raw";
import { handleInstallationQuotaGet } from "../src/control/quota-inspect";
import type { ControlBindings, OperatorAuth } from "../src/control/types";
import type { QuotaDoState } from "../src/quota-do";

declare module "cloudflare:test" {
  interface ProvidedEnv {
    DB: D1Database;
  }
}

const GATEWAY_ORIGIN = "https://ai-gateway.test";
const FIXTURE_INSTALLATION_ID = "inst-1";
const FIXTURE_ORG_ID = "org-quota-001";
const FIXTURE_PERIOD_START = "2026-08-01T00:00:00.000Z";
const FIXTURE_PERIOD_END = "2026-09-01T00:00:00.000Z";

type OperatorPrincipal = {
  operatorId: string;
};

function createFakeOperatorAuth(
  principal: OperatorPrincipal | null = { operatorId: "operator-test" },
): OperatorAuth {
  return {
    resolve() {
      return principal;
    },
  };
}

type DoFetchCall = {
  url: string;
  init?: RequestInit;
};

function buildQuotaDoState(overrides: Partial<QuotaDoState> = {}): QuotaDoState {
  return {
    periodCounters: {
      requestsUsed: 0,
      tokensUsed: 0,
      costUsed: 0,
      inFlight: 0,
    },
    jtiReplay: {},
    idempotency: {},
    creditedRequests: {},
    admittedRequests: {},
    ...overrides,
  };
}

function createFakeDoNamespace(
  state: QuotaDoState,
  options: { throwOnFetch?: boolean } = {},
): {
  namespace: DurableObjectNamespace;
  fetchCalls: DoFetchCall[];
  idFromNameCalls: string[];
} {
  const fetchCalls: DoFetchCall[] = [];
  const idFromNameCalls: string[] = [];

  const namespace = {
    idFromName(name: string) {
      idFromNameCalls.push(name);
      return { name } as DurableObjectId;
    },
    get(_id: DurableObjectId) {
      return {
        fetch(url: string, init?: RequestInit) {
          fetchCalls.push({ url, init });
          if (options.throwOnFetch) {
            throw new Error("do_fetch_failed");
          }
          return Promise.resolve(
            Response.json({ kind: "inspect", state }),
          );
        },
      } as DurableObjectStub;
    },
  } as unknown as DurableObjectNamespace;

  return { namespace, fetchCalls, idFromNameCalls };
}

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

async function clearTables(): Promise<void> {
  await env.DB.batch([
    env.DB.prepare("DELETE FROM entitlement"),
    env.DB.prepare("DELETE FROM installation"),
  ]);
}

async function seedInstallation(
  installationId: string = FIXTURE_INSTALLATION_ID,
): Promise<void> {
  await env.DB.prepare(
    `INSERT INTO installation (installation_id, org_id, display_name, status, region, enrolled_at)
     VALUES (?, ?, ?, ?, ?, ?)`,
  )
    .bind(
      installationId,
      FIXTURE_ORG_ID,
      "Quota Inspect Clinic",
      "active",
      "us-east-1",
      "2026-08-01T12:00:00.000Z",
    )
    .run();
}

async function seedEntitlement(
  installationId: string = FIXTURE_INSTALLATION_ID,
  overrides: {
    request_quota?: number;
    token_budget?: number;
    cost_budget?: number;
    plan?: string;
    status?: string;
  } = {},
): Promise<void> {
  await env.DB.prepare(
    `INSERT INTO entitlement (
       entitlement_id, installation_id, plan, period_start, period_end,
       request_quota, token_budget, cost_budget, allowed_capabilities,
       soft_threshold, status
     ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
  )
    .bind(
      crypto.randomUUID(),
      installationId,
      overrides.plan ?? "professional",
      FIXTURE_PERIOD_START,
      FIXTURE_PERIOD_END,
      overrides.request_quota ?? 4000,
      overrides.token_budget ?? 4_000_000,
      overrides.cost_budget ?? 100,
      "[]",
      0.8,
      overrides.status ?? "active",
    )
    .run();
}

function bindings(
  doNamespace?: DurableObjectNamespace,
): ControlBindings {
  return {
    DB: env.DB,
    ...(doNamespace ? { DO: doNamespace } : {}),
  };
}

function quotaRequest(
  installationId: string = FIXTURE_INSTALLATION_ID,
  options: { method?: string; verbose?: boolean } = {},
): Request {
  const verbose = options.verbose ? "?verbose=true" : "";
  return new Request(
    `${GATEWAY_ORIGIN}/control/installations/${installationId}/quota${verbose}`,
    {
      method: options.method ?? "GET",
      headers: { authorization: "Bearer operator-test" },
    },
  );
}

beforeAll(async () => {
  await applyPlatformSchema(env.DB, migrationSql);
  await applyPlatformSchema(env.DB, uniqueEntitlementSql);
});

beforeEach(async () => {
  await clearTables();
});

describe("quota_inspect_operator_auth", () => {
  it("returns 401 when operator auth resolves null", async () => {
    await seedInstallation();

    const response = await handleInstallationQuotaGet(
      quotaRequest(),
      bindings(createFakeDoNamespace(buildQuotaDoState()).namespace),
      createFakeOperatorAuth(null),
    );

    expect(response.status).toBe(401);
    expect(await response.json()).toEqual({ error: "unauthorized" });
  });
});

describe("quota_inspect_method_not_allowed", () => {
  it("returns 405 for POST on the quota path", async () => {
    await seedInstallation();

    const response = await handleInstallationQuotaGet(
      quotaRequest(FIXTURE_INSTALLATION_ID, { method: "POST" }),
      bindings(createFakeDoNamespace(buildQuotaDoState()).namespace),
      createFakeOperatorAuth(),
    );

    expect(response.status).toBe(405);
    expect(await response.json()).toEqual({ error: "method_not_allowed" });
  });
});

describe("quota_inspect_installation_not_found", () => {
  it("returns 404 for an unknown installation id", async () => {
    const response = await handleInstallationQuotaGet(
      quotaRequest("missing-installation"),
      bindings(createFakeDoNamespace(buildQuotaDoState()).namespace),
      createFakeOperatorAuth(),
    );

    expect(response.status).toBe(404);
    expect(await response.json()).toEqual({ error: "installation_not_found" });
  });
});

describe("quota_inspect_canonicalizes_uppercase_installation_id", () => {
  it("inspects a lowercase-stored installation when the path id is uppercase", async () => {
    await seedInstallation();
    await seedEntitlement();

    const { namespace, idFromNameCalls } = createFakeDoNamespace(
      buildQuotaDoState(),
    );

    const response = await handleInstallationQuotaGet(
      quotaRequest(FIXTURE_INSTALLATION_ID.toUpperCase()),
      bindings(namespace),
      createFakeOperatorAuth(),
    );

    expect(response.status).toBe(200);
    expect(await response.json()).toMatchObject({
      installation_id: FIXTURE_INSTALLATION_ID,
    });
    expect(idFromNameCalls).toEqual([FIXTURE_INSTALLATION_ID]);
  });
});

describe("quota_inspect_do_unavailable", () => {
  it("returns 503 when bindings.DO is undefined", async () => {
    await seedInstallation();

    const response = await handleInstallationQuotaGet(
      quotaRequest(),
      bindings(),
      createFakeOperatorAuth(),
    );

    expect(response.status).toBe(503);
    expect(await response.json()).toEqual({ error: "quota_do_unavailable" });
  });

  it("returns 503 when the DO stub fetch throws", async () => {
    await seedInstallation();
    const { namespace } = createFakeDoNamespace(buildQuotaDoState(), {
      throwOnFetch: true,
    });

    const response = await handleInstallationQuotaGet(
      quotaRequest(),
      bindings(namespace),
      createFakeOperatorAuth(),
    );

    expect(response.status).toBe(503);
    expect(await response.json()).toEqual({ error: "quota_do_unavailable" });
  });
});

describe("quota_inspect_happy_path", () => {
  it("returns counters, entitlement, remaining, and map counts", async () => {
    await seedInstallation();
    await seedEntitlement();

    const idempotency = {
      "idem-1": {
        expiresAt: Date.now() + 3_600_000,
        requestReference: "REF-001",
        state: "completed" as const,
        requestId: "req-1",
      },
      "idem-2": {
        expiresAt: Date.now() + 3_600_000,
        requestReference: "REF-002",
        state: "completed" as const,
        requestId: "req-2",
      },
    };
    const jtiReplay = {
      "jti-1": { expiresAt: Date.now() + 3_600_000 },
      "jti-2": { expiresAt: Date.now() + 3_600_000 },
    };
    const creditedRequests = {
      "req-1": { expiresAt: Date.now() + 3_600_000 },
      "req-2": { expiresAt: Date.now() + 3_600_000 },
    };

    const { namespace } = createFakeDoNamespace(
      buildQuotaDoState({
        boundInstallationId: FIXTURE_INSTALLATION_ID,
        periodBounds: {
          period_start: FIXTURE_PERIOD_START,
          period_end: FIXTURE_PERIOD_END,
        },
        periodCounters: {
          requestsUsed: 2,
          tokensUsed: 60,
          costUsed: 0.01,
          inFlight: 0,
        },
        idempotency,
        jtiReplay,
        creditedRequests,
        admittedRequests: {},
      }),
    );

    const response = await handleInstallationQuotaGet(
      quotaRequest(),
      bindings(namespace),
      createFakeOperatorAuth(),
    );

    expect(response.status).toBe(200);
    const body = (await response.json()) as {
      installation_id: string;
      bound_installation_id: string | null;
      period_bounds: { period_start: string; period_end: string } | null;
      period_counters: {
        requests_used: number;
        tokens_used: number;
        cost_used: number;
        in_flight: number;
      };
      entitlement: {
        plan: string;
        status: string;
        period_start: string;
        period_end: string;
        request_quota: number;
        token_budget: number;
        cost_budget: number;
      } | null;
      remaining: {
        requests: number;
        tokens: number;
        cost: number;
      } | null;
      idempotency_keys: number;
      jti_replay_entries: number;
      admitted_requests: number;
      credited_requests: number;
      maps?: unknown;
    };

    expect(body).toEqual({
      installation_id: FIXTURE_INSTALLATION_ID,
      bound_installation_id: FIXTURE_INSTALLATION_ID,
      period_bounds: {
        period_start: FIXTURE_PERIOD_START,
        period_end: FIXTURE_PERIOD_END,
      },
      period_counters: {
        requests_used: 2,
        tokens_used: 60,
        cost_used: 0.01,
        in_flight: 0,
      },
      entitlement: {
        plan: "professional",
        status: "active",
        period_start: FIXTURE_PERIOD_START,
        period_end: FIXTURE_PERIOD_END,
        request_quota: 4000,
        token_budget: 4_000_000,
        cost_budget: 100,
      },
      remaining: {
        requests: 3998,
        tokens: 3_999_940,
        cost: expect.closeTo(99.99, 5),
      },
      idempotency_keys: 2,
      jti_replay_entries: 2,
      admitted_requests: 0,
      credited_requests: 2,
    });
    expect(body.maps).toBeUndefined();
  });
});

describe("quota_inspect_without_entitlement", () => {
  it("returns null entitlement and remaining with counters present", async () => {
    await seedInstallation();

    const { namespace } = createFakeDoNamespace(
      buildQuotaDoState({
        periodCounters: {
          requestsUsed: 1,
          tokensUsed: 10,
          costUsed: 0.5,
          inFlight: 0,
        },
      }),
    );

    const response = await handleInstallationQuotaGet(
      quotaRequest(),
      bindings(namespace),
      createFakeOperatorAuth(),
    );

    expect(response.status).toBe(200);
    const body = await response.json();
    expect(body).toMatchObject({
      installation_id: FIXTURE_INSTALLATION_ID,
      entitlement: null,
      remaining: null,
      period_counters: {
        requests_used: 1,
        tokens_used: 10,
        cost_used: 0.5,
        in_flight: 0,
      },
    });
  });
});

describe("quota_inspect_empty_do_state", () => {
  it("returns null bound_installation_id and period_bounds with zeroed counters", async () => {
    await seedInstallation();
    await seedEntitlement();

    const { namespace } = createFakeDoNamespace(buildQuotaDoState());

    const response = await handleInstallationQuotaGet(
      quotaRequest(),
      bindings(namespace),
      createFakeOperatorAuth(),
    );

    expect(response.status).toBe(200);
    expect(await response.json()).toMatchObject({
      installation_id: FIXTURE_INSTALLATION_ID,
      bound_installation_id: null,
      period_bounds: null,
      period_counters: {
        requests_used: 0,
        tokens_used: 0,
        cost_used: 0,
        in_flight: 0,
      },
      idempotency_keys: 0,
      jti_replay_entries: 0,
      admitted_requests: 0,
      credited_requests: 0,
    });
  });
});

describe("quota_inspect_verbose_maps", () => {
  it("includes maps when verbose=true and omits them otherwise", async () => {
    await seedInstallation();
    await seedEntitlement();

    const idempotency = {
      "idem-verbose": {
        expiresAt: Date.now() + 3_600_000,
        requestReference: "REF-V",
        state: "admitted" as const,
        requestId: "req-v",
      },
    };
    const jtiReplay = {
      "jti-verbose": { expiresAt: Date.now() + 3_600_000 },
    };
    const admittedRequests = {
      "req-v": {
        requestReference: "REF-V",
        admittedAt: Date.now(),
        entitlement: {
          plan: "standard",
          period_bounds: {
            period_start: FIXTURE_PERIOD_START,
            period_end: FIXTURE_PERIOD_END,
          },
          request_quota: 100,
          token_cost_budget: { token_budget: 1000, cost_budget: 10 },
          allowed_capabilities: [],
          soft_threshold: 0,
          status: "active",
        },
      },
    };
    const creditedRequests = {
      "req-c": { expiresAt: Date.now() + 3_600_000 },
    };

    const { namespace } = createFakeDoNamespace(
      buildQuotaDoState({
        idempotency,
        jtiReplay,
        admittedRequests,
        creditedRequests,
      }),
    );

    const verboseResponse = await handleInstallationQuotaGet(
      quotaRequest(FIXTURE_INSTALLATION_ID, { verbose: true }),
      bindings(namespace),
      createFakeOperatorAuth(),
    );
    expect(verboseResponse.status).toBe(200);
    const verboseBody = (await verboseResponse.json()) as {
      maps: {
        idempotency: Record<string, unknown>;
        jti_replay: Record<string, unknown>;
        admitted_requests: Record<string, unknown>;
        credited_requests: Record<string, unknown>;
        truncated: boolean;
      };
    };
    expect(verboseBody.maps).toEqual({
      idempotency,
      jti_replay: jtiReplay,
      admitted_requests: admittedRequests,
      credited_requests: creditedRequests,
      truncated: false,
    });

    const plainResponse = await handleInstallationQuotaGet(
      quotaRequest(),
      bindings(namespace),
      createFakeOperatorAuth(),
    );
    expect(plainResponse.status).toBe(200);
    const plainBody = await plainResponse.json();
    expect(plainBody).not.toHaveProperty("maps");
  });
});

describe("quota_inspect_do_rpc_contract", () => {
  it("POSTs inspect RPC to the quota DO stub", async () => {
    await seedInstallation();
    await seedEntitlement();

    const { namespace, fetchCalls } = createFakeDoNamespace(buildQuotaDoState());

    const response = await handleInstallationQuotaGet(
      quotaRequest(),
      bindings(namespace),
      createFakeOperatorAuth(),
    );
    expect(response.status).toBe(200);

    expect(fetchCalls).toHaveLength(1);
    expect(fetchCalls[0]?.url).toBe("https://quota-do.internal/rpc");
    expect(fetchCalls[0]?.init?.method).toBe("POST");
    expect(JSON.parse(String(fetchCalls[0]?.init?.body))).toEqual({
      kind: "inspect",
    });
  });
});
