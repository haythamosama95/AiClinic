import { env } from "cloudflare:test";
import { beforeAll, beforeEach, describe, expect, it } from "vitest";
import migrationSql from "../migrations/20260731120000_platform_schema.sql?raw";

declare module "cloudflare:test" {
  interface ProvidedEnv {
    DB: D1Database;
  }
}

const GATEWAY_ORIGIN = "https://ai-gateway.test";

export type OperatorPrincipal = {
  operatorId: string;
};

/** Port seam matching `src/control/index.ts` `OperatorAuth` (Clarification Q2). */
export type OperatorAuth = {
  resolve(_request: Request): OperatorPrincipal | null;
};

const FAKE_OPERATOR: OperatorPrincipal = {
  operatorId: "operator-test-principal",
};

/** Fake `OperatorAuth` returning a fixed operator principal or `null`. */
export function createFakeOperatorAuth(
  principal: OperatorPrincipal | null = FAKE_OPERATOR,
): OperatorAuth {
  return {
    resolve() {
      return principal;
    },
  };
}

type ControlBindings = { DB: D1Database };

type ControlHandlers = {
  handleEnroll: (
    request: Request,
    bindings: ControlBindings,
    operatorAuth: OperatorAuth,
  ) => Promise<Response>;
  handleRotate: (
    request: Request,
    bindings: ControlBindings,
    operatorAuth: OperatorAuth,
  ) => Promise<Response>;
  handleSuspend: (
    request: Request,
    bindings: ControlBindings,
    operatorAuth: OperatorAuth,
  ) => Promise<Response>;
  handleResume: (
    request: Request,
    bindings: ControlBindings,
    operatorAuth: OperatorAuth,
  ) => Promise<Response>;
  handleDelete: (
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

type TableCounts = {
  installation: number;
  installation_key: number;
  entitlement: number;
  control_audit: number;
};

const FIXTURE_INSTALLATION_ID = "inst-test-001";
const FIXTURE_ORG_ID = "org-test-001";

const DEFAULT_ENROLL_PAYLOAD: EnrollPayload = {
  org_id: FIXTURE_ORG_ID,
  display_name: "Test Clinic",
  region: "us-east-1",
  plan: "starter",
  public_key: "dGVzdC1wdWJsaWMta2V5",
  algorithm: "EdDSA",
  kid: "kid-test-001",
};

/** Loads lifecycle handlers from `src/control/` (absent until Phase 3). */
async function loadControlHandlers(): Promise<ControlHandlers> {
  return import(/* @vite-ignore */ "../src/control") as Promise<ControlHandlers>;
}

function bindings(): ControlBindings {
  return { DB: env.DB };
}

async function readTableCounts(): Promise<TableCounts> {
  const [installation, installation_key, entitlement, control_audit] =
    await Promise.all([
      env.DB.prepare("SELECT COUNT(*) AS count FROM installation")
        .first<{ count: number }>(),
      env.DB.prepare("SELECT COUNT(*) AS count FROM installation_key")
        .first<{ count: number }>(),
      env.DB.prepare("SELECT COUNT(*) AS count FROM entitlement")
        .first<{ count: number }>(),
      env.DB.prepare("SELECT COUNT(*) AS count FROM control_audit")
        .first<{ count: number }>(),
    ]);

  return {
    installation: installation?.count ?? 0,
    installation_key: installation_key?.count ?? 0,
    entitlement: entitlement?.count ?? 0,
    control_audit: control_audit?.count ?? 0,
  };
}

async function clearLifecycleTables(): Promise<void> {
  await env.DB.batch([
    env.DB.prepare("DELETE FROM control_audit"),
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

function buildLifecycleRequest(
  installationId: string,
  action: "rotate" | "suspend" | "resume" | "delete",
  body?: Record<string, unknown>,
): Request {
  return new Request(
    `${GATEWAY_ORIGIN}/control/installations/${installationId}/${action}`,
    {
      method: "POST",
      headers: {
        "content-type": "application/json",
        authorization: "Bearer operator-test",
      },
      body: body ? JSON.stringify(body) : "{}",
    },
  );
}

async function enrollFixture(
  handlers: ControlHandlers,
  operatorAuth: OperatorAuth = createFakeOperatorAuth(),
  installationId: string = FIXTURE_INSTALLATION_ID,
  payload: EnrollPayload = DEFAULT_ENROLL_PAYLOAD,
): Promise<Response> {
  const response = await handlers.handleEnroll(
    buildEnrollRequest(installationId, payload),
    bindings(),
    operatorAuth,
  );
  expect(response.ok).toBe(true);
  return response;
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

beforeAll(async () => {
  await applyPlatformSchema(env.DB, migrationSql);
});

beforeEach(async () => {
  await clearLifecycleTables();
});

describe("enroll_writes_all_four_tables", () => {
  it("writes installation, key, entitlement, and audit rows", async () => {
    const { handleEnroll } = await loadControlHandlers();
    const operatorAuth = createFakeOperatorAuth();

    const response = await handleEnroll(
      buildEnrollRequest(),
      bindings(),
      operatorAuth,
    );

    expect(response.ok).toBe(true);

    const counts = await readTableCounts();
    expect(counts).toEqual({
      installation: 1,
      installation_key: 1,
      entitlement: 1,
      control_audit: 1,
    });

    const installation = await env.DB.prepare(
      "SELECT installation_id, org_id, display_name, status, region, enrolled_at FROM installation",
    ).first<{
      installation_id: string;
      org_id: string;
      display_name: string;
      status: string;
      region: string;
      enrolled_at: string;
    }>();
    expect(installation).toMatchObject({
      installation_id: FIXTURE_INSTALLATION_ID,
      org_id: FIXTURE_ORG_ID,
      display_name: DEFAULT_ENROLL_PAYLOAD.display_name,
      region: DEFAULT_ENROLL_PAYLOAD.region,
    });
    expect(installation?.status).toBeTruthy();
    expect(installation?.enrolled_at).toBeTruthy();

    const installationKey = await env.DB.prepare(
      "SELECT key_id, installation_id, public_key, algorithm, valid_from, valid_until, revoked_at FROM installation_key",
    ).first<{
      key_id: string;
      installation_id: string;
      public_key: string;
      algorithm: string;
      valid_from: string;
      valid_until: string | null;
      revoked_at: string | null;
    }>();
    expect(installationKey).toMatchObject({
      key_id: DEFAULT_ENROLL_PAYLOAD.kid,
      installation_id: FIXTURE_INSTALLATION_ID,
      public_key: DEFAULT_ENROLL_PAYLOAD.public_key,
      algorithm: DEFAULT_ENROLL_PAYLOAD.algorithm,
    });
    expect(installationKey?.valid_from).toBeTruthy();

    const entitlement = await env.DB.prepare(
      `SELECT plan, period_start, period_end, request_quota, token_budget, cost_budget,
              allowed_capabilities, soft_threshold, status
       FROM entitlement`,
    ).first<{
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
      request_quota: 0,
      token_budget: 0,
      cost_budget: 0,
      allowed_capabilities: "[]",
      soft_threshold: 0,
      status: "pending",
    });
    expect(entitlement?.period_start).toBeTruthy();
    expect(entitlement?.period_start).toBe(entitlement?.period_end);

    const audit = await env.DB.prepare(
      "SELECT operator_id, action, target FROM control_audit",
    ).first<{
      operator_id: string;
      action: string;
      target: string;
    }>();
    expect(audit).toMatchObject({
      operator_id: FAKE_OPERATOR.operatorId,
      action: "enroll",
    });
    expect(audit?.target).toBeTruthy();

    const body = (await response.json()) as { platform_base_url?: string };
    expect(body.platform_base_url).toBe(GATEWAY_ORIGIN);
  });
});

describe("lifecycle_suspend_audit", () => {
  it("writes suspend audit and sets installation status", async () => {
    const handlers = await loadControlHandlers();
    const operatorAuth = createFakeOperatorAuth();

    await enrollFixture(handlers, operatorAuth);

    const beforeCounts = await readTableCounts();

    const response = await handlers.handleSuspend(
      buildLifecycleRequest(FIXTURE_INSTALLATION_ID, "suspend"),
      bindings(),
      operatorAuth,
    );
    expect(response.ok).toBe(true);

    const afterCounts = await readTableCounts();
    expect(afterCounts.control_audit).toBe(beforeCounts.control_audit + 1);

    const installation = await env.DB.prepare(
      "SELECT status FROM installation WHERE installation_id = ?",
    )
      .bind(FIXTURE_INSTALLATION_ID)
      .first<{ status: string }>();
    expect(installation?.status).toBe("suspended");

    const audit = await env.DB.prepare(
      "SELECT operator_id, action FROM control_audit WHERE action = 'suspend'",
    ).first<{ operator_id: string; action: string }>();
    expect(audit).toMatchObject({
      operator_id: FAKE_OPERATOR.operatorId,
      action: "suspend",
    });
  });
});

describe("lifecycle_resume_audit", () => {
  it("writes resume audit and restores active status", async () => {
    const handlers = await loadControlHandlers();
    const operatorAuth = createFakeOperatorAuth();

    await enrollFixture(handlers, operatorAuth);

    const enrolled = await env.DB.prepare(
      "SELECT status FROM installation WHERE installation_id = ?",
    )
      .bind(FIXTURE_INSTALLATION_ID)
      .first<{ status: string }>();
    const priorActiveStatus = enrolled?.status;
    expect(priorActiveStatus).toBeTruthy();

    await handlers.handleSuspend(
      buildLifecycleRequest(FIXTURE_INSTALLATION_ID, "suspend"),
      bindings(),
      operatorAuth,
    );

    const beforeCounts = await readTableCounts();

    const response = await handlers.handleResume(
      buildLifecycleRequest(FIXTURE_INSTALLATION_ID, "resume"),
      bindings(),
      operatorAuth,
    );
    expect(response.ok).toBe(true);

    const afterCounts = await readTableCounts();
    expect(afterCounts.control_audit).toBe(beforeCounts.control_audit + 1);

    const installation = await env.DB.prepare(
      "SELECT status FROM installation WHERE installation_id = ?",
    )
      .bind(FIXTURE_INSTALLATION_ID)
      .first<{ status: string }>();
    expect(installation?.status).toBe(priorActiveStatus);

    const audit = await env.DB.prepare(
      "SELECT operator_id, action FROM control_audit WHERE action = 'resume'",
    ).first<{ operator_id: string; action: string }>();
    expect(audit).toMatchObject({
      operator_id: FAKE_OPERATOR.operatorId,
      action: "resume",
    });
  });
});

describe("lifecycle_rotate_audit", () => {
  it("adds a new key row and writes rotate audit", async () => {
    const handlers = await loadControlHandlers();
    const operatorAuth = createFakeOperatorAuth();

    await enrollFixture(handlers, operatorAuth);

    const beforeCounts = await readTableCounts();
    expect(beforeCounts.installation_key).toBe(1);

    const rotateKid = "kid-test-002";
    const response = await handlers.handleRotate(
      buildLifecycleRequest(FIXTURE_INSTALLATION_ID, "rotate", {
        kid: rotateKid,
        public_key: "bmV3LXB1YmxpYy1rZXk=",
        algorithm: "EdDSA",
      }),
      bindings(),
      operatorAuth,
    );
    expect(response.ok).toBe(true);

    const afterCounts = await readTableCounts();
    expect(afterCounts.installation_key).toBe(2);
    expect(afterCounts.control_audit).toBe(beforeCounts.control_audit + 1);

    const keys = await env.DB.prepare(
      "SELECT key_id FROM installation_key WHERE installation_id = ? ORDER BY key_id",
    )
      .bind(FIXTURE_INSTALLATION_ID)
      .all<{ key_id: string }>();
    expect(keys.results?.map((row) => row.key_id)).toEqual([
      DEFAULT_ENROLL_PAYLOAD.kid,
      rotateKid,
    ]);

    const audit = await env.DB.prepare(
      "SELECT operator_id, action FROM control_audit WHERE action = 'rotate'",
    ).first<{ operator_id: string; action: string }>();
    expect(audit).toMatchObject({
      operator_id: FAKE_OPERATOR.operatorId,
      action: "rotate",
    });
  });
});

describe("lifecycle_delete_audit", () => {
  it("writes delete audit and transitions lifecycle status", async () => {
    const handlers = await loadControlHandlers();
    const operatorAuth = createFakeOperatorAuth();

    await enrollFixture(handlers, operatorAuth);

    const beforeCounts = await readTableCounts();
    expect(beforeCounts.installation).toBe(1);

    const response = await handlers.handleDelete(
      buildLifecycleRequest(FIXTURE_INSTALLATION_ID, "delete"),
      bindings(),
      operatorAuth,
    );
    expect(response.ok).toBe(true);

    const afterCounts = await readTableCounts();
    expect(afterCounts.installation).toBe(1);
    expect(afterCounts.control_audit).toBe(beforeCounts.control_audit + 1);

    const installation = await env.DB.prepare(
      "SELECT status FROM installation WHERE installation_id = ?",
    )
      .bind(FIXTURE_INSTALLATION_ID)
      .first<{ status: string }>();
    expect(installation?.status).not.toBe("active");
    expect(installation?.status).toBeTruthy();

    const audit = await env.DB.prepare(
      "SELECT operator_id, action FROM control_audit WHERE action = 'delete'",
    ).first<{ operator_id: string; action: string }>();
    expect(audit).toMatchObject({
      operator_id: FAKE_OPERATOR.operatorId,
      action: "delete",
    });
  });
});

describe("non_operator_credentials_rejected", () => {
  it("rejects all five mutations without D1 writes", async () => {
    const handlers = await loadControlHandlers();
    const rejectAuth = createFakeOperatorAuth(null);

    const mutations: Array<{
      label: string;
      invoke: () => Promise<Response>;
    }> = [
      {
        label: "enroll",
        invoke: () =>
          handlers.handleEnroll(
            buildEnrollRequest("inst-reject-001", {
              ...DEFAULT_ENROLL_PAYLOAD,
              org_id: "org-reject-001",
              kid: "kid-reject-001",
            }),
            bindings(),
            rejectAuth,
          ),
      },
      {
        label: "rotate",
        invoke: () =>
          handlers.handleRotate(
            buildLifecycleRequest("inst-reject-002", "rotate", {
              kid: "kid-reject-rotate",
              public_key: "cHVibGlj",
              algorithm: "EdDSA",
            }),
            bindings(),
            rejectAuth,
          ),
      },
      {
        label: "suspend",
        invoke: () =>
          handlers.handleSuspend(
            buildLifecycleRequest("inst-reject-003", "suspend"),
            bindings(),
            rejectAuth,
          ),
      },
      {
        label: "resume",
        invoke: () =>
          handlers.handleResume(
            buildLifecycleRequest("inst-reject-004", "resume"),
            bindings(),
            rejectAuth,
          ),
      },
      {
        label: "delete",
        invoke: () =>
          handlers.handleDelete(
            buildLifecycleRequest("inst-reject-005", "delete"),
            bindings(),
            rejectAuth,
          ),
      },
    ];

    for (const mutation of mutations) {
      const beforeCounts = await readTableCounts();

      const response = await mutation.invoke();

      expect(response.ok, `${mutation.label} should reject non-operator`).toBe(
        false,
      );
      expect(
        response.status,
        `${mutation.label} should be terminal non-2xx`,
      ).toBeGreaterThanOrEqual(400);

      const afterCounts = await readTableCounts();
      expect(afterCounts, `${mutation.label} must not write D1 rows`).toEqual(
        beforeCounts,
      );
    }
  });
});

describe("duplicate_enrollment_deterministic", () => {
  it("rejects duplicate enroll without changing row counts", async () => {
    const { handleEnroll } = await loadControlHandlers();
    const operatorAuth = createFakeOperatorAuth();

    const firstResponse = await handleEnroll(
      buildEnrollRequest(),
      bindings(),
      operatorAuth,
    );
    expect(firstResponse.ok).toBe(true);

    const countsAfterFirst = await readTableCounts();

    const duplicateResponse = await handleEnroll(
      buildEnrollRequest(),
      bindings(),
      operatorAuth,
    );
    expect(duplicateResponse.ok).toBe(false);
    expect(duplicateResponse.status).toBeGreaterThanOrEqual(400);

    const countsAfterDuplicate = await readTableCounts();
    expect(countsAfterDuplicate).toEqual(countsAfterFirst);
  });
});
