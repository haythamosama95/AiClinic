import { env, SELF } from "cloudflare:test";
import { beforeAll, beforeEach, describe, expect, it } from "vitest";
import migrationSql from "../migrations/20260731120000_platform_schema.sql?raw";
import tokenContractMigrationSql from "../migrations/20260803120000_token_contract.sql?raw";
import killSwitchMigrationSql from "../migrations/20260807120000_kill_switch.sql?raw";
import {
  createCapabilityRegistry,
  setCapabilityRegistry,
} from "../src/capability";
import { isolateConfigCache } from "../src/config-cache";
import { load, type Manifest } from "../src/manifest";

declare module "cloudflare:test" {
  interface ProvidedEnv {
    DB: D1Database;
    R2: R2Bucket;
    OPERATOR_BEARER_TOKEN: string;
    OPERATOR_ID: string;
  }
}

const GATEWAY_ORIGIN = "https://ai-gateway.test";
const AUDIENCE = "ai-platform";
const NOW_SECONDS = 1_720_000_450;

const FIXTURE_INSTALLATION_ID = "inst-disc-001";
const FIXTURE_ORG_ID = "org-disc-001";
const FIXTURE_GRANTED_CAPABILITY_ID = "clinic.granted";
const FIXTURE_DEPRECATED_CAPABILITY_ID = "clinic.deprecated";
const FIXTURE_RETIRED_CAPABILITY_ID = "clinic.retired";
const FIXTURE_UNGRANTED_CAPABILITY_ID = "clinic.ungranted";
const FIXTURE_GATED_CAPABILITY_ID = "clinic.gated";
const FIXTURE_CAPABILITY_VERSION = "1.0.0";
const FIXTURE_NOW = "2026-07-31T12:00:00.000Z";

type ManifestWire = Record<string, unknown>;
type AatClaims = {
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

type TestKeypair = {
  privateKey: CryptoKey;
  kid: string;
  publicKeyB64: string;
};

const DEFAULT_CLAIMS: AatClaims = {
  iss: FIXTURE_INSTALLATION_ID,
  aud: AUDIENCE,
  sub: "actor-disc-001",
  org: FIXTURE_ORG_ID,
  branch: "branch-disc-001",
  role: "clinician",
  scopes: ["ai.access"],
  jti: "jti-disc-001",
  iat: NOW_SECONDS - 30,
  exp: NOW_SECONDS + 300,
  ver: "1",
};

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

async function generateTestKeypair(kid: string): Promise<TestKeypair> {
  const keyPair = await crypto.subtle.generateKey(
    { name: "Ed25519" },
    true,
    ["sign", "verify"],
  );
  const rawPublicKey = await crypto.subtle.exportKey("raw", keyPair.publicKey);
  return {
    privateKey: keyPair.privateKey,
    kid,
    publicKeyB64: base64urlEncode(new Uint8Array(rawPublicKey)),
  };
}

async function mintToken(
  keypair: TestKeypair,
  claims: Partial<AatClaims> = {},
): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const payload: AatClaims = {
    ...DEFAULT_CLAIMS,
    iat: now - 30,
    exp: now + 300,
    ...claims,
  };
  const header = { alg: "EdDSA", kid: keypair.kid };
  const headerB64 = base64urlEncode(JSON.stringify(header));
  const payloadB64 = base64urlEncode(JSON.stringify(payload));
  const signingInput = `${headerB64}.${payloadB64}`;
  const signature = await crypto.subtle.sign(
    { name: "Ed25519" },
    keypair.privateKey,
    new TextEncoder().encode(signingInput),
  );
  return `${signingInput}.${base64urlEncode(new Uint8Array(signature))}`;
}

function validManifest(
  capabilityId: string,
  version: string,
  lifecycleState: string = "active",
  minimumPlanTier: string = "standard",
): ManifestWire {
  return {
    Identity: {
      capabilityId,
      version,
      title: `${capabilityId} fixture`,
      lifecycleState,
      successorId: null,
    },
    Access: {
      requiredCapabilityScope: `ai.${capabilityId}`,
      minimumPlanTier,
      allowedStaffRoles: ["clinician", "nurse"],
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
      systemInstructionArtifactRef: "prompt/visit-summary-system@v1",
      businessRuleFragmentRefs: ["rules/visit-summary@v1"],
      contextRenderingTemplateRef: "templates/visit-summary@v1",
      outputFormatInstructionDerivationRule: "derive_from_output_mode",
    },
    Output: {
      mode: "prose",
      outputSchemaRef: null,
      businessValidationRuleRefs: [],
      repairPolicy: { allowed: false, maxAttempts: 0 },
    },
    Routing: {
      routingPolicyRef: "routing/standard",
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
      evalSuiteRef: "evals/visit-summary@v1",
    },
  };
}

function buildRegistry(...manifests: ManifestWire[]): void {
  const loaded = manifests.map((wire) => load(wire));
  setCapabilityRegistry(createCapabilityRegistry(loaded), { replace: true });
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

async function clearDiscoveryTables(): Promise<void> {
  await env.DB.batch([
    env.DB.prepare("DELETE FROM capability_grant"),
    env.DB.prepare("DELETE FROM entitlement"),
    env.DB.prepare("DELETE FROM installation_key"),
    env.DB.prepare("DELETE FROM installation"),
  ]);
}

async function seedInstallationKey(
  keypair: TestKeypair,
  installationId: string = FIXTURE_INSTALLATION_ID,
): Promise<void> {
  const enrolledAt = new Date().toISOString();
  const validFrom = new Date(Date.now() - 3_600_000).toISOString();

  await env.DB
    .prepare(
      `INSERT INTO installation (
        installation_id, org_id, display_name, status, region, enrolled_at
      ) VALUES (?, ?, ?, 'active', 'us-east-1', ?)`,
    )
    .bind(installationId, FIXTURE_ORG_ID, "Discovery Test Clinic", enrolledAt)
    .run();

  await env.DB
    .prepare(
      `INSERT INTO installation_key (
        key_id, installation_id, public_key, algorithm, valid_from, valid_until, revoked_at
      ) VALUES (?, ?, ?, 'EdDSA', ?, NULL, NULL)`,
    )
    .bind(keypair.kid, installationId, keypair.publicKeyB64, validFrom)
    .run();
}

async function seedEntitlement(
  options: {
    plan?: string;
    allowedCapabilities?: string[];
    installationId?: string;
    status?: string;
  } = {},
): Promise<void> {
  const {
    plan = "professional",
    allowedCapabilities = [FIXTURE_GRANTED_CAPABILITY_ID],
    installationId = FIXTURE_INSTALLATION_ID,
    status = "active",
  } = options;

  await env.DB
    .prepare(
      `INSERT INTO entitlement (
        entitlement_id, installation_id, plan, period_start, period_end,
        request_quota, token_budget, cost_budget, allowed_capabilities,
        soft_threshold, status
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
    )
    .bind(
      `ent-${installationId}`,
      installationId,
      plan,
      FIXTURE_NOW,
      FIXTURE_NOW,
      1_000,
      1_000_000,
      100,
      JSON.stringify(allowedCapabilities),
      0.8,
      status,
    )
    .run();
}

async function seedCapabilityGrant(
  capabilityId: string,
  capabilityVersion: string = FIXTURE_CAPABILITY_VERSION,
  installationId: string = FIXTURE_INSTALLATION_ID,
): Promise<void> {
  await env.DB
    .prepare(
      `INSERT INTO capability_grant (
        grant_id, scope, capability_id, capability_version,
        granted_at, revoked_at, changed_at, changed_by
      ) VALUES (?, ?, ?, ?, ?, NULL, ?, 'operator-test')`,
    )
    .bind(
      `grant-${capabilityId}-${capabilityVersion}`,
      `installation:${installationId}`,
      capabilityId,
      capabilityVersion,
      FIXTURE_NOW,
      FIXTURE_NOW,
    )
    .run();
}

function discoveryRequest(
  token?: string,
  headers: Record<string, string> = {},
): Request {
  const requestHeaders: Record<string, string> = { ...headers };
  if (token !== undefined) {
    requestHeaders.authorization = `Bearer ${token}`;
  }
  return new Request(`${GATEWAY_ORIGIN}/v1/capabilities`, {
    method: "GET",
    headers: requestHeaders,
  });
}

function manifestIds(manifests: Manifest[]): string[] {
  return manifests.map((manifest) => manifest.Identity.capabilityId as string);
}

let fixtureKeypair: TestKeypair;

beforeAll(async () => {
  await applyPlatformSchema(env.DB, migrationSql);
  await applyPlatformSchema(env.DB, tokenContractMigrationSql);
  await applyPlatformSchema(env.DB, killSwitchMigrationSql);
  fixtureKeypair = await generateTestKeypair("kid-disc-001");
});

beforeEach(async () => {
  isolateConfigCache.clear();
  await clearDiscoveryTables();
});

describe("T1 discovery_http_granted_active_manifests", () => {
  it("returns only granted effective-active or deprecated manifests", async () => {
    buildRegistry(
      validManifest(FIXTURE_GRANTED_CAPABILITY_ID, FIXTURE_CAPABILITY_VERSION, "active"),
      validManifest(
        FIXTURE_DEPRECATED_CAPABILITY_ID,
        FIXTURE_CAPABILITY_VERSION,
        "deprecated",
      ),
      validManifest(FIXTURE_RETIRED_CAPABILITY_ID, FIXTURE_CAPABILITY_VERSION, "retired"),
      validManifest(
        FIXTURE_UNGRANTED_CAPABILITY_ID,
        FIXTURE_CAPABILITY_VERSION,
        "active",
      ),
    );

    await seedInstallationKey(fixtureKeypair);
    await seedEntitlement({
      allowedCapabilities: [
        FIXTURE_GRANTED_CAPABILITY_ID,
        FIXTURE_DEPRECATED_CAPABILITY_ID,
        FIXTURE_RETIRED_CAPABILITY_ID,
        FIXTURE_UNGRANTED_CAPABILITY_ID,
      ],
    });
    await seedCapabilityGrant(FIXTURE_GRANTED_CAPABILITY_ID);
    await seedCapabilityGrant(FIXTURE_DEPRECATED_CAPABILITY_ID);

    const token = await mintToken(fixtureKeypair);
    const response = await SELF.fetch(discoveryRequest(token));

    expect(response.status).toBe(200);
    expect(response.headers.get("Cache-Control")).toBe("private, must-revalidate");
    expect(response.headers.get("ETag")).toMatch(/^".+"$/);

    const body = (await response.json()) as { manifests: Manifest[] };
    expect(manifestIds(body.manifests).sort()).toEqual(
      [FIXTURE_GRANTED_CAPABILITY_ID, FIXTURE_DEPRECATED_CAPABILITY_ID].sort(),
    );
    expect(
      body.manifests.every(
        (manifest) =>
          manifest.Identity.lifecycleState === "active" ||
          manifest.Identity.lifecycleState === "deprecated",
      ),
    ).toBe(true);
  });
});

describe("T2 discovery_http_etag_not_modified", () => {
  it("returns 304 when If-None-Match matches and carries Cache-Control", async () => {
    buildRegistry(
      validManifest(FIXTURE_GRANTED_CAPABILITY_ID, FIXTURE_CAPABILITY_VERSION, "active"),
    );

    await seedInstallationKey(fixtureKeypair);
    await seedEntitlement({ allowedCapabilities: [FIXTURE_GRANTED_CAPABILITY_ID] });
    await seedCapabilityGrant(FIXTURE_GRANTED_CAPABILITY_ID);

    const token = await mintToken(fixtureKeypair);
    const first = await SELF.fetch(discoveryRequest(token));
    expect(first.status).toBe(200);
    const etag = first.headers.get("ETag");
    expect(etag).not.toBeNull();

    const second = await SELF.fetch(
      discoveryRequest(token, { "If-None-Match": etag! }),
    );
    expect(second.status).toBe(304);
    expect(second.headers.get("Cache-Control")).toBe("private, must-revalidate");
    expect(second.headers.get("ETag")).toBe(etag);
    expect(await second.text()).toBe("");
  });
});

describe("T3 discovery_http_changed_manifest_changes_etag", () => {
  it("changes ETag when the granted manifest set changes", async () => {
    buildRegistry(
      validManifest(FIXTURE_GRANTED_CAPABILITY_ID, FIXTURE_CAPABILITY_VERSION, "active"),
      validManifest("clinic.secondary", FIXTURE_CAPABILITY_VERSION, "active"),
    );

    await seedInstallationKey(fixtureKeypair);
    await seedEntitlement({
      allowedCapabilities: [FIXTURE_GRANTED_CAPABILITY_ID, "clinic.secondary"],
    });
    await seedCapabilityGrant(FIXTURE_GRANTED_CAPABILITY_ID);
    await seedCapabilityGrant("clinic.secondary");

    const token = await mintToken(fixtureKeypair);
    const first = await SELF.fetch(discoveryRequest(token));
    const firstEtag = first.headers.get("ETag");
    expect(first.status).toBe(200);
    expect(firstEtag).not.toBeNull();

    await env.DB
      .prepare("DELETE FROM capability_grant WHERE capability_id = ?")
      .bind("clinic.secondary")
      .run();
    isolateConfigCache.clear();

    const second = await SELF.fetch(discoveryRequest(token));
    expect(second.status).toBe(200);
    const secondEtag = second.headers.get("ETag");
    expect(secondEtag).not.toBeNull();
    expect(secondEtag).not.toBe(firstEtag);
  });
});

describe("T4 discovery_http_ineligible_plan_capability_absent", () => {
  it("omits entitlement-gated capabilities for ineligible plans without an error code", async () => {
    buildRegistry(
      validManifest(
        FIXTURE_GATED_CAPABILITY_ID,
        FIXTURE_CAPABILITY_VERSION,
        "active",
        "standard",
      ),
    );

    await seedInstallationKey(fixtureKeypair);
    await seedEntitlement({
      plan: "starter",
      allowedCapabilities: [FIXTURE_GATED_CAPABILITY_ID],
    });
    await seedCapabilityGrant(FIXTURE_GATED_CAPABILITY_ID);

    const token = await mintToken(fixtureKeypair);
    const response = await SELF.fetch(discoveryRequest(token));

    expect(response.status).toBe(200);
    const body = (await response.json()) as { manifests: Manifest[] };
    expect(body.manifests).toHaveLength(0);
    expect(
      body.manifests.some(
        (manifest) => manifest.Identity.capabilityId === FIXTURE_GATED_CAPABILITY_ID,
      ),
    ).toBe(false);
  });
});

describe("T5 discovery_http_unauthenticated", () => {
  it("returns taxonomy unauthenticated without a manifest body or journal row for missing or invalid AAT", async () => {
    buildRegistry(
      validManifest(FIXTURE_GRANTED_CAPABILITY_ID, FIXTURE_CAPABILITY_VERSION, "active"),
    );

    const beforeCount = await env.DB
      .prepare("SELECT COUNT(*) AS count FROM ai_request")
      .first<{ count: number }>();

    const missing = await SELF.fetch(discoveryRequest());
    expect(missing.status).toBe(401);
    const missingBody = (await missing.json()) as { code: string; manifests?: unknown };
    expect(missingBody.code).toBe("unauthenticated");
    expect(missingBody.manifests).toBeUndefined();

    const invalid = await SELF.fetch(discoveryRequest("not-a-valid-token"));
    expect(invalid.status).toBe(401);
    const invalidBody = (await invalid.json()) as { code: string; manifests?: unknown };
    expect(invalidBody.code).toBe("unauthenticated");
    expect(invalidBody.manifests).toBeUndefined();

    const nonBearer = await SELF.fetch(
      discoveryRequest(undefined, { Authorization: "Basic not-an-aat" }),
    );
    expect(nonBearer.status).toBe(401);
    const nonBearerBody = (await nonBearer.json()) as {
      code: string;
      manifests?: unknown;
    };
    expect(nonBearerBody.code).toBe("unauthenticated");
    expect(nonBearerBody.manifests).toBeUndefined();

    const afterCount = await env.DB
      .prepare("SELECT COUNT(*) AS count FROM ai_request")
      .first<{ count: number }>();
    expect(afterCount?.count ?? -1).toBe(beforeCount?.count ?? 0);
  });
});
