import { env, SELF } from "cloudflare:test";
import { beforeAll, beforeEach, describe, expect, it } from "vitest";
import migrationSql from "../migrations/20260731120000_platform_schema.sql?raw";

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
  handleRevokeKey: (
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

describe("lifecycle_revoke_key_audit", () => {
  it("stamps revoked_at and writes revoke-key audit", async () => {
    const handlers = await loadControlHandlers();
    const operatorAuth = createFakeOperatorAuth();

    await enrollFixture(handlers, operatorAuth);

    const beforeCounts = await readTableCounts();
    const response = await handlers.handleRevokeKey(
      buildLifecycleRequest(FIXTURE_INSTALLATION_ID, "revoke-key", {
        kid: DEFAULT_ENROLL_PAYLOAD.kid,
      }),
      bindings(),
      operatorAuth,
    );
    expect(response.ok).toBe(true);

    const afterCounts = await readTableCounts();
    expect(afterCounts.installation_key).toBe(1);
    expect(afterCounts.control_audit).toBe(beforeCounts.control_audit + 1);

    const key = await env.DB.prepare(
      "SELECT key_id, revoked_at FROM installation_key WHERE key_id = ?",
    )
      .bind(DEFAULT_ENROLL_PAYLOAD.kid)
      .first<{ key_id: string; revoked_at: string | null }>();
    expect(key?.key_id).toBe(DEFAULT_ENROLL_PAYLOAD.kid);
    expect(key?.revoked_at).toBeTruthy();

    const audit = await env.DB.prepare(
      "SELECT operator_id, action, after_pointer FROM control_audit WHERE action = 'revoke-key'",
    ).first<{ operator_id: string; action: string; after_pointer: string }>();
    expect(audit).toMatchObject({
      operator_id: FAKE_OPERATOR.operatorId,
      action: "revoke-key",
      after_pointer: DEFAULT_ENROLL_PAYLOAD.kid,
    });
  });

  it("rejects revoke of unknown kid with 404 key_not_found", async () => {
    const handlers = await loadControlHandlers();
    const operatorAuth = createFakeOperatorAuth();
    await enrollFixture(handlers, operatorAuth);
    const beforeCounts = await readTableCounts();

    const response = await handlers.handleRevokeKey(
      buildLifecycleRequest(FIXTURE_INSTALLATION_ID, "revoke-key", {
        kid: "kid-does-not-exist",
      }),
      bindings(),
      operatorAuth,
    );

    expect(response.status).toBe(404);
    expect(await response.json()).toEqual({ error: "key_not_found" });
    expect(await readTableCounts()).toEqual(beforeCounts);
  });

  it("rejects double revoke with 409 key_already_revoked", async () => {
    const handlers = await loadControlHandlers();
    const operatorAuth = createFakeOperatorAuth();
    await enrollFixture(handlers, operatorAuth);

    expect(
      (
        await handlers.handleRevokeKey(
          buildLifecycleRequest(FIXTURE_INSTALLATION_ID, "revoke-key", {
            kid: DEFAULT_ENROLL_PAYLOAD.kid,
          }),
          bindings(),
          operatorAuth,
        )
      ).ok,
    ).toBe(true);

    const beforeCounts = await readTableCounts();
    const response = await handlers.handleRevokeKey(
      buildLifecycleRequest(FIXTURE_INSTALLATION_ID, "revoke-key", {
        kid: DEFAULT_ENROLL_PAYLOAD.kid,
      }),
      bindings(),
      operatorAuth,
    );

    expect(response.status).toBe(409);
    expect(await response.json()).toEqual({ error: "key_already_revoked" });
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
  it("rejects all six mutations with 401 unauthorized and no D1 writes", async () => {
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
        label: "revoke-key",
        invoke: () =>
          handlers.handleRevokeKey(
            buildLifecycleRequest("inst-reject-006", "revoke-key", {
              kid: "kid-reject-revoke",
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
      expect(response.status, `${mutation.label} status`).toBe(401);
      expect(await response.json(), `${mutation.label} body`).toEqual({
        error: "unauthorized",
      });

      const afterCounts = await readTableCounts();
      expect(afterCounts, `${mutation.label} must not write D1 rows`).toEqual(
        beforeCounts,
      );
    }
  });
});

describe("duplicate_enrollment_deterministic", () => {
  it("rejects duplicate enroll with 409 already_enrolled without changing row counts", async () => {
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
    expect(duplicateResponse.status).toBe(409);
    expect(await duplicateResponse.json()).toEqual({
      error: "already_enrolled",
    });

    const countsAfterDuplicate = await readTableCounts();
    expect(countsAfterDuplicate).toEqual(countsAfterFirst);
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
  it("routes enroll through worker.fetch with secret auth and journals OPERATOR_ID", async () => {
    const enrolled = await SELF.fetch(
      buildEnrollRequest(
        FIXTURE_INSTALLATION_ID,
        DEFAULT_ENROLL_PAYLOAD,
        TEST_OPERATOR_BEARER,
      ),
    );

    expect(enrolled.status).toBe(200);
    const body = (await enrolled.json()) as { platform_base_url?: string };
    expect(body.platform_base_url).toBe(GATEWAY_ORIGIN);

    const audit = await env.DB.prepare(
      "SELECT operator_id, action FROM control_audit WHERE action = 'enroll'",
    ).first<{ operator_id: string; action: string }>();
    expect(audit).toEqual({
      operator_id: TEST_OPERATOR_ID,
      action: "enroll",
    });
    expect(audit?.operator_id).not.toBe(TEST_OPERATOR_BEARER);

    const wrong = await SELF.fetch(
      buildEnrollRequest(
        "inst-e2e-unauth",
        {
          ...DEFAULT_ENROLL_PAYLOAD,
          org_id: "org-e2e-unauth",
          kid: "kid-e2e-unauth",
        },
        "wrong-token",
      ),
    );
    expect(wrong.status).toBe(401);
    expect(await wrong.json()).toEqual({ error: "unauthorized" });
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

  it("rejects rotate-on-deleted with 409 illegal_lifecycle_transition", async () => {
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
    const response = await handlers.handleRotate(
      buildLifecycleRequest(FIXTURE_INSTALLATION_ID, "rotate", {
        kid: "kid-rotate-deleted",
        public_key: "bmV3LXB1YmxpYy1rZXk=",
        algorithm: "EdDSA",
      }),
      bindings(),
      operatorAuth,
    );

    expect(response.status).toBe(409);
    expect(await response.json()).toEqual({
      error: "illegal_lifecycle_transition",
    });
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
  it("rejects same org_id with different installation_id as 409 already_enrolled", async () => {
    const { handleEnroll } = await loadControlHandlers();
    const operatorAuth = createFakeOperatorAuth();

    expect(
      (await handleEnroll(buildEnrollRequest(), bindings(), operatorAuth)).ok,
    ).toBe(true);
    const countsAfterFirst = await readTableCounts();

    const second = await handleEnroll(
      buildEnrollRequest("inst-test-002", {
        ...DEFAULT_ENROLL_PAYLOAD,
        kid: "kid-test-002",
      }),
      bindings(),
      operatorAuth,
    );

    expect(second.status).toBe(409);
    expect(await second.json()).toEqual({ error: "already_enrolled" });
    expect(await readTableCounts()).toEqual(countsAfterFirst);
  });
});

describe("enroll_invalid_payload", () => {
  it("rejects enroll missing org_id with 400 invalid_payload", async () => {
    const { handleEnroll } = await loadControlHandlers();
    const operatorAuth = createFakeOperatorAuth();
    const { org_id: _omit, ...withoutOrgId } = DEFAULT_ENROLL_PAYLOAD;
    const beforeCounts = await readTableCounts();

    const response = await handleEnroll(
      buildEnrollRequest(
        FIXTURE_INSTALLATION_ID,
        withoutOrgId as typeof DEFAULT_ENROLL_PAYLOAD,
      ),
      bindings(),
      operatorAuth,
    );

    expect(response.status).toBe(400);
    expect(await response.json()).toEqual({ error: "invalid_payload" });
    expect(await readTableCounts()).toEqual(beforeCounts);
  });
});

describe("rotate_duplicate_kid", () => {
  it("rejects rotate reusing an existing kid with 409 duplicate_kid", async () => {
    const handlers = await loadControlHandlers();
    const operatorAuth = createFakeOperatorAuth();
    await enrollFixture(handlers, operatorAuth);
    const beforeCounts = await readTableCounts();

    const response = await handlers.handleRotate(
      buildLifecycleRequest(FIXTURE_INSTALLATION_ID, "rotate", {
        kid: DEFAULT_ENROLL_PAYLOAD.kid,
        public_key: "ZHVwbGljYXRlLWtpZA==",
        algorithm: "EdDSA",
      }),
      bindings(),
      operatorAuth,
    );

    expect(response.status).toBe(409);
    expect(await response.json()).toEqual({ error: "duplicate_kid" });
    expect(await readTableCounts()).toEqual(beforeCounts);
  });
});

describe("enroll_invalid_json", () => {
  it("rejects enroll non-JSON body with 400 invalid_json", async () => {
    const { handleEnroll } = await loadControlHandlers();
    const operatorAuth = createFakeOperatorAuth();
    const beforeCounts = await readTableCounts();

    const response = await handleEnroll(
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
      bindings(),
      operatorAuth,
    );

    expect(response.status).toBe(400);
    expect(await response.json()).toEqual({ error: "invalid_json" });
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
    const unknownId = "inst-does-not-exist";

    const cases: Array<{ label: string; invoke: () => Promise<Response> }> = [
      {
        label: "rotate",
        invoke: () =>
          handlers.handleRotate(
            buildLifecycleRequest(unknownId, "rotate", {
              kid: "kid-missing",
              public_key: "cHVibGlj",
              algorithm: "EdDSA",
            }),
            bindings(),
            operatorAuth,
          ),
      },
      {
        label: "revoke-key",
        invoke: () =>
          handlers.handleRevokeKey(
            buildLifecycleRequest(unknownId, "revoke-key", {
              kid: "kid-missing",
            }),
            bindings(),
            operatorAuth,
          ),
      },
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

    for (const testCase of cases) {
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
