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
import { applySqlStatements } from "./split-sql-statements";

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
