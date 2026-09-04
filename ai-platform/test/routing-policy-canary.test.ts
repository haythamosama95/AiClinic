import { env } from "cloudflare:test";
import { beforeAll, beforeEach, describe, expect, it, vi } from "vitest";
import migrationSql from "../migrations/20260731120000_platform_schema.sql?raw";
import canaryMigrationSql from "../migrations/20260803100000_routing_policy_canary.sql?raw";
import statusMigrationSql from "../migrations/20260805190000_routing_policy_status.sql?raw";
import {
  ConfigCache,
  createD1ConfigReader,
  type D1Reader,
} from "../src/config-cache";
import {
  createCapabilityRegistry,
  setCapabilityRegistry,
} from "../src/capability";
import { load } from "../src/manifest";
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

const GATEWAY_ORIGIN = "https://ai-gateway.test";
const COHORT_INSTALLATION_ID = "inst-j3-routing-cohort";
const OTHER_INSTALLATION_ID = "inst-j3-routing-other";
const FIXTURE_POLICY_ID = "standard";
const FIXTURE_POLICY_REF = "routing/standard@v1";
const FIXTURE_VERSION_V1 = "1";
const FIXTURE_VERSION_V2 = "2";
const FIXTURE_CAPABILITY_ID = "clinic.j3";
const FIXTURE_CAPABILITY_V1 = "1.0.0";
const FIXTURE_CAPABILITY_V2 = "2.0.0";
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
  handleRoutingPolicyPromote: (
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

function minimalCapabilityManifest(version: string): Record<string, unknown> {
  return {
    Identity: {
      capabilityId: FIXTURE_CAPABILITY_ID,
      version,
      title: "J3 routing fixture",
      lifecycleState: "active",
      successorId: null,
    },
    Access: {
      requiredCapabilityScope: `ai.${FIXTURE_CAPABILITY_ID}`,
      minimumPlanTier: "standard",
      allowedStaffRoles: ["clinician"],
      killSwitchFlag: false,
    },
    Interaction: { interactionMode: "single_shot" },
    Input: {
      userIntentShape: "plain_text",
      priorTurnShape: null,
      sizeLimits: { maxChars: 8_000 },
      allowedLanguages: ["en"],
    },
    "Context requirements": [
      {
        key: "visit.chief_complaint@v1",
        required: true,
        shapeRef: "visit.chief_complaint@v1",
        maxSize: 4_096,
      },
    ],
    "Prompt binding": {
      systemInstructionArtifactRef: `prompt/j3-system@v${version}`,
      businessRuleFragmentRefs: [],
      contextRenderingTemplateRef: "templates/j3@v1",
      outputFormatInstructionDerivationRule: "derive_from_output_mode",
    },
    Output: {
      mode: "prose",
      outputSchemaRef: null,
      businessValidationRuleRefs: [],
      repairPolicy: { allowed: false, maxAttempts: 0 },
    },
    Routing: {
      routingPolicyRef: FIXTURE_POLICY_REF,
      requiredProviderFeatures: {
        structuredOutput: false,
        contextWindow: 32_000,
        language: "en",
      },
      latencyClass: "standard",
      degradedTierPolicy: "fallback_chain",
    },
    Economics: {
      maxInputTokens: 8_000,
      maxOutputTokens: 1_024,
      perRequestTokenCeiling: 9_024,
      quotaWeight: 1,
    },
    Governance: {
      acceptanceMode: "advisory_display",
      retentionClass: "diagnostic_30d",
      evalSuiteRef: "evals/j3@v1",
    },
  };
}

function registerClinicJ3Capabilities(): void {
  const registry = createCapabilityRegistry([
    load(minimalCapabilityManifest(FIXTURE_CAPABILITY_V1)),
    load(minimalCapabilityManifest(FIXTURE_CAPABILITY_V2)),
  ]);
  setCapabilityRegistry(registry, { replace: true });
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

function buildPublishRequest(document: Record<string, unknown>): Request {
  return new Request(`${GATEWAY_ORIGIN}/control/routing-policies/publish`, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      authorization: `Bearer ${FAKE_OPERATOR_ID}`,
    },
    body: JSON.stringify({ document }),
  });
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

function buildPromoteRequest(version: string): Request {
  return new Request(
    `${GATEWAY_ORIGIN}/control/routing-policies/${FIXTURE_POLICY_ID}/versions/${version}/promote`,
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

async function publishAndPromoteVersion(
  handlers: Pick<
    RoutingControlHandlers,
    "handleRoutingPolicyPublish" | "handleRoutingPolicyPromote"
  >,
  bindings: { DB: D1Database; R2?: R2Bucket },
  operatorAuth: OperatorAuth,
  version: number,
  providerId: string,
): Promise<void> {
  const versionKey = String(version);
  const publish = await handlers.handleRoutingPolicyPublish(
    buildPublishRequest(policyDocument(version, providerId)),
    bindings,
    operatorAuth,
  );
  expect(publish.ok).toBe(true);

  const promote = await handlers.handleRoutingPolicyPromote(
    buildPromoteRequest(versionKey),
    bindings,
    operatorAuth,
  );
  expect(promote.ok).toBe(true);
}

async function publishAndPromoteV1(
  handlers: Pick<
    RoutingControlHandlers,
    "handleRoutingPolicyPublish" | "handleRoutingPolicyPromote"
  >,
  bindings: { DB: D1Database; R2?: R2Bucket },
  operatorAuth: OperatorAuth,
): Promise<void> {
  await publishAndPromoteVersion(
    handlers,
    bindings,
    operatorAuth,
    1,
    "deepseek",
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
      capabilityId: FIXTURE_CAPABILITY_ID,
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

async function assertAuditPointersNonNull(
  db: D1Database,
  action: string,
  options: { requireBefore?: boolean; requireAfter?: boolean } = {},
): Promise<void> {
  const requireBefore = options.requireBefore ?? true;
  const requireAfter = options.requireAfter ?? true;
  const row = await db
    .prepare(
      `SELECT before_pointer, after_pointer FROM control_audit
       WHERE action = ? ORDER BY recorded_at DESC LIMIT 1`,
    )
    .bind(action)
    .first<{ before_pointer: string | null; after_pointer: string | null }>();

  expect(row).toBeTruthy();
  if (requireBefore) {
    expect(row!.before_pointer).not.toBeNull();
  }
  if (requireAfter) {
    expect(row!.after_pointer).not.toBeNull();
  }
}

async function countActiveRows(
  db: D1Database,
  policyId: string = FIXTURE_POLICY_ID,
): Promise<number> {
  const row = await db
    .prepare(
      `SELECT COUNT(*) AS count FROM routing_policy
       WHERE policy_id = ? AND status = 'active'`,
    )
    .bind(policyId)
    .first<{ count: number }>();
  return row?.count ?? 0;
}

async function assertExactlyOneActive(
  db: D1Database,
  policyId: string = FIXTURE_POLICY_ID,
): Promise<void> {
  expect(await countActiveRows(db, policyId)).toBe(1);
}

beforeAll(async () => {
  await applyPlatformSchema(env.DB, migrationSql);
  await applyPlatformSchema(env.DB, canaryMigrationSql);
  await applyPlatformSchema(env.DB, statusMigrationSql);
});

beforeEach(async () => {
  await clearTables(env.DB);
  vi.setSystemTime(new Date(FIXTURE_NOW));
  registerClinicJ3Capabilities();
});

describe("T-J3-04 every_activation_writes_control_audit_with_operator_identity", () => {
  it("covers all six control actions including routing_policy_promote", async () => {
    await seedInstallation(env.DB, COHORT_INSTALLATION_ID);
    await seedInstallation(env.DB, OTHER_INSTALLATION_ID);

    const operatorAuth = createFakeOperatorAuth();
    const bindings = { DB: env.DB, R2: env.R2 };
    const {
      handleRoutingPolicyPublish,
      handleRoutingPolicyCanary,
      handleRoutingPolicyPromote,
      handleRoutingPolicyRollback,
      handleCohortActivate,
      handleCohortPromote,
    } = await loadRoutingControlHandlers();

    await publishAndPromoteV1(
      { handleRoutingPolicyPublish, handleRoutingPolicyPromote },
      bindings,
      operatorAuth,
    );
    await assertControlAudit(env.DB, {
      operatorId: FAKE_OPERATOR_ID,
      action: "routing_policy_publish",
    });
    await assertControlAudit(env.DB, {
      operatorId: FAKE_OPERATOR_ID,
      action: "routing_policy_promote",
    });
    await assertAuditPointersNonNull(env.DB, "routing_policy_promote", {
      requireBefore: false,
      requireAfter: true,
    });

    const publishV2 = await handleRoutingPolicyPublish(
      buildPublishRequest( policyDocument(2, "gemini")),
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
    await assertAuditPointersNonNull(env.DB, "routing_policy_canary", {
      requireBefore: false,
      requireAfter: true,
    });

    const activate = await handleCohortActivate(
      buildCohortActivateRequest(
        FIXTURE_CAPABILITY_ID,
        FIXTURE_CAPABILITY_V2,
        [COHORT_INSTALLATION_ID],
      ),
      { DB: env.DB },
      operatorAuth,
    );
    expect(activate.ok).toBe(true);
    await assertControlAudit(env.DB, {
      operatorId: FAKE_OPERATOR_ID,
      action: "cohort_activate",
    });

    const promote = await handleCohortPromote(
      buildCohortPromoteRequest(FIXTURE_CAPABILITY_ID, FIXTURE_CAPABILITY_V2),
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
    await assertAuditPointersNonNull(env.DB, "routing_policy_rollback");

    expect(await countControlAuditsForAction(env.DB, "routing_policy_publish")).toBe(
      2,
    );
    expect(await countControlAuditsForAction(env.DB, "routing_policy_promote")).toBe(
      1,
    );

    const cache = new ConfigCache();
    const reader = createD1ConfigReader(env.DB, env.R2);
    for (const installationId of [COHORT_INSTALLATION_ID, OTHER_INSTALLATION_ID]) {
      const outcome = await routeForInstallation(installationId, cache, reader);
      expect(outcome.routing_decision.policy_version).toBe(1);
    }
  });
});

describe("routing_policy_canary_split", () => {
  it("canary cohort receives new policy version while others keep previous", async () => {
    await seedInstallation(env.DB, COHORT_INSTALLATION_ID);
    await seedInstallation(env.DB, OTHER_INSTALLATION_ID);

    const operatorAuth = createFakeOperatorAuth();
    const bindings = { DB: env.DB, R2: env.R2 };
    const {
      handleRoutingPolicyPublish,
      handleRoutingPolicyCanary,
      handleRoutingPolicyPromote,
    } = await loadRoutingControlHandlers();

    await publishAndPromoteV1(
      { handleRoutingPolicyPublish, handleRoutingPolicyPromote },
      bindings,
      operatorAuth,
    );

    expect(
      (
        await handleRoutingPolicyPublish(
          buildPublishRequest( policyDocument(2, "gemini")),
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

    await assertAuditPointersNonNull(env.DB, "routing_policy_canary", {
      requireBefore: false,
      requireAfter: true,
    });

    const cache = new ConfigCache();
    const reader = createD1ConfigReader(env.DB, env.R2);

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

  it("publish_does_not_activate_until_promote", async () => {
    await seedInstallation(env.DB, COHORT_INSTALLATION_ID);
    await seedInstallation(env.DB, OTHER_INSTALLATION_ID);

    const operatorAuth = createFakeOperatorAuth();
    const bindings = { DB: env.DB, R2: env.R2 };
    const { handleRoutingPolicyPublish, handleRoutingPolicyPromote } =
      await loadRoutingControlHandlers();

    await publishAndPromoteV1(
      { handleRoutingPolicyPublish, handleRoutingPolicyPromote },
      bindings,
      operatorAuth,
    );

    expect(
      (
        await handleRoutingPolicyPublish(
          buildPublishRequest( policyDocument(2, "gemini")),
          bindings,
          operatorAuth,
        )
      ).ok,
    ).toBe(true);

    const cache = new ConfigCache();
    const reader = createD1ConfigReader(env.DB, env.R2);
    for (const installationId of [COHORT_INSTALLATION_ID, OTHER_INSTALLATION_ID]) {
      const outcome = await routeForInstallation(installationId, cache, reader);
      expect(outcome.routing_decision.policy_version).toBe(1);
    }
  });

  it("rollback_restores_previous_policy_version", async () => {
    await seedInstallation(env.DB, COHORT_INSTALLATION_ID);
    await seedInstallation(env.DB, OTHER_INSTALLATION_ID);

    const operatorAuth = createFakeOperatorAuth();
    const bindings = { DB: env.DB, R2: env.R2 };
    const {
      handleRoutingPolicyPublish,
      handleRoutingPolicyCanary,
      handleRoutingPolicyPromote,
      handleRoutingPolicyRollback,
    } = await loadRoutingControlHandlers();

    await publishAndPromoteV1(
      { handleRoutingPolicyPublish, handleRoutingPolicyPromote },
      bindings,
      operatorAuth,
    );
    expect(
      (
        await handleRoutingPolicyPublish(
          buildPublishRequest( policyDocument(2, "gemini")),
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

    const rollback = await handleRoutingPolicyRollback(
      buildRollbackRequest(FIXTURE_VERSION_V2),
      bindings,
      operatorAuth,
    );
    expect(rollback.ok).toBe(true);
    await assertAuditPointersNonNull(env.DB, "routing_policy_rollback");

    const cache = new ConfigCache();
    const reader = createD1ConfigReader(env.DB, env.R2);
    for (const installationId of [COHORT_INSTALLATION_ID, OTHER_INSTALLATION_ID]) {
      const outcome = await routeForInstallation(installationId, cache, reader);
      expect(outcome.routing_decision.policy_version).toBe(1);
    }
  });

  it("promote_makes_canary_global", async () => {
    await seedInstallation(env.DB, COHORT_INSTALLATION_ID);
    await seedInstallation(env.DB, OTHER_INSTALLATION_ID);

    const operatorAuth = createFakeOperatorAuth();
    const bindings = { DB: env.DB, R2: env.R2 };
    const {
      handleRoutingPolicyPublish,
      handleRoutingPolicyCanary,
      handleRoutingPolicyPromote,
    } = await loadRoutingControlHandlers();

    await publishAndPromoteV1(
      { handleRoutingPolicyPublish, handleRoutingPolicyPromote },
      bindings,
      operatorAuth,
    );

    vi.setSystemTime(new Date("2026-08-03T12:01:00.000Z"));
    expect(
      (
        await handleRoutingPolicyPublish(
          buildPublishRequest( policyDocument(2, "gemini")),
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

    const promoteV2 = await handleRoutingPolicyPromote(
      buildPromoteRequest(FIXTURE_VERSION_V2),
      bindings,
      operatorAuth,
    );
    expect(promoteV2.ok).toBe(true);
    await assertControlAudit(env.DB, {
      operatorId: FAKE_OPERATOR_ID,
      action: "routing_policy_promote",
      target: `${FIXTURE_POLICY_ID}@${FIXTURE_VERSION_V2}`,
    });
    await assertAuditPointersNonNull(env.DB, "routing_policy_promote");

    const cache = new ConfigCache();
    const reader = createD1ConfigReader(env.DB, env.R2);
    for (const installationId of [COHORT_INSTALLATION_ID, OTHER_INSTALLATION_ID]) {
      const outcome = await routeForInstallation(installationId, cache, reader);
      expect(outcome.routing_decision.policy_version).toBe(2);
    }
  });

  it("rollback_after_promote_reactivates_prior", async () => {
    await seedInstallation(env.DB, COHORT_INSTALLATION_ID);
    await seedInstallation(env.DB, OTHER_INSTALLATION_ID);

    const operatorAuth = createFakeOperatorAuth();
    const bindings = { DB: env.DB, R2: env.R2 };
    const {
      handleRoutingPolicyPublish,
      handleRoutingPolicyPromote,
      handleRoutingPolicyRollback,
    } = await loadRoutingControlHandlers();

    await publishAndPromoteV1(
      { handleRoutingPolicyPublish, handleRoutingPolicyPromote },
      bindings,
      operatorAuth,
    );

    vi.setSystemTime(new Date("2026-08-03T12:01:00.000Z"));
    expect(
      (
        await handleRoutingPolicyPublish(
          buildPublishRequest( policyDocument(2, "gemini")),
          bindings,
          operatorAuth,
        )
      ).ok,
    ).toBe(true);
    expect(
      (
        await handleRoutingPolicyPromote(
          buildPromoteRequest(FIXTURE_VERSION_V2),
          bindings,
          operatorAuth,
        )
      ).ok,
    ).toBe(true);

    const rollback = await handleRoutingPolicyRollback(
      buildRollbackRequest(FIXTURE_VERSION_V2),
      bindings,
      operatorAuth,
    );
    expect(rollback.ok).toBe(true);
    await assertAuditPointersNonNull(env.DB, "routing_policy_rollback");

    const cache = new ConfigCache();
    const reader = createD1ConfigReader(env.DB, env.R2);
    for (const installationId of [COHORT_INSTALLATION_ID, OTHER_INSTALLATION_ID]) {
      const outcome = await routeForInstallation(installationId, cache, reader);
      expect(outcome.routing_decision.policy_version).toBe(1);
    }
  });

  it("published_versions_ordering_later_promote_wins", async () => {
    await seedInstallation(env.DB, COHORT_INSTALLATION_ID);

    const operatorAuth = createFakeOperatorAuth();
    const bindings = { DB: env.DB, R2: env.R2 };
    const { handleRoutingPolicyPublish, handleRoutingPolicyPromote } =
      await loadRoutingControlHandlers();

    await publishAndPromoteV1(
      { handleRoutingPolicyPublish, handleRoutingPolicyPromote },
      bindings,
      operatorAuth,
    );

    vi.setSystemTime(new Date("2026-08-03T13:00:00.000Z"));
    expect(
      (
        await handleRoutingPolicyPublish(
          buildPublishRequest( policyDocument(2, "gemini")),
          bindings,
          operatorAuth,
        )
      ).ok,
    ).toBe(true);
    expect(
      (
        await handleRoutingPolicyPromote(
          buildPromoteRequest(FIXTURE_VERSION_V2),
          bindings,
          operatorAuth,
        )
      ).ok,
    ).toBe(true);

    const active = await env.DB.prepare(
      `SELECT version, status, active_from FROM routing_policy
       WHERE policy_id = ? AND status = 'active'
       ORDER BY active_from DESC, rowid DESC LIMIT 1`,
    )
      .bind(FIXTURE_POLICY_ID)
      .first<{ version: string; status: string; active_from: string }>();

    expect(active?.version).toBe(FIXTURE_VERSION_V2);
    expect(active?.active_from).toBe("2026-08-03T13:00:00.000Z");

    const cache = new ConfigCache();
    const reader = createD1ConfigReader(env.DB, env.R2);
    const outcome = await routeForInstallation(
      COHORT_INSTALLATION_ID,
      cache,
      reader,
    );
    expect(outcome.routing_decision.policy_version).toBe(2);
  });

  it("rejects non-operator credentials on all routing mutations", async () => {
    const handlers = await loadRoutingControlHandlers();
    const bindings = { DB: env.DB, R2: env.R2 };
    const unauth = createFakeOperatorAuth(null);

    const responses = await Promise.all([
      handlers.handleRoutingPolicyPublish(
        buildPublishRequest( policyDocument(1, "deepseek")),
        bindings,
        unauth,
      ),
      handlers.handleRoutingPolicyCanary(
        buildCanaryRequest(FIXTURE_VERSION_V1, [COHORT_INSTALLATION_ID]),
        bindings,
        unauth,
      ),
      handlers.handleRoutingPolicyPromote(
        buildPromoteRequest(FIXTURE_VERSION_V1),
        bindings,
        unauth,
      ),
      handlers.handleRoutingPolicyRollback(
        buildRollbackRequest(FIXTURE_VERSION_V1),
        bindings,
        unauth,
      ),
    ]);

    for (const response of responses) {
      expect(response.status).toBe(401);
    }

    const auditCount = await env.DB.prepare(
      "SELECT COUNT(*) AS count FROM control_audit",
    ).first<{ count: number }>();
    expect(auditCount?.count ?? 0).toBe(0);
  });

  it("rejects empty installation_ids on canary with 400", async () => {
    await seedInstallation(env.DB, COHORT_INSTALLATION_ID);
    const operatorAuth = createFakeOperatorAuth();
    const bindings = { DB: env.DB, R2: env.R2 };
    const {
      handleRoutingPolicyPublish,
      handleRoutingPolicyCanary,
      handleRoutingPolicyPromote,
    } = await loadRoutingControlHandlers();

    await publishAndPromoteV1(
      { handleRoutingPolicyPublish, handleRoutingPolicyPromote },
      bindings,
      operatorAuth,
    );
    expect(
      (
        await handleRoutingPolicyPublish(
          buildPublishRequest( policyDocument(2, "gemini")),
          bindings,
          operatorAuth,
        )
      ).ok,
    ).toBe(true);

    const response = await handleRoutingPolicyCanary(
      buildCanaryRequest(FIXTURE_VERSION_V2, []),
      bindings,
      operatorAuth,
    );
    expect(response.status).toBe(400);
    expect(await response.json()).toEqual({ error: "missing_installation_ids" });
  });

  it("rejects malformed JSON on canary with 400", async () => {
    const { handleRoutingPolicyCanary } = await loadRoutingControlHandlers();
    const response = await handleRoutingPolicyCanary(
      new Request(
        `${GATEWAY_ORIGIN}/control/routing-policies/${FIXTURE_POLICY_ID}/versions/${FIXTURE_VERSION_V1}/canary`,
        {
          method: "POST",
          headers: {
            "content-type": "application/json",
            authorization: `Bearer ${FAKE_OPERATOR_ID}`,
          },
          body: "{not-json",
        },
      ),
      { DB: env.DB, R2: env.R2 },
      createFakeOperatorAuth(),
    );
    expect(response.status).toBe(400);
    expect(await response.json()).toEqual({ error: "invalid_json" });
  });

  it("rejects canary, promote, and rollback of unpublished version with 404", async () => {
    const operatorAuth = createFakeOperatorAuth();
    const bindings = { DB: env.DB, R2: env.R2 };
    const {
      handleRoutingPolicyCanary,
      handleRoutingPolicyPromote,
      handleRoutingPolicyRollback,
    } = await loadRoutingControlHandlers();

    const canary = await handleRoutingPolicyCanary(
      buildCanaryRequest("99", [COHORT_INSTALLATION_ID]),
      bindings,
      operatorAuth,
    );
    expect(canary.status).toBe(404);
    expect(await canary.json()).toEqual({ error: "policy_version_not_found" });

    const promote = await handleRoutingPolicyPromote(
      buildPromoteRequest("99"),
      bindings,
      operatorAuth,
    );
    expect(promote.status).toBe(404);
    expect(await promote.json()).toEqual({ error: "policy_version_not_found" });

    const rollback = await handleRoutingPolicyRollback(
      buildRollbackRequest("99"),
      bindings,
      operatorAuth,
    );
    expect(rollback.status).toBe(404);
    expect(await rollback.json()).toEqual({ error: "policy_version_not_found" });
  });

  it("rejects canary with unknown installation with 404", async () => {
    const operatorAuth = createFakeOperatorAuth();
    const bindings = { DB: env.DB, R2: env.R2 };
    const {
      handleRoutingPolicyPublish,
      handleRoutingPolicyCanary,
      handleRoutingPolicyPromote,
    } = await loadRoutingControlHandlers();

    await publishAndPromoteV1(
      { handleRoutingPolicyPublish, handleRoutingPolicyPromote },
      bindings,
      operatorAuth,
    );
    expect(
      (
        await handleRoutingPolicyPublish(
          buildPublishRequest( policyDocument(2, "gemini")),
          bindings,
          operatorAuth,
        )
      ).ok,
    ).toBe(true);

    const response = await handleRoutingPolicyCanary(
      buildCanaryRequest(FIXTURE_VERSION_V2, ["inst-does-not-exist"]),
      bindings,
      operatorAuth,
    );
    expect(response.status).toBe(404);
    expect(await response.json()).toEqual({ error: "installation_not_found" });
  });

  it("rejects canary of active version with 409 illegal_policy_transition", async () => {
    await seedInstallation(env.DB, COHORT_INSTALLATION_ID);
    const operatorAuth = createFakeOperatorAuth();
    const bindings = { DB: env.DB, R2: env.R2 };
    const {
      handleRoutingPolicyPublish,
      handleRoutingPolicyCanary,
      handleRoutingPolicyPromote,
    } = await loadRoutingControlHandlers();

    await publishAndPromoteV1(
      { handleRoutingPolicyPublish, handleRoutingPolicyPromote },
      bindings,
      operatorAuth,
    );
    await assertExactlyOneActive(env.DB);

    const response = await handleRoutingPolicyCanary(
      buildCanaryRequest(FIXTURE_VERSION_V1, [COHORT_INSTALLATION_ID]),
      bindings,
      operatorAuth,
    );
    expect(response.status).toBe(409);
    expect(await response.json()).toEqual({
      error: "illegal_policy_transition",
    });
    await assertExactlyOneActive(env.DB);
  });

  it("rejects rollback of sole active version with no superseded prior", async () => {
    await seedInstallation(env.DB, COHORT_INSTALLATION_ID);
    const operatorAuth = createFakeOperatorAuth();
    const bindings = { DB: env.DB, R2: env.R2 };
    const {
      handleRoutingPolicyPublish,
      handleRoutingPolicyPromote,
      handleRoutingPolicyRollback,
    } = await loadRoutingControlHandlers();

    await publishAndPromoteV1(
      { handleRoutingPolicyPublish, handleRoutingPolicyPromote },
      bindings,
      operatorAuth,
    );
    await assertExactlyOneActive(env.DB);

    const response = await handleRoutingPolicyRollback(
      buildRollbackRequest(FIXTURE_VERSION_V1),
      bindings,
      operatorAuth,
    );
    expect(response.status).toBe(409);
    expect(await response.json()).toEqual({
      error: "illegal_policy_transition",
    });
    await assertExactlyOneActive(env.DB);
  });

  it("keeps exactly one active row per policy after every mutation", async () => {
    await seedInstallation(env.DB, COHORT_INSTALLATION_ID);
    await seedInstallation(env.DB, OTHER_INSTALLATION_ID);

    const operatorAuth = createFakeOperatorAuth();
    const bindings = { DB: env.DB, R2: env.R2 };
    const {
      handleRoutingPolicyPublish,
      handleRoutingPolicyCanary,
      handleRoutingPolicyPromote,
      handleRoutingPolicyRollback,
    } = await loadRoutingControlHandlers();

    await publishAndPromoteV1(
      { handleRoutingPolicyPublish, handleRoutingPolicyPromote },
      bindings,
      operatorAuth,
    );
    await assertExactlyOneActive(env.DB);

    vi.setSystemTime(new Date("2026-08-03T12:01:00.000Z"));
    expect(
      (
        await handleRoutingPolicyPublish(
          buildPublishRequest( policyDocument(2, "gemini")),
          bindings,
          operatorAuth,
        )
      ).ok,
    ).toBe(true);
    await assertExactlyOneActive(env.DB);

    expect(
      (
        await handleRoutingPolicyCanary(
          buildCanaryRequest(FIXTURE_VERSION_V2, [COHORT_INSTALLATION_ID]),
          bindings,
          operatorAuth,
        )
      ).ok,
    ).toBe(true);
    await assertExactlyOneActive(env.DB);

    expect(
      (
        await handleRoutingPolicyRollback(
          buildRollbackRequest(FIXTURE_VERSION_V2),
          bindings,
          operatorAuth,
        )
      ).ok,
    ).toBe(true);
    await assertExactlyOneActive(env.DB);

    expect(
      (
        await handleRoutingPolicyCanary(
          buildCanaryRequest(FIXTURE_VERSION_V2, [COHORT_INSTALLATION_ID]),
          bindings,
          operatorAuth,
        )
      ).ok,
    ).toBe(true);
    await assertExactlyOneActive(env.DB);

    expect(
      (
        await handleRoutingPolicyPromote(
          buildPromoteRequest(FIXTURE_VERSION_V2),
          bindings,
          operatorAuth,
        )
      ).ok,
    ).toBe(true);
    await assertExactlyOneActive(env.DB);

    expect(
      (
        await handleRoutingPolicyRollback(
          buildRollbackRequest(FIXTURE_VERSION_V2),
          bindings,
          operatorAuth,
        )
      ).ok,
    ).toBe(true);
    await assertExactlyOneActive(env.DB);
  });
});

describe("routing_policy_publish_document_validation", () => {
  it("rejects invalid policy identity with 400 invalid_policy_identity and does not persist", async () => {
    const operatorAuth = createFakeOperatorAuth();
    const bindings = { DB: env.DB, R2: env.R2 };
    const { handleRoutingPolicyPublish } = await loadRoutingControlHandlers();
    const valid = policyDocument(1, "deepseek");

    const missingPolicyId = { ...valid };
    delete missingPolicyId.policy_id;
    const missingId = await handleRoutingPolicyPublish(
      buildPublishRequest(missingPolicyId),
      bindings,
      operatorAuth,
    );
    expect(missingId.status).toBe(400);
    expect(await missingId.json()).toEqual({
      error: "invalid_policy_identity",
    });

    const stringVersion = await handleRoutingPolicyPublish(
      buildPublishRequest({ ...valid, policy_version: "1" }),
      bindings,
      operatorAuth,
    );
    expect(stringVersion.status).toBe(400);
    expect(await stringVersion.json()).toEqual({
      error: "invalid_policy_identity",
    });

    const zeroVersion = await handleRoutingPolicyPublish(
      buildPublishRequest({ ...valid, policy_version: 0 }),
      bindings,
      operatorAuth,
    );
    expect(zeroVersion.status).toBe(400);
    expect(await zeroVersion.json()).toEqual({
      error: "invalid_policy_identity",
    });

    const nonIntegerVersion = await handleRoutingPolicyPublish(
      buildPublishRequest({ ...valid, policy_version: 1.5 }),
      bindings,
      operatorAuth,
    );
    expect(nonIntegerVersion.status).toBe(400);
    expect(await nonIntegerVersion.json()).toEqual({
      error: "invalid_policy_identity",
    });

    const emptyPolicyId = await handleRoutingPolicyPublish(
      buildPublishRequest({ ...valid, policy_id: "" }),
      bindings,
      operatorAuth,
    );
    expect(emptyPolicyId.status).toBe(400);
    expect(await emptyPolicyId.json()).toEqual({
      error: "invalid_policy_identity",
    });

    const stored = await env.DB
      .prepare("SELECT COUNT(*) AS count FROM routing_policy")
      .first<{ count: number }>();
    expect(stored?.count ?? 0).toBe(0);
    expect(
      await env.R2.get(
        `control/routing-policy/${FIXTURE_POLICY_ID}/${FIXTURE_VERSION_V1}.json`,
      ),
    ).toBeNull();
  });

  it("warns with unreferenced_policy when no manifest references the policy identity", async () => {
    const operatorAuth = createFakeOperatorAuth();
    const bindings = { DB: env.DB, R2: env.R2 };
    const { handleRoutingPolicyPublish } = await loadRoutingControlHandlers();
    const unreferencedPolicyId = "orphan-policy";
    const document = {
      ...policyDocument(1, "deepseek"),
      policy_id: unreferencedPolicyId,
    };

    const response = await handleRoutingPolicyPublish(
      buildPublishRequest(document),
      bindings,
      operatorAuth,
    );
    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({
      warnings: ["unreferenced_policy"],
    });

    const stored = await env.DB
      .prepare(
        `SELECT COUNT(*) AS count FROM routing_policy
         WHERE policy_id = ? AND version = ?`,
      )
      .bind(unreferencedPolicyId, FIXTURE_VERSION_V1)
      .first<{ count: number }>();
    expect(stored?.count ?? 0).toBe(1);
    const object = await env.R2.get(
      `control/routing-policy/${unreferencedPolicyId}/${FIXTURE_VERSION_V1}.json`,
    );
    expect(object).not.toBeNull();
    const published = JSON.parse(await object!.text()) as { policy_id: string };
    expect(published.policy_id).toBe(unreferencedPolicyId);
  });

  it("warns on publish when no target latency_class matches published visit-summary", async () => {
    const operatorAuth = createFakeOperatorAuth();
    const bindings = { DB: env.DB, R2: env.R2 };
    const { handleRoutingPolicyPublish } = await loadRoutingControlHandlers();

    const unmatchedPublish = await handleRoutingPolicyPublish(
      buildPublishRequest( policyDocument(1, "deepseek")),
      bindings,
      operatorAuth,
    );
    expect(unmatchedPublish.status).toBe(200);
    const unmatchedBody = (await unmatchedPublish.json()) as {
      warnings?: string[];
    };
    expect(unmatchedBody.warnings).toEqual(
      expect.arrayContaining(["latency_class_mismatch"]),
    );
  });

  it("does not warn when a target latency_class matches published visit-summary", async () => {
    const operatorAuth = createFakeOperatorAuth();
    const bindings = { DB: env.DB, R2: env.R2 };
    const { handleRoutingPolicyPublish } = await loadRoutingControlHandlers();

    const aligned = policyDocument(1, "deepseek");
    const alignedTargets = (
      aligned.rules as Array<{
        targets: Array<{ features: { latency_class: string } }>;
      }>
    )[0].targets;
    for (const target of alignedTargets) {
      target.features.latency_class = "standard";
    }

    const alignedPublish = await handleRoutingPolicyPublish(
      buildPublishRequest( aligned),
      bindings,
      operatorAuth,
    );
    expect(alignedPublish.status).toBe(200);
    const alignedBody = (await alignedPublish.json()) as {
      warnings?: string[];
    };
    expect(alignedBody.warnings ?? []).not.toContain("latency_class_mismatch");
  });
});

describe("routing_policy_control_robustness", () => {
  it("rejects duplicate publish of the same policy version with 409 already_published", async () => {
    const operatorAuth = createFakeOperatorAuth();
    const bindings = { DB: env.DB, R2: env.R2 };
    const { handleRoutingPolicyPublish } = await loadRoutingControlHandlers();
    const document = policyDocument(1, "deepseek");

    const first = await handleRoutingPolicyPublish(
      buildPublishRequest( document),
      bindings,
      operatorAuth,
    );
    expect(first.status).toBe(200);

    const duplicate = await handleRoutingPolicyPublish(
      buildPublishRequest( document),
      bindings,
      operatorAuth,
    );
    expect(duplicate.status).toBe(409);
    expect(await duplicate.json()).toEqual({ error: "already_published" });

    const stored = await env.DB
      .prepare(
        `SELECT COUNT(*) AS count FROM routing_policy
         WHERE policy_id = ? AND version = ?`,
      )
      .bind(FIXTURE_POLICY_ID, FIXTURE_VERSION_V1)
      .first<{ count: number }>();
    expect(stored?.count ?? 0).toBe(1);
    expect(
      await countControlAuditsForAction(env.DB, "routing_policy_publish"),
    ).toBe(1);
  });

  it("does not overwrite the published R2 document on 409 already_published", async () => {
    const operatorAuth = createFakeOperatorAuth();
    const bindings = { DB: env.DB, R2: env.R2 };
    const { handleRoutingPolicyPublish } = await loadRoutingControlHandlers();
    const original = policyDocument(1, "deepseek");
    const conflicting = policyDocument(1, "gemini");

    const first = await handleRoutingPolicyPublish(
      buildPublishRequest( original),
      bindings,
      operatorAuth,
    );
    expect(first.status).toBe(200);

    const duplicate = await handleRoutingPolicyPublish(
      buildPublishRequest( conflicting),
      bindings,
      operatorAuth,
    );
    expect(duplicate.status).toBe(409);
    expect(await duplicate.json()).toEqual({ error: "already_published" });

    const stored = await env.R2.get(
      `control/routing-policy/${FIXTURE_POLICY_ID}/${FIXTURE_VERSION_V1}.json`,
    );
    expect(stored).not.toBeNull();
    const published = JSON.parse(await stored!.text()) as {
      rules: Array<{ targets: Array<{ provider_id: string }> }>;
    };
    expect(published.rules[0]?.targets[0]?.provider_id).toBe("deepseek");
    expect(published.rules[0]?.targets[0]?.provider_id).not.toBe("gemini");
  });

  it("rollback resurrects later rowid when superseded versions share active_from", async () => {
    await seedInstallation(env.DB, COHORT_INSTALLATION_ID);

    const operatorAuth = createFakeOperatorAuth();
    const bindings = { DB: env.DB, R2: env.R2 };
    const {
      handleRoutingPolicyPublish,
      handleRoutingPolicyPromote,
      handleRoutingPolicyRollback,
    } = await loadRoutingControlHandlers();
    const handlers = { handleRoutingPolicyPublish, handleRoutingPolicyPromote };

    vi.setSystemTime(new Date("2026-08-03T12:00:00.000Z"));
    await publishAndPromoteVersion(handlers, bindings, operatorAuth, 9, "deepseek");
    await publishAndPromoteVersion(handlers, bindings, operatorAuth, 10, "gemini");

    const tied = await env.DB
      .prepare(
        `SELECT version, active_from FROM routing_policy
         WHERE policy_id = ? AND version IN ('9', '10')
         ORDER BY rowid`,
      )
      .bind(FIXTURE_POLICY_ID)
      .all<{ version: string; active_from: string }>();
    expect(tied.results).toEqual([
      { version: "9", active_from: "2026-08-03T12:00:00.000Z" },
      { version: "10", active_from: "2026-08-03T12:00:00.000Z" },
    ]);

    vi.setSystemTime(new Date("2026-08-03T12:01:00.000Z"));
    await publishAndPromoteVersion(handlers, bindings, operatorAuth, 11, "deepseek");

    const rollback = await handleRoutingPolicyRollback(
      buildRollbackRequest("11"),
      bindings,
      operatorAuth,
    );
    expect(rollback.status).toBe(200);

    const active = await env.DB
      .prepare(
        `SELECT version FROM routing_policy
         WHERE policy_id = ? AND status = 'active'`,
      )
      .bind(FIXTURE_POLICY_ID)
      .first<{ version: string }>();
    expect(active?.version).toBe("10");

    const cache = new ConfigCache();
    const reader = createD1ConfigReader(env.DB, env.R2);
    const outcome = await routeForInstallation(
      COHORT_INSTALLATION_ID,
      cache,
      reader,
    );
    expect(outcome.routing_decision.policy_version).toBe(10);
  });

  it("promote audit before_pointer uses later rowid when two actives share active_from", async () => {
    const operatorAuth = createFakeOperatorAuth();
    const bindings = { DB: env.DB, R2: env.R2 };
    const { handleRoutingPolicyPublish, handleRoutingPolicyPromote } =
      await loadRoutingControlHandlers();
    const sameFrom = "2026-08-03T12:00:00.000Z";

    await env.DB.batch([
      env.DB.prepare(
        `INSERT INTO routing_policy (
           policy_id, version, content_pointer, active_from, activated_by,
           canary_installation_ids, status
         ) VALUES (?, '9', 'control/routing-policy/standard/9.json', ?, ?, NULL, 'active')`,
      ).bind(FIXTURE_POLICY_ID, sameFrom, FAKE_OPERATOR_ID),
      env.DB.prepare(
        `INSERT INTO routing_policy (
           policy_id, version, content_pointer, active_from, activated_by,
           canary_installation_ids, status
         ) VALUES (?, '10', 'control/routing-policy/standard/10.json', ?, ?, NULL, 'active')`,
      ).bind(FIXTURE_POLICY_ID, sameFrom, FAKE_OPERATOR_ID),
    ]);

    const publish = await handleRoutingPolicyPublish(
      buildPublishRequest( policyDocument(11, "deepseek")),
      bindings,
      operatorAuth,
    );
    expect(publish.status).toBe(200);

    const promote = await handleRoutingPolicyPromote(
      buildPromoteRequest("11"),
      bindings,
      operatorAuth,
    );
    expect(promote.status).toBe(200);

    await assertControlAudit(env.DB, {
      operatorId: FAKE_OPERATOR_ID,
      action: "routing_policy_promote",
      target: `${FIXTURE_POLICY_ID}@11`,
    });
    const audit = await env.DB
      .prepare(
        `SELECT before_pointer FROM control_audit
         WHERE action = 'routing_policy_promote'
         ORDER BY recorded_at DESC LIMIT 1`,
      )
      .first<{ before_pointer: string | null }>();
    expect(audit?.before_pointer).toBe(`${FIXTURE_POLICY_ID}@10`);
  });
});
