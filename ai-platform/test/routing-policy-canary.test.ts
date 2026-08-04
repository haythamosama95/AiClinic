import { env } from "cloudflare:test";
import { beforeAll, beforeEach, describe, expect, it, vi } from "vitest";
import migrationSql from "../migrations/20260731120000_platform_schema.sql?raw";
import canaryMigrationSql from "../migrations/20260803100000_routing_policy_canary.sql?raw";
import {
  ConfigCache,
  type ConfigEntityKind,
  type D1Reader,
} from "../src/config-cache";
import { preloadRoutingPolicyForInstallation, selectCandidateChain } from "../src/router";
import {
  assertControlAudit,
  countControlAuditsForAction,
} from "./helpers/control-audit-assert";

declare module "cloudflare:test" {
  interface ProvidedEnv {
    DB: D1Database;
    R2: R2Bucket;
  }
}

type D1Row = Record<string, unknown>;

const GATEWAY_ORIGIN = "https://ai-gateway.test";
const COHORT_INSTALLATION_ID = "inst-j3-routing-cohort";
const OTHER_INSTALLATION_ID = "inst-j3-routing-other";
const FIXTURE_POLICY_ID = "standard";
const FIXTURE_POLICY_REF = "routing/standard@v1";
const FIXTURE_VERSION_V1 = "1";
const FIXTURE_VERSION_V2 = "2";
const FIXTURE_NOW = "2026-08-03T12:00:00.000Z";
const FAKE_OPERATOR_ID = "operator-j3-routing";

type OperatorPrincipal = { operatorId: string };
type OperatorAuth = {
  resolve(_request: Request): OperatorPrincipal | null;
};

function createFakeOperatorAuth(
  principal: OperatorPrincipal | null = { operatorId: FAKE_OPERATOR_ID },
): OperatorAuth {
  return { resolve() { return principal; } };
}

type RoutingControlHandlers = {
  handleRoutingPolicyPublish: (
    request: Request,
    bindings: { DB: D1Database; R2?: R2Bucket },
    operatorAuth: OperatorAuth,
  ) => Promise<Response>;
  handleRoutingPolicyCanary: (
    request: Request,
    bindings: { DB: D1Database; R2?: R2Bucket },
    operatorAuth: OperatorAuth,
  ) => Promise<Response>;
  handleRoutingPolicyRollback: (
    request: Request,
    bindings: { DB: D1Database; R2?: R2Bucket },
    operatorAuth: OperatorAuth,
  ) => Promise<Response>;
  handleCohortActivate: (
    request: Request,
    bindings: { DB: D1Database },
    operatorAuth: OperatorAuth,
  ) => Promise<Response>;
  handleCohortPromote: (
    request: Request,
    bindings: { DB: D1Database },
    operatorAuth: OperatorAuth,
  ) => Promise<Response>;
};

async function loadRoutingControlHandlers(): Promise<RoutingControlHandlers> {
  return import(/* @vite-ignore */ "../src/control") as Promise<RoutingControlHandlers>;
}

function policyDocument(version: number, providerId: string): Record<string, unknown> {
  return {
    schema_version: 1,
    policy_id: FIXTURE_POLICY_ID,
    policy_version: version,
    defaults: { cost_class: "standard", max_parallel_attempts: 1 },
    rules: [
      {
        rule_id: "catch-all",
        match: {},
        requires: {
          structured_output: false,
          min_context_window: 0,
          languages: ["en"],
        },
        targets: [
          {
            provider_id: providerId,
            model_id: `${providerId}-chat`,
            features: {
              structured_output: false,
              min_context_window: 128_000,
              languages: ["en"],
              latency_class: "interactive",
              cost_class: "standard",
            },
            max_attempts: 2,
            timeout_ms: 30_000,
          },
        ],
      },
    ],
    overrides: [],
  };
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

async function clearTables(db: D1Database): Promise<void> {
  await db.batch([
    db.prepare("DELETE FROM control_audit"),
    db.prepare("DELETE FROM routing_policy"),
    db.prepare("DELETE FROM capability_grant"),
    db.prepare("DELETE FROM entitlement"),
    db.prepare("DELETE FROM installation_key"),
    db.prepare("DELETE FROM installation"),
  ]);
}

async function seedInstallation(
  db: D1Database,
  installationId: string,
): Promise<void> {
  await db
    .prepare(
      `INSERT INTO installation (
        installation_id, org_id, display_name, status, region, enrolled_at
      ) VALUES (?, ?, ?, ?, ?, ?)`,
    )
    .bind(
      installationId,
      "org-j3-routing",
      `Routing ${installationId}`,
      "active",
      "us-east-1",
      FIXTURE_NOW,
    )
    .run();
}

function makeRoutingD1Reader(db: D1Database, r2: R2Bucket): D1Reader {
  return {
    async read(prefixedKey: string): Promise<D1Row | "miss"> {
      const separator = prefixedKey.indexOf(":");
      if (separator === -1) {
        return "miss";
      }
      const kind = prefixedKey.slice(0, separator) as ConfigEntityKind;
      const key = prefixedKey.slice(separator + 1);

      if (kind !== "active_routing_policy") {
        return "miss";
      }

      const slash = key.lastIndexOf("/");
      const policyRef = slash === -1 ? key : key.slice(0, slash);
      const installationId = slash === -1 ? null : key.slice(slash + 1);
      const policyId = policyRef.replace(/^routing\//, "").replace(/@v\d+$/, "");

      const canaryRow = installationId
        ? await db
            .prepare(
              `SELECT policy_id, version, content_pointer, active_from, activated_by,
                      canary_installation_ids
               FROM routing_policy
               WHERE policy_id = ? AND canary_installation_ids IS NOT NULL`,
            )
            .bind(policyId)
            .first<D1Row>()
        : null;

      if (canaryRow && installationId) {
        const ids = JSON.parse(
          String(canaryRow.canary_installation_ids),
        ) as string[];
        if (ids.includes(installationId)) {
          const object = await r2.get(String(canaryRow.content_pointer));
          if (object) {
            const document = JSON.parse(await object.text());
            return { ...canaryRow, document };
          }
        }
      }

      const globalRow = await db
        .prepare(
          `SELECT policy_id, version, content_pointer, active_from, activated_by,
                  canary_installation_ids
           FROM routing_policy
           WHERE policy_id = ? AND canary_installation_ids IS NULL
           ORDER BY active_from DESC LIMIT 1`,
        )
        .bind(policyId)
        .first<D1Row>();

      if (!globalRow) {
        return "miss";
      }

      const object = await r2.get(String(globalRow.content_pointer));
      if (!object) {
        return "miss";
      }
      const document = JSON.parse(await object.text());
      return { ...globalRow, document };
    },
  };
}

function buildPublishRequest(
  version: string,
  document: Record<string, unknown>,
): Request {
  return new Request(
    `${GATEWAY_ORIGIN}/control/routing-policies/${FIXTURE_POLICY_ID}/versions/${version}/publish`,
    {
      method: "POST",
      headers: {
        "content-type": "application/json",
        authorization: `Bearer ${FAKE_OPERATOR_ID}`,
      },
      body: JSON.stringify({ document }),
    },
  );
}

function buildCanaryRequest(
  version: string,
  installationIds: string[],
): Request {
  return new Request(
    `${GATEWAY_ORIGIN}/control/routing-policies/${FIXTURE_POLICY_ID}/versions/${version}/canary`,
    {
      method: "POST",
      headers: {
        "content-type": "application/json",
        authorization: `Bearer ${FAKE_OPERATOR_ID}`,
      },
      body: JSON.stringify({ installation_ids: installationIds }),
    },
  );
}

function buildRollbackRequest(version: string): Request {
  return new Request(
    `${GATEWAY_ORIGIN}/control/routing-policies/${FIXTURE_POLICY_ID}/versions/${version}/rollback`,
    {
      method: "POST",
      headers: {
        "content-type": "application/json",
        authorization: `Bearer ${FAKE_OPERATOR_ID}`,
      },
      body: "{}",
    },
  );
}

function buildCohortActivateRequest(
  capabilityId: string,
  version: string,
  installationIds: string[],
): Request {
  return new Request(
    `${GATEWAY_ORIGIN}/control/capabilities/${capabilityId}/versions/${version}/activate`,
    {
      method: "POST",
      headers: {
        "content-type": "application/json",
        authorization: `Bearer ${FAKE_OPERATOR_ID}`,
      },
      body: JSON.stringify({ installation_ids: installationIds }),
    },
  );
}

function buildCohortPromoteRequest(
  capabilityId: string,
  version: string,
): Request {
  return new Request(
    `${GATEWAY_ORIGIN}/control/capabilities/${capabilityId}/versions/${version}/promote`,
    {
      method: "POST",
      headers: {
        "content-type": "application/json",
        authorization: `Bearer ${FAKE_OPERATOR_ID}`,
      },
      body: "{}",
    },
  );
}

async function routeForInstallation(
  installationId: string,
  cache: ConfigCache,
  reader: D1Reader,
): Promise<ReturnType<typeof selectCandidateChain>> {
  await preloadRoutingPolicyForInstallation(
    cache,
    reader,
    FIXTURE_POLICY_REF,
    installationId,
  );
  return selectCandidateChain({
    cache,
    policyCacheKey: FIXTURE_POLICY_REF,
    context: {
      installationId,
      capabilityId: "clinic.j3",
      routingTier: "standard",
      requirements: {
        structured_output_required: false,
        min_context_window: 0,
        languages: ["en"],
        latency_class: "interactive",
      },
      manifestCostClass: "standard",
      entitlementMaxCostClass: "premium",
    },
  });
}

beforeAll(async () => {
  await applyPlatformSchema(env.DB, migrationSql);
  await applyPlatformSchema(env.DB, canaryMigrationSql);
});

beforeEach(async () => {
  await clearTables(env.DB);
  vi.setSystemTime(new Date(FIXTURE_NOW));
});

describe("T-J3-04 every_activation_writes_control_audit_with_operator_identity", () => {
  it("activate, promote, canary, and roll back each write control_audit", async () => {
    await seedInstallation(env.DB, COHORT_INSTALLATION_ID);
    await seedInstallation(env.DB, OTHER_INSTALLATION_ID);

    const operatorAuth = createFakeOperatorAuth();
    const bindings = { DB: env.DB, R2: env.R2 };
    const {
      handleRoutingPolicyPublish,
      handleRoutingPolicyCanary,
      handleRoutingPolicyRollback,
      handleCohortActivate,
      handleCohortPromote,
    } = await loadRoutingControlHandlers();

    const publishV1 = await handleRoutingPolicyPublish(
      buildPublishRequest(FIXTURE_VERSION_V1, policyDocument(1, "deepseek")),
      bindings,
      operatorAuth,
    );
    expect(publishV1.ok).toBe(true);
    await assertControlAudit(env.DB, {
      operatorId: FAKE_OPERATOR_ID,
      action: "routing_policy_publish",
    });

    const publishV2 = await handleRoutingPolicyPublish(
      buildPublishRequest(FIXTURE_VERSION_V2, policyDocument(2, "gemini")),
      bindings,
      operatorAuth,
    );
    expect(publishV2.ok).toBe(true);

    const canary = await handleRoutingPolicyCanary(
      buildCanaryRequest(FIXTURE_VERSION_V2, [COHORT_INSTALLATION_ID]),
      bindings,
      operatorAuth,
    );
    expect(canary.ok).toBe(true);
    await assertControlAudit(env.DB, {
      operatorId: FAKE_OPERATOR_ID,
      action: "routing_policy_canary",
    });

    const activate = await handleCohortActivate(
      buildCohortActivateRequest("clinic.j3", "2.0.0", [COHORT_INSTALLATION_ID]),
      { DB: env.DB },
      operatorAuth,
    );
    expect(activate.ok).toBe(true);
    await assertControlAudit(env.DB, {
      operatorId: FAKE_OPERATOR_ID,
      action: "cohort_activate",
    });

    const promote = await handleCohortPromote(
      buildCohortPromoteRequest("clinic.j3", "2.0.0"),
      { DB: env.DB },
      operatorAuth,
    );
    expect(promote.ok).toBe(true);
    await assertControlAudit(env.DB, {
      operatorId: FAKE_OPERATOR_ID,
      action: "cohort_promote",
    });

    const rollback = await handleRoutingPolicyRollback(
      buildRollbackRequest(FIXTURE_VERSION_V2),
      bindings,
      operatorAuth,
    );
    expect(rollback.ok).toBe(true);
    await assertControlAudit(env.DB, {
      operatorId: FAKE_OPERATOR_ID,
      action: "routing_policy_rollback",
    });

    expect(await countControlAuditsForAction(env.DB, "routing_policy_publish")).toBe(
      2,
    );
  });
});

describe("routing_policy_canary_split", () => {
  it("canary cohort receives new policy version while others keep previous", async () => {
    await seedInstallation(env.DB, COHORT_INSTALLATION_ID);
    await seedInstallation(env.DB, OTHER_INSTALLATION_ID);

    const operatorAuth = createFakeOperatorAuth();
    const bindings = { DB: env.DB, R2: env.R2 };
    const { handleRoutingPolicyPublish, handleRoutingPolicyCanary } =
      await loadRoutingControlHandlers();

    expect(
      (
        await handleRoutingPolicyPublish(
          buildPublishRequest(FIXTURE_VERSION_V1, policyDocument(1, "deepseek")),
          bindings,
          operatorAuth,
        )
      ).ok,
    ).toBe(true);
    expect(
      (
        await handleRoutingPolicyPublish(
          buildPublishRequest(FIXTURE_VERSION_V2, policyDocument(2, "gemini")),
          bindings,
          operatorAuth,
        )
      ).ok,
    ).toBe(true);
    expect(
      (
        await handleRoutingPolicyCanary(
          buildCanaryRequest(FIXTURE_VERSION_V2, [COHORT_INSTALLATION_ID]),
          bindings,
          operatorAuth,
        )
      ).ok,
    ).toBe(true);

    const cache = new ConfigCache();
    const reader = makeRoutingD1Reader(env.DB, env.R2);

    const cohortOutcome = await routeForInstallation(
      COHORT_INSTALLATION_ID,
      cache,
      reader,
    );
    expect(cohortOutcome.routing_decision.policy_version).toBe(2);
    expect(cohortOutcome.routing_decision.chain[0]?.provider_id).toBe("gemini");

    const otherOutcome = await routeForInstallation(
      OTHER_INSTALLATION_ID,
      cache,
      reader,
    );
    expect(otherOutcome.routing_decision.policy_version).toBe(1);
    expect(otherOutcome.routing_decision.chain[0]?.provider_id).toBe("deepseek");
  });

  it("rejects non-operator credentials on control mutations", async () => {
    const { handleRoutingPolicyPublish } = await loadRoutingControlHandlers();
    const response = await handleRoutingPolicyPublish(
      buildPublishRequest(FIXTURE_VERSION_V1, policyDocument(1, "deepseek")),
      { DB: env.DB, R2: env.R2 },
      createFakeOperatorAuth(null),
    );
    expect(response.status).toBe(401);
    const auditCount = await env.DB.prepare(
      "SELECT COUNT(*) AS count FROM control_audit",
    ).first<{ count: number }>();
    expect(auditCount?.count ?? 0).toBe(0);
  });
});
