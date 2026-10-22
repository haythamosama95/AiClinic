import { env, SELF } from "cloudflare:test";
import { CHANNEL_VERSIONS } from "vendor-contracts";
import { createAccessTeam } from "vendor-contracts/testkit";
import { beforeAll, describe, expect, it } from "vitest";
import migrationSql from "../migrations/20260731120000_platform_schema.sql?raw";
import tokenContractMigrationSql from "../migrations/20260803120000_token_contract.sql?raw";
import issuerKeyTenantBindingMigrationSql from "../migrations/20261003130000_issuer_key_tenant_binding.sql?raw";
import operatorCredentialMigrationSql from "../migrations/20261003120000_operator_credential_and_platform_alert.sql?raw";
import rm31AlertDeliverySql from "../migrations/20261021130000_rm31_alert_delivery.sql?raw";
import routingPolicyCanarySql from "../migrations/20260803100000_routing_policy_canary.sql?raw";
import routingPolicyStatusSql from "../migrations/20260805190000_routing_policy_status.sql?raw";
import rm33RoutingIntegritySql from "../migrations/20261021140000_rm33_routing_configuration_integrity.sql?raw";
import rm33ActivationGenerationSql from "../migrations/20261021150000_rm33_routing_activation_generation.sql?raw";
import planVersionPaidGrantCoverageMigrationSql from "../migrations/20261003140000_plan_version_paid_grant_coverage.sql?raw";
import rm30UsageAccountingMigrationSql from "../migrations/20261021120000_rm30_usage_accounting_identity.sql?raw";
import { applySqlStatements } from "./split-sql-statements";
import { VendorEntrypoint } from "../src/vendor/entrypoint";

declare module "cloudflare:test" {
  interface ProvidedEnv {
    DB: D1Database;
    ACCESS_TEAM_DOMAIN: string;
    ACCESS_AUD: string;
    VENDOR: {
      beginTokenContractRotation(
        args: Record<string, unknown>,
      ): Promise<{
        result: string;
        code: string;
        detail: string;
      }>;
      publishRoutingPolicy(
        args: Record<string, unknown>,
      ): Promise<{
        result: string;
        code: string;
        detail: string;
      }>;
      canaryRoutingPolicy(
        args: Record<string, unknown>,
      ): Promise<{
        result: string;
        code: string;
        detail: string;
      }>;
      promoteRoutingPolicy(
        args: Record<string, unknown>,
      ): Promise<{
        result: string;
        code: string;
        detail: string;
      }>;
      rollbackRoutingPolicy(
        args: Record<string, unknown>,
      ): Promise<{
        result: string;
        code: string;
        detail: string;
      }>;
    };
  }
}

const GATEWAY_ORIGIN = "https://ai-gateway.test";
const CONTRACT_VERSION = CHANNEL_VERSIONS.vendorEntrypoint;

async function applySql(db: D1Database, sql: string): Promise<void> {
  await applySqlStatements(db, sql);
}

let accessTeam: Awaited<ReturnType<typeof createAccessTeam>> | null = null;

async function mintAccessJwt(): Promise<string> {
  if (accessTeam === null) {
    accessTeam = await createAccessTeam({
      issuer: `https://${env.ACCESS_TEAM_DOMAIN}`,
    });
    const { fetchMock } = await import("cloudflare:test");
    fetchMock.activate();
    fetchMock.disableNetConnect();
    fetchMock
      .get(`https://${env.ACCESS_TEAM_DOMAIN}`)
      .intercept({ path: "/cdn-cgi/access/certs", method: "GET" })
      .reply(200, JSON.stringify({ keys: accessTeam.certs.keys }))
      .persist();
  }
  const now = Math.floor(Date.now() / 1000);
  return accessTeam.mint({
    email: "operator@clinic.test",
    aud: env.ACCESS_AUD,
    iat: now - 60,
    exp: now + 3600,
  });
}

beforeAll(async () => {
  await applySql(env.DB, migrationSql);
  await applySql(env.DB, tokenContractMigrationSql);
  await applySql(env.DB, issuerKeyTenantBindingMigrationSql);
  await applySql(env.DB, operatorCredentialMigrationSql);
  await applySql(env.DB, rm31AlertDeliverySql);
  await applySql(env.DB, routingPolicyCanarySql);
  await applySql(env.DB, routingPolicyStatusSql);
  await applySql(env.DB, rm33RoutingIntegritySql);
  await applySql(env.DB, rm33ActivationGenerationSql);
  await applySql(env.DB, planVersionPaidGrantCoverageMigrationSql);
  await applySql(env.DB, rm30UsageAccountingMigrationSql);
  await env.DB.prepare(
    `INSERT OR IGNORE INTO token_contract (ver, added_at, retired_at, changed_by)
     VALUES ('1', '2026-08-03T00:00:00.000Z', NULL, 'seed')`,
  ).run();
});

describe("removed_control_http_routes", () => {
  it("returns 404 for POST enroll without bearer", async () => {
    const response = await SELF.fetch(
      new Request(
        `${GATEWAY_ORIGIN}/control/installations/11111111-1111-4111-8111-111111111111/enroll`,
        {
          method: "POST",
          headers: { "content-type": "application/json" },
          body: JSON.stringify({ org_id: crypto.randomUUID() }),
        },
      ),
    );
    expect(response.status).toBe(404);
  });

  it("returns 404 for rotate and revoke-key lifecycle routes", async () => {
    const installationId = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
    const rotate = await SELF.fetch(
      new Request(
        `${GATEWAY_ORIGIN}/control/installations/${installationId}/rotate`,
        {
          method: "POST",
          headers: { "content-type": "application/json" },
          body: "{}",
        },
      ),
    );
    expect(rotate.status).toBe(404);

    const revoke = await SELF.fetch(
      new Request(
        `${GATEWAY_ORIGIN}/control/installations/${installationId}/revoke-key`,
        {
          method: "POST",
          headers: { "content-type": "application/json" },
          body: "{}",
        },
      ),
    );
    expect(revoke.status).toBe(404);
  });
});

describe("class_h_vendor_entrypoint", () => {
  it("beginTokenContractRotation advances current contract without operator bearer", async () => {
    const accessJwt = await mintAccessJwt();
    const envelope = await env.VENDOR.beginTokenContractRotation({
      contract_version: CONTRACT_VERSION,
      access_jwt: accessJwt,
    });
    expect(envelope.result).toBe("ok");
    expect(envelope.code).toBe("");
    const current = await env.DB.prepare(
      "SELECT ver FROM token_contract WHERE retired_at IS NULL ORDER BY ver DESC LIMIT 1",
    ).first<{ ver: string }>();
    expect(current?.ver).toBe("2");
  });

  it("publishRoutingPolicy rejects missing document via Access JWT only", async () => {
    const accessJwt = await mintAccessJwt();
    const envelope = await env.VENDOR.publishRoutingPolicy({
      contract_version: CONTRACT_VERSION,
      access_jwt: accessJwt,
    });
    expect(envelope.result).not.toBe("ok");
    expect(envelope.code).toBe("missing_document");
  });

  it("R8-PUB1: canary, promote and rollback handlers pass the R2 binding", async () => {
    // Seed the installation and policy chain so each handler reaches the R2 check
    // instead of returning installation_not_found or policy_version_not_found early.
    await env.DB.prepare(
      `INSERT OR IGNORE INTO installation (
        installation_id, org_id, display_name, status, region, enrolled_at
      ) VALUES ('inst-r2-binding-probe', 'org-r2-probe', 'R2 probe', 'active', 'us-east-1', '2026-08-03T00:00:00.000Z')`,
    ).run();
    await env.DB.prepare(
      `INSERT OR IGNORE INTO routing_policy (
        policy_id, version, content_pointer, active_from, activated_by
      ) VALUES ('standard', '1',
        'control/routing-policy/standard/1/sha256-${"0".repeat(64)}.json',
        '2026-08-03T00:00:00.000Z', 'seed')`,
    ).run();
    await env.DB.prepare(
      `INSERT OR IGNORE INTO routing_policy_activation (
        policy_id, generation, active_version, predecessor_version, predecessor_state
      ) VALUES ('standard', 0, NULL, NULL, 'unknown')`,
    ).run();
    const accessJwt = await mintAccessJwt();
    const args = {
      contract_version: CONTRACT_VERSION,
      access_jwt: accessJwt,
      policy_id: "standard",
      version: "1",
      installation_ids: ["inst-r2-binding-probe"],
    };
    const handlers = [
      env.VENDOR.canaryRoutingPolicy(args),
      env.VENDOR.promoteRoutingPolicy(args),
      env.VENDOR.rollbackRoutingPolicy(args),
    ];
    for (const envelope of await Promise.all(handlers)) {
      expect(envelope.code).not.toBe("missing_r2_binding");
      expect(envelope.code).not.toBe("installation_not_found");
      expect(envelope.code).not.toBe("policy_version_not_found");
    }
  });
});

describe("R9-RT1 countLedgerRows", () => {
  type DoOutcome = number | "unreachable" | "recovery_blocked";

  function fakeDoNamespace(
    outcomes: Record<string, DoOutcome>,
    seen: Array<Record<string, unknown>>,
  ): DurableObjectNamespace {
    return {
      idFromName: (name: string) => name,
      get: (id: string) => ({
        fetch: async (_url: string, init?: RequestInit) => {
          const body = JSON.parse(String(init?.body)) as Record<string, unknown>;
          seen.push(body);
          const outcome = outcomes[id];
          if (outcome === "unreachable") {
            throw new Error("clinic DO unreachable");
          }
          if (outcome === "recovery_blocked") {
            return new Response(
              JSON.stringify({
                contract_version: CHANNEL_VERSIONS.platformDo,
                kind: body.kind,
                result: "recovery_blocked",
              }),
              { status: 409, headers: { "Content-Type": "application/json" } },
            );
          }
          return new Response(
            JSON.stringify({
              contract_version: body.contract_version,
              kind: "count_terms",
              terms: outcome,
            }),
            { status: 200, headers: { "Content-Type": "application/json" } },
          );
        },
      }),
    } as unknown as DurableObjectNamespace;
  }

  function vendorWithDo(doNamespace: DurableObjectNamespace): VendorEntrypoint {
    return new VendorEntrypoint(
      {} as ExecutionContext,
      { ...env, DO: doNamespace } as unknown as ConstructorParameters<
        typeof VendorEntrypoint
      >[1],
    );
  }

  async function insertInstallation(id: string, status: string): Promise<void> {
    await env.DB.prepare(
      `INSERT INTO installation (installation_id, org_id, display_name, status, region, enrolled_at)
       VALUES (?, ?, ?, ?, 'eu', '2026-10-01T00:00:00.000Z')`,
    )
      .bind(id, `org-${id}`, `Clinic ${id}`, status)
      .run();
  }

  it("R9-RT1 countLedgerRows counts live DO terms across every installation, including deleted", async () => {
    await insertInstallation("inst-ledger-active", "active");
    await insertInstallation("inst-ledger-deleted", "deleted");
    const seen: Array<Record<string, unknown>> = [];
    const vendor = vendorWithDo(
      fakeDoNamespace({ "inst-ledger-active": 3, "inst-ledger-deleted": 4 }, seen),
    );

    const counted = await vendor.countLedgerRows({
      contract_version: CONTRACT_VERSION,
    });

    expect(counted.result).toBe("ok");
    expect(JSON.parse(counted.detail)).toEqual({
      terms: 7,
      grants: 0,
      installations: 2,
    });
    expect(seen.map((body) => body.kind)).toEqual(["count_terms", "count_terms"]);
    expect(
      await env.DB.prepare("SELECT COUNT(*) AS count FROM usage_term_retention").first<{
        count: number;
      }>(),
    ).toEqual({ count: 0 });
  });

  it("R9-RT1 countLedgerRows is transient when any clinic DO is unreachable", async () => {
    await insertInstallation("inst-down-active", "active");
    await insertInstallation("inst-down-deleted", "deleted");

    for (const outcome of ["unreachable", "recovery_blocked"] as const) {
      const vendor = vendorWithDo(
        fakeDoNamespace({ "inst-down-active": 2, "inst-down-deleted": outcome }, []),
      );

      const counted = await vendor.countLedgerRows({
        contract_version: CONTRACT_VERSION,
      });

      expect(counted).toEqual({
        contract_version: CONTRACT_VERSION,
        result: "transient",
        code: "",
        detail: "unavailable",
      });
      expect(counted).not.toHaveProperty("receipt");
    }
  });

  it("R9-RT1 countLedgerRows writes nothing", async () => {
    await insertInstallation("inst-readonly", "active");
    const before = {
      installation: await env.DB.prepare("SELECT COUNT(*) AS count FROM installation").first<{ count: number }>(),
      grants: await env.DB.prepare("SELECT COUNT(*) AS count FROM grant_ledger").first<{ count: number }>(),
      retention: await env.DB.prepare("SELECT COUNT(*) AS count FROM usage_term_retention").first<{ count: number }>(),
    };
    const seen: Array<Record<string, unknown>> = [];
    const vendor = vendorWithDo(fakeDoNamespace({ "inst-readonly": 1 }, seen));

    const counted = await vendor.countLedgerRows({
      contract_version: CONTRACT_VERSION,
    });

    expect(counted.result).toBe("ok");
    expect(seen.every((body) => body.kind === "count_terms")).toBe(true);
    expect(await env.DB.prepare("SELECT COUNT(*) AS count FROM installation").first<{ count: number }>()).toEqual(before.installation);
    expect(await env.DB.prepare("SELECT COUNT(*) AS count FROM grant_ledger").first<{ count: number }>()).toEqual(before.grants);
    expect(await env.DB.prepare("SELECT COUNT(*) AS count FROM usage_term_retention").first<{ count: number }>()).toEqual(before.retention);
  });
});

describe("R9-RT1 readLaunchState", () => {
  const PUBLISHED_DEVELOPMENT_KEY =
    '{"kid":"platform-test","pkcs8":"MC4CAQAwBQYDK2VwBCIEIN2ndQQArm1dlsCuHaGGaUB8nnqfj7W2HaVbj_JJA9Lk","public_key":"GNzxZ6Gymues_aeJArGyb3wDESTOUJeqhuZBfTByni0"}';

  function bytesToBase64Url(bytes: Uint8Array): string {
    let binary = "";
    for (const byte of bytes) binary += String.fromCharCode(byte);
    return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/u, "");
  }

  async function signingSecret(kid: string): Promise<{ json: string; pkcs8: string; publicKey: string }> {
    const pair = await crypto.subtle.generateKey("Ed25519", true, ["sign", "verify"]);
    const pkcs8 = bytesToBase64Url(new Uint8Array(await crypto.subtle.exportKey("pkcs8", pair.privateKey)));
    const publicKey = bytesToBase64Url(new Uint8Array(await crypto.subtle.exportKey("raw", pair.publicKey)));
    return { json: JSON.stringify({ kid, pkcs8, public_key: publicKey }), pkcs8, publicKey };
  }

  function vendorWith(overrides: Record<string, unknown>): VendorEntrypoint {
    return new VendorEntrypoint(
      {} as ExecutionContext,
      { ...env, ...overrides } as unknown as ConstructorParameters<
        typeof VendorEntrypoint
      >[1],
    );
  }

  it("R9-RT1 readLaunchState returns channel versions and a public signing key, never the private key", async () => {
    const secret = await signingSecret("staging-launch-1");
    const vendor = vendorWith({ ENVIRONMENT: "staging", PLATFORM_SIGNING_KEY: secret.json });

    const state = await vendor.readLaunchState({ contract_version: CONTRACT_VERSION });

    expect(state.result).toBe("ok");
    expect(state.code).toBe("");
    expect(state.detail).not.toContain(secret.pkcs8);
    expect(JSON.parse(state.detail)).toEqual({
      channel_versions: CHANNEL_VERSIONS,
      environment: "staging",
      signing_key: { kid: "staging-launch-1", public_key: secret.publicKey },
      legacy_routing_policy_ids: [],
    });
    expect(Object.keys(CHANNEL_VERSIONS)).toHaveLength(9);
  });

  it("R9-RT1 readLaunchState returns null signing_key when the secret is missing", async () => {
    const vendor = vendorWith({ ENVIRONMENT: "staging", PLATFORM_SIGNING_KEY: undefined });

    const state = await vendor.readLaunchState({ contract_version: CONTRACT_VERSION });

    expect(state.result).toBe("ok");
    expect(JSON.parse(state.detail)).toEqual({
      channel_versions: CHANNEL_VERSIONS,
      environment: "staging",
      signing_key: null,
      legacy_routing_policy_ids: [],
    });
  });

  it("FV-P4 readLaunchState lists published, canary and active routing rows with a NULL content digest, and none once republished with a digest", async () => {
    const insert = (policyId: string, version: string, status: string, digest: string | null) =>
      env.DB.prepare(
        `INSERT INTO routing_policy (policy_id, version, content_pointer, active_from, activated_by, status, content_sha256)
         VALUES (?, ?, ?, '2026-10-01T00:00:00.000Z', 'operator-test', ?, ?)`,
      )
        .bind(policyId, version, `control/routing-policy/${policyId}/${version}.json`, status, digest)
        .run();
    await insert("fv-p4-legacy-a", "1", "published", null);
    await insert("fv-p4-legacy-b", "2", "active", null);
    await insert("fv-p4-legacy-c", "3", "canary", null);
    await insert("fv-p4-superseded", "1", "superseded", null);
    await insert("fv-p4-digested", "1", "active", "a".repeat(64));
    const secret = await signingSecret("staging-fv-p4");
    const vendor = vendorWith({ ENVIRONMENT: "staging", PLATFORM_SIGNING_KEY: secret.json });

    const before = JSON.parse((await vendor.readLaunchState({ contract_version: CONTRACT_VERSION })).detail);
    expect(before.legacy_routing_policy_ids).toEqual([
      "fv-p4-legacy-a@1",
      "fv-p4-legacy-b@2",
      "fv-p4-legacy-c@3",
    ]);

    // Republished: the quarantined rows are replaced by digested versions and the legacy rows are retired.
    await env.DB.prepare(
      `UPDATE routing_policy SET status = 'superseded' WHERE policy_id LIKE 'fv-p4-legacy-%'`,
    ).run();
    await insert("fv-p4-legacy-a", "4", "published", "b".repeat(64));
    const after = JSON.parse((await vendor.readLaunchState({ contract_version: CONTRACT_VERSION })).detail);
    expect(after.legacy_routing_policy_ids).toEqual([]);
  });

  it("R9-RT1 readLaunchState returns null signing_key for the published development key under production", async () => {
    const vendor = vendorWith({ ENVIRONMENT: "production", PLATFORM_SIGNING_KEY: PUBLISHED_DEVELOPMENT_KEY });

    const state = await vendor.readLaunchState({ contract_version: CONTRACT_VERSION });

    expect(state.result).toBe("ok");
    expect(JSON.parse(state.detail).signing_key).toBeNull();
    expect(state.detail).not.toContain("pkcs8");
  });

  it("R9-RT1 readLaunchState returns null signing_key when the public key does not match the secret", async () => {
    const mine = await signingSecret("staging-mismatch");
    const other = await signingSecret("unused");
    const mismatched = JSON.stringify({
      kid: "staging-mismatch",
      pkcs8: JSON.parse(mine.json).pkcs8,
      public_key: other.publicKey,
    });
    const vendor = vendorWith({ ENVIRONMENT: "staging", PLATFORM_SIGNING_KEY: mismatched });

    const state = await vendor.readLaunchState({ contract_version: CONTRACT_VERSION });

    expect(state.result).toBe("ok");
    expect(JSON.parse(state.detail).signing_key).toBeNull();
    expect(state.detail).not.toContain(mine.pkcs8);
  });

  it("R9-RT1 readLaunchState writes nothing", async () => {
    await env.DB.prepare(
      `INSERT INTO installation (installation_id, org_id, display_name, status, region, enrolled_at)
       VALUES ('inst-launch-readonly', 'org-inst-launch-readonly', 'Clinic launch', 'active', 'eu', '2026-10-01T00:00:00.000Z')`,
    ).run();
    const count = async (table: string) =>
      env.DB.prepare(`SELECT COUNT(*) AS count FROM ${table}`).first<{ count: number }>();
    const before = {
      installation: await count("installation"),
      grants: await count("grant_ledger"),
      retention: await count("usage_term_retention"),
    };
    const secret = await signingSecret("staging-readonly");
    const vendor = vendorWith({ ENVIRONMENT: "staging", PLATFORM_SIGNING_KEY: secret.json });

    const state = await vendor.readLaunchState({ contract_version: CONTRACT_VERSION });

    expect(state.result).toBe("ok");
    expect(await count("installation")).toEqual(before.installation);
    expect(await count("grant_ledger")).toEqual(before.grants);
    expect(await count("usage_term_retention")).toEqual(before.retention);
  });
});
