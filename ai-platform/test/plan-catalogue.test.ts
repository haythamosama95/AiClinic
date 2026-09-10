import { env } from "cloudflare:test";
import { beforeAll, beforeEach, describe, expect, it, vi } from "vitest";
import migrationSql from "../migrations/20260731120000_platform_schema.sql?raw";
import uniqueEntitlementSql from "../migrations/20260821130000_entitlement_installation_unique.sql?raw";
import planCatalogueSql from "../migrations/20260911120000_plan_catalogue.sql?raw";
import {
  ConfigCache,
  createD1ConfigReader,
  loadConfig,
  type ConfigEntityKind,
} from "../src/config-cache";
import type { ReaderSpy } from "./config-cache.test";
import { assertControlAudit } from "./helpers/control-audit-assert";

declare module "cloudflare:test" {
  interface ProvidedEnv {
    DB: D1Database;
  }
}

const GATEWAY_ORIGIN = "https://ai-gateway.test";
const TEST_OPERATOR_ID = "operator-test-principal";

const FIXTURE_INSTALLATION_ID = "c1000000-0000-4000-8000-000000000020";
const FIXTURE_ORG_ID = "d2000000-0000-4000-8000-000000000021";
const FIXTURE_KID = "f47ac10b-58cc-4372-a567-0e02b2c3d479";
const FIXTURE_PUBLIC_KEY_B64 = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA";
const FIXTURE_CAPABILITY_ID = "clinic.visit_summary";
const FIXTURE_CAPABILITY_VERSION = "1.0.0";
const FIXTURE_PLAN_NAME = "professional";

const PLANS_KIND = "plans" as ConfigEntityKind;

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

type PlanPayload = {
  name: string;
  credit_budget: number;
  request_quota: number;
  max_cost_class: string;
  soft_threshold: number;
  allowed_capabilities: string[];
  status: string;
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

type OverridePayload = {
  credit_budget?: number;
  request_quota?: number;
  token_budget?: number;
  cost_budget?: number;
  period_start?: string;
  period_end?: string;
  soft_threshold?: number;
};

type PlanCatalogueHandlers = {
  handleEnroll: (
    request: Request,
    bindings: ControlBindings,
    operatorAuth: OperatorAuth,
  ) => Promise<Response>;
  handlePlanCreate: (
    request: Request,
    bindings: ControlBindings,
    operatorAuth: OperatorAuth,
  ) => Promise<Response>;
  handlePlanUpdate: (
    request: Request,
    bindings: ControlBindings,
    operatorAuth: OperatorAuth,
  ) => Promise<Response>;
  handlePlanDelete: (
    request: Request,
    bindings: ControlBindings,
    operatorAuth: OperatorAuth,
  ) => Promise<Response>;
  handleEntitle: (
    request: Request,
    bindings: ControlBindings,
    operatorAuth: OperatorAuth,
  ) => Promise<Response>;
  handleOverride: (
    request: Request,
    bindings: ControlBindings,
    operatorAuth: OperatorAuth,
  ) => Promise<Response>;
  dispatchControlRequest: (
    request: Request,
    bindings: ControlBindings,
    operatorAuth: OperatorAuth,
  ) => Promise<Response>;
};

type EnrollPayload = {
  org_id: string;
  display_name: string;
  region: string;
  plan: string;
  public_key: string;
  algorithm: string;
  kid: string;
};

const DEFAULT_ENROLL_PAYLOAD: EnrollPayload = {
  org_id: FIXTURE_ORG_ID,
  display_name: "Plan Catalogue Clinic",
  region: "us-east-1",
  plan: FIXTURE_PLAN_NAME,
  public_key: FIXTURE_PUBLIC_KEY_B64,
  algorithm: "EdDSA",
  kid: FIXTURE_KID,
};

const DEFAULT_PLAN_PAYLOAD: PlanPayload = {
  name: FIXTURE_PLAN_NAME,
  credit_budget: 10_000,
  request_quota: 1_000,
  max_cost_class: "standard",
  soft_threshold: 0.8,
  allowed_capabilities: [FIXTURE_CAPABILITY_ID],
  status: "active",
};

const DEFAULT_ENTITLE_PAYLOAD: EntitlePayload = {
  period_start: "2026-08-01T00:00:00.000Z",
  period_end: "2026-09-01T00:00:00.000Z",
  request_quota: 0,
  token_budget: 500_000,
  cost_budget: 50,
  soft_threshold: 0,
  allowed_capabilities: [],
  grants: [
    {
      capability_id: FIXTURE_CAPABILITY_ID,
      capability_version: FIXTURE_CAPABILITY_VERSION,
      scope: "installation",
    },
  ],
};

async function loadPlanCatalogueHandlers(): Promise<PlanCatalogueHandlers> {
  return import(/* @vite-ignore */ "../src/control") as Promise<PlanCatalogueHandlers>;
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

async function clearCatalogueTables(): Promise<void> {
  await env.DB.batch([
    env.DB.prepare("DELETE FROM control_audit"),
    env.DB.prepare("DELETE FROM capability_grant"),
    env.DB.prepare("DELETE FROM entitlement"),
    env.DB.prepare("DELETE FROM installation_key"),
    env.DB.prepare("DELETE FROM installation"),
    env.DB.prepare("DELETE FROM plan"),
  ]);
}

async function countPlanRows(): Promise<number> {
  try {
    const row = await env.DB.prepare("SELECT COUNT(*) AS count FROM plan").first<{
      count: number;
    }>();
    return row?.count ?? 0;
  } catch {
    return 0;
  }
}

async function countControlAuditRows(): Promise<number> {
  const row = await env.DB.prepare(
    "SELECT COUNT(*) AS count FROM control_audit",
  ).first<{ count: number }>();
  return row?.count ?? 0;
}

function buildPlanCreateRequest(
  payload: PlanPayload = DEFAULT_PLAN_PAYLOAD,
  bearerToken: string = "operator-test",
): Request {
  return new Request(`${GATEWAY_ORIGIN}/control/plans/create`, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      authorization: `Bearer ${bearerToken}`,
    },
    body: JSON.stringify(payload),
  });
}

function buildPlanUpdateRequest(
  name: string = FIXTURE_PLAN_NAME,
  payload: Partial<PlanPayload> = {},
  bearerToken: string = "operator-test",
): Request {
  return new Request(`${GATEWAY_ORIGIN}/control/plans/${name}/update`, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      authorization: `Bearer ${bearerToken}`,
    },
    body: JSON.stringify(payload),
  });
}

function buildPlanDeleteRequest(
  name: string = FIXTURE_PLAN_NAME,
  bearerToken: string = "operator-test",
): Request {
  return new Request(`${GATEWAY_ORIGIN}/control/plans/${name}/delete`, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      authorization: `Bearer ${bearerToken}`,
    },
    body: "{}",
  });
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

function buildOverrideRequest(
  installationId: string = FIXTURE_INSTALLATION_ID,
  payload: OverridePayload = { credit_budget: 20_000 },
  bearerToken: string = "operator-test",
): Request {
  return new Request(
    `${GATEWAY_ORIGIN}/control/installations/${installationId}/override`,
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
  handlers: PlanCatalogueHandlers,
  operatorAuth: OperatorAuth = createFakeOperatorAuth(),
): Promise<void> {
  const response = await handlers.handleEnroll(
    buildEnrollRequest(),
    bindings(),
    operatorAuth,
  );
  expect(response.ok).toBe(true);
}

async function seedCataloguePlan(
  payload: PlanPayload = DEFAULT_PLAN_PAYLOAD,
): Promise<void> {
  await env.DB.prepare(
    `INSERT INTO plan (
      name, credit_budget, request_quota, max_cost_class,
      soft_threshold, allowed_capabilities, status
    ) VALUES (?, ?, ?, ?, ?, ?, ?)`,
  )
    .bind(
      payload.name,
      payload.credit_budget,
      payload.request_quota,
      payload.max_cost_class,
      payload.soft_threshold,
      JSON.stringify(payload.allowed_capabilities),
      payload.status,
    )
    .run();
}

async function seedEntitlementForCacheTest(
  installationId: string = FIXTURE_INSTALLATION_ID,
): Promise<void> {
  await env.DB.prepare(
    `INSERT INTO installation (
      installation_id, org_id, display_name, status, region, enrolled_at
    ) VALUES (?, ?, 'Cache Test Clinic', 'active', 'us-east-1', '2026-08-01T00:00:00.000Z')`,
  )
    .bind(installationId, FIXTURE_ORG_ID)
    .run();

  await env.DB.prepare(
    `INSERT INTO entitlement (
      entitlement_id, installation_id, plan, period_start, period_end,
      request_quota, token_budget, cost_budget, credit_budget, max_cost_class,
      allowed_capabilities, soft_threshold, status
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
  )
    .bind(
      `ent-${installationId}`,
      installationId,
      FIXTURE_PLAN_NAME,
      "2026-08-01T00:00:00.000Z",
      "2026-09-01T00:00:00.000Z",
      1_000,
      500_000,
      50,
      DEFAULT_PLAN_PAYLOAD.credit_budget,
      DEFAULT_PLAN_PAYLOAD.max_cost_class,
      JSON.stringify([FIXTURE_CAPABILITY_ID]),
      0.8,
      "active",
    )
    .run();
}

function spiedProductionReader(db: D1Database): ReaderSpy {
  const inner = createD1ConfigReader(db);
  const read = vi.fn((key: string) => inner.read(key));
  return {
    read,
    readCount: () => read.mock.calls.length,
  };
}

async function warmConfigEntry(
  cache: ConfigCache,
  reader: ReaderSpy,
  kind: ConfigEntityKind,
  key: string,
): Promise<void> {
  await loadConfig(cache, reader, kind, key);
  reader.read.mockClear();
}

beforeAll(async () => {
  await applyPlatformSchema(env.DB, migrationSql);
  await applyPlatformSchema(env.DB, uniqueEntitlementSql);
  await applyPlatformSchema(env.DB, planCatalogueSql);
});

beforeEach(async () => {
  await clearCatalogueTables();
});

describe("plan_create_audit", () => {
  it("writes a plan row and control_audit with operator identity", async () => {
    const handlers = await loadPlanCatalogueHandlers();
    const operatorAuth = createFakeOperatorAuth();
    const beforePlanCount = await countPlanRows();
    const beforeAuditCount = await countControlAuditRows();

    const response = await handlers.handlePlanCreate(
      buildPlanCreateRequest(),
      bindings(),
      operatorAuth,
    );
    expect(response.ok).toBe(true);

    expect(await countPlanRows()).toBe(beforePlanCount + 1);

    const plan = await env.DB.prepare(
      `SELECT name, credit_budget, request_quota, max_cost_class, soft_threshold,
              allowed_capabilities, status
       FROM plan WHERE name = ?`,
    )
      .bind(FIXTURE_PLAN_NAME)
      .first<{
        name: string;
        credit_budget: number;
        request_quota: number;
        max_cost_class: string;
        soft_threshold: number;
        allowed_capabilities: string;
        status: string;
      }>();

    expect(plan).toMatchObject({
      name: DEFAULT_PLAN_PAYLOAD.name,
      credit_budget: DEFAULT_PLAN_PAYLOAD.credit_budget,
      request_quota: DEFAULT_PLAN_PAYLOAD.request_quota,
      max_cost_class: DEFAULT_PLAN_PAYLOAD.max_cost_class,
      soft_threshold: DEFAULT_PLAN_PAYLOAD.soft_threshold,
      status: DEFAULT_PLAN_PAYLOAD.status,
    });
    expect(JSON.parse(plan?.allowed_capabilities ?? "[]")).toEqual(
      DEFAULT_PLAN_PAYLOAD.allowed_capabilities,
    );

    expect(await countControlAuditRows()).toBe(beforeAuditCount + 1);
    await assertControlAudit(env.DB, {
      operatorId: FAKE_OPERATOR.operatorId,
      action: "plan_create",
      target: FIXTURE_PLAN_NAME,
    });
  });
});

describe("plan_update_audit", () => {
  it("updates the plan row and journals control_audit with operator identity", async () => {
    const handlers = await loadPlanCatalogueHandlers();
    const operatorAuth = createFakeOperatorAuth();

    expect(
      (
        await handlers.handlePlanCreate(
          buildPlanCreateRequest(),
          bindings(),
          operatorAuth,
        )
      ).ok,
    ).toBe(true);

    const beforeAuditCount = await countControlAuditRows();
    const updatedQuota = 2_500;

    const response = await handlers.handlePlanUpdate(
      buildPlanUpdateRequest(FIXTURE_PLAN_NAME, {
        credit_budget: 15_000,
        request_quota: updatedQuota,
        max_cost_class: "premium",
        soft_threshold: 0.9,
        allowed_capabilities: [FIXTURE_CAPABILITY_ID],
        status: "active",
      }),
      bindings(),
      operatorAuth,
    );
    expect(response.ok).toBe(true);

    const plan = await env.DB.prepare(
      `SELECT credit_budget, request_quota, max_cost_class, soft_threshold
       FROM plan WHERE name = ?`,
    )
      .bind(FIXTURE_PLAN_NAME)
      .first<{
        credit_budget: number;
        request_quota: number;
        max_cost_class: string;
        soft_threshold: number;
      }>();

    expect(plan).toMatchObject({
      credit_budget: 15_000,
      request_quota: updatedQuota,
      max_cost_class: "premium",
      soft_threshold: 0.9,
    });

    expect(await countControlAuditRows()).toBe(beforeAuditCount + 1);
    await assertControlAudit(env.DB, {
      operatorId: FAKE_OPERATOR.operatorId,
      action: "plan_update",
      target: FIXTURE_PLAN_NAME,
    });
  });
});

describe("plan_delete_audit", () => {
  it("journals plan_delete with operator identity and retains the plan row", async () => {
    const handlers = await loadPlanCatalogueHandlers();
    const operatorAuth = createFakeOperatorAuth();

    expect(
      (
        await handlers.handlePlanCreate(
          buildPlanCreateRequest(),
          bindings(),
          operatorAuth,
        )
      ).ok,
    ).toBe(true);

    const beforePlanCount = await countPlanRows();
    const beforeAuditCount = await countControlAuditRows();

    const response = await handlers.handlePlanDelete(
      buildPlanDeleteRequest(),
      bindings(),
      operatorAuth,
    );
    expect(response.ok).toBe(true);

    expect(await countPlanRows()).toBe(beforePlanCount);
    expect(await countControlAuditRows()).toBe(beforeAuditCount + 1);
    await assertControlAudit(env.DB, {
      operatorId: FAKE_OPERATOR.operatorId,
      action: "plan_delete",
      target: FIXTURE_PLAN_NAME,
    });
  });
});

describe("plan_crud_non_operator_rejected", () => {
  it("rejects create, update, and delete without operator credentials", async () => {
    const handlers = await loadPlanCatalogueHandlers();
    const rejectAuth = createFakeOperatorAuth(null);

    const mutations: Array<{
      label: string;
      invoke: () => Promise<Response>;
    }> = [
      {
        label: "create",
        invoke: () =>
          handlers.handlePlanCreate(
            buildPlanCreateRequest(),
            bindings(),
            rejectAuth,
          ),
      },
      {
        label: "update",
        invoke: () =>
          handlers.handlePlanUpdate(
            buildPlanUpdateRequest("other-plan", { request_quota: 1 }),
            bindings(),
            rejectAuth,
          ),
      },
      {
        label: "delete",
        invoke: () =>
          handlers.handlePlanDelete(
            buildPlanDeleteRequest("other-plan"),
            bindings(),
            rejectAuth,
          ),
      },
    ];

    for (const mutation of mutations) {
      const beforePlanCount = await countPlanRows();
      const beforeAuditCount = await countControlAuditRows();

      const response = await mutation.invoke();

      expect(response.ok, `${mutation.label} should reject non-operator`).toBe(
        false,
      );
      expect(response.status, `${mutation.label} status`).toBe(401);
      expect(await response.json(), `${mutation.label} body`).toEqual({
        error: "unauthorized",
      });
      expect(await countPlanRows(), `${mutation.label} plan rows`).toBe(
        beforePlanCount,
      );
      expect(await countControlAuditRows(), `${mutation.label} audit rows`).toBe(
        beforeAuditCount,
      );
    }
  });
});

describe("assign_plan_populates_economics_one_audited_mutation", () => {
  it("copies catalogue economics onto a pending entitlement in one audited mutation", async () => {
    const handlers = await loadPlanCatalogueHandlers();
    const operatorAuth = createFakeOperatorAuth();

    expect(
      (
        await handlers.handlePlanCreate(
          buildPlanCreateRequest(),
          bindings(),
          operatorAuth,
        )
      ).ok,
    ).toBe(true);

    await enrollFixture(handlers, operatorAuth);

    const pending = await env.DB.prepare(
      "SELECT status FROM entitlement WHERE installation_id = ?",
    )
      .bind(FIXTURE_INSTALLATION_ID)
      .first<{ status: string }>();
    expect(pending?.status).toBe("pending");

    const beforeAuditCount = await countControlAuditRows();

    const response = await handlers.handleEntitle(
      buildEntitleRequest(),
      bindings(),
      operatorAuth,
    );
    expect(response.ok).toBe(true);

    const entitlement = await env.DB.prepare(
      `SELECT credit_budget, request_quota, max_cost_class, soft_threshold,
              allowed_capabilities, status
       FROM entitlement WHERE installation_id = ?`,
    )
      .bind(FIXTURE_INSTALLATION_ID)
      .first<{
        credit_budget: number;
        request_quota: number;
        max_cost_class: string;
        soft_threshold: number;
        allowed_capabilities: string;
        status: string;
      }>();

    expect(entitlement).toMatchObject({
      credit_budget: DEFAULT_PLAN_PAYLOAD.credit_budget,
      request_quota: DEFAULT_PLAN_PAYLOAD.request_quota,
      max_cost_class: DEFAULT_PLAN_PAYLOAD.max_cost_class,
      soft_threshold: DEFAULT_PLAN_PAYLOAD.soft_threshold,
      status: "active",
    });
    expect(JSON.parse(entitlement?.allowed_capabilities ?? "[]")).toEqual(
      DEFAULT_PLAN_PAYLOAD.allowed_capabilities,
    );

    expect(await countControlAuditRows()).toBe(beforeAuditCount + 1);
    await assertControlAudit(env.DB, {
      operatorId: FAKE_OPERATOR.operatorId,
      action: "entitle",
      target: FIXTURE_INSTALLATION_ID,
    });
  });
});

describe("per_installation_override_recorded_as_such", () => {
  it("journals override distinctly from plan assignment", async () => {
    const handlers = await loadPlanCatalogueHandlers();
    const operatorAuth = createFakeOperatorAuth();

    expect(
      (
        await handlers.handlePlanCreate(
          buildPlanCreateRequest(),
          bindings(),
          operatorAuth,
        )
      ).ok,
    ).toBe(true);

    await enrollFixture(handlers, operatorAuth);
    expect(
      (await handlers.handleEntitle(buildEntitleRequest(), bindings(), operatorAuth))
        .ok,
    ).toBe(true);

    const beforeAuditCount = await countControlAuditRows();

    const response = await handlers.handleOverride(
      buildOverrideRequest(),
      bindings(),
      operatorAuth,
    );
    expect(response.ok).toBe(true);

    const entitlement = await env.DB.prepare(
      "SELECT credit_budget FROM entitlement WHERE installation_id = ?",
    )
      .bind(FIXTURE_INSTALLATION_ID)
      .first<{ credit_budget: number }>();
    expect(entitlement?.credit_budget).toBe(20_000);

    expect(await countControlAuditRows()).toBe(beforeAuditCount + 1);
    await assertControlAudit(env.DB, {
      operatorId: FAKE_OPERATOR.operatorId,
      action: "override",
      target: FIXTURE_INSTALLATION_ID,
    });

    const entitleAudits = await env.DB.prepare(
      "SELECT COUNT(*) AS count FROM control_audit WHERE action = 'entitle'",
    ).first<{ count: number }>();
    const overrideAudits = await env.DB.prepare(
      "SELECT COUNT(*) AS count FROM control_audit WHERE action = 'override'",
    ).first<{ count: number }>();
    expect(entitleAudits?.count).toBe(1);
    expect(overrideAudits?.count).toBe(1);
  });
});

describe("assignment_non_operator_rejected", () => {
  it("rejects assign-plan and override without operator credentials", async () => {
    const handlers = await loadPlanCatalogueHandlers();
    const operatorAuth = createFakeOperatorAuth();

    await enrollFixture(handlers, operatorAuth);

    const rejectAuth = createFakeOperatorAuth(null);
    const beforeEntitlement = await env.DB.prepare(
      `SELECT status, request_quota FROM entitlement WHERE installation_id = ?`,
    )
      .bind(FIXTURE_INSTALLATION_ID)
      .first<{
        status: string;
        request_quota: number;
      }>();
    const beforeAuditCount = await countControlAuditRows();

    const entitleResponse = await handlers.handleEntitle(
      buildEntitleRequest(),
      bindings(),
      rejectAuth,
    );
    expect(entitleResponse.status).toBe(401);
    expect(await entitleResponse.json()).toEqual({ error: "unauthorized" });

    const overrideResponse = await handlers.dispatchControlRequest(
      buildOverrideRequest(),
      bindings(),
      rejectAuth,
    );
    expect(overrideResponse.status).toBe(401);
    expect(await overrideResponse.json()).toEqual({ error: "unauthorized" });

    const afterEntitlement = await env.DB.prepare(
      `SELECT status, request_quota FROM entitlement WHERE installation_id = ?`,
    )
      .bind(FIXTURE_INSTALLATION_ID)
      .first<{
        status: string;
        request_quota: number;
      }>();
    expect(afterEntitlement).toEqual(beforeEntitlement);
    expect(await countControlAuditRows()).toBe(beforeAuditCount);
  });
});

describe("config_cache_plan_cold_one_d1_read", () => {
  it("serves a plan from a cold isolate with exactly one D1 read", async () => {
    await seedCataloguePlan();

    const cache = new ConfigCache();
    const reader = spiedProductionReader(env.DB);

    const row = await loadConfig(cache, reader, PLANS_KIND, FIXTURE_PLAN_NAME);

    expect(reader.readCount()).toBe(1);
    expect(row.name).toBe(FIXTURE_PLAN_NAME);
    expect(row.credit_budget).toBe(DEFAULT_PLAN_PAYLOAD.credit_budget);
  });
});

describe("config_cache_plan_warm_zero_io", () => {
  it("serves a warm plan entry with zero reader I/O", async () => {
    await seedCataloguePlan();

    const cache = new ConfigCache();
    const reader = spiedProductionReader(env.DB);

    await warmConfigEntry(cache, reader, PLANS_KIND, FIXTURE_PLAN_NAME);
    const row = await loadConfig(cache, reader, PLANS_KIND, FIXTURE_PLAN_NAME);

    expect(reader.readCount()).toBe(0);
    expect(row.name).toBe(FIXTURE_PLAN_NAME);
  });
});

describe("config_cache_entitlement_cold_one_d1_read", () => {
  it("serves an entitlement including credit_budget with exactly one D1 read", async () => {
    await seedEntitlementForCacheTest();

    const cache = new ConfigCache();
    const reader = spiedProductionReader(env.DB);

    const row = await loadConfig(
      cache,
      reader,
      "entitlements",
      FIXTURE_INSTALLATION_ID,
    );

    expect(reader.readCount()).toBe(1);
    expect(row.credit_budget).toBe(10_000);
    expect(row.max_cost_class).toBe("standard");
  });
});

describe("config_cache_entitlement_warm_zero_io", () => {
  it("serves a warm entitlement entry with zero reader I/O", async () => {
    await seedEntitlementForCacheTest();

    const cache = new ConfigCache();
    const reader = spiedProductionReader(env.DB);

    await warmConfigEntry(cache, reader, "entitlements", FIXTURE_INSTALLATION_ID);
    const row = await loadConfig(
      cache,
      reader,
      "entitlements",
      FIXTURE_INSTALLATION_ID,
    );

    expect(reader.readCount()).toBe(0);
    expect(row.credit_budget).toBe(10_000);
  });
});
