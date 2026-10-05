import { env, SELF } from "cloudflare:test";
import { beforeAll, beforeEach, describe, expect, it } from "vitest";
import migrationSql from "../migrations/20260731120000_platform_schema.sql?raw";
import issuerKeyTenantBindingMigrationSql from "../migrations/20261003130000_issuer_key_tenant_binding.sql?raw";
import planVersionPaidGrantCoverageMigrationSql from "../migrations/20261003140000_plan_version_paid_grant_coverage.sql?raw";
import usageTermMigrationSql from "../migrations/20261006120000_usage_term.sql?raw";
import { applySqlStatements } from "../split-sql-statements";

declare module "cloudflare:test" {
  interface ProvidedEnv {
    DB: D1Database;
    R2: R2Bucket;
    OPERATOR_BEARER_TOKEN: string;
    OPERATOR_ID: string;
  }
}

const TEST_OPERATOR_BEARER = "test-operator-bearer-token";
const TEST_OPERATOR_ID = "operator-test-principal";

const GATEWAY_ORIGIN = "https://ai-gateway.test";

export type OperatorPrincipal = {
  operatorId: string;
};

/** Port seam matching `src/control/index.ts` `OperatorAuth` (Clarification Q2). */
export type OperatorAuth = {
  resolve(_request: Request): OperatorPrincipal | null;
};

const FAKE_OPERATOR: OperatorPrincipal = {
  operatorId: TEST_OPERATOR_ID,
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
  createSecretOperatorAuth: (options: {
    bearerToken: string;
    operatorId: string;
  }) => OperatorAuth;
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

type TableCounts = {
  installation: number;
  tenant_binding: number;
  entitlement: number;
  control_audit: number;
};

const FIXTURE_INSTALLATION_ID = "a1b2c3d4-e5f6-7890-abcd-ef1234567890";
const FIXTURE_INSTALLATION_ID_2 = "b1b2c3d4-e5f6-7890-abcd-ef1234567891";
const FIXTURE_ORG_ID = "d2000000-0000-4000-8000-000000000001";
const FIXTURE_KID = "f47ac10b-58cc-4372-a567-0e02b2c3d479";
const FIXTURE_KID_2 = "a47ac10b-58cc-4372-a567-0e02b2c3d480";
const FIXTURE_PUBLIC_KEY_B64 = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA";
const FIXTURE_PUBLIC_KEY_B64_ALT =
  "AZeVzdEsbUSAw3kOR7Vn6D6oZB03vUIyQvk-Mq2mwLc";

const DEFAULT_ENROLL_PAYLOAD: EnrollPayload = {
  org_id: FIXTURE_ORG_ID,
  display_name: "Test Clinic",
  region: "us-east-1",
  plan: "starter",
  public_key: FIXTURE_PUBLIC_KEY_B64,
  algorithm: "EdDSA",
  kid: FIXTURE_KID,
};

/** Loads lifecycle handlers from `src/control/` (absent until Phase 3). */
async function loadControlHandlers(): Promise<ControlHandlers> {
  return import(/* @vite-ignore */ "../src/control") as Promise<ControlHandlers>;
}

function bindings(): ControlBindings {
  return { DB: env.DB };
}

async function readTableCounts(): Promise<TableCounts> {
  const [installation, tenant_binding, entitlement, control_audit] =
    await Promise.all([
      env.DB.prepare("SELECT COUNT(*) AS count FROM installation")
        .first<{ count: number }>(),
      env.DB.prepare("SELECT COUNT(*) AS count FROM tenant_binding")
        .first<{ count: number }>(),
      env.DB.prepare("SELECT COUNT(*) AS count FROM entitlement")
        .first<{ count: number }>(),
      env.DB.prepare("SELECT COUNT(*) AS count FROM control_audit")
        .first<{ count: number }>(),
    ]);

  return {
    installation: installation?.count ?? 0,
    tenant_binding: tenant_binding?.count ?? 0,
    entitlement: entitlement?.count ?? 0,
    control_audit: control_audit?.count ?? 0,
  };
}

async function clearLifecycleTables(): Promise<void> {
  await env.DB.batch([
    env.DB.prepare("DELETE FROM control_audit"),
    env.DB.prepare("DELETE FROM entitlement"),
    env.DB.prepare("DELETE FROM coverage_event"),
    env.DB.prepare("DELETE FROM grant_ledger"),
    env.DB.prepare("DELETE FROM coverage_mirror"),
    env.DB.prepare("DELETE FROM plan_version"),
    env.DB.prepare("DELETE FROM service_key"),
    env.DB.prepare("DELETE FROM tenant_binding"),
    env.DB.prepare("DELETE FROM issuer_key"),
    env.DB.prepare("DELETE FROM installation"),
  ]);
}

async function seedActiveInstallation(
  installationId: string = FIXTURE_INSTALLATION_ID,
  orgId: string = FIXTURE_ORG_ID,
  options: { pendingEntitlement?: boolean } = {},
): Promise<void> {
  const enrolledAt = new Date().toISOString();
  const statements: D1PreparedStatement[] = [
    env.DB.prepare(
      `INSERT INTO installation (
        installation_id, org_id, display_name, status, region, enrolled_at
      ) VALUES (?, ?, ?, 'active', 'us-east-1', ?)`,
    ).bind(installationId, orgId, DEFAULT_ENROLL_PAYLOAD.display_name, enrolledAt),
    env.DB.prepare(
      `INSERT INTO tenant_binding (
        org_id, installation_id, epoch, status, created_at
      ) VALUES (?, ?, 1, 'active', ?)`,
    ).bind(orgId, installationId, enrolledAt),
  ];
  if (options.pendingEntitlement) {
    statements.push(
      env.DB.prepare(
        `INSERT INTO entitlement (
          entitlement_id, installation_id, plan, period_start, period_end,
          request_quota, token_budget, cost_budget, allowed_capabilities,
          soft_threshold, status
        ) VALUES (?, ?, ?, ?, ?, 0, 0, 0, '[]', 0, 'pending')`,
      ).bind(
        `ent-${installationId}`,
        installationId,
        DEFAULT_ENROLL_PAYLOAD.plan,
        enrolledAt,
        enrolledAt,
      ),
    );
  }
  await env.DB.batch(statements);
}

async function dispatchControl(
  request: Request,
  operatorAuth: OperatorAuth = createFakeOperatorAuth(),
): Promise<Response> {
  const { dispatchControlRequest } = await loadControlHandlers();
  return dispatchControlRequest(request, bindings(), operatorAuth);
}

function buildEnrollRequest(
  installationId: string = FIXTURE_INSTALLATION_ID,
  payload: EnrollPayload = DEFAULT_ENROLL_PAYLOAD,
  bearerToken: string = "operator-test",
): Request {
  return new Request(
    `${GATEWAY_ORIGIN}/control/installations/${installationId}/enroll`,
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

function buildLifecycleRequest(
  installationId: string,
  action: "rotate" | "revoke-key" | "suspend" | "resume" | "delete",
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
  _handlers: ControlHandlers,
  _operatorAuth: OperatorAuth = createFakeOperatorAuth(),
  installationId: string = FIXTURE_INSTALLATION_ID,
  payload: EnrollPayload = DEFAULT_ENROLL_PAYLOAD,
): Promise<void> {
  await seedActiveInstallation(installationId, payload.org_id, {
    pendingEntitlement: true,
  });
}

async function applyPlatformSchema(db: D1Database, sql: string): Promise<void> {
  await applySqlStatements(db, sql);
}

beforeAll(async () => {
  await applyPlatformSchema(env.DB, migrationSql);
  await applyPlatformSchema(env.DB, issuerKeyTenantBindingMigrationSql);
  await applyPlatformSchema(env.DB, planVersionPaidGrantCoverageMigrationSql);
  await applyPlatformSchema(env.DB, usageTermMigrationSql);
});

beforeEach(async () => {
  await clearLifecycleTables();
});

describe("enroll_route_removed", () => {
  it("returns 404 for POST enroll without writing lifecycle rows", async () => {
    const beforeCounts = await readTableCounts();
    const response = await dispatchControl(buildEnrollRequest());
    expect(response.status).toBe(404);
    expect(await readTableCounts()).toEqual(beforeCounts);
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

describe("lifecycle_rotate_revoke_routes_removed", () => {
  it("returns 404 for rotate and revoke-key without lifecycle writes", async () => {
    const handlers = await loadControlHandlers();
    const operatorAuth = createFakeOperatorAuth();
    await enrollFixture(handlers, operatorAuth);
    const beforeCounts = await readTableCounts();

    const rotate = await dispatchControl(
      buildLifecycleRequest(FIXTURE_INSTALLATION_ID, "rotate", {
        kid: FIXTURE_KID_2,
        public_key: FIXTURE_PUBLIC_KEY_B64_ALT,
        algorithm: "EdDSA",
      }),
      operatorAuth,
    );
    expect(rotate.status).toBe(404);

    const revoke = await dispatchControl(
      buildLifecycleRequest(FIXTURE_INSTALLATION_ID, "revoke-key", {
        kid: DEFAULT_ENROLL_PAYLOAD.kid,
      }),
      operatorAuth,
    );
    expect(revoke.status).toBe(404);
    expect(await readTableCounts()).toEqual(beforeCounts);
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
    expect(installation?.status).toBe("deleted");

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
  it("returns 404 for removed routes and 401 for active lifecycle routes", async () => {
    const handlers = await loadControlHandlers();
    const rejectAuth = createFakeOperatorAuth(null);

    const removedRoutes: Array<{ label: string; invoke: () => Promise<Response> }> = [
      {
        label: "enroll",
        invoke: () =>
          dispatchControl(
            buildEnrollRequest("11111111-1111-4111-8111-111111111001", {
              ...DEFAULT_ENROLL_PAYLOAD,
              org_id: "22222222-2222-4222-8222-222222222201",
              kid: "33333333-3333-4333-8333-333333333301",
            }),
            rejectAuth,
          ),
      },
      {
        label: "rotate",
        invoke: () =>
          dispatchControl(
            buildLifecycleRequest("44444444-4444-4444-8444-444444444401", "rotate", {
              kid: "55555555-5555-4555-8555-555555555501",
              public_key: FIXTURE_PUBLIC_KEY_B64_ALT,
              algorithm: "EdDSA",
            }),
            rejectAuth,
          ),
      },
      {
        label: "revoke-key",
        invoke: () =>
          dispatchControl(
            buildLifecycleRequest("66666666-6666-4666-8666-666666666601", "revoke-key", {
              kid: "77777777-7777-4777-8777-777777777701",
            }),
            rejectAuth,
          ),
      },
    ];

    for (const mutation of removedRoutes) {
      const beforeCounts = await readTableCounts();
      const response = await mutation.invoke();
      expect(response.status, `${mutation.label} status`).toBe(404);
      expect(await readTableCounts()).toEqual(beforeCounts);
    }

    const activeRoutes: Array<{ label: string; invoke: () => Promise<Response> }> = [
      {
        label: "suspend",
        invoke: () =>
          handlers.handleSuspend(
            buildLifecycleRequest("88888888-8888-4888-8888-888888888801", "suspend"),
            bindings(),
            rejectAuth,
          ),
      },
      {
        label: "resume",
        invoke: () =>
          handlers.handleResume(
            buildLifecycleRequest("99999999-9999-4999-8999-999999999901", "resume"),
            bindings(),
            rejectAuth,
          ),
      },
      {
        label: "delete",
        invoke: () =>
          handlers.handleDelete(
            buildLifecycleRequest("aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaa01", "delete"),
            bindings(),
            rejectAuth,
          ),
      },
    ];

    for (const mutation of activeRoutes) {
      const beforeCounts = await readTableCounts();
      const response = await mutation.invoke();
      expect(response.status, `${mutation.label} status`).toBe(401);
      expect(await response.json()).toEqual({ error: "unauthorized" });
      expect(await readTableCounts()).toEqual(beforeCounts);
    }
  });
});

describe("duplicate_enrollment_deterministic", () => {
  it("returns 404 for duplicate enroll attempts without changing row counts", async () => {
    const operatorAuth = createFakeOperatorAuth();
    await seedActiveInstallation();
    const countsAfterSeed = await readTableCounts();

    const firstResponse = await dispatchControl(buildEnrollRequest(), operatorAuth);
    expect(firstResponse.status).toBe(404);

    const duplicateResponse = await dispatchControl(buildEnrollRequest(), operatorAuth);
    expect(duplicateResponse.status).toBe(404);
    expect(await readTableCounts()).toEqual(countsAfterSeed);
  });
});

describe("secret_operator_auth_verifies_credential", () => {
  it("rejects missing, empty, and wrong bearer tokens; never returns the credential as operatorId", async () => {
    const { createSecretOperatorAuth } = await loadControlHandlers();
    const auth = createSecretOperatorAuth({
      bearerToken: TEST_OPERATOR_BEARER,
      operatorId: TEST_OPERATOR_ID,
    });

    expect(
      auth.resolve(
        new Request(`${GATEWAY_ORIGIN}/control/installations/x/enroll`),
      ),
    ).toBeNull();

    expect(
      auth.resolve(
        new Request(`${GATEWAY_ORIGIN}/control/installations/x/enroll`, {
          headers: { authorization: "Bearer " },
        }),
      ),
    ).toBeNull();

    expect(
      auth.resolve(
        new Request(`${GATEWAY_ORIGIN}/control/installations/x/enroll`, {
          headers: { authorization: "Bearer wrong-token" },
        }),
      ),
    ).toBeNull();

    const principal = auth.resolve(
      new Request(`${GATEWAY_ORIGIN}/control/installations/x/enroll`, {
        headers: { authorization: `Bearer ${TEST_OPERATOR_BEARER}` },
      }),
    );
    expect(principal).toEqual({ operatorId: TEST_OPERATOR_ID });
    expect(principal?.operatorId).not.toBe(TEST_OPERATOR_BEARER);
  });

  it("attributes every successful control request to the single configured operatorId", async () => {
    const { createSecretOperatorAuth } = await loadControlHandlers();
    const auth = createSecretOperatorAuth({
      bearerToken: TEST_OPERATOR_BEARER,
      operatorId: TEST_OPERATOR_ID,
    });

    const enroll = auth.resolve(
      new Request(`${GATEWAY_ORIGIN}/control/installations/a/enroll`, {
        headers: { authorization: `Bearer ${TEST_OPERATOR_BEARER}` },
      }),
    );
    const entitle = auth.resolve(
      new Request(`${GATEWAY_ORIGIN}/control/installations/b/entitle`, {
        headers: { authorization: `Bearer ${TEST_OPERATOR_BEARER}` },
      }),
    );

    expect(enroll).toEqual({ operatorId: TEST_OPERATOR_ID });
    expect(entitle).toEqual({ operatorId: TEST_OPERATOR_ID });
    expect(enroll?.operatorId).toBe(entitle?.operatorId);
  });

  it("fails closed when configured secret or operator id is empty", async () => {
    const { createSecretOperatorAuth } = await loadControlHandlers();
    const emptySecret = createSecretOperatorAuth({
      bearerToken: "",
      operatorId: TEST_OPERATOR_ID,
    });
    const emptyId = createSecretOperatorAuth({
      bearerToken: TEST_OPERATOR_BEARER,
      operatorId: "",
    });
    const request = new Request(
      `${GATEWAY_ORIGIN}/control/installations/x/enroll`,
      { headers: { authorization: `Bearer ${TEST_OPERATOR_BEARER}` } },
    );
    expect(emptySecret.resolve(request)).toBeNull();
    expect(emptyId.resolve(request)).toBeNull();
  });
});

describe("control_route_end_to_end", () => {
  it("returns 404 for enroll via worker.fetch regardless of operator bearer", async () => {
    const enrolled = await SELF.fetch(
      buildEnrollRequest(
        FIXTURE_INSTALLATION_ID,
        DEFAULT_ENROLL_PAYLOAD,
        TEST_OPERATOR_BEARER,
      ),
    );
    expect(enrolled.status).toBe(404);

    const wrong = await SELF.fetch(
      buildEnrollRequest(
        "eeeeeeee-eeee-4eee-8eee-eeeeeeeeee01",
        {
          ...DEFAULT_ENROLL_PAYLOAD,
          org_id: "ffffffff-ffff-4fff-8fff-fffffffffff1",
          kid: "12121212-1212-4212-8212-121212121201",
        },
        "wrong-token",
      ),
    );
    expect(wrong.status).toBe(404);
  });
});

describe("lifecycle_illegal_transitions", () => {
  it("rejects suspend-on-deleted with 409 illegal_lifecycle_transition", async () => {
    const handlers = await loadControlHandlers();
    const operatorAuth = createFakeOperatorAuth();

    await enrollFixture(handlers, operatorAuth);
    expect(
      (
        await handlers.handleDelete(
          buildLifecycleRequest(FIXTURE_INSTALLATION_ID, "delete"),
          bindings(),
          operatorAuth,
        )
      ).ok,
    ).toBe(true);

    const beforeCounts = await readTableCounts();

    const response = await handlers.handleSuspend(
      buildLifecycleRequest(FIXTURE_INSTALLATION_ID, "suspend"),
      bindings(),
      operatorAuth,
    );

    expect(response.status).toBe(409);
    expect(await response.json()).toEqual({
      error: "illegal_lifecycle_transition",
    });

    const afterStatus = await env.DB.prepare(
      "SELECT status FROM installation WHERE installation_id = ?",
    )
      .bind(FIXTURE_INSTALLATION_ID)
      .first<{ status: string }>();
    expect(afterStatus?.status).toBe("deleted");
    expect(await readTableCounts()).toEqual(beforeCounts);
  });

  it("rejects resume-on-active with 409 and no phantom resume audit", async () => {
    const handlers = await loadControlHandlers();
    const operatorAuth = createFakeOperatorAuth();

    await enrollFixture(handlers, operatorAuth);
    const beforeCounts = await readTableCounts();

    const response = await handlers.handleResume(
      buildLifecycleRequest(FIXTURE_INSTALLATION_ID, "resume"),
      bindings(),
      operatorAuth,
    );

    expect(response.status).toBe(409);
    expect(await response.json()).toEqual({
      error: "illegal_lifecycle_transition",
    });

    const resumeAudits = await env.DB.prepare(
      "SELECT COUNT(*) AS count FROM control_audit WHERE action = 'resume'",
    ).first<{ count: number }>();
    expect(resumeAudits?.count ?? 0).toBe(0);
    expect(await readTableCounts()).toEqual(beforeCounts);
  });

  it("returns 404 for rotate on a deleted installation", async () => {
    const handlers = await loadControlHandlers();
    const operatorAuth = createFakeOperatorAuth();

    await enrollFixture(handlers, operatorAuth);
    expect(
      (
        await handlers.handleDelete(
          buildLifecycleRequest(FIXTURE_INSTALLATION_ID, "delete"),
          bindings(),
          operatorAuth,
        )
      ).ok,
    ).toBe(true);

    const beforeCounts = await readTableCounts();
    const response = await dispatchControl(
      buildLifecycleRequest(FIXTURE_INSTALLATION_ID, "rotate", {
        kid: "16161616-1616-4616-8616-161616161601",
        public_key: FIXTURE_PUBLIC_KEY_B64_ALT,
        algorithm: "EdDSA",
      }),
      operatorAuth,
    );

    expect(response.status).toBe(404);
    expect(await readTableCounts()).toEqual(beforeCounts);
  });

  it("rejects double-delete with 409 illegal_lifecycle_transition", async () => {
    const handlers = await loadControlHandlers();
    const operatorAuth = createFakeOperatorAuth();

    await enrollFixture(handlers, operatorAuth);
    expect(
      (
        await handlers.handleDelete(
          buildLifecycleRequest(FIXTURE_INSTALLATION_ID, "delete"),
          bindings(),
          operatorAuth,
        )
      ).ok,
    ).toBe(true);

    const beforeCounts = await readTableCounts();
    const response = await handlers.handleDelete(
      buildLifecycleRequest(FIXTURE_INSTALLATION_ID, "delete"),
      bindings(),
      operatorAuth,
    );

    expect(response.status).toBe(409);
    expect(await response.json()).toEqual({
      error: "illegal_lifecycle_transition",
    });

    const deleteAudits = await env.DB.prepare(
      "SELECT COUNT(*) AS count FROM control_audit WHERE action = 'delete'",
    ).first<{ count: number }>();
    expect(deleteAudits?.count).toBe(1);
    expect(await readTableCounts()).toEqual(beforeCounts);
  });

  it("rejects suspend already-suspended with 409 illegal_lifecycle_transition", async () => {
    const handlers = await loadControlHandlers();
    const operatorAuth = createFakeOperatorAuth();

    await enrollFixture(handlers, operatorAuth);
    expect(
      (
        await handlers.handleSuspend(
          buildLifecycleRequest(FIXTURE_INSTALLATION_ID, "suspend"),
          bindings(),
          operatorAuth,
        )
      ).ok,
    ).toBe(true);

    const beforeCounts = await readTableCounts();
    const response = await handlers.handleSuspend(
      buildLifecycleRequest(FIXTURE_INSTALLATION_ID, "suspend"),
      bindings(),
      operatorAuth,
    );

    expect(response.status).toBe(409);
    expect(await response.json()).toEqual({
      error: "illegal_lifecycle_transition",
    });

    const suspendAudits = await env.DB.prepare(
      "SELECT COUNT(*) AS count FROM control_audit WHERE action = 'suspend'",
    ).first<{ count: number }>();
    expect(suspendAudits?.count).toBe(1);
    expect(await readTableCounts()).toEqual(beforeCounts);
  });
});

describe("suspend_resume_entitlement_unchanged", () => {
  it("leaves entitlement row byte-identical across suspend and resume", async () => {
    const handlers = await loadControlHandlers();
    const operatorAuth = createFakeOperatorAuth();
    await enrollFixture(handlers, operatorAuth);

    const entitlementSelect = `SELECT entitlement_id, installation_id, plan, period_start,
            period_end, request_quota, token_budget, cost_budget,
            allowed_capabilities, soft_threshold, status
     FROM entitlement WHERE installation_id = ?`;

    type EntitlementRow = {
      entitlement_id: string;
      installation_id: string;
      plan: string;
      period_start: string;
      period_end: string;
      request_quota: number;
      token_budget: number;
      cost_budget: number;
      allowed_capabilities: string;
      soft_threshold: number;
      status: string;
    };

    const before = await env.DB.prepare(entitlementSelect)
      .bind(FIXTURE_INSTALLATION_ID)
      .first<EntitlementRow>();
    expect(before).toBeTruthy();
    const beforeSnapshot = JSON.stringify(before);

    expect(
      (
        await handlers.handleSuspend(
          buildLifecycleRequest(FIXTURE_INSTALLATION_ID, "suspend"),
          bindings(),
          operatorAuth,
        )
      ).ok,
    ).toBe(true);

    const afterSuspend = await env.DB.prepare(entitlementSelect)
      .bind(FIXTURE_INSTALLATION_ID)
      .first<EntitlementRow>();
    expect(JSON.stringify(afterSuspend)).toBe(beforeSnapshot);

    expect(
      (
        await handlers.handleResume(
          buildLifecycleRequest(FIXTURE_INSTALLATION_ID, "resume"),
          bindings(),
          operatorAuth,
        )
      ).ok,
    ).toBe(true);

    const afterResume = await env.DB.prepare(entitlementSelect)
      .bind(FIXTURE_INSTALLATION_ID)
      .first<EntitlementRow>();
    expect(JSON.stringify(afterResume)).toBe(beforeSnapshot);
  });
});

describe("duplicate_enrollment_same_org_different_installation", () => {
  it("returns 404 for enroll on a second installation id without extra writes", async () => {
    const operatorAuth = createFakeOperatorAuth();
    await seedActiveInstallation();
    const countsAfterSeed = await readTableCounts();

    const second = await dispatchControl(
      buildEnrollRequest(FIXTURE_INSTALLATION_ID_2, {
        ...DEFAULT_ENROLL_PAYLOAD,
        kid: FIXTURE_KID_2,
      }),
      operatorAuth,
    );

    expect(second.status).toBe(404);
    expect(await readTableCounts()).toEqual(countsAfterSeed);
  });
});

describe("enroll_invalid_payload", () => {
  it("returns 404 for invalid enroll payloads without D1 writes", async () => {
    const operatorAuth = createFakeOperatorAuth();
    const { org_id: _omit, ...withoutOrgId } = DEFAULT_ENROLL_PAYLOAD;
    const payloads: EnrollPayload[] = [
      withoutOrgId as EnrollPayload,
      { ...DEFAULT_ENROLL_PAYLOAD, plan: "verify" },
      { ...DEFAULT_ENROLL_PAYLOAD, algorithm: "RS256" },
      { ...DEFAULT_ENROLL_PAYLOAD, org_id: "org-not-uuid" },
      { ...DEFAULT_ENROLL_PAYLOAD, public_key: "c2hvcnQ" },
    ];

    for (const payload of payloads) {
      const beforeCounts = await readTableCounts();
      const response = await dispatchControl(
        buildEnrollRequest(FIXTURE_INSTALLATION_ID, payload),
        operatorAuth,
      );
      expect(response.status).toBe(404);
      expect(await readTableCounts()).toEqual(beforeCounts);
    }

    const beforeCounts = await readTableCounts();
    const nonUuidPath = await dispatchControl(
      buildEnrollRequest("not-a-uuid", DEFAULT_ENROLL_PAYLOAD),
      operatorAuth,
    );
    expect(nonUuidPath.status).toBe(404);
    expect(await readTableCounts()).toEqual(beforeCounts);
  });
});

describe("rotate_duplicate_kid", () => {
  it("returns 404 for rotate payloads without lifecycle writes", async () => {
    const handlers = await loadControlHandlers();
    const operatorAuth = createFakeOperatorAuth();
    await enrollFixture(handlers, operatorAuth);
    const beforeCounts = await readTableCounts();

    const payloads = [
      {
        kid: FIXTURE_KID,
        public_key: FIXTURE_PUBLIC_KEY_B64_ALT,
        algorithm: "EdDSA",
      },
      {
        kid: "14141414-1414-4414-8414-141414141401",
        public_key: FIXTURE_PUBLIC_KEY_B64_ALT,
        algorithm: "RS256",
      },
    ];

    for (const body of payloads) {
      const response = await dispatchControl(
        buildLifecycleRequest(FIXTURE_INSTALLATION_ID, "rotate", body),
        operatorAuth,
      );
      expect(response.status).toBe(404);
    }
    expect(await readTableCounts()).toEqual(beforeCounts);
  });
});

describe("enroll_invalid_json", () => {
  it("returns 404 for enroll non-JSON body without D1 writes", async () => {
    const operatorAuth = createFakeOperatorAuth();
    const beforeCounts = await readTableCounts();

    const response = await dispatchControl(
      new Request(
        `${GATEWAY_ORIGIN}/control/installations/${FIXTURE_INSTALLATION_ID}/enroll`,
        {
          method: "POST",
          headers: {
            "content-type": "application/json",
            authorization: "Bearer operator-test",
          },
          body: "not-json{",
        },
      ),
      operatorAuth,
    );

    expect(response.status).toBe(404);
    expect(await readTableCounts()).toEqual(beforeCounts);
  });
});

describe("invalid_route_rejected", () => {
  it("rejects when installation id cannot be parsed with 400 invalid_route", async () => {
    const handlers = await loadControlHandlers();
    const operatorAuth = createFakeOperatorAuth();
    const beforeCounts = await readTableCounts();

    const response = await handlers.handleSuspend(
      new Request(`${GATEWAY_ORIGIN}/control/not-installations/x/suspend`, {
        method: "POST",
        headers: {
          "content-type": "application/json",
          authorization: "Bearer operator-test",
        },
        body: "{}",
      }),
      bindings(),
      operatorAuth,
    );

    expect(response.status).toBe(400);
    expect(await response.json()).toEqual({ error: "invalid_route" });
    expect(await readTableCounts()).toEqual(beforeCounts);
  });
});

describe("installation_not_found", () => {
  it("rejects rotate/revoke-key/suspend/resume/delete on unknown id with 404", async () => {
    const handlers = await loadControlHandlers();
    const operatorAuth = createFakeOperatorAuth();
    const unknownId = "00000000-0000-4000-8000-000000000098";

    const removedCases: Array<{ label: string; invoke: () => Promise<Response> }> = [
      {
        label: "rotate",
        invoke: () =>
          dispatchControl(
            buildLifecycleRequest(unknownId, "rotate", {
              kid: "15151515-1515-4515-8515-151515151501",
              public_key: FIXTURE_PUBLIC_KEY_B64_ALT,
              algorithm: "EdDSA",
            }),
            operatorAuth,
          ),
      },
      {
        label: "revoke-key",
        invoke: () =>
          dispatchControl(
            buildLifecycleRequest(unknownId, "revoke-key", {
              kid: "15151515-1515-4515-8515-151515151501",
            }),
            operatorAuth,
          ),
      },
    ];

    for (const testCase of removedCases) {
      const beforeCounts = await readTableCounts();
      const response = await testCase.invoke();
      expect(response.status, `${testCase.label} status`).toBe(404);
      expect(await readTableCounts()).toEqual(beforeCounts);
    }

    const activeCases: Array<{ label: string; invoke: () => Promise<Response> }> = [
      {
        label: "suspend",
        invoke: () =>
          handlers.handleSuspend(
            buildLifecycleRequest(unknownId, "suspend"),
            bindings(),
            operatorAuth,
          ),
      },
      {
        label: "resume",
        invoke: () =>
          handlers.handleResume(
            buildLifecycleRequest(unknownId, "resume"),
            bindings(),
            operatorAuth,
          ),
      },
      {
        label: "delete",
        invoke: () =>
          handlers.handleDelete(
            buildLifecycleRequest(unknownId, "delete"),
            bindings(),
            operatorAuth,
          ),
      },
    ];

    for (const testCase of activeCases) {
      const beforeCounts = await readTableCounts();
      const response = await testCase.invoke();
      expect(response.status, `${testCase.label} status`).toBe(404);
      expect(await response.json(), `${testCase.label} body`).toEqual({
        error: "installation_not_found",
      });
      expect(await readTableCounts()).toEqual(beforeCounts);
    }
  });
});
