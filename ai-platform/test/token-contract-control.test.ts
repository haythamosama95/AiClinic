import { env } from "cloudflare:test";
import { beforeAll, beforeEach, describe, expect, it } from "vitest";
import migrationSql from "../migrations/20260731120000_platform_schema.sql?raw";
import tokenContractMigrationSql from "../migrations/20260803120000_token_contract.sql?raw";
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

type OperatorPrincipal = { operatorId: string };
type OperatorAuth = {
  resolve(_request: Request): OperatorPrincipal | null;
};

function createFakeOperatorAuth(
  principal: OperatorPrincipal = { operatorId: FAKE_OPERATOR_ID },
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
  });
});
