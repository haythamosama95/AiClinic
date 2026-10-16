import { spawn } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { describe, expect, it } from "vitest";
import type { JourneyOperationDefinition } from "../src/catalog/journey-types.ts";
import { STAGE7_OPERATIONS } from "../src/catalog/stage-7-discovery.ts";
import {
  STAGE8_OPERATIONS,
  buildVisitSummaryContextJson,
} from "../src/catalog/stage-8-ingress.ts";
import { STAGE9_OPERATIONS } from "../src/catalog/stage-9-guard.ts";
import { STAGE10_OPERATIONS } from "../src/catalog/stage-10-stream.ts";
import { STAGE11_OPERATIONS } from "../src/catalog/stage-11-settlement.ts";
import { STAGE12_OPERATIONS } from "../src/catalog/stage-12-lookup-support.ts";
import { Stage7DiscoveryPage } from "../src/components/Stage7DiscoveryPage.tsx";
import { sendCapabilitiesRequest } from "../src/lib/gateway-api.ts";
import {
  importIssuerPrivateKey,
  issuerContractVersionHeader,
  type IssuerKeyMaterial,
  type IssuerTokenClaims,
} from "../src/lib/issuer-token.ts";
import {
  buildJourneyDefaultParams,
  sendJourneyRequest,
} from "../src/lib/journey-api.ts";
import { extractRequestReferenceFromSse } from "../src/lib/sse-format.ts";
import type { ClinicEnrollmentMaterial, HttpExchange } from "../src/types.ts";

const GATEWAY_ORIGIN = "http://127.0.0.1:8787";
const DEV_VARS_PATH = path.resolve(
  import.meta.dirname,
  "../../ai-platform/.dev.vars",
);
const BACKEND_ENV_PATH = path.resolve(
  import.meta.dirname,
  "../../backend/local/.env",
);

type SmokeTenantScope = {
  org_id: string;
  branch_id: string;
};

function readEnvFile(filePath: string): Record<string, string> {
  if (!fs.existsSync(filePath)) {
    return {};
  }

  const values: Record<string, string> = {};
  for (const line of fs.readFileSync(filePath, "utf8").split("\n")) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith("#")) {
      continue;
    }
    const separator = trimmed.indexOf("=");
    if (separator === -1) {
      continue;
    }
    values[trimmed.slice(0, separator).trim()] = trimmed
      .slice(separator + 1)
      .trim();
  }
  return values;
}

function runCommand(
  command: string,
  args: string[],
  cwd: string,
  env: Record<string, string> = process.env as Record<string, string>,
): Promise<{ stdout: string; stderr: string; code: number | null }> {
  return new Promise((resolve, reject) => {
    const child = spawn(command, args, { cwd, shell: false, env });
    let stdout = "";
    let stderr = "";

    child.stdout.on("data", (chunk: Buffer) => {
      stdout += chunk.toString();
    });
    child.stderr.on("data", (chunk: Buffer) => {
      stderr += chunk.toString();
    });
    child.on("error", reject);
    child.on("close", (code) => resolve({ stdout, stderr, code }));
  });
}

async function queryPostgresJson<T>(sql: string): Promise<T | null> {
  const backendEnv = readEnvFile(BACKEND_ENV_PATH);
  const password = backendEnv.POSTGRES_PASSWORD ?? "postgres";
  const port = backendEnv.SUPABASE_DB_PORT ?? "54322";
  const repoRoot = path.resolve(import.meta.dirname, "../..");

  const result = await runCommand(
    "psql",
    [
      "-h",
      "127.0.0.1",
      "-p",
      port,
      "-U",
      "postgres",
      "-d",
      "postgres",
      "-t",
      "-A",
      "-c",
      sql,
    ],
    repoRoot,
    { ...process.env, PGPASSWORD: password },
  );

  if (result.code !== 0) {
    throw new Error(result.stderr || result.stdout || "Postgres query failed");
  }

  const row = result.stdout.trim();
  if (!row) {
    return null;
  }

  return JSON.parse(row) as T;
}

function pkcs8Base64urlFromEd25519Secret(secretBytes: Uint8Array): string {
  const seed = secretBytes.slice(0, 32);
  const prefix = new Uint8Array([
    0x30, 0x2e, 0x02, 0x01, 0x00, 0x30, 0x05, 0x06, 0x03, 0x2b, 0x65, 0x70,
    0x04, 0x22, 0x04, 0x20,
  ]);
  const pkcs8 = new Uint8Array(prefix.length + seed.length);
  pkcs8.set(prefix);
  pkcs8.set(seed, prefix.length);
  let binary = "";
  for (const byte of pkcs8) {
    binary += String.fromCharCode(byte);
  }
  return btoa(binary)
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/u, "");
}

async function loadTestIssuerKeyMaterial(): Promise<IssuerKeyMaterial> {
  const devVars = readEnvFile(DEV_VARS_PATH);
  const kidFromVars = devVars.TEST_ISSUER_KID?.trim();
  const pkcs8FromVars = devVars.TEST_ISSUER_PRIVATE_KEY_PKCS8?.trim();
  if (kidFromVars && pkcs8FromVars) {
    return importIssuerPrivateKey(kidFromVars, pkcs8FromVars);
  }

  const row = await queryPostgresJson<{ kid: string; secret_b64: string }>(`
SELECT row_to_json(row) FROM (
  SELECT
    ik.kid,
    ds.decrypted_secret AS secret_b64
  FROM ai_internal.issuer_key ik
  JOIN vault.decrypted_secrets ds ON ds.id = ik.secret_ref
  WHERE ik.status = 'signing'
  ORDER BY ik.not_before DESC
  LIMIT 1
) row;
`.trim());

  if (!row?.kid || !row.secret_b64) {
    throw new Error(
      "Test issuer key not found. Set TEST_ISSUER_KID and TEST_ISSUER_PRIVATE_KEY_PKCS8 in ai-platform/.dev.vars or seed ai_internal.issuer_key.",
    );
  }

  const secretBytes = Uint8Array.from(atob(row.secret_b64), (char) =>
    char.charCodeAt(0),
  );
  return importIssuerPrivateKey(
    row.kid,
    pkcs8Base64urlFromEd25519Secret(secretBytes),
  );
}

async function loadSmokeTenantScope(): Promise<SmokeTenantScope> {
  const row = await queryPostgresJson<SmokeTenantScope>(`
SELECT row_to_json(row) FROM (
  SELECT
    o.id::text AS org_id,
    b.id::text AS branch_id
  FROM public.organizations o
  JOIN public.branches b
    ON b.organization_id = o.id
   AND b.is_deleted = false
  WHERE o.is_deleted = false
  ORDER BY o.created_at, b.created_at
  LIMIT 1
) row;
`.trim());

  if (!row?.org_id || !row.branch_id) {
    throw new Error(
      "Smoke tenant scope missing. Seed at least one organization and branch in local Supabase.",
    );
  }

  return row;
}

function clinicMaterial(scope: SmokeTenantScope): ClinicEnrollmentMaterial {
  return {
    installation_id: "",
    kid: "",
    public_key: "",
    org_id: scope.org_id,
    branch_id: scope.branch_id,
    display_name: "clinic-pages-smoke",
    aat_ver: "2",
  };
}

function findOperation(
  operations: JourneyOperationDefinition[],
  id: string,
): JourneyOperationDefinition {
  const operation = operations.find((candidate) => candidate.id === id);
  if (!operation) {
    throw new Error(`Expected catalog operation ${id}`);
  }
  return operation;
}

function assertHttpExchangeRaw(exchange: HttpExchange): void {
  expect(exchange.request.raw.length).toBeGreaterThan(0);
  expect(exchange.response.raw.length).toBeGreaterThan(0);
}

function assertIssuerTokenRequest(
  exchange: HttpExchange,
  method: string,
  pathFragment: string,
): void {
  assertHttpExchangeRaw(exchange);
  expect(exchange.request.method).toBe(method);
  expect(exchange.request.url).toContain(pathFragment);
  expect(exchange.request.url.startsWith(GATEWAY_ORIGIN)).toBe(true);
  expect(exchange.request.raw).toContain("Authorization: Bearer ");
  expect(exchange.request.raw).toContain(
    `Aip-Contract-Version: ${issuerContractVersionHeader()}`,
  );
  expect(exchange.response.status).not.toBe(401);
}

describe("clinic_pages_smoke", () => {
  it("E2E-P7.1-01", async () => {
    void Stage7DiscoveryPage;

    const issuerKey = await loadTestIssuerKeyMaterial();
    const tenantScope = await loadSmokeTenantScope();
    const issuerClaims: IssuerTokenClaims = {
      org: tenantScope.org_id,
      branch: tenantScope.branch_id,
    };
    const material = clinicMaterial(tenantScope);
    const credentials = {
      operatorBearer: "",
      issuerKey,
      issuerClaims,
    };

    const capabilitiesOperation = findOperation(
      STAGE7_OPERATIONS,
      "get-capabilities",
    );
    expect(capabilitiesOperation.path).toBe("/v1/capabilities");
    const capabilitiesExchange = await sendCapabilitiesRequest(
      issuerKey,
      issuerClaims,
    );
    assertIssuerTokenRequest(
      capabilitiesExchange,
      "GET",
      "/v1/capabilities",
    );
    expect(capabilitiesExchange.response.status).toBe(200);

    const ingressOperation = findOperation(
      STAGE8_OPERATIONS,
      "post-requests-visit-summary",
    );
    const ingressParams = buildJourneyDefaultParams(
      ingressOperation.fields,
      material,
    );
    ingressParams.context = buildVisitSummaryContextJson(
      tenantScope.org_id,
      tenantScope.branch_id,
    );
    const ingressExchange = await sendJourneyRequest(
      ingressOperation,
      ingressParams,
      credentials,
    );
    assertIssuerTokenRequest(ingressExchange, "POST", "/v1/requests");

    const guardOperation = findOperation(STAGE9_OPERATIONS, "guard-s1-normal");
    const guardParams = buildJourneyDefaultParams(
      guardOperation.fields,
      material,
    );
    const guardExchange = await sendJourneyRequest(
      guardOperation,
      guardParams,
      credentials,
    );
    assertIssuerTokenRequest(guardExchange, "POST", "/v1/requests");

    const streamOperation = findOperation(
      STAGE10_OPERATIONS,
      "stream-sse-happy",
    );
    const streamParams = buildJourneyDefaultParams(
      streamOperation.fields,
      material,
    );
    streamParams.context = buildVisitSummaryContextJson(
      tenantScope.org_id,
      tenantScope.branch_id,
    );
    const streamExchange = await sendJourneyRequest(
      streamOperation,
      streamParams,
      credentials,
    );
    assertIssuerTokenRequest(streamExchange, "POST", "/v1/requests");

    const requestReference =
      extractRequestReferenceFromSse(streamExchange.response.rawBody) ??
      streamExchange.response.pinned?.find(
        (row) => row.name === "request_reference",
      )?.value;

    expect(typeof requestReference).toBe("string");
    expect((requestReference as string).length).toBeGreaterThan(0);

    const settlementOperation = findOperation(
      STAGE11_OPERATIONS,
      "settle-get-terminal",
    );
    const settlementExchange = await sendJourneyRequest(
      settlementOperation,
      { request_reference: requestReference as string },
      credentials,
    );
    assertIssuerTokenRequest(
      settlementExchange,
      "GET",
      `/v1/requests/${encodeURIComponent(requestReference as string)}`,
    );

    const lookupOperation = findOperation(
      STAGE12_OPERATIONS,
      "get-request-by-reference",
    );
    const lookupExchange = await sendJourneyRequest(
      lookupOperation,
      { request_reference: requestReference as string },
      credentials,
    );
    assertIssuerTokenRequest(
      lookupExchange,
      "GET",
      `/v1/requests/${encodeURIComponent(requestReference as string)}`,
    );
  });
});
