import { env } from "cloudflare:test";
import { beforeAll, beforeEach, describe, expect, it } from "vitest";
import migrationSql from "../migrations/20260731120000_platform_schema.sql?raw";
import tokenContractMigrationSql from "../migrations/20260803120000_token_contract.sql?raw";
import { ConfigCache, createD1ConfigReader } from "../src/config-cache";
import { EnrolledKeyVerifier, type VerifyContext } from "../src/identity";
import { assertControlAudit } from "./helpers/control-audit-assert";

declare module "cloudflare:test" {
  interface ProvidedEnv {
    DB: D1Database;
  }
}

const GATEWAY_ORIGIN = "https://ai-gateway.test";
const FAKE_OPERATOR_ID = "operator-j4-token-contract";
const NEW_VER = "2";
const PRIOR_VER = "1";
const AUDIENCE = "ai-platform";
const CLOCK_SKEW_SECONDS = 60;
const NOW = 1_720_000_450;

const FIXTURE_ISS = "a1b2c3d4-e5f6-7890-abcd-ef1234567890";
const FIXTURE_KID = "f47ac10b-58cc-4372-a567-0e02b2c3d479";
const FIXTURE_SUB = "c1000000-0000-4000-8000-000000000001";
const FIXTURE_ORG = "d2000000-0000-4000-8000-000000000001";
const FIXTURE_BRANCH = "e3000000-0000-4000-8000-000000000001";
const FIXTURE_JTI = "f4000000-0000-4000-8000-000000000001";

type OperatorPrincipal = { operatorId: string };
type OperatorAuth = {
  resolve(_request: Request): OperatorPrincipal | null;
};

type TestKeypair = {
  publicKey: CryptoKey;
  privateKey: CryptoKey;
  kid: string;
  publicKeyB64: string;
};

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

function createFakeOperatorAuth(
  principal: OperatorPrincipal | null = { operatorId: FAKE_OPERATOR_ID },
): OperatorAuth {
  return {
    resolve() {
      return principal;
    },
  };
}

type TokenContractControlHandlers = {
  handleTokenContractBeginRotation: (
    request: Request,
    bindings: { DB: D1Database },
    operatorAuth: OperatorAuth,
  ) => Promise<Response>;
  handleTokenContractRetire: (
    request: Request,
    bindings: { DB: D1Database },
    operatorAuth: OperatorAuth,
  ) => Promise<Response>;
};

async function loadTokenContractHandlers(): Promise<TokenContractControlHandlers> {
  return import(/* @vite-ignore */ "../src/control") as Promise<TokenContractControlHandlers>;
}

function bindings(): { DB: D1Database } {
  return { DB: env.DB };
}

async function applySql(db: D1Database, sql: string): Promise<void> {
  const statements = sql
    .replace(/--.*$/gm, "")
    .split(";")
    .map((statement) => statement.trim())
    .filter((statement) => statement.length > 0);

  for (const statement of statements) {
    await db.prepare(statement).run();
  }
}

async function countAcceptedContracts(): Promise<number> {
  const row = await env.DB.prepare(
    "SELECT COUNT(*) AS count FROM token_contract WHERE retired_at IS NULL",
  ).first<{ count: number }>();
  return row?.count ?? 0;
}

async function clearTokenContractTables(): Promise<void> {
  await env.DB.batch([
    env.DB.prepare("DELETE FROM control_audit"),
    env.DB.prepare("DELETE FROM installation_key"),
    env.DB.prepare("DELETE FROM installation"),
    env.DB.prepare("DELETE FROM token_contract"),
    env.DB.prepare(
      `INSERT INTO token_contract (ver, added_at, retired_at, changed_by)
       VALUES ('1', '2026-08-03T00:00:00.000Z', NULL, 'seed')`,
    ),
  ]);
}

function buildBeginRotationRequest(ver: string = NEW_VER): Request {
  return new Request(`${GATEWAY_ORIGIN}/control/token-contract/begin-rotation`, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      authorization: `Bearer ${FAKE_OPERATOR_ID}`,
    },
    body: JSON.stringify({ ver }),
  });
}

function buildRetireRequest(ver: string = PRIOR_VER): Request {
  return new Request(`${GATEWAY_ORIGIN}/control/token-contract/retire`, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      authorization: `Bearer ${FAKE_OPERATOR_ID}`,
    },
    body: JSON.stringify({ ver }),
  });
}

function buildBeginRotationRequestBody(body: unknown): Request {
  return new Request(`${GATEWAY_ORIGIN}/control/token-contract/begin-rotation`, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      authorization: `Bearer ${FAKE_OPERATOR_ID}`,
    },
    body: JSON.stringify(body),
  });
}

function buildRetireRequestBody(body: unknown): Request {
  return new Request(`${GATEWAY_ORIGIN}/control/token-contract/retire`, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      authorization: `Bearer ${FAKE_OPERATOR_ID}`,
    },
    body: JSON.stringify(body),
  });
}

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

async function generateTestKeypair(kid: string = FIXTURE_KID): Promise<TestKeypair> {
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

async function mintToken(
  keypair: TestKeypair,
  claims: Partial<AatClaims> = {},
): Promise<string> {
  const payload: AatClaims = {
    iss: FIXTURE_ISS,
    aud: AUDIENCE,
    sub: FIXTURE_SUB,
    org: FIXTURE_ORG,
    branch: FIXTURE_BRANCH,
    role: "doctor",
    scopes: ["ai.access"],
    jti: FIXTURE_JTI,
    iat: NOW - 30,
    exp: NOW + 300,
    ver: "1",
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

async function seedActiveInstallation(keypair: TestKeypair): Promise<void> {
  const enrolledAt = new Date(NOW * 1000).toISOString();
  const validFrom = new Date((NOW - 3600) * 1000).toISOString();
  await env.DB.prepare(
    `INSERT INTO installation
      (installation_id, org_id, display_name, status, region, enrolled_at)
     VALUES (?, ?, ?, 'active', ?, ?)`,
  )
    .bind(FIXTURE_ISS, FIXTURE_ORG, "J4 Clinic", "us-east-1", enrolledAt)
    .run();
  await env.DB.prepare(
    `INSERT INTO installation_key
      (key_id, installation_id, public_key, algorithm, valid_from, valid_until, revoked_at)
     VALUES (?, ?, ?, 'EdDSA', ?, NULL, NULL)`,
  )
    .bind(keypair.kid, FIXTURE_ISS, keypair.publicKeyB64, validFrom)
    .run();
}

function buildD1VerifyContext(): VerifyContext {
  return {
    audience: AUDIENCE,
    clockSkewSeconds: CLOCK_SKEW_SECONDS,
    now: NOW,
    cache: new ConfigCache(),
    reader: createD1ConfigReader(env.DB),
  };
}

beforeAll(async () => {
  await applySql(env.DB, migrationSql);
  await applySql(env.DB, tokenContractMigrationSql);
});

beforeEach(async () => {
  await clearTokenContractTables();
});

describe("T-J4-04 accepted_set_is_one_when_stable_and_two_mid_rotation", () => {
  it("counts exactly one accepted ver when stable and two mid-rotation", async () => {
    const stableCount = await countAcceptedContracts();
    expect(stableCount).toBe(1);

    const { handleTokenContractBeginRotation } = await loadTokenContractHandlers();
    const operatorAuth = createFakeOperatorAuth({
      operatorId: FAKE_OPERATOR_ID,
    });

    const response = await handleTokenContractBeginRotation(
      buildBeginRotationRequest(),
      bindings(),
      operatorAuth,
    );
    expect(response.ok).toBe(true);

    const midRotationCount = await countAcceptedContracts();
    expect(midRotationCount).toBe(2);
  });
});

describe("T-J4-05 begin_rotation_adds_ver_and_keeps_prior", () => {
  it("inserts the new ver, keeps the prior accepted, and audits begin-rotation", async () => {
    const { handleTokenContractBeginRotation } = await loadTokenContractHandlers();
    const operatorAuth = createFakeOperatorAuth({
      operatorId: FAKE_OPERATOR_ID,
    });

    const response = await handleTokenContractBeginRotation(
      buildBeginRotationRequest(),
      bindings(),
      operatorAuth,
    );
    expect(response.ok).toBe(true);

    const prior = await env.DB.prepare(
      "SELECT ver, retired_at FROM token_contract WHERE ver = ?",
    )
      .bind(PRIOR_VER)
      .first<{ ver: string; retired_at: string | null }>();
    const added = await env.DB.prepare(
      "SELECT ver, retired_at FROM token_contract WHERE ver = ?",
    )
      .bind(NEW_VER)
      .first<{ ver: string; retired_at: string | null }>();

    expect(prior?.retired_at).toBeNull();
    expect(added?.ver).toBe(NEW_VER);
    expect(added?.retired_at).toBeNull();

    await assertControlAudit(env.DB, {
      operatorId: FAKE_OPERATOR_ID,
      action: "token_contract_begin_rotation",
      target: NEW_VER,
    });
  });
});

describe("T-J4-06 retire_stamps_retired_at_and_returns_set_to_one", () => {
  it("stamps retired_at, returns accepted count to one, and audits retire", async () => {
    const handlers = await loadTokenContractHandlers();
    const operatorAuth = createFakeOperatorAuth({
      operatorId: FAKE_OPERATOR_ID,
    });

    const beginResponse = await handlers.handleTokenContractBeginRotation(
      buildBeginRotationRequest(),
      bindings(),
      operatorAuth,
    );
    expect(beginResponse.ok).toBe(true);

    const retireResponse = await handlers.handleTokenContractRetire(
      buildRetireRequest(),
      bindings(),
      operatorAuth,
    );
    expect(retireResponse.ok).toBe(true);

    const retired = await env.DB.prepare(
      "SELECT retired_at FROM token_contract WHERE ver = ?",
    )
      .bind(PRIOR_VER)
      .first<{ retired_at: string | null }>();
    expect(retired?.retired_at).toBeTruthy();

    const acceptedCount = await countAcceptedContracts();
    expect(acceptedCount).toBe(1);

    await assertControlAudit(env.DB, {
      operatorId: FAKE_OPERATOR_ID,
      action: "token_contract_retire",
      target: PRIOR_VER,
    });
  });
});

describe("T-J4-10 rotation_requires_no_re_enrollment", () => {
  it("same enrolled iss and kid still verify under both accepted vers after begin-rotation", async () => {
    const keypair = await generateTestKeypair();
    await seedActiveInstallation(keypair);

    const { handleTokenContractBeginRotation } = await loadTokenContractHandlers();
    const operatorAuth = createFakeOperatorAuth({
      operatorId: FAKE_OPERATOR_ID,
    });

    const response = await handleTokenContractBeginRotation(
      buildBeginRotationRequest(),
      bindings(),
      operatorAuth,
    );
    expect(response.ok).toBe(true);

    const accepted = await env.DB.prepare(
      "SELECT ver FROM token_contract WHERE retired_at IS NULL ORDER BY ver",
    ).all<{ ver: string }>();
    expect(accepted.results?.map((row) => row.ver)).toEqual([PRIOR_VER, NEW_VER]);

    const priorStillAccepted = await env.DB.prepare(
      "SELECT retired_at FROM token_contract WHERE ver = ?",
    )
      .bind(PRIOR_VER)
      .first<{ retired_at: string | null }>();
    expect(priorStillAccepted?.retired_at).toBeNull();

    const verifier = new EnrolledKeyVerifier();
    const ctx = buildD1VerifyContext();
    const tokenVer1 = await mintToken(keypair, {
      ver: PRIOR_VER,
      jti: "a0000000-0000-4000-8000-000000000001",
    });
    const tokenVer2 = await mintToken(keypair, {
      ver: NEW_VER,
      jti: "b0000000-0000-4000-8000-000000000001",
    });

    const result1 = await verifier.verify(tokenVer1, ctx);
    const result2 = await verifier.verify(tokenVer2, ctx);
    expect(result1.ok).toBe(true);
    expect(result2.ok).toBe(true);
    if (result1.ok && result2.ok) {
      expect(result1.principal.installationId).toBe(FIXTURE_ISS);
      expect(result2.principal.installationId).toBe(FIXTURE_ISS);
    }
  });
});

describe("writer_enforcement_refuses_third_accepted_ver", () => {
  it("returns 409 rotation_already_open and leaves accepted set unchanged", async () => {
    const { handleTokenContractBeginRotation } = await loadTokenContractHandlers();
    const operatorAuth = createFakeOperatorAuth();

    const first = await handleTokenContractBeginRotation(
      buildBeginRotationRequest(NEW_VER),
      bindings(),
      operatorAuth,
    );
    expect(first.ok).toBe(true);
    expect(await countAcceptedContracts()).toBe(2);

    const second = await handleTokenContractBeginRotation(
      buildBeginRotationRequest("3"),
      bindings(),
      operatorAuth,
    );
    expect(second.status).toBe(409);
    expect(await second.json()).toEqual({ error: "rotation_already_open" });
    expect(await countAcceptedContracts()).toBe(2);

    const third = await env.DB.prepare(
      "SELECT ver FROM token_contract WHERE ver = ?",
    )
      .bind("3")
      .first();
    expect(third).toBeNull();
  });
});

describe("retire_error_branches", () => {
  it("returns 404 ver_not_found for an unknown ver", async () => {
    const { handleTokenContractRetire } = await loadTokenContractHandlers();
    const response = await handleTokenContractRetire(
      buildRetireRequest("never-existed"),
      bindings(),
      createFakeOperatorAuth(),
    );
    expect(response.status).toBe(404);
    expect(await response.json()).toEqual({ error: "ver_not_found" });
  });

  it("returns 409 ver_already_retired on double-retire", async () => {
    const handlers = await loadTokenContractHandlers();
    const operatorAuth = createFakeOperatorAuth();

    expect(
      (
        await handlers.handleTokenContractBeginRotation(
          buildBeginRotationRequest(),
          bindings(),
          operatorAuth,
        )
      ).ok,
    ).toBe(true);

    const firstRetire = await handlers.handleTokenContractRetire(
      buildRetireRequest(PRIOR_VER),
      bindings(),
      operatorAuth,
    );
    expect(firstRetire.ok).toBe(true);

    const secondRetire = await handlers.handleTokenContractRetire(
      buildRetireRequest(PRIOR_VER),
      bindings(),
      operatorAuth,
    );
    expect(secondRetire.status).toBe(409);
    expect(await secondRetire.json()).toEqual({ error: "ver_already_retired" });
  });

  it("returns 409 no_rotation_open when retiring the sole accepted ver", async () => {
    const { handleTokenContractRetire } = await loadTokenContractHandlers();
    const response = await handleTokenContractRetire(
      buildRetireRequest(PRIOR_VER),
      bindings(),
      createFakeOperatorAuth(),
    );
    expect(response.status).toBe(409);
    expect(await response.json()).toEqual({ error: "no_rotation_open" });
    expect(await countAcceptedContracts()).toBe(1);
  });

  it("cancel-rotation retires the newly added ver and returns to one", async () => {
    const handlers = await loadTokenContractHandlers();
    const operatorAuth = createFakeOperatorAuth();

    expect(
      (
        await handlers.handleTokenContractBeginRotation(
          buildBeginRotationRequest(NEW_VER),
          bindings(),
          operatorAuth,
        )
      ).ok,
    ).toBe(true);
    expect(await countAcceptedContracts()).toBe(2);

    const cancel = await handlers.handleTokenContractRetire(
      buildRetireRequest(NEW_VER),
      bindings(),
      operatorAuth,
    );
    expect(cancel.ok).toBe(true);
    expect(await countAcceptedContracts()).toBe(1);

    const cancelled = await env.DB.prepare(
      "SELECT retired_at FROM token_contract WHERE ver = ?",
    )
      .bind(NEW_VER)
      .first<{ retired_at: string | null }>();
    expect(cancelled?.retired_at).toBeTruthy();

    const prior = await env.DB.prepare(
      "SELECT retired_at FROM token_contract WHERE ver = ?",
    )
      .bind(PRIOR_VER)
      .first<{ retired_at: string | null }>();
    expect(prior?.retired_at).toBeNull();
  });
});

describe("token_contract_operator_auth_and_payload_validation", () => {
  it("rejects both mutations with 401 unauthorized and no D1 writes", async () => {
    const handlers = await loadTokenContractHandlers();
    const rejectAuth = createFakeOperatorAuth(null);
    const auditBefore = await env.DB.prepare(
      "SELECT COUNT(*) AS count FROM control_audit",
    ).first<{ count: number }>();

    const begin = await handlers.handleTokenContractBeginRotation(
      buildBeginRotationRequest(),
      bindings(),
      rejectAuth,
    );
    const retire = await handlers.handleTokenContractRetire(
      buildRetireRequest(),
      bindings(),
      rejectAuth,
    );

    expect(begin.status).toBe(401);
    expect(await begin.json()).toEqual({ error: "unauthorized" });
    expect(retire.status).toBe(401);
    expect(await retire.json()).toEqual({ error: "unauthorized" });
    expect(await countAcceptedContracts()).toBe(1);

    const auditAfter = await env.DB.prepare(
      "SELECT COUNT(*) AS count FROM control_audit",
    ).first<{ count: number }>();
    expect(auditAfter?.count ?? 0).toBe(auditBefore?.count ?? 0);
  });

  it("returns 400 invalid_ver for empty or missing ver on both handlers", async () => {
    const handlers = await loadTokenContractHandlers();
    const operatorAuth = createFakeOperatorAuth();

    const beginEmpty = await handlers.handleTokenContractBeginRotation(
      buildBeginRotationRequestBody({ ver: "   " }),
      bindings(),
      operatorAuth,
    );
    const beginMissing = await handlers.handleTokenContractBeginRotation(
      buildBeginRotationRequestBody({}),
      bindings(),
      operatorAuth,
    );
    const retireEmpty = await handlers.handleTokenContractRetire(
      buildRetireRequestBody({ ver: "" }),
      bindings(),
      operatorAuth,
    );
    const retireMissing = await handlers.handleTokenContractRetire(
      buildRetireRequestBody({}),
      bindings(),
      operatorAuth,
    );

    for (const response of [beginEmpty, beginMissing, retireEmpty, retireMissing]) {
      expect(response.status).toBe(400);
      expect(await response.json()).toEqual({ error: "invalid_ver" });
    }
    expect(await countAcceptedContracts()).toBe(1);
  });
});

describe("d1_config_reader_token_contracts_identity_path", () => {
  it("verifies accepted, refuses retired, and refuses unknown ver through createD1ConfigReader", async () => {
    const keypair = await generateTestKeypair();
    await seedActiveInstallation(keypair);

    const handlers = await loadTokenContractHandlers();
    const operatorAuth = createFakeOperatorAuth();
    expect(
      (
        await handlers.handleTokenContractBeginRotation(
          buildBeginRotationRequest(NEW_VER),
          bindings(),
          operatorAuth,
        )
      ).ok,
    ).toBe(true);

    const verifier = new EnrolledKeyVerifier();
    const acceptedCtx = buildD1VerifyContext();
    const acceptedToken = await mintToken(keypair, {
      ver: PRIOR_VER,
      jti: "c0000000-0000-4000-8000-000000000001",
    });
    const acceptedResult = await verifier.verify(acceptedToken, acceptedCtx);
    expect(acceptedResult.ok).toBe(true);

    expect(
      (
        await handlers.handleTokenContractRetire(
          buildRetireRequest(PRIOR_VER),
          bindings(),
          operatorAuth,
        )
      ).ok,
    ).toBe(true);

    const retiredCtx = buildD1VerifyContext();
    const retiredToken = await mintToken(keypair, {
      ver: PRIOR_VER,
      jti: "d0000000-0000-4000-8000-000000000001",
    });
    const retiredResult = await verifier.verify(retiredToken, retiredCtx);
    expect(retiredResult.ok).toBe(false);
    if (!retiredResult.ok) {
      expect(retiredResult.code).toBe("unauthenticated");
    }

    const unknownCtx = buildD1VerifyContext();
    const unknownToken = await mintToken(keypair, {
      ver: "never-accepted",
      jti: "e0000000-0000-4000-8000-000000000001",
    });
    const unknownResult = await verifier.verify(unknownToken, unknownCtx);
    expect(unknownResult.ok).toBe(false);
    if (!unknownResult.ok) {
      expect(unknownResult.code).toBe("unauthenticated");
    }
  });
});
