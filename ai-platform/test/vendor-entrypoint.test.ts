import { env, SELF } from "cloudflare:test";
import { CHANNEL_VERSIONS } from "vendor-contracts";
import { createAccessTeam } from "vendor-contracts/testkit";
import { beforeAll, describe, expect, it } from "vitest";
import migrationSql from "../migrations/20260731120000_platform_schema.sql?raw";
import tokenContractMigrationSql from "../migrations/20260803120000_token_contract.sql?raw";
import issuerKeyTenantBindingMigrationSql from "../migrations/20261003130000_issuer_key_tenant_binding.sql?raw";
import operatorCredentialMigrationSql from "../migrations/20261003120000_operator_credential_and_platform_alert.sql?raw";
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
});
