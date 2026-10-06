/**
 * System-test harness — Wave 1 foundation (plan §3.2 / §3.3).
 */

import { vi } from "vitest";

const { artifactByRef, resolveArtifactMock, resolvePromptVersionMock } =
  vi.hoisted(() => {
    const artifactByRef: Record<string, string> = {
      "clinic.visit_summary/system@v1":
        "You are a clinical documentation assistant.\n",
      "clinic.visit_summary/rules-visit-summary@v1":
        "## Rules\n- Advisory only.\n",
      "clinic.visit_summary/template-visit-summary@v1":
        '<key name="visit.chief_complaint@v1">{{visit.chief_complaint@v1}}</key>\n',
    };

    function fnv1a(content: string): string {
      let hash = 0x811c9dc5;
      for (let index = 0; index < content.length; index += 1) {
        hash ^= content.charCodeAt(index);
        hash = Math.imul(hash, 0x01000193);
      }
      return (hash >>> 0).toString(16).padStart(8, "0");
    }

    return {
      artifactByRef,
      resolveArtifactMock(ref: string): string | undefined {
        return artifactByRef[ref];
      },
      resolvePromptVersionMock(manifest: {
        "Prompt binding": {
          systemInstructionArtifactRef: unknown;
          businessRuleFragmentRefs?: unknown;
          contextRenderingTemplateRef?: unknown;
        };
      }): string {
        const binding = manifest["Prompt binding"];
        const refs = [
          String(binding.systemInstructionArtifactRef),
          ...(Array.isArray(binding.businessRuleFragmentRefs)
            ? binding.businessRuleFragmentRefs.map(String)
            : []),
          ...(binding.contextRenderingTemplateRef != null &&
            String(binding.contextRenderingTemplateRef).length > 0
            ? [String(binding.contextRenderingTemplateRef)]
            : []),
        ];
        const parts = refs
          .map((ref) => artifactByRef[ref])
          .filter((content): content is string => content !== undefined);
        return fnv1a(parts.join("\0"));
      },
    };
  });

vi.mock("../../src/prompt/registry", () => ({
  resolveArtifact: resolveArtifactMock,
  resolvePromptVersion: resolvePromptVersionMock,
}));

import { env, SELF, runDurableObjectAlarm } from "cloudflare:test";
import { CHANNEL_VERSIONS, grantIdPaid, sha256Hex } from "vendor-contracts";
import { createAboGrantSigner, createSoftwareAuthenticator } from "vendor-contracts/testkit";
import migrationSql from "../../migrations/20260731120000_platform_schema.sql?raw";
import capabilityGrantLifecycleSql from "../../migrations/20260802100000_capability_grant_lifecycle.sql?raw";
import canaryMigrationSql from "../../migrations/20260803100000_routing_policy_canary.sql?raw";
import tokenContractMigrationSql from "../../migrations/20260803120000_token_contract.sql?raw";
import retentionIndexesSql from "../../migrations/20260805120000_f3_retention_indexes.sql?raw";
import conversationIndexSql from "../../migrations/20260805180000_h3_conversation_index.sql?raw";
import statusMigrationSql from "../../migrations/20260805190000_routing_policy_status.sql?raw";
import killSwitchMigrationSql from "../../migrations/20260807120000_kill_switch.sql?raw";
import graceQueueMigrationSql from "../../migrations/20260821120000_grace_admission_queue.sql?raw";
import entitlementUniqueSql from "../../migrations/20260821130000_entitlement_installation_unique.sql?raw";
import planCatalogueSql from "../../migrations/20260911120000_plan_catalogue.sql?raw";
import quotaWeightMigrationSql from "../../migrations/20260911180000_usage_rollup_quota_weight.sql?raw";
import invoiceMigrationSql from "../../migrations/20260911200000_invoice.sql?raw";
import operatorCredentialMigrationSql from "../../migrations/20261003120000_operator_credential_and_platform_alert.sql?raw";
import issuerKeyTenantBindingMigrationSql from "../../migrations/20261003130000_issuer_key_tenant_binding.sql?raw";
import planVersionPaidGrantCoverageMigrationSql from "../../migrations/20261003140000_plan_version_paid_grant_coverage.sql?raw";
import usageTermMigrationSql from "../../migrations/20261006120000_usage_term.sql?raw";
import ceilingPolicyMigrationSql from "../../migrations/20261006130000_ceiling_policy.sql?raw";
import grantVoidMigrationSql from "../../migrations/20261006140000_grant_void.sql?raw";
import transferMigrationSql from "../../migrations/20261006150000_transfer.sql?raw";
import fallbackAdmissionFeedMigrationSql from "../../migrations/20261006160000_fallback_admission_feed.sql?raw";
import dropInvoicingSql from "../../migrations/20261006170000_drop_invoicing.sql?raw";
import dropPlanEntitlementSql from "../../migrations/20261006170100_drop_plan_entitlement.sql?raw";
import { applySqlStatements } from "../split-sql-statements";
import {
  createCapabilityRegistry,
  setCapabilityRegistry,
} from "../../src/capability";
import { VISIT_CHIEF_COMPLAINT_V1 } from "../../src/context";
import { isolateConfigCache } from "../../src/config-cache";
import { load, type Manifest } from "../../src/manifest";

declare module "cloudflare:test" {
  interface ProvidedEnv {
    DB: D1Database;
    R2: R2Bucket;
    DO: DurableObjectNamespace;
    OPERATOR_BEARER_TOKEN: string;
    OPERATOR_ID: string;
    RATE_LIMITER_INSTALLATION: RateLimit;
    RATE_LIMITER_INSTALLATION_ACTOR: RateLimit;
    RATE_LIMITER_INSTALLATION_CAPABILITY: RateLimit;
    BUILD_SHA: string;
    ENVIRONMENT: string;
    VENDOR: {
      registerOperatorCredential(
        args: Record<string, unknown>,
      ): Promise<VendorResultEnvelope>;
      revokeOperatorCredential(
        args: Record<string, unknown>,
      ): Promise<VendorResultEnvelope>;
      listOperatorCredentials(
        args: Record<string, unknown>,
      ): Promise<VendorResultEnvelope>;
      registerIssuerKey(
        args: Record<string, unknown>,
      ): Promise<VendorResultEnvelope>;
    };
    TEST_CLOCK: string;
    ACCESS_TEAM_DOMAIN: string;
    ACCESS_AUD: string;
    WEBAUTHN_RP_ID: string;
    WEBAUTHN_ORIGIN: string;
    HEARTBEAT_URL: string;
    ALERT_EMAIL_TO: string;
    SEND_EMAIL: {
      send(message: {
        from: string;
        to: string;
        subject: string;
        text: string;
      }): Promise<void>;
    };
  }
}

export const GATEWAY_ORIGIN = "https://ai-gateway.test";
export const ISSUER_ID =
  (env as { ISSUER_ID?: string }).ISSUER_ID ?? "issuer-test";
const VENDOR_CONTRACT_VERSION = CHANNEL_VERSIONS.vendorEntrypoint;
export const OPERATOR_BEARER = "test-operator-bearer-token";
export const OPERATOR_ID = "operator-test-principal";
export const CAPABILITY_ID = "clinic.visit_summary";
export const CAPABILITY_VERSION = "1.0.0";
export const POLICY_ID = "standard";
export const POLICY_VERSION = "1";
export const POLICY_REF = "routing/standard";

export const PLATFORM_TABLES = [
  "installation",
  "issuer_key",
  "tenant_binding",
  "capability_grant",
  "routing_policy",
  "kill_switch",
  "token_contract",
  "ai_request",
  "ai_attempt",
  "usage_event",
  "usage_rollup",
  "platform_counter",
  "control_audit",
  "fallback_admission",
  "feed_consumer",
  "plan_version",
  "coverage_mirror",
  "grant_ledger",
] as const;

export type SseEvent = { event: string; data: Record<string, unknown> };

export type TestKeypair = {
  publicKey: CryptoKey;
  privateKey: CryptoKey;
  kid: string;
  publicKeyB64: string;
};

export type Scenario = {
  installationId: string;
  orgId: string;
  branchId: string;
  actorId: string;
  kid: string;
  keypair: TestKeypair;
  /** Plan stored on the pending entitlement enroll used to write. */
  plan?: string;
};

export type AatClaims = {
  iss: string;
  aud: string;
  sub: string;
  org: string;
  branch: string;
  role: string;
  scopes: string[];
  jti: string;
  iat: number;
  exp: number;
  ver: string;
};

export type EntitlePayload = {
  period_start: string;
  period_end: string;
  request_quota: number;
  token_budget: number;
  cost_budget: number;
  /**
   * G2 (057): optional catalogue-plan credit budget override. The entitle
   * endpoint ignores unknown body fields; this only steers `seedCataloguePlan`.
   * Defaults to the G1 live-plan default (10_000) when omitted.
   */
  credit_budget?: number;
  soft_threshold: number;
  allowed_capabilities: string[];
  grants: Array<{
    capability_id: string;
    capability_version: string;
    scope?: "installation" | "plan";
  }>;
};

export const DEFAULT_ENTITLE_PAYLOAD: EntitlePayload = {
  period_start: "2026-07-01T00:00:00.000Z",
  period_end: "2026-09-01T00:00:00.000Z",
  request_quota: 1000,
  token_budget: 500000,
  cost_budget: 50.0,
  soft_threshold: 0.8,
  allowed_capabilities: [CAPABILITY_ID],
  grants: [
    {
      capability_id: CAPABILITY_ID,
      capability_version: CAPABILITY_VERSION,
      scope: "installation",
    },
    {
      capability_id: CAPABILITY_ID,
      capability_version: CAPABILITY_VERSION,
      scope: "plan",
    },
  ],
};

const MIGRATION_SQL = [
  migrationSql,
  capabilityGrantLifecycleSql,
  canaryMigrationSql,
  tokenContractMigrationSql,
  retentionIndexesSql,
  conversationIndexSql,
  statusMigrationSql,
  killSwitchMigrationSql,
  graceQueueMigrationSql,
  entitlementUniqueSql,
  planCatalogueSql,
  quotaWeightMigrationSql,
  invoiceMigrationSql,
  operatorCredentialMigrationSql,
  issuerKeyTenantBindingMigrationSql,
  planVersionPaidGrantCoverageMigrationSql,
  usageTermMigrationSql,
  ceilingPolicyMigrationSql,
  grantVoidMigrationSql,
  transferMigrationSql,
  fallbackAdmissionFeedMigrationSql,
  dropInvoicingSql,
  dropPlanEntitlementSql,
];

const CATALOGUE_PLAN_NAME = "standard";

/**
 * G1 live-plan default credit budget (mirrors `DEFAULT_PLAN_PAYLOAD` in
 * `test/plan-catalogue.test.ts`). G2 admission treats `creditsUsed >=
 * credit_budget` as exhausted, so a live plan must seed a positive budget;
 * `0` would fail admission immediately (`0 >= 0`).
 */
const DEFAULT_PLAN_CREDIT_BUDGET = 10_000;

async function seedCataloguePlan(
  _db: D1Database,
  _payload: EntitlePayload = DEFAULT_ENTITLE_PAYLOAD,
  _planName: string = CATALOGUE_PLAN_NAME,
): Promise<void> {
  // Transitional `plan` catalogue removed in P3.10; coverage uses plan_version.
}

let migrationsApplied = false;

function base64urlEncode(data: string | Uint8Array): string {
  const bytes =
    typeof data === "string" ? new TextEncoder().encode(data) : data;
  let binary = "";
  for (const byte of bytes) {
    binary += String.fromCharCode(byte);
  }
  return btoa(binary)
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/u, "");
}

function randomUuid(): string {
  return crypto.randomUUID();
}

function nowSeconds(): number {
  return Math.floor(Date.now() / 1000);
}

export async function applySql(db: D1Database, sql: string): Promise<void> {
  await applySqlStatements(db, sql);
}

export async function applyAllMigrations(db: D1Database): Promise<void> {
  if (migrationsApplied) {
    return;
  }
  for (const sql of MIGRATION_SQL) {
    await applySql(db, sql);
  }
  await db
    .prepare(
      `INSERT OR IGNORE INTO token_contract (ver, added_at, retired_at, changed_by)
       VALUES ('1', '2026-08-03T00:00:00.000Z', NULL, 'seed')`,
    )
    .run();
  await seedCataloguePlan(db);
  await ensureHarnessTestClockTable();
  await ensureHarnessAdmissionFaultTable();
  migrationsApplied = true;
}

export async function resetPlatformState(): Promise<void> {
  await ensureHarnessTestClockTable();
  await env.DB.batch([
    env.DB.prepare("DELETE FROM platform_alert"),
    env.DB.prepare("DELETE FROM assertion_used"),
    env.DB.prepare("DELETE FROM operator_credential"),
    env.DB.prepare("DELETE FROM harness_test_clock"),
    env.DB.prepare("DELETE FROM control_audit"),
    env.DB.prepare("DELETE FROM fallback_admission"),
    env.DB.prepare("DELETE FROM feed_consumer"),
    env.DB.prepare("DELETE FROM harness_admission_fault"),
    env.DB.prepare("DELETE FROM platform_counter"),
    env.DB.prepare("DELETE FROM usage_rollup"),
    env.DB.prepare("DELETE FROM usage_event"),
    env.DB.prepare("DELETE FROM ai_attempt"),
    env.DB.prepare("DELETE FROM ai_request"),
    env.DB.prepare("DELETE FROM capability_grant"),
    env.DB.prepare("DELETE FROM routing_policy"),
    env.DB.prepare("DELETE FROM kill_switch"),
    env.DB.prepare("DELETE FROM coverage_event"),
    env.DB.prepare("DELETE FROM grant_void"),
    env.DB.prepare("DELETE FROM transfer_step"),
    env.DB.prepare("DELETE FROM transfer"),
    env.DB.prepare("DELETE FROM grant_ledger"),
    env.DB.prepare("DELETE FROM coverage_mirror"),
    env.DB.prepare("DELETE FROM plan_version"),
    env.DB.prepare("DELETE FROM service_key"),
    env.DB.prepare("DELETE FROM tenant_binding"),
    env.DB.prepare("DELETE FROM issuer_key"),
    env.DB.prepare("DELETE FROM installation"),
    env.DB.prepare("DELETE FROM token_contract"),
  ]);

  await env.DB.batch([
    env.DB.prepare(
      `INSERT INTO token_contract (ver, added_at, retired_at, changed_by)
       VALUES ('2', '2026-10-03T13:00:00.000Z', NULL, 'seed')`,
    ),
    env.DB.prepare(
      `INSERT INTO token_contract (ver, added_at, retired_at, changed_by)
       VALUES ('1', '2026-08-03T00:00:00.000Z', '2026-10-03T13:00:00.000Z', 'seed')`,
    ),
  ]);
  await seedCataloguePlan(env.DB);
  vendorTestClockIso = null;
  clearHarnessIssuerRegistry();
  clearCoverClinicBootstrap();
  clearEntitlementHarnessState();
}

export function visitSummaryManifest(): Manifest {
  return load({
    Identity: {
      capabilityId: CAPABILITY_ID,
      version: CAPABILITY_VERSION,
      title: "Visit summary",
      lifecycleState: "active",
      successorId: null,
    },
    Access: {
      requiredCapabilityScope: "ai.visit_summary",
      minimumPlanTier: "standard",
      allowedStaffRoles: ["administrator", "clinician", "nurse"],
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
        key: VISIT_CHIEF_COMPLAINT_V1,
        required: true,
        shapeRef: VISIT_CHIEF_COMPLAINT_V1,
        maxSize: 4_096,
      },
    ],
    "Prompt binding": {
      systemInstructionArtifactRef: "clinic.visit_summary/system@v1",
      businessRuleFragmentRefs: ["clinic.visit_summary/rules-visit-summary@v1"],
      contextRenderingTemplateRef: "clinic.visit_summary/template-visit-summary@v1",
      outputFormatInstructionDerivationRule: "derive_from_output_mode",
    },
    Output: {
      mode: "prose",
      outputSchemaRef: null,
      businessValidationRuleRefs: [],
      repairPolicy: { allowed: false, maxAttempts: 0 },
    },
    Routing: {
      routingPolicyRef: POLICY_REF,
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
      evalSuiteRef: "evals/visit@v1",
    },
  });
}

export function registerVisitSummaryCapability(): void {
  setCapabilityRegistry(createCapabilityRegistry([visitSummaryManifest()]), {
    replace: true,
  });
}

async function generateKeypair(kid: string): Promise<TestKeypair> {
  const keyPair = await crypto.subtle.generateKey(
    { name: "Ed25519" },
    true,
    ["sign", "verify"],
  );
  const rawPublicKey = await crypto.subtle.exportKey("raw", keyPair.publicKey);
  return {
    publicKey: keyPair.publicKey,
    privateKey: keyPair.privateKey,
    kid,
    publicKeyB64: base64urlEncode(new Uint8Array(rawPublicKey)),
  };
}

export async function newScenario(): Promise<Scenario> {
  const installationId = randomUuid();
  const orgId = randomUuid();
  const branchId = randomUuid();
  const actorId = randomUuid();
  const kid = randomUuid();
  const keypair = await generateKeypair(kid);
  return { installationId, orgId, branchId, actorId, kid, keypair };
}

type HarnessIssuerRegistry = {
  kid: string;
  privateKey: CryptoKey;
  publicKeyB64: string;
  signerCredentialId: string;
  signerAuthenticator: Awaited<ReturnType<typeof createSoftwareAuthenticator>>;
};

let harnessIssuerRegistry: HarnessIssuerRegistry | null = null;

function clearHarnessIssuerRegistry(): void {
  harnessIssuerRegistry = null;
}

/** Re-register harness issuer after advancing the test clock (new `not_before`). */
export function resetHarnessIssuerRegistry(): void {
  clearHarnessIssuerRegistry();
}

async function harnessNowSeconds(): Promise<number> {
  const iso = getVendorTestClockIso();
  if (iso) {
    return Math.floor(Date.parse(iso) / 1000);
  }
  if (env.TEST_CLOCK === "1") {
    const row = await env.DB.prepare(
      "SELECT now_iso FROM harness_test_clock WHERE id = 'default'",
    ).first<{ now_iso: string }>();
    if (row?.now_iso) {
      const parsed = Date.parse(row.now_iso);
      if (!Number.isNaN(parsed)) {
        return Math.floor(parsed / 1000);
      }
    }
  }
  return nowSeconds();
}

async function operationForRegisterIssuerKey(input: {
  kid: string;
  publicKey: string;
  notBefore: string;
  notAfter: string;
  accessJwt: string;
}): Promise<Record<string, unknown>> {
  return {
    op: "registerIssuerKey",
    params: {
      contract_version: VENDOR_CONTRACT_VERSION,
      access_jwt: input.accessJwt,
      kid: input.kid,
      public_key: input.publicKey,
      not_before: input.notBefore,
      not_after: input.notAfter,
    },
    actor_email: VENDOR_OPERATOR_EMAIL,
    issued_at: getVendorTestClockIso() ?? new Date().toISOString(),
    nonce: randomUuid(),
    contract_version: VENDOR_CONTRACT_VERSION,
  };
}

async function bootstrapHarnessOperatorCredential(
  authenticator: Awaited<ReturnType<typeof createSoftwareAuthenticator>>,
): Promise<{ credentialId: string; accessJwt: string }> {
  const existing = await env.DB.prepare(
    `SELECT credential_id FROM operator_credential
     WHERE status = 'active'
     ORDER BY rowid DESC
     LIMIT 1`,
  ).first<{ credential_id: string }>();
  if (existing?.credential_id) {
    return {
      credentialId: existing.credential_id,
      accessJwt: await mintVendorAccessJwt(),
    };
  }

  const credentialId = randomUuid();
  const attestation = encodeVendorAttestation(await authenticator.attest());
  const accessJwt = await mintVendorAccessJwt();
  const result = await vendorCall(
    "registerOperatorCredential",
    {
      contract_version: VENDOR_CONTRACT_VERSION,
      credential_id: credentialId,
      attestation,
    },
    { accessJwt },
  );
  if (result.result !== "ok") {
    throw new Error(`registerOperatorCredential failed: ${result.code}`);
  }
  const row = JSON.parse(result.detail) as Record<string, unknown>;
  await setTestClock(String(row.activates_at));
  return { credentialId, accessJwt };
}

async function ensureHarnessIssuerRegistered(): Promise<HarnessIssuerRegistry> {
  if (harnessIssuerRegistry !== null) {
    return harnessIssuerRegistry;
  }
  await setupVendorHarness();
  const signerAuthenticator = await createSoftwareAuthenticator("EdDSA");
  const { credentialId: signerCredentialId } =
    await bootstrapHarnessOperatorCredential(signerAuthenticator);

  const kid = randomUuid();
  const keyPair = await crypto.subtle.generateKey(
    { name: "Ed25519" },
    true,
    ["sign", "verify"],
  );
  const rawPublicKey = await crypto.subtle.exportKey("raw", keyPair.publicKey);
  const publicKeyB64 = base64urlEncode(new Uint8Array(rawPublicKey));
  const notBefore = getVendorTestClockIso() ?? new Date().toISOString();
  const notAfter = new Date(
    Date.parse(notBefore) + 365 * 24 * 60 * 60 * 1000,
  ).toISOString();
  const accessJwt = await mintVendorAccessJwt();
  const operation = await operationForRegisterIssuerKey({
    kid,
    publicKey: publicKeyB64,
    notBefore,
    notAfter,
    accessJwt,
  });
  const assertion = encodeVendorAssertion(
    await signerAuthenticator.assert({
      operation,
      rpId: env.WEBAUTHN_RP_ID,
      origin: env.WEBAUTHN_ORIGIN,
      up: true,
      uv: true,
    }),
  );
  const envelope = await vendorCall(
    "registerIssuerKey",
    {
      contract_version: VENDOR_CONTRACT_VERSION,
      kid,
      public_key: publicKeyB64,
      not_before: notBefore,
      not_after: notAfter,
      signer_credential_id: signerCredentialId,
      operation,
      assertion,
    },
    { accessJwt },
  );
  if (envelope.result !== "ok") {
    throw new Error(`registerIssuerKey failed: ${envelope.code}`);
  }

  harnessIssuerRegistry = {
    kid,
    privateKey: keyPair.privateKey,
    publicKeyB64,
    signerCredentialId,
    signerAuthenticator,
  };
  return harnessIssuerRegistry;
}

export async function mintAat(
  scenario: Scenario,
  overrides: Partial<AatClaims> = {},
): Promise<string> {
  const issuer = await ensureHarnessIssuerRegistered();
  const now = await harnessNowSeconds();
  const payload: AatClaims = {
    iss: ISSUER_ID,
    aud: "ai-platform",
    sub: scenario.actorId,
    org: scenario.orgId,
    branch: scenario.branchId,
    role: "clinician",
    scopes: ["ai.visit_summary", "ai.access"],
    jti: randomUuid(),
    iat: now - 30,
    exp: now + 300,
    ver: "2",
    ...overrides,
  };
  const header = { alg: "EdDSA", kid: issuer.kid, typ: "JWT" };
  const headerB64 = base64urlEncode(JSON.stringify(header));
  const payloadB64 = base64urlEncode(JSON.stringify(payload));
  const signingInput = `${headerB64}.${payloadB64}`;
  const signature = await crypto.subtle.sign(
    { name: "Ed25519" },
    issuer.privateKey,
    new TextEncoder().encode(signingInput),
  );
  return `${signingInput}.${base64urlEncode(new Uint8Array(signature))}`;
}

export function enrollPayload(scenario: Scenario): Record<string, unknown> {
  return {
    org_id: scenario.orgId,
    display_name: "System Test Clinic",
    region: "us-east-1",
    plan: "standard",
    public_key: scenario.keypair.publicKeyB64,
    algorithm: "EdDSA",
    kid: scenario.kid,
  };
}

export function vendorEnvelopeToHttp(
  envelope: VendorResultEnvelope,
): { status: number; json: Record<string, unknown> } {
  if (envelope.result === "ok") {
    const json =
      envelope.detail.length > 0
        ? (JSON.parse(envelope.detail) as Record<string, unknown>)
        : {};
    return { status: 200, json };
  }
  if (envelope.result === "conflict") {
    return { status: 409, json: { error: envelope.code } };
  }
  if (envelope.code === "unauthenticated") {
    return { status: 401, json: { error: "unauthorized" } };
  }
  if (
    envelope.code === "capability_not_found" ||
    envelope.code === "not_found" ||
    envelope.code === "installation_not_found"
  ) {
    return { status: 404, json: { error: envelope.code } };
  }
  return { status: 400, json: { error: envelope.code } };
}

const VENDOR_LIFECYCLE_REASON = "system-test";

export async function vendorSuspend(
  scenario: Scenario,
): Promise<{ status: number; json: Record<string, unknown> }> {
  const accessJwt = await mintVendorAccessJwt();
  return vendorEnvelopeToHttp(
    await vendorCall(
      "suspend",
      {
        contract_version: VENDOR_CONTRACT_VERSION,
        org_id: scenario.orgId,
        reason: VENDOR_LIFECYCLE_REASON,
      },
      { accessJwt },
    ),
  );
}

export async function vendorResume(
  scenario: Scenario,
): Promise<{ status: number; json: Record<string, unknown> }> {
  const accessJwt = await mintVendorAccessJwt();
  return vendorEnvelopeToHttp(
    await vendorCall(
      "resume",
      {
        contract_version: VENDOR_CONTRACT_VERSION,
        org_id: scenario.orgId,
        reason: VENDOR_LIFECYCLE_REASON,
      },
      { accessJwt },
    ),
  );
}

export async function vendorDeleteInstallation(
  scenario: Scenario,
  reason = "decommission",
): Promise<{ status: number; json: Record<string, unknown> }> {
  const signer = coverClinicSigner();
  const accessJwt = await mintVendorAccessJwt();
  const operation = {
    op: "deleteInstallation",
    params: {
      contract_version: VENDOR_CONTRACT_VERSION,
      access_jwt: accessJwt,
      org_id: scenario.orgId,
      reason,
    },
    actor_email: VENDOR_OPERATOR_EMAIL,
    issued_at: getVendorTestClockIso() ?? new Date().toISOString(),
    nonce: randomUuid(),
    contract_version: VENDOR_CONTRACT_VERSION,
  };
  const assertion = encodeVendorAssertion(
    await signer.signerAuthenticator.assert({
      operation,
      rpId: env.WEBAUTHN_RP_ID,
      origin: env.WEBAUTHN_ORIGIN,
      up: true,
      uv: true,
    }),
  );
  const envelope = await vendorCall(
    "deleteInstallation",
    {
      contract_version: VENDOR_CONTRACT_VERSION,
      org_id: scenario.orgId,
      reason,
      signer_credential_id: signer.signerCredentialId,
      operation,
      assertion,
    },
    { accessJwt },
  );
  if (envelope.result === "applied" || envelope.result === "ok") {
    return {
      status: 200,
      json:
        envelope.detail.length > 0
          ? (JSON.parse(envelope.detail) as Record<string, unknown>)
          : {},
    };
  }
  if (envelope.result === "conflict") {
    return { status: 409, json: { error: envelope.code } };
  }
  if (envelope.code === "unauthenticated") {
    return { status: 401, json: { error: "unauthorized" } };
  }
  return { status: 400, json: { error: envelope.code } };
}

export function visitSummaryInvokeBody(
  scenario: Scenario,
  overrides: Record<string, unknown> = {},
): Record<string, unknown> {
  return {
    capability_id: CAPABILITY_ID,
    capability_version: CAPABILITY_VERSION,
    user_intent: "Summarize the visit.",
    context: {
      org: scenario.orgId,
      branch: scenario.branchId,
      [VISIT_CHIEF_COMPLAINT_V1]: {
        visit_id: randomUuid(),
        complaint: "Headache for three days.",
        recorded_at: new Date().toISOString(),
      },
    },
    ...overrides,
  };
}

export async function parseSseEvents(response: Response): Promise<SseEvent[]> {
  const text = await response.text();
  const events: SseEvent[] = [];
  const blocks = text.split("\n\n").filter((block) => block.trim().length > 0);
  for (const block of blocks) {
    const lines = block.split("\n");
    let event = "";
    let data: Record<string, unknown> = {};
    for (const line of lines) {
      if (line.startsWith("event: ")) {
        event = line.slice(7);
      } else if (line.startsWith("data: ")) {
        data = JSON.parse(line.slice(6)) as Record<string, unknown>;
      }
    }
    if (event) {
      events.push({ event, data });
    }
  }
  return events;
}

export async function flushBackgroundWork(): Promise<void> {
  await new Promise((resolve) => setTimeout(resolve, 150));
}

export async function invoke(
  scenario: Scenario,
  opts: {
    token?: string;
    idempotencyKey?: string;
    traceId?: string;
    capabilityVersion?: string;
    body?: Record<string, unknown>;
    signal?: AbortSignal;
  } = {},
): Promise<{
  status: number;
  headers: Headers;
  body: Record<string, unknown> | null;
  events: SseEvent[];
}> {
  const token = opts.token ?? (await mintAat(scenario));
  const headers: Record<string, string> = {
    authorization: `Bearer ${token}`,
    "content-type": "application/json",
    "x-idempotency-key": opts.idempotencyKey ?? randomUuid(),
    "x-capability-version": opts.capabilityVersion ?? CAPABILITY_VERSION,
  };
  if (opts.traceId) {
    headers["x-trace-id"] = opts.traceId;
  }
  if (!headers["Aip-Contract-Version"]) {
    headers["Aip-Contract-Version"] = "1";
  }

  const response = await SELF.fetch(
    new Request(`${GATEWAY_ORIGIN}/v1/requests`, {
      method: "POST",
      headers,
      body: JSON.stringify(
        opts.body ?? visitSummaryInvokeBody(scenario),
      ),
      signal: opts.signal,
    }),
  );

  const contentType = response.headers.get("content-type") ?? "";
  if (contentType.includes("text/event-stream")) {
    const events = await parseSseEvents(response);
    await flushBackgroundWork();
    return {
      status: response.status,
      headers: response.headers,
      body: null,
      events,
    };
  }

  const text = await response.text();
  await flushBackgroundWork();
  return {
    status: response.status,
    headers: response.headers,
    body: text.length > 0 ? (JSON.parse(text) as Record<string, unknown>) : null,
    events: [],
  };
}

export async function getCapabilities(
  token: string,
  ifNoneMatch?: string,
): Promise<{ status: number; etag: string | null; body: Record<string, unknown> | null }> {
  const headers: Record<string, string> = {
    authorization: `Bearer ${token}`,
  };
  if (ifNoneMatch) {
    headers["if-none-match"] = ifNoneMatch;
  }
  if (!headers["Aip-Contract-Version"]) {
    headers["Aip-Contract-Version"] = "1";
  }
  const response = await SELF.fetch(
    new Request(`${GATEWAY_ORIGIN}/v1/capabilities`, { headers }),
  );
  const etag = response.headers.get("ETag");
  if (response.status === 304) {
    return { status: response.status, etag, body: null };
  }
  const text = await response.text();
  return {
    status: response.status,
    etag,
    body: text.length > 0 ? (JSON.parse(text) as Record<string, unknown>) : null,
  };
}

export async function getRequest(
  token: string,
  ref: string,
): Promise<{ status: number; body: Record<string, unknown> | null }> {
  const response = await SELF.fetch(
    new Request(`${GATEWAY_ORIGIN}/v1/requests/${ref}`, {
      headers: {
        authorization: `Bearer ${token}`,
        "Aip-Contract-Version": "1",
      },
    }),
  );
  const text = await response.text();
  return {
    status: response.status,
    body: text.length > 0 ? (JSON.parse(text) as Record<string, unknown>) : null,
  };
}

export function fakePolicyTarget(
  modelId: string,
  opts: {
    providerId?: string;
    minContextWindow?: number;
    languages?: string[] | string;
    costClass?: string;
    latencyClass?: string;
    structuredOutput?: boolean;
  } = {},
): Record<string, unknown> {
  const languages = opts.languages ?? ["en"];
  return {
    provider_id: opts.providerId ?? "fake",
    model_id: modelId,
    features: {
      structured_output: opts.structuredOutput ?? false,
      min_context_window: opts.minContextWindow ?? 32_000,
      languages,
      latency_class: opts.latencyClass ?? "standard",
      cost_class: opts.costClass ?? "standard",
    },
    max_attempts: 1,
    timeout_ms: 30_000,
  };
}

export function fakePolicyDocument(
  policyId: string,
  version: string | number,
  opts: {
    ruleId?: string;
    targets?: Record<string, unknown>[];
    overrides?: Record<string, unknown>[];
    requires?: Record<string, unknown>;
    canaryRules?: Record<string, unknown>[];
  } = {},
): Record<string, unknown> {
  const requires = opts.requires ?? {
    structured_output: false,
    min_context_window: 0,
    languages: ["en"],
  };
  const targets = opts.targets ?? [fakePolicyTarget("fake-v1")];
  const rules: Record<string, unknown>[] = opts.canaryRules ?? [
    {
      rule_id: opts.ruleId ?? "catch-all",
      match: {},
      requires,
      targets,
    },
  ];
  return {
    schema_version: 1,
    policy_id: policyId,
    policy_version: Number(version),
    defaults: { cost_class: "standard", max_parallel_attempts: 1 },
    rules,
    overrides: opts.overrides ?? [],
  };
}

export async function publishPolicy(
  policyId: string,
  version: string,
  document: Record<string, unknown>,
): Promise<{ status: number; json: Record<string, unknown> }> {
  const accessJwt = await mintVendorAccessJwt();
  const result = vendorEnvelopeToHttp(
    await vendorCall(
      "publishRoutingPolicy",
      { contract_version: VENDOR_CONTRACT_VERSION, document },
      { accessJwt },
    ),
  );
  if (result.status === 200) {
    const policy = await getRoutingPolicy(policyId, version);
    if (!policy || policy.status !== "published") {
      throw new Error(
        `publishPolicy: expected D1 row status=published for ${policyId}@${version}`,
      );
    }
    const pointer = String(policy.content_pointer);
    if (!(await r2Exists(pointer))) {
      throw new Error(`publishPolicy: R2 object missing at ${pointer}`);
    }
    const stored = await getR2Json(pointer);
    if (stored.policy_id !== document.policy_id) {
      throw new Error("publishPolicy: R2 round-trip policy_id mismatch");
    }
  }
  if (result.status === 200) {
    clearConfigCache();
  }
  return result;
}

export async function canary(
  policyId: string,
  version: string,
  installationIds: string[],
): Promise<{ status: number; json: Record<string, unknown> }> {
  const accessJwt = await mintVendorAccessJwt();
  const result = vendorEnvelopeToHttp(
    await vendorCall(
      "canaryRoutingPolicy",
      {
        contract_version: VENDOR_CONTRACT_VERSION,
        policy_id: policyId,
        version,
        installation_ids: installationIds,
      },
      { accessJwt },
    ),
  );
  if (result.status === 200) {
    clearConfigCache();
  }
  return result;
}

export async function promote(
  policyId: string,
  version: string,
): Promise<{ status: number; json: Record<string, unknown> }> {
  const accessJwt = await mintVendorAccessJwt();
  const result = vendorEnvelopeToHttp(
    await vendorCall(
      "promoteRoutingPolicy",
      {
        contract_version: VENDOR_CONTRACT_VERSION,
        policy_id: policyId,
        version,
      },
      { accessJwt },
    ),
  );
  if (result.status === 200) {
    clearConfigCache();
  }
  return result;
}

export async function rollback(
  policyId: string,
  version: string,
): Promise<{ status: number; json: Record<string, unknown> }> {
  const accessJwt = await mintVendorAccessJwt();
  const result = vendorEnvelopeToHttp(
    await vendorCall(
      "rollbackRoutingPolicy",
      {
        contract_version: VENDOR_CONTRACT_VERSION,
        policy_id: policyId,
        version,
      },
      { accessJwt },
    ),
  );
  if (result.status === 200) {
    clearConfigCache();
  }
  return result;
}

export async function queryOne<T extends Record<string, unknown>>(
  sql: string,
  params: unknown[] = [],
): Promise<T | null> {
  return env.DB.prepare(sql).bind(...params).first<T>();
}

export async function queryAll<T extends Record<string, unknown>>(
  sql: string,
  params: unknown[] = [],
): Promise<T[]> {
  const result = await env.DB.prepare(sql).bind(...params).all<T>();
  return result.results ?? [];
}

export async function count(
  table: string,
  where?: string,
  params: unknown[] = [],
): Promise<number> {
  const sql = where
    ? `SELECT COUNT(*) AS c FROM ${table} WHERE ${where}`
    : `SELECT COUNT(*) AS c FROM ${table}`;
  const row = await env.DB.prepare(sql).bind(...params).first<{ c: number }>();
  return row?.c ?? 0;
}

export const d1 = {
  queryOne,
  queryAll,
  count,
  getAiRequest,
  getAttempts,
  getUsageEvents,
  getEntitlement,
  getGrants,
  getAudits,
  getRoutingPolicy,
};

export async function getAiRequest(ref: string): Promise<Record<string, unknown> | null> {
  return queryOne(
    "SELECT * FROM ai_request WHERE request_reference = ?",
    [ref],
  );
}

export async function getAttempts(requestId: string): Promise<Record<string, unknown>[]> {
  return queryAll(
    "SELECT * FROM ai_attempt WHERE request_id = ? ORDER BY attempt_no",
    [requestId],
  );
}

export async function getUsageEvents(requestId: string): Promise<Record<string, unknown>[]> {
  return queryAll("SELECT * FROM usage_event WHERE request_id = ?", [requestId]);
}

export const COVER_PLAN_ID = "live-monthly";

const entitledInstallationIds = new Set<string>();
const entitlementSnapshotByInstallation = new Map<string, EntitlePayload>();

function clearEntitlementHarnessState(): void {
  entitledInstallationIds.clear();
  entitlementSnapshotByInstallation.clear();
}

function isIsoInstant(value: string): boolean {
  return (
    /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{3})?Z$/u.test(value) &&
    !Number.isNaN(Date.parse(value))
  );
}

export function validateEntitlePayload(
  payload: EntitlePayload,
): { ok: true } | { ok: false; error: string } {
  if (!isIsoInstant(payload.period_start) || !isIsoInstant(payload.period_end)) {
    return { ok: false, error: "invalid_payload" };
  }
  if (Date.parse(payload.period_start) >= Date.parse(payload.period_end)) {
    return { ok: false, error: "invalid_payload" };
  }
  for (const field of [
    payload.request_quota,
    payload.token_budget,
    payload.cost_budget,
  ]) {
    if (!Number.isInteger(field) || field < 0) {
      return { ok: false, error: "invalid_payload" };
    }
  }
  if (
    typeof payload.soft_threshold !== "number" ||
    payload.soft_threshold < 0 ||
    payload.soft_threshold > 1
  ) {
    return { ok: false, error: "invalid_payload" };
  }
  if (
    !Array.isArray(payload.allowed_capabilities) ||
    !payload.allowed_capabilities.every((entry) => typeof entry === "string")
  ) {
    return { ok: false, error: "invalid_payload" };
  }
  if (!Array.isArray(payload.grants) || payload.grants.length === 0) {
    return { ok: false, error: "invalid_payload" };
  }
  for (const grant of payload.grants) {
    if (grant.scope !== "installation" && grant.scope !== "plan") {
      return { ok: false, error: "invalid_payload" };
    }
  }
  return { ok: true };
}

export async function getEntitlement(
  installationId: string,
): Promise<Record<string, unknown> | null> {
  const binding = await queryOne<{ org_id: string }>(
    "SELECT org_id FROM tenant_binding WHERE installation_id = ?",
    [installationId],
  );
  if (!binding) {
    return null;
  }
  const snapshot = entitlementSnapshotByInstallation.get(installationId);
  if (!snapshot) {
    return {
      entitlement_id: installationId,
      installation_id: installationId,
      plan: "standard",
      status: "pending",
      allowed_capabilities: "[]",
      request_quota: 0,
      token_budget: 0,
      cost_budget: 0,
      soft_threshold: 0,
    };
  }
  return {
    entitlement_id: installationId,
    installation_id: installationId,
    plan: COVER_PLAN_ID,
    period_start: snapshot.period_start,
    period_end: snapshot.period_end,
    request_quota: snapshot.request_quota,
    token_budget: snapshot.token_budget,
    cost_budget: snapshot.cost_budget,
    allowed_capabilities: JSON.stringify(snapshot.allowed_capabilities),
    soft_threshold: snapshot.soft_threshold,
    status: "active",
  };
}

export async function getGrants(scope: string): Promise<Record<string, unknown>[]> {
  return queryAll(
    "SELECT * FROM capability_grant WHERE scope = ? ORDER BY changed_at",
    [scope],
  );
}

export async function getAudits(
  action: string,
  target: string,
): Promise<Record<string, unknown>[]> {
  return queryAll(
    "SELECT * FROM control_audit WHERE action = ? AND target = ? ORDER BY recorded_at",
    [action, target],
  );
}

export async function getRoutingPolicy(
  policyId: string,
  version: string,
): Promise<Record<string, unknown> | null> {
  return queryOne(
    "SELECT * FROM routing_policy WHERE policy_id = ? AND version = ?",
    [policyId, version],
  );
}

export async function getR2Json(key: string): Promise<Record<string, unknown>> {
  const object = await env.R2.get(key);
  if (!object) {
    throw new Error(`R2 object not found: ${key}`);
  }
  return JSON.parse(await object.text()) as Record<string, unknown>;
}

export async function r2Exists(key: string): Promise<boolean> {
  const object = await env.R2.head(key);
  return object !== null;
}

/**
 * Trigger the worker scheduled handler for a cron expression.
 * `SELF.scheduled` is not exposed by @cloudflare/vitest-pool-workers 0.8.71 in
 * this project — invoke the exported worker module `scheduled()` with pool env.
 */
const vendorHeartbeatHarness = {
  capturedFetches: [] as string[],
  fetchThrows: false,
  interceptReady: false,
};

export const vendorHarnessState = {
  capturedEmails: [] as Array<{
    from: string;
    to: string;
    subject: string;
    text: string;
  }>,
  sendEmailThrows: false,
};

export const vendorSendEmailBinding = {
  async send(message: {
    from: string;
    to: string;
    subject: string;
    text: string;
  }): Promise<void> {
    if (vendorHarnessState.sendEmailThrows) {
      throw new Error("send_email failure injected by harness");
    }
    vendorHarnessState.capturedEmails.push({ ...message });
  },
};

async function ensureHeartbeatFetchMock(): Promise<void> {
  await ensureVendorAccessTeam();
  if (vendorHeartbeatHarness.interceptReady) {
    return;
  }
  const { fetchMock } = await import("cloudflare:test");
  const heartbeatUrl = env.HEARTBEAT_URL;
  const parsed = new URL(heartbeatUrl);
  fetchMock
    .get(parsed.origin)
    .intercept({ path: parsed.pathname, method: "GET" })
    .reply(() => {
      vendorHeartbeatHarness.capturedFetches.push(heartbeatUrl);
      if (vendorHeartbeatHarness.fetchThrows) {
        throw new Error("heartbeat fetch failure injected by harness");
      }
      return { statusCode: 200, data: "ok" };
    })
    .persist();
  vendorHeartbeatHarness.interceptReady = true;
}

export function setSendPlatformEmailThrows(throws: boolean): void {
  vendorHarnessState.sendEmailThrows = throws;
}

export function setHeartbeatFetchThrows(throws: boolean): void {
  vendorHeartbeatHarness.fetchThrows = throws;
}

export function clearCapturedHeartbeatFetches(): void {
  vendorHeartbeatHarness.capturedFetches.length = 0;
}

export function getCapturedHeartbeatFetches(): ReadonlyArray<string> {
  return vendorHeartbeatHarness.capturedFetches;
}

export async function runScheduled(cron: string): Promise<void> {
  await ensureHeartbeatFetchMock();
  const workerModule = await import("../../src/worker");
  await workerModule.default.scheduled(
    { cron, scheduledTime: Date.now(), noRetry() { } },
    env as never,
    {} as ExecutionContext,
  );
}

export function clearConfigCache(): void {
  isolateConfigCache.clear();
}

export function terminalEventTypes(events: SseEvent[]): string[] {
  const terminals = new Set([
    "completed",
    "failed",
    "cancelled",
    "context_requested",
  ]);
  return events.filter((event) => terminals.has(event.event)).map((e) => e.event);
}

export async function newClinic(scenario?: Scenario): Promise<Scenario> {
  const ready = scenario ?? (await newScenario());
  const issuer = await ensureHarnessIssuerRegistered();
  ready.kid = issuer.kid;
  const token = await mintAat(ready);
  const response = await SELF.fetch(
    new Request(`${GATEWAY_ORIGIN}/v1/capabilities`, {
      headers: {
        authorization: `Bearer ${token}`,
        "Aip-Contract-Version": "1",
      },
    }),
  );
  if (response.status !== 200) {
    const text = await response.text();
    throw new Error(`newClinic capabilities failed (${response.status}): ${text}`);
  }
  const binding = await queryOne<{ installation_id: string }>(
    "SELECT installation_id FROM tenant_binding WHERE org_id = ? AND status = 'active'",
    [ready.orgId],
  );
  if (!binding?.installation_id) {
    throw new Error("newClinic: tenant_binding missing after capabilities");
  }
  ready.installationId = binding.installation_id;
  clearConfigCache();
  return ready;
}

async function ensureDefaultCohortGrants(scenario: Scenario): Promise<void> {
  const activated = await vendorClassH("activateCohort", {
    capability_id: CAPABILITY_ID,
    capability_version: CAPABILITY_VERSION,
    installation_ids: [scenario.installationId],
  });
  if (activated.status !== 200) {
    throw new Error(
      `activateCohort failed (${activated.status}): ${JSON.stringify(activated.json)}`,
    );
  }
  const promoted = await vendorClassH("promoteCohort", {
    capability_id: CAPABILITY_ID,
    capability_version: CAPABILITY_VERSION,
  });
  if (promoted.status !== 200) {
    throw new Error(
      `promoteCohort failed (${promoted.status}): ${JSON.stringify(promoted.json)}`,
    );
  }
}

export async function entitleScenario(
  scenario: Scenario,
  payload: EntitlePayload = DEFAULT_ENTITLE_PAYLOAD,
): Promise<{ status: number; json: Record<string, unknown> }> {
  const validated = validateEntitlePayload(payload);
  if (!validated.ok) {
    return { status: 400, json: { error: validated.error } };
  }
  if (entitledInstallationIds.has(scenario.installationId)) {
    return { status: 409, json: { error: "not_pending" } };
  }

  await coverClinic(scenario, {
    capabilities: payload.allowed_capabilities,
    max_allowance_per_month: payload.request_quota,
  });
  await ensureDefaultCohortGrants(scenario);

  entitlementSnapshotByInstallation.set(scenario.installationId, payload);
  entitledInstallationIds.add(scenario.installationId);
  clearConfigCache();
  return { status: 200, json: { status: "active" } };
}

const COVER_PLAN_VERSION = 1;
const COVER_PLAN_DISPLAY = "Live Monthly";
const COVER_DEFAULT_CAPABILITIES = [CAPABILITY_ID];
const COVER_DEFAULT_MAX_COST_CLASS = 2;
const COVER_DEFAULT_CONCURRENCY = 4;
const COVER_DEFAULT_ALLOWANCE = 10_000;

export type CoverClinicOptions = {
  capabilities?: string[];
  concurrency_limit?: number;
  max_allowance_per_month?: number;
};

type CoverClinicBootstrap = {
  signerCredentialId: string;
  signerAuthenticator: Awaited<ReturnType<typeof createSoftwareAuthenticator>>;
  aboSigner: Awaited<ReturnType<typeof createAboGrantSigner>>;
  aboKid: string;
};

let coverClinicBootstrap: CoverClinicBootstrap | null = null;

function clearCoverClinicBootstrap(): void {
  coverClinicBootstrap = null;
}

async function operationForCoverPublishPlan(input: {
  accessJwt: string;
  capabilities: string[];
  concurrencyLimit: number;
  maxAllowance: number;
}): Promise<Record<string, unknown>> {
  return {
    op: "publishPlanVersion",
    params: {
      contract_version: VENDOR_CONTRACT_VERSION,
      access_jwt: input.accessJwt,
      plan_id: COVER_PLAN_ID,
      version: COVER_PLAN_VERSION,
      display_name: COVER_PLAN_DISPLAY,
      capabilities: input.capabilities,
      max_cost_class: COVER_DEFAULT_MAX_COST_CLASS,
      concurrency_limit: input.concurrencyLimit,
      max_allowance_per_month: input.maxAllowance,
    },
    actor_email: VENDOR_OPERATOR_EMAIL,
    issued_at: getVendorTestClockIso() ?? new Date().toISOString(),
    nonce: randomUuid(),
    contract_version: VENDOR_CONTRACT_VERSION,
  };
}

async function ensureCoverClinicBootstrap(): Promise<CoverClinicBootstrap> {
  if (coverClinicBootstrap !== null) {
    return coverClinicBootstrap;
  }
  await setupVendorHarness();
  const issuer = await ensureHarnessIssuerRegistered();
  const aboSigner = await createAboGrantSigner();
  const rawPublicKey = await crypto.subtle.exportKey("raw", aboSigner.publicKey);
  const publicKeyB64 = base64urlEncode(new Uint8Array(rawPublicKey));
  const notBefore = getVendorTestClockIso() ?? new Date().toISOString();
  const notAfter = new Date(
    Date.parse(notBefore) + 365 * 24 * 60 * 60 * 1000,
  ).toISOString();
  const accessJwt = await mintVendorAccessJwt();
  const registerOperation = {
    op: "registerServiceKey",
    params: {
      contract_version: VENDOR_CONTRACT_VERSION,
      access_jwt: accessJwt,
      kid: aboSigner.kid,
      public_key: publicKeyB64,
      not_before: notBefore,
      not_after: notAfter,
    },
    actor_email: VENDOR_OPERATOR_EMAIL,
    issued_at: notBefore,
    nonce: randomUuid(),
    contract_version: VENDOR_CONTRACT_VERSION,
  };
  const registerAssertion = encodeVendorAssertion(
    await issuer.signerAuthenticator.assert({
      operation: registerOperation,
      rpId: env.WEBAUTHN_RP_ID,
      origin: env.WEBAUTHN_ORIGIN,
      up: true,
      uv: true,
    }),
  );
  const registerResult = await vendorCall(
    "registerServiceKey",
    {
      contract_version: VENDOR_CONTRACT_VERSION,
      kid: aboSigner.kid,
      public_key: publicKeyB64,
      not_before: notBefore,
      not_after: notAfter,
      signer_credential_id: issuer.signerCredentialId,
      operation: registerOperation,
      assertion: registerAssertion,
    },
    { accessJwt },
  );
  if (registerResult.result !== "ok") {
    throw new Error(`registerServiceKey failed: ${registerResult.code}`);
  }
  coverClinicBootstrap = {
    signerCredentialId: issuer.signerCredentialId,
    signerAuthenticator: issuer.signerAuthenticator,
    aboSigner,
    aboKid: aboSigner.kid,
  };
  return coverClinicBootstrap;
}

export function coverClinicSigner(): {
  signerCredentialId: string;
  signerAuthenticator: CoverClinicBootstrap["signerAuthenticator"];
} {
  if (coverClinicBootstrap === null) {
    throw new Error("coverClinicSigner: call coverClinic() first");
  }
  return {
    signerCredentialId: coverClinicBootstrap.signerCredentialId,
    signerAuthenticator: coverClinicBootstrap.signerAuthenticator,
  };
}

export function coverClinicAboKid(): string {
  if (coverClinicBootstrap === null) {
    throw new Error("coverClinicAboKid: call coverClinic() first");
  }
  return coverClinicBootstrap.aboKid;
}

export async function signCoverAbo(
  body: Record<string, unknown>,
): Promise<string> {
  const boot = await ensureCoverClinicBootstrap();
  return boot.aboSigner.sign(body);
}

async function buildCoverPaidGrantEnvelope(input: {
  orgId: string;
  grantId: string;
  allowanceCredits: number;
}): Promise<Record<string, unknown>> {
  const paidAt = getVendorTestClockIso() ?? new Date().toISOString();
  const paymentRef = randomUuid().replace(/-/g, "");
  const contentSha256 = await sha256Hex(new TextEncoder().encode(paymentRef));
  return {
    contract_version: VENDOR_CONTRACT_VERSION,
    grant_id: input.grantId,
    org_id: input.orgId,
    kind: "term",
    placement: "queue",
    source: { kind: "paid", ref: paymentRef },
    plan: { plan_id: COVER_PLAN_ID, plan_version: COVER_PLAN_VERSION },
    duration: { unit: "month", count: 1 },
    allowance_credits: input.allowanceCredits,
    grace: { days: 7, cap_rule: "proportional" },
    paid_at: paidAt,
    evidence: {
      content_sha256: contentSha256,
      approvals: [{ credential_id: "cred-001", assertion: "stub" }],
    },
  };
}

function quotaDoStubForInstallation(installationId: string) {
  return env.DO.get(env.DO.idFromName(installationId));
}

export async function coverClinic(
  scenario: Scenario,
  opts: CoverClinicOptions = {},
): Promise<void> {
  const boot = await ensureCoverClinicBootstrap();
  const capabilities = opts.capabilities ?? COVER_DEFAULT_CAPABILITIES;
  const concurrencyLimit =
    opts.concurrency_limit ?? COVER_DEFAULT_CONCURRENCY;
  const maxAllowance =
    opts.max_allowance_per_month ?? COVER_DEFAULT_ALLOWANCE;

  const accessJwt = await mintVendorAccessJwt();
  const publishOperation = await operationForCoverPublishPlan({
    accessJwt,
    capabilities,
    concurrencyLimit,
    maxAllowance,
  });
  const publishAssertion = encodeVendorAssertion(
    await boot.signerAuthenticator.assert({
      operation: publishOperation,
      rpId: env.WEBAUTHN_RP_ID,
      origin: env.WEBAUTHN_ORIGIN,
      up: true,
      uv: true,
    }),
  );
  const published = await vendorCall(
    "publishPlanVersion",
    {
      contract_version: VENDOR_CONTRACT_VERSION,
      plan_id: COVER_PLAN_ID,
      version: COVER_PLAN_VERSION,
      display_name: COVER_PLAN_DISPLAY,
      capabilities,
      max_cost_class: COVER_DEFAULT_MAX_COST_CLASS,
      concurrency_limit: concurrencyLimit,
      max_allowance_per_month: maxAllowance,
      signer_credential_id: boot.signerCredentialId,
      operation: publishOperation,
      assertion: publishAssertion,
    },
    { accessJwt },
  );
  if (published.result !== "ok") {
    throw new Error(`publishPlanVersion failed: ${published.code}`);
  }

  const grantId = await grantIdPaid(randomUuid().replace(/-/g, ""));
  const envelope = await buildCoverPaidGrantEnvelope({
    orgId: scenario.orgId,
    grantId,
    allowanceCredits: maxAllowance,
  });
  const aboSignature = await boot.aboSigner.sign(envelope);
  const granted = await vendorCall("grant", {
    contract_version: VENDOR_CONTRACT_VERSION,
    envelope,
    abo_kid: boot.aboKid,
    abo_signature: aboSignature,
  });
  if (
    granted.result !== "applied" &&
    granted.result !== "already_applied"
  ) {
    throw new Error(`grant failed: ${granted.code}`);
  }

  const binding = await queryOne<{ installation_id: string }>(
    "SELECT installation_id FROM tenant_binding WHERE org_id = ? AND status = 'active'",
    [scenario.orgId],
  );
  if (!binding?.installation_id) {
    throw new Error("coverClinic: tenant_binding missing after grant");
  }
  scenario.installationId = binding.installation_id;
  await runDurableObjectAlarm(
    quotaDoStubForInstallation(scenario.installationId),
  );
  clearConfigCache();
}

export async function setupPromotedFakePolicy(
  scenario: Scenario,
  payload: EntitlePayload = DEFAULT_ENTITLE_PAYLOAD,
): Promise<void> {
  await coverClinic(scenario, {
    capabilities: payload.allowed_capabilities,
    max_allowance_per_month: payload.request_quota,
  });
  await newClinic(scenario);
  await ensureDefaultCohortGrants(scenario);
  entitlementSnapshotByInstallation.set(scenario.installationId, payload);
  entitledInstallationIds.add(scenario.installationId);
  const document = fakePolicyDocument(POLICY_ID, POLICY_VERSION);
  const published = await publishPolicy(POLICY_ID, POLICY_VERSION, document);
  if (published.status !== 200) {
    throw new Error(`publish failed: ${published.status}`);
  }
  const promoted = await promote(POLICY_ID, POLICY_VERSION);
  if (promoted.status !== 200) {
    throw new Error(`promote failed: ${promoted.status}`);
  }
  clearConfigCache();
}

// --- P3.1 vendor entrypoint harness (H-AP) ---

export type VendorResultEnvelope = {
  contract_version?: number;
  result: string;
  code: string;
  detail: string;
  receipt?: unknown;
};

export type VendorMethod =
  | "registerOperatorCredential"
  | "revokeOperatorCredential"
  | "listOperatorCredentials"
  | "registerIssuerKey"
  | "publishPlanVersion"
  | "registerServiceKey"
  | "revokeServiceKey"
  | "listServiceKeys"
  | "retirePlanVersion"
  | "grant"
  | "getCoverage"
  | "listGrants"
  | "readCoverageEvents"
  | "setCeilingPolicy"
  | "suspend"
  | "resume"
  | "inspectCoverage"
  | "voidForReversal"
  | "releaseHeld"
  | "voidGrant"
  | "listGrantsForVoid"
  | "beginTransfer"
  | "transferOut"
  | "transferIn"
  | "deleteInstallation"
  | "feedConsumerHealth"
  | "publishRoutingPolicy"
  | "canaryRoutingPolicy"
  | "promoteRoutingPolicy"
  | "rollbackRoutingPolicy"
  | "armKillSwitch"
  | "disarmKillSwitch"
  | "deprecateCapability"
  | "retireCapability"
  | "activateCohort"
  | "promoteCohort"
  | "beginTokenContractRotation"
  | "retireTokenContract"
  | "supportLookup"
  | "rebuildClinicDo"
  | "rebuildGrantLedger"
  | "refreshCoverageSnapshot";

export const VENDOR_OPERATOR_EMAIL = "operator@clinic.test";

type AccessTeam = Awaited<
  ReturnType<
    typeof import("vendor-contracts/testkit").createAccessTeam
  >
>;

let vendorAccessTeam: AccessTeam | null = null;

function vendorAccessIssuer(): string {
  return `https://${env.ACCESS_TEAM_DOMAIN}`;
}

export function clearCapturedVendorEmails(): void {
  vendorHarnessState.capturedEmails.length = 0;
}

export function getCapturedVendorEmails(): ReadonlyArray<{
  from: string;
  to: string;
  subject: string;
  text: string;
}> {
  return vendorHarnessState.capturedEmails;
}

export async function mintVendorAccessJwt(
  overrides: {
    email?: string;
    aud?: string;
    exp?: number;
    iat?: number;
    kid?: string;
  } = {},
): Promise<string> {
  await ensureVendorAccessTeam();
  let now = Math.floor(Date.now() / 1000);
  if (env.TEST_CLOCK === "1") {
    const row = await env.DB.prepare(
      "SELECT now_iso FROM harness_test_clock WHERE id = 'default'",
    ).first<{ now_iso: string }>();
    if (row?.now_iso) {
      const parsed = Date.parse(row.now_iso);
      if (!Number.isNaN(parsed)) {
        now = Math.floor(parsed / 1000);
      }
    }
  }
  return vendorAccessTeam!.mint({
    email: overrides.email ?? VENDOR_OPERATOR_EMAIL,
    aud: overrides.aud ?? env.ACCESS_AUD,
    iat: overrides.iat ?? now - 60,
    exp: overrides.exp ?? now + 3600,
    kid: overrides.kid,
  });
}

async function ensureVendorAccessTeam(): Promise<void> {
  if (vendorAccessTeam !== null) {
    return;
  }
  const { createAccessTeam } = await import("vendor-contracts/testkit");
  const { fetchMock } = await import("cloudflare:test");
  vendorAccessTeam = await createAccessTeam({ issuer: vendorAccessIssuer() });
  fetchMock.activate();
  fetchMock.disableNetConnect();
  fetchMock
    .get(vendorAccessIssuer())
    .intercept({ path: "/cdn-cgi/access/certs", method: "GET" })
    .reply(200, JSON.stringify({ keys: vendorAccessTeam.certs.keys }))
    .persist();
}

export async function setupVendorHarness(): Promise<void> {
  await ensureVendorAccessTeam();
  Object.assign(env.SEND_EMAIL, vendorSendEmailBinding);
  clearCapturedVendorEmails();
  vendorHarnessState.sendEmailThrows = false;
  vendorHeartbeatHarness.fetchThrows = false;
  clearCapturedHeartbeatFetches();
}

export async function vendorSupportLookup(
  args: { reference?: string; subscription_ref?: string; org_id?: string },
): Promise<{ status: number; json: Record<string, unknown> }> {
  const http = await vendorClassH("supportLookup", args);
  if (http.json.error === "not_found") {
    return { status: 404, json: http.json };
  }
  return http;
}

export async function vendorClassH(
  method: VendorMethod,
  args: Record<string, unknown> = {},
): Promise<{ status: number; json: Record<string, unknown> }> {
  await setupVendorHarness();
  const accessJwt = await mintVendorAccessJwt();
  return vendorEnvelopeToHttp(
    await vendorCall(
      method,
      { contract_version: VENDOR_CONTRACT_VERSION, ...args },
      { accessJwt },
    ),
  );
}

export async function vendorCall(
  method: VendorMethod,
  args: Record<string, unknown>,
  opts: {
    accessJwt?: string;
    assertion?: Record<string, unknown>;
  } = {},
): Promise<VendorResultEnvelope> {
  const payload: Record<string, unknown> = { ...args };
  if (opts.accessJwt !== undefined) {
    payload.access_jwt = opts.accessJwt;
  }
  if (opts.assertion !== undefined) {
    payload.assertion = opts.assertion;
  }
  return env.VENDOR[method](payload);
}

let vendorTestClockIso: string | null = null;

async function ensureHarnessTestClockTable(): Promise<void> {
  await env.DB.prepare(
    `CREATE TABLE IF NOT EXISTS harness_test_clock (
       id TEXT PRIMARY KEY,
       now_iso TEXT NOT NULL
     )`,
  ).run();
}

async function ensureHarnessAdmissionFaultTable(): Promise<void> {
  await env.DB.prepare(
    `CREATE TABLE IF NOT EXISTS harness_admission_fault (
       id TEXT PRIMARY KEY,
       mode TEXT NOT NULL,
       hold_until INTEGER
     )`,
  ).run();
}

export async function setAdmissionFault(
  mode: "throw" | "hold",
  opts: { hold_until?: number } = {},
): Promise<void> {
  await ensureHarnessAdmissionFaultTable();
  await env.DB.prepare(
    `INSERT OR REPLACE INTO harness_admission_fault (id, mode, hold_until)
     VALUES ('default', ?, ?)`,
  )
    .bind(mode, opts.hold_until ?? null)
    .run();
}

export async function clearAdmissionFault(): Promise<void> {
  await ensureHarnessAdmissionFaultTable();
  await env.DB
    .prepare("DELETE FROM harness_admission_fault WHERE id = 'default'")
    .run();
}

export async function mintFeedToken(): Promise<string> {
  const issuer = await ensureHarnessIssuerRegistered();
  const now = await harnessNowSeconds();
  const payload = {
    iss: ISSUER_ID,
    aud: "ai-platform-feed",
    sub: "backend-feed",
    jti: randomUuid(),
    iat: now,
    exp: now + 120,
    ver: "2",
  };
  const header = { alg: "EdDSA", kid: issuer.kid, typ: "JWT" };
  const { canonicalize } = await import("vendor-contracts");
  const headerB64 = base64urlEncode(canonicalize(header));
  const payloadB64 = base64urlEncode(canonicalize(payload));
  const signingInput = `${headerB64}.${payloadB64}`;
  const signature = await crypto.subtle.sign(
    { name: "Ed25519" },
    issuer.privateKey,
    new TextEncoder().encode(signingInput),
  );
  return `${signingInput}.${base64urlEncode(new Uint8Array(signature))}`;
}

export async function setTestClock(isoUtc: string): Promise<void> {
  await ensureHarnessTestClockTable();
  await env.DB.prepare(
    `INSERT OR REPLACE INTO harness_test_clock (id, now_iso) VALUES ('default', ?)`,
  )
    .bind(isoUtc)
    .run();
  vendorTestClockIso = isoUtc;
}

export function getVendorTestClockIso(): string | null {
  return vendorTestClockIso;
}

export async function vendorTableCount(table: string): Promise<number> {
  return count(table);
}

export function encodeVendorAssertion(
  assertion: {
    alg: "ES256" | "EdDSA";
    authenticatorData: Uint8Array;
    clientDataJSON: Uint8Array;
    signature: Uint8Array;
  },
): Record<string, string> {
  return {
    alg: assertion.alg,
    authenticator_data: base64urlEncode(assertion.authenticatorData),
    client_data_json: base64urlEncode(assertion.clientDataJSON),
    signature: base64urlEncode(assertion.signature),
  };
}

export function encodeVendorAttestation(attestation: {
  alg: "ES256" | "EdDSA";
  publicKey: Uint8Array;
}): { alg: "ES256" | "EdDSA"; public_key: string } {
  return {
    alg: attestation.alg,
    public_key: base64urlEncode(attestation.publicKey),
  };
}
