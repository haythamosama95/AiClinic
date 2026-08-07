import { env } from "cloudflare:test";
import { beforeAll, beforeEach, describe, expect, it } from "vitest";
import migrationSql from "../migrations/20260731120000_platform_schema.sql?raw";
import {
  ConfigCache,
  type ConfigEntityKind,
  type D1Reader,
} from "../src/config-cache";

declare module "cloudflare:test" {
  interface ProvidedEnv {
    DB: D1Database;
  }
}

type D1Row = Record<string, unknown>;

const GATEWAY_ORIGIN = "https://ai-gateway.test";
const TEST_OPERATOR_ID = "operator-test-principal";

const FIXTURE_INSTALLATION_ID = "inst-entitle-001";
const FIXTURE_ORG_ID = "org-entitle-001";
const FIXTURE_CAPABILITY_ID = "clinic.visit_summary";
const FIXTURE_CAPABILITY_VERSION = "1.0.0";

type OperatorPrincipal = {
  operatorId: string;
};

type OperatorAuth = {
  resolve(_request: Request): OperatorPrincipal | null;
};

const FAKE_OPERATOR: OperatorPrincipal = {
  operatorId: TEST_OPERATOR_ID,
};

function createFakeOperatorAuth(
  principal: OperatorPrincipal | null = FAKE_OPERATOR,
): OperatorAuth {
  return {
    resolve() {
      return principal;
    },
  };
}

type ControlBindings = { DB: D1Database };

type EnrollPayload = {
  org_id: string;
  display_name: string;
  region: string;
  plan: string;
  public_key: string;
  algorithm: string;
  kid: string;
};

type EntitlePayload = {
  period_start: string;
  period_end: string;
  request_quota: number;
  token_budget: number;
  cost_budget: number;
  soft_threshold: number;
  allowed_capabilities: string[];
  grants: Array<{
    capability_id: string;
    capability_version: string;
    scope?: "installation" | "plan";
  }>;
};

type ControlHandlers = {
  handleEnroll: (
    request: Request,
    bindings: ControlBindings,
    operatorAuth: OperatorAuth,
  ) => Promise<Response>;
  handleEntitle: (
    request: Request,
    bindings: ControlBindings,
    operatorAuth: OperatorAuth,
  ) => Promise<Response>;
};

type EntitlementHandlers = {
  evaluateEntitlement: (
    principal: {
      installationId: string;
      organizationId: string;
      branchId: string;
      actorId: string;
      role: string;
      scopes: readonly string[];
      jti: string;
      iat: number;
      exp: number;
      ver: string;
    },
    ctx: {
      capabilityId: string;
      capabilityVersion: string;
      minimumPlanTier: string;
      providerId: string;
    },
    cache: ConfigCache,
    reader: D1Reader,
  ) => Promise<
    | { ok: true }
    | {
        ok: false;
        code: "forbidden_capability" | "capability_disabled";
        path: string;
      }
  >;
};

const DEFAULT_ENROLL_PAYLOAD: EnrollPayload = {
  org_id: FIXTURE_ORG_ID,
  display_name: "Entitle Test Clinic",
  region: "us-east-1",
  plan: "professional",
  public_key: "dGVzdC1wdWJsaWMta2V5",
  algorithm: "EdDSA",
  kid: "kid-entitle-001",
};

const DEFAULT_ENTITLE_PAYLOAD: EntitlePayload = {
  period_start: "2026-08-01T00:00:00.000Z",
  period_end: "2026-09-01T00:00:00.000Z",
  request_quota: 1000,
  token_budget: 500000,
  cost_budget: 50.0,
  soft_threshold: 0.8,
  allowed_capabilities: [FIXTURE_CAPABILITY_ID],
  grants: [
    {
      capability_id: FIXTURE_CAPABILITY_ID,
      capability_version: FIXTURE_CAPABILITY_VERSION,
      scope: "installation",
    },
  ],
};

async function loadControlHandlers(): Promise<ControlHandlers> {
  return import(/* @vite-ignore */ "../src/control") as Promise<ControlHandlers>;
}

async function loadEntitlementHandlers(): Promise<EntitlementHandlers> {
  return import(/* @vite-ignore */ "../src/entitlement") as Promise<EntitlementHandlers>;
}

function bindings(): ControlBindings {
  return { DB: env.DB };
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

async function clearLifecycleTables(): Promise<void> {
  await env.DB.batch([
    env.DB.prepare("DELETE FROM control_audit"),
    env.DB.prepare("DELETE FROM capability_grant"),
    env.DB.prepare("DELETE FROM entitlement"),
    env.DB.prepare("DELETE FROM installation_key"),
    env.DB.prepare("DELETE FROM installation"),
  ]);
}

function buildEnrollRequest(
  installationId: string = FIXTURE_INSTALLATION_ID,
  payload: EnrollPayload = DEFAULT_ENROLL_PAYLOAD,
): Request {
  return new Request(
    `${GATEWAY_ORIGIN}/control/installations/${installationId}/enroll`,
    {
      method: "POST",
      headers: {
        "content-type": "application/json",
        authorization: "Bearer operator-test",
      },
      body: JSON.stringify(payload),
    },
  );
}

function buildEntitleRequest(
  installationId: string = FIXTURE_INSTALLATION_ID,
  payload: EntitlePayload = DEFAULT_ENTITLE_PAYLOAD,
  bearerToken: string = "operator-test",
): Request {
  return new Request(
    `${GATEWAY_ORIGIN}/control/installations/${installationId}/entitle`,
    {
      method: "POST",
      headers: {
        "content-type": "application/json",
        authorization: `Bearer ${bearerToken}`,
      },
      body: JSON.stringify(payload),
    },
  );
}

async function enrollFixture(
  handlers: ControlHandlers,
  operatorAuth: OperatorAuth = createFakeOperatorAuth(),
  installationId: string = FIXTURE_INSTALLATION_ID,
): Promise<void> {
  const response = await handlers.handleEnroll(
    buildEnrollRequest(installationId),
    bindings(),
    operatorAuth,
  );
  expect(response.ok).toBe(true);
}

function makePlatformD1Reader(db: D1Database): D1Reader {
  return {
    async read(prefixedKey: string): Promise<D1Row | "miss"> {
      const separator = prefixedKey.indexOf(":");
      if (separator === -1) {
        return "miss";
      }

      const kind = prefixedKey.slice(0, separator) as ConfigEntityKind;
      const key = prefixedKey.slice(separator + 1);

      switch (kind) {
        case "installations": {
          const row = await db
            .prepare(
              "SELECT installation_id, org_id, display_name, status, region, enrolled_at FROM installation WHERE installation_id = ?",
            )
            .bind(key)
            .first<D1Row>();
          return row ?? "miss";
        }
        case "entitlements": {
          const row = await db
            .prepare(
              `SELECT entitlement_id, installation_id, plan, period_start, period_end,
                      request_quota, token_budget, cost_budget, allowed_capabilities,
                      soft_threshold, status
               FROM entitlement WHERE installation_id = ?`,
            )
            .bind(key)
            .first<D1Row>();
          return row ?? "miss";
        }
        case "grants": {
          let scope: string;
          let capabilityId: string;
          if (key.startsWith("plan:")) {
            const slash = key.lastIndexOf("/");
            if (slash === -1) {
              return "miss";
            }
            scope = key.slice(0, slash);
            capabilityId = key.slice(slash + 1);
          } else {
            const [installationId, capId] = key.split("/", 2);
            if (!installationId || !capId) {
              return "miss";
            }
            scope = `installation:${installationId}`;
            capabilityId = capId;
          }

          const row = await db
            .prepare(
              `SELECT grant_id, scope, capability_id, capability_version,
                      granted_at, revoked_at, changed_at, changed_by
               FROM capability_grant
               WHERE scope = ? AND capability_id = ?
               ORDER BY changed_at DESC LIMIT 1`,
            )
            .bind(scope, capabilityId)
            .first<D1Row>();
          return row ?? "miss";
        }
        case "kill_switches": {
          return { active: false };
        }
        default:
          return "miss";
      }
    },
  };
}

beforeAll(async () => {
  await applyPlatformSchema(env.DB, migrationSql);
});

beforeEach(async () => {
  await clearLifecycleTables();
});

describe("entitle_activate_writes_entitlement_grant_and_audit", () => {
  it("writes entitlement, capability_grant, and control_audit with operator identity", async () => {
    const handlers = await loadControlHandlers();
    const operatorAuth = createFakeOperatorAuth();
    await enrollFixture(handlers, operatorAuth);

    const beforeGrantCount = await env.DB.prepare(
      "SELECT COUNT(*) AS count FROM capability_grant",
    ).first<{ count: number }>();

    const response = await handlers.handleEntitle(
      buildEntitleRequest(),
      bindings(),
      operatorAuth,
    );
    expect(response.ok).toBe(true);

    const entitlement = await env.DB.prepare(
      `SELECT status, allowed_capabilities FROM entitlement WHERE installation_id = ?`,
    )
      .bind(FIXTURE_INSTALLATION_ID)
      .first<{ status: string; allowed_capabilities: string }>();
    expect(entitlement?.status).toBe("active");
    expect(JSON.parse(entitlement?.allowed_capabilities ?? "[]")).toEqual([
      FIXTURE_CAPABILITY_ID,
    ]);

    const grant = await env.DB.prepare(
      `SELECT scope, capability_id, capability_version, revoked_at
       FROM capability_grant WHERE capability_id = ?`,
    )
      .bind(FIXTURE_CAPABILITY_ID)
      .first<{
        scope: string;
        capability_id: string;
        capability_version: string;
        revoked_at: string | null;
      }>();
    expect(grant).toMatchObject({
      scope: `installation:${FIXTURE_INSTALLATION_ID}`,
      capability_id: FIXTURE_CAPABILITY_ID,
      capability_version: FIXTURE_CAPABILITY_VERSION,
      revoked_at: null,
    });

    const afterGrantCount = await env.DB.prepare(
      "SELECT COUNT(*) AS count FROM capability_grant",
    ).first<{ count: number }>();
    expect(afterGrantCount?.count).toBe((beforeGrantCount?.count ?? 0) + 1);

    const audit = await env.DB.prepare(
      "SELECT operator_id, action, target FROM control_audit WHERE action = 'entitle'",
    ).first<{ operator_id: string; action: string; target: string }>();
    expect(audit).toMatchObject({
      operator_id: FAKE_OPERATOR.operatorId,
      action: "entitle",
      target: FIXTURE_INSTALLATION_ID,
    });
  });
});

describe("entitle_sets_budget_fields_admission_reads", () => {
  it("writes budget fields and moves status to active", async () => {
    const handlers = await loadControlHandlers();
    const operatorAuth = createFakeOperatorAuth();
    await enrollFixture(handlers, operatorAuth);

    const response = await handlers.handleEntitle(
      buildEntitleRequest(),
      bindings(),
      operatorAuth,
    );
    expect(response.ok).toBe(true);

    const entitlement = await env.DB.prepare(
      `SELECT plan, period_start, period_end, request_quota, token_budget, cost_budget,
              allowed_capabilities, soft_threshold, status
       FROM entitlement WHERE installation_id = ?`,
    )
      .bind(FIXTURE_INSTALLATION_ID)
      .first<{
        plan: string;
        period_start: string;
        period_end: string;
        request_quota: number;
        token_budget: number;
        cost_budget: number;
        allowed_capabilities: string;
        soft_threshold: number;
        status: string;
      }>();

    expect(entitlement).toMatchObject({
      plan: DEFAULT_ENROLL_PAYLOAD.plan,
      period_start: DEFAULT_ENTITLE_PAYLOAD.period_start,
      period_end: DEFAULT_ENTITLE_PAYLOAD.period_end,
      request_quota: DEFAULT_ENTITLE_PAYLOAD.request_quota,
      token_budget: DEFAULT_ENTITLE_PAYLOAD.token_budget,
      cost_budget: DEFAULT_ENTITLE_PAYLOAD.cost_budget,
      soft_threshold: DEFAULT_ENTITLE_PAYLOAD.soft_threshold,
      status: "active",
    });
    expect(JSON.parse(entitlement?.allowed_capabilities ?? "[]")).toEqual(
      DEFAULT_ENTITLE_PAYLOAD.allowed_capabilities,
    );
  });
});

describe("pending_enroll_fails_entitlement_until_activated", () => {
  it("pending enroll fails evaluateEntitlement until entitle runs", async () => {
    const handlers = await loadControlHandlers();
    const { evaluateEntitlement } = await loadEntitlementHandlers();
    const operatorAuth = createFakeOperatorAuth();
    await enrollFixture(handlers, operatorAuth);

    const cache = new ConfigCache();
    const reader = makePlatformD1Reader(env.DB);
    const principal = {
      installationId: FIXTURE_INSTALLATION_ID,
      organizationId: FIXTURE_ORG_ID,
      branchId: "branch-001",
      actorId: "actor-001",
      role: "clinician",
      scopes: ["ai.visit_summary"],
      jti: "jti-001",
      iat: 1_700_000_000,
      exp: 1_700_000_300,
      ver: "1",
    };
    const ctx = {
      capabilityId: FIXTURE_CAPABILITY_ID,
      capabilityVersion: FIXTURE_CAPABILITY_VERSION,
      minimumPlanTier: "standard",
      providerId: "deepseek",
    };

    const pendingResult = await evaluateEntitlement(
      principal,
      ctx,
      cache,
      reader,
    );
    expect(pendingResult).toEqual({
      ok: false,
      code: "forbidden_capability",
      path: "ai_disabled",
    });

    const entitleResponse = await handlers.handleEntitle(
      buildEntitleRequest(),
      bindings(),
      operatorAuth,
    );
    expect(entitleResponse.ok).toBe(true);

    const activeCache = new ConfigCache();
    const activeResult = await evaluateEntitlement(
      principal,
      ctx,
      activeCache,
      reader,
    );
    expect(activeResult).toEqual({ ok: true });
  });
});

describe("entitle_non_operator_rejected", () => {
  it("rejects non-operator credentials without mutating entitlement or grants", async () => {
    const handlers = await loadControlHandlers();
    const operatorAuth = createFakeOperatorAuth();
    await enrollFixture(handlers, operatorAuth);

    const beforeEntitlement = await env.DB.prepare(
      "SELECT status, request_quota FROM entitlement WHERE installation_id = ?",
    )
      .bind(FIXTURE_INSTALLATION_ID)
      .first<{ status: string; request_quota: number }>();
    const beforeGrantCount = await env.DB.prepare(
      "SELECT COUNT(*) AS count FROM capability_grant",
    ).first<{ count: number }>();

    const response = await handlers.handleEntitle(
      buildEntitleRequest(),
      bindings(),
      createFakeOperatorAuth(null),
    );

    expect(response.status).toBe(401);
    expect(await response.json()).toEqual({ error: "unauthorized" });

    const afterEntitlement = await env.DB.prepare(
      "SELECT status, request_quota FROM entitlement WHERE installation_id = ?",
    )
      .bind(FIXTURE_INSTALLATION_ID)
      .first<{ status: string; request_quota: number }>();
    expect(afterEntitlement).toEqual(beforeEntitlement);

    const afterGrantCount = await env.DB.prepare(
      "SELECT COUNT(*) AS count FROM capability_grant",
    ).first<{ count: number }>();
    expect(afterGrantCount?.count).toBe(beforeGrantCount?.count ?? 0);
  });
});
