import { spawn, spawnSync } from "node:child_process";
import { mkdir } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import test, { after, before } from "node:test";
import assert from "node:assert/strict";
import { createClient } from "@supabase/supabase-js";
import { MockAgent } from "undici";
import { unstable_startWorker as startWorker } from "wrangler";
import {
  createAccessTeam,
  createSoftwareAuthenticator,
} from "vendor-contracts/testkit";

const REPO_ROOT = path.resolve(
  path.dirname(fileURLToPath(import.meta.url)),
  "../../..",
);
const FULLSTACK_ROOT = path.join(REPO_ROOT, "e2e/fullstack");
const PLATFORM_CONFIG = path.join(REPO_ROOT, "ai-platform/wrangler.toml");
const HARNESS_CONFIG = path.join(FULLSTACK_ROOT, "wrangler.toml");
const ABO_CONFIG = path.join(REPO_ROOT, "abo/wrangler.toml");
const PAYMOB_WORKER = path.join(REPO_ROOT, "abo/test/stubs/paymob/worker.ts");
const PLATFORM_PERSIST = path.join(FULLSTACK_ROOT, ".wrangler/platform");
const REGISTRY_DIR = path.join(FULLSTACK_ROOT, ".wrangler/registry");
const ABO_PERSIST = path.join(FULLSTACK_ROOT, ".wrangler/abo");

const SUPABASE_URL = process.env.SUPABASE_URL ?? "http://127.0.0.1:54321";
const SUPABASE_ANON_KEY =
  process.env.SUPABASE_ANON_KEY ??
  process.env.ANON_KEY ??
  "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0";
const DB_URL =
  process.env.DB_URL ??
  "postgresql://postgres:postgres@127.0.0.1:54322/postgres";
const PLATFORM_URL = process.env.PLATFORM_URL ?? "http://127.0.0.1:8787";
const ABO_URL = process.env.ABO_URL ?? "http://127.0.0.1:8788";
const HARNESS_URL = process.env.HARNESS_URL ?? "http://127.0.0.1:8790";
const PAYMOB_URL = process.env.PAYMOB_URL ?? "http://127.0.0.1:8789";

const ACCESS_TEAM_DOMAIN = "access.test";
const ACCESS_AUD = "vendor-access-aud";
const WEBAUTHN_RP_ID = "ops.vendor.test";
const WEBAUTHN_ORIGIN = "https://ops.vendor.test";
const OPERATOR_EMAIL = "operator@clinic.test";
const BILLING_HOST = "billing.vendor.test";

let stack = null;

function base64urlEncode(bytes) {
  return Buffer.from(bytes).toString("base64url");
}

function runWrangler(args, { cwd = REPO_ROOT, env = {} } = {}) {
  const result = spawnSync("npx", ["wrangler", ...args], {
    cwd,
    env: { ...process.env, ...env },
    encoding: "utf8",
  });
  if (result.status !== 0) {
    throw new Error(
      `wrangler ${args.join(" ")} failed (${result.status}): ${result.stderr || result.stdout}`,
    );
  }
  return result.stdout;
}

function psqlQuery(sql) {
  const result = spawnSync(
    "psql",
    [DB_URL, "-v", "ON_ERROR_STOP=1", "-t", "-A", "-c", sql],
    { encoding: "utf8" },
  );
  if (result.status !== 0) {
    throw new Error(`psql failed: ${result.stderr || result.stdout}`);
  }
  return result.stdout.trim();
}

async function waitForHttp(url, { timeoutMs = 120_000, accept = [200] } = {}) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    try {
      const response = await fetch(url);
      if (accept.includes(response.status)) {
        return response;
      }
    } catch {
      // worker still starting
    }
    await new Promise((resolve) => setTimeout(resolve, 500));
  }
  throw new Error(`Timed out waiting for ${url}`);
}

function spawnDevProcess(args, env = {}) {
  const child = spawn("npx", ["wrangler", ...args], {
    cwd: REPO_ROOT,
    env: { ...process.env, ...env },
    stdio: ["ignore", "pipe", "pipe"],
  });
  return child;
}

async function stopChild(child) {
  if (!child || child.killed) {
    return;
  }
  child.kill("SIGTERM");
  await new Promise((resolve) => {
    const timer = setTimeout(() => {
      child.kill("SIGKILL");
      resolve();
    }, 5_000);
    child.on("exit", () => {
      clearTimeout(timer);
      resolve();
    });
  });
}

async function applyPlatformMigrations() {
  runWrangler([
    "d1",
    "migrations",
    "apply",
    "ai-platform-development",
    "--local",
    "--env",
    "development",
    "--config",
    PLATFORM_CONFIG,
    "--persist-to",
    PLATFORM_PERSIST,
  ]);
}

async function applyAboMigrations() {
  runWrangler([
    "d1",
    "migrations",
    "apply",
    "abo-development",
    "--local",
    "--env",
    "development",
    "--config",
    ABO_CONFIG,
    "--persist-to",
    ABO_PERSIST,
  ]);
}

async function insertActiveOperatorCredential({
  credentialId,
  operatorEmail,
  publicKeyCose,
}) {
  const activatesAt = new Date(Date.now() - 60_000).toISOString();
  const sql = `INSERT INTO operator_credential
    (credential_id, operator_email, public_key_cose, alg, status, activates_at, approved_by, revoked_by)
    VALUES (
      '${credentialId}',
      '${operatorEmail}',
      '${publicKeyCose}',
      'EdDSA',
      'active',
      '${activatesAt}',
      NULL,
      NULL
    )`;
  runWrangler([
    "d1",
    "execute",
    "ai-platform-development",
    "--local",
    "--env",
    "development",
    "--config",
    PLATFORM_CONFIG,
    "--persist-to",
    PLATFORM_PERSIST,
    "--command",
    sql,
  ]);
}

function readSigningIssuerKeys() {
  const row = psqlQuery(
    "SELECT kid, public_key FROM ai_internal.issuer_key WHERE status = 'signing' LIMIT 1",
  );
  if (!row) {
    return [];
  }
  const [kid, publicKey] = row.split("|");
  return [{ kid, public_key: publicKey }];
}

async function rpc(client, fn, args = {}) {
  const { data, error } = await client.rpc(fn, args);
  if (error) {
    throw new Error(`${fn} failed: ${error.message}`);
  }
  return data;
}

async function signIn(email, password) {
  const client = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data, error } = await client.auth.signInWithPassword({
    email,
    password,
  });
  if (error) {
    throw new Error(`sign in ${email} failed: ${error.message}`);
  }
  return client;
}

async function createClinicUsers() {
  psqlQuery(`
    DELETE FROM public.staff_branch_assignments sba
    USING public.staff_members sm
    WHERE sba.staff_member_id = sm.id
      AND sm.auth_user_id IN (SELECT id FROM auth.users WHERE email LIKE 'p5-1-%');
    DELETE FROM public.staff_members sm
    WHERE sm.auth_user_id IN (SELECT id FROM auth.users WHERE email LIKE 'p5-1-%');
    DELETE FROM auth.users WHERE email LIKE 'p5-1-%';
  `);

  const bootstrap = await signIn("admin@admin", "admin");

  let orgResult = await rpc(bootstrap, "bootstrap_create_organization", {
    p_name: "H-FS Org A",
    p_settings_json: {},
    p_currency_code: "EGP",
    p_timezone: "UTC",
  });
  if (!orgResult?.success) {
    const existingOrg = psqlQuery(
      "SELECT id FROM public.organizations WHERE is_deleted = false ORDER BY created_at LIMIT 1",
    );
    orgResult = {
      success: true,
      data: { organization_id: existingOrg },
    };
  }
  const orgId = orgResult.data.organization_id;
  await bootstrap.auth.refreshSession();

  let branchResult = await rpc(bootstrap, "bootstrap_create_branch", {
    p_organization_id: orgId,
    p_name: "H-FS Main",
    p_code: "HFS1",
  });
  if (!branchResult?.success) {
    const existingBranch = psqlQuery(
      `SELECT id FROM public.branches WHERE organization_id = '${orgId}' AND is_deleted = false LIMIT 1`,
    );
    branchResult = {
      success: true,
      data: { branch_id: existingBranch },
    };
  }
  const branchId = branchResult.data.branch_id;
  await bootstrap.auth.refreshSession();

  const createStaff = async (username, password, fullName, role) => {
    const result = await rpc(bootstrap, "create_staff_account", {
      p_username: username,
      p_password: password,
      p_full_name: fullName,
      p_role: role,
      p_branch_ids: [branchId],
      p_primary_branch_id: branchId,
      p_phone: null,
    });
    if (!result?.success) {
      throw new Error(
        `create_staff_account(${username}) failed: ${result?.error_code ?? "unknown"}`,
      );
    }
    return signIn(username, password);
  };

  const member = await createStaff(
    "p5-1-member",
    "P5MemberPass1!",
    "P5.1 Org A Member",
    "doctor",
  );
  const administrator = await createStaff(
    "p5-1-admin",
    "P5AdminPass1!",
    "P5.1 Administrator",
    "administrator",
  );
  const doctor = await createStaff(
    "p5-1-doctor",
    "P5DoctorPass1!",
    "P5.1 Doctor",
    "doctor",
  );

  return {
    orgId,
    branchId,
    member,
    administrator,
    doctor,
  };
}

async function startStack() {
  await mkdir(PLATFORM_PERSIST, { recursive: true });
  await mkdir(REGISTRY_DIR, { recursive: true });
  await mkdir(ABO_PERSIST, { recursive: true });
  await applyPlatformMigrations();

  const accessTeam = await createAccessTeam({
    issuer: `https://${ACCESS_TEAM_DOMAIN}`,
  });
  const authenticator = await createSoftwareAuthenticator("EdDSA");
  const attestation = await authenticator.attest();
  const credentialId = crypto.randomUUID();
  const publicKeyCose = base64urlEncode(attestation.publicKey);

  const mockFetch = new MockAgent();
  mockFetch
    .get(`https://${ACCESS_TEAM_DOMAIN}`)
    .intercept({
      path: "/cdn-cgi/access/certs",
      method: "GET",
    })
    .reply(200, JSON.stringify({ keys: accessTeam.certs.keys }), {
      headers: { "content-type": "application/json" },
    })
    .persist();

  const platformWorker = await startWorker({
    config: PLATFORM_CONFIG,
    env: "development",
    dev: {
      server: { hostname: "127.0.0.1", port: 8787 },
      inspector: false,
      persist: PLATFORM_PERSIST,
      registry: REGISTRY_DIR,
      mockFetch,
    },
  });
  await platformWorker.ready;
  await insertActiveOperatorCredential({
    credentialId,
    operatorEmail: OPERATOR_EMAIL,
    publicKeyCose,
  });

  const harnessWorker = await startWorker({
    config: HARNESS_CONFIG,
    env: undefined,
    dev: {
      server: { hostname: "127.0.0.1", port: 8790 },
      inspector: false,
      registry: REGISTRY_DIR,
    },
  });
  await harnessWorker.ready;

  await waitForHttp(`${PLATFORM_URL}/health`);
  const harnessProbe = await fetch(`${HARNESS_URL}/register-issuer-key`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ contract_version: 1 }),
  });
  if (harnessProbe.status === 404) {
    throw new Error("Harness register-issuer-key route is unavailable");
  }

  const issuerKeys = readSigningIssuerKeys();

  const paymob = spawnDevProcess([
    "dev",
    PAYMOB_WORKER,
    "--port",
    "8789",
    "--ip",
    "127.0.0.1",
    "--inspector-port",
    "9230",
  ]);
  await waitForHttp(`${PAYMOB_URL}/`, { accept: [200, 404] });

  await applyAboMigrations();
  const abo = spawnDevProcess(
    [
      "dev",
      "--config",
      ABO_CONFIG,
      "--env",
      "development",
      "--port",
      "8788",
      "--ip",
      "127.0.0.1",
      "--inspector-port",
      "9231",
      "--persist-to",
      ABO_PERSIST,
    ],
    {
      PAYMOB_BASE_URL: PAYMOB_URL,
      ISSUER_KEYS: JSON.stringify(issuerKeys),
    },
  );
  await waitForHttp(`${ABO_URL}/v1/offers`, {
    accept: [401, 403, 400],
  });

  const clinic = await createClinicUsers();

  return {
    accessTeam,
    authenticator,
    credentialId,
    publicKeyCose,
    platformWorker,
    harnessWorker,
    paymob,
    abo,
    issuerKeys,
    clinic,
    async stop() {
      await stopChild(paymob);
      await stopChild(abo);
      await harnessWorker.dispose();
      await platformWorker.dispose();
      await mockFetch.close();
    },
    async restartAbo(nextIssuerKeys = issuerKeys) {
      await stopChild(abo);
      const restarted = spawnDevProcess(
        [
          "dev",
          "--config",
          ABO_CONFIG,
          "--env",
          "development",
          "--port",
          "8788",
          "--ip",
          "127.0.0.1",
          "--inspector-port",
          "9231",
          "--persist-to",
          ABO_PERSIST,
        ],
        {
          PAYMOB_BASE_URL: PAYMOB_URL,
          ISSUER_KEYS: JSON.stringify(nextIssuerKeys),
        },
      );
      await waitForHttp(`${ABO_URL}/v1/offers`, {
        accept: [401, 403, 400],
      });
      return restarted;
    },
  };
}

before(async () => {
  stack = await startStack();
});

after(async () => {
  await stack?.stop();
  stack = null;
});

async function assertRunnerWired() {
  const response = await fetch(`${HARNESS_URL}/register-issuer-key`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ contract_version: 1 }),
  }).catch(() => null);

  assert.notEqual(
    response,
    null,
    "H-FS runner is not wired: harness worker is not reachable",
  );
  assert.notEqual(
    response.status,
    404,
    "H-FS runner is not wired: register-issuer-key route is unavailable",
  );
}

test("E2E-P5.1-01 Org A member issue_ai_token(1) is accepted by the local platform and A's binding is created", async () => {
  await assertRunnerWired();

  const capabilities = await fetch(`${PLATFORM_URL}/v1/capabilities`, {
    headers: {
      authorization: "Bearer <ai-token-not-minted-yet>",
    },
  });

  assert.equal(
    capabilities.status,
    200,
    "runner does not yet accept that token",
  );
});

test("E2E-P5.1-02 Administrator issue_billing_token(1) is accepted by the local ABO and a doctor receives FORBIDDEN_ROLE", async () => {
  await assertRunnerWired();

  const offers = await fetch(`${ABO_URL}/v1/offers`, {
    headers: {
      authorization: "Bearer <billing-token-not-minted-yet>",
      host: BILLING_HOST,
    },
  });

  assert.equal(offers.status, 200, "ABO does not yet accept that token");

  const doctorBilling = await stack.clinic.doctor.rpc("issue_billing_token", {
    p_contract_version: 1,
  });

  assert.equal(
    doctorBilling?.success,
    false,
    "doctor FORBIDDEN_ROLE path is not wired",
  );
  assert.equal(doctorBilling?.error_code, "FORBIDDEN_ROLE");
});

test("E2E-P5.1-03 Billing token at the platform and AI token at the ABO are 401", async () => {
  await assertRunnerWired();

  assert.ok(
    stack.wrongAudienceTokens,
    "wrong-audience tokens are not minted yet",
  );
  const { billingToken, aiToken } = stack.wrongAudienceTokens;

  const billingAtPlatform = await fetch(`${PLATFORM_URL}/v1/capabilities`, {
    headers: {
      authorization: `Bearer ${billingToken}`,
    },
  });
  assert.equal(
    billingAtPlatform.status,
    401,
    "billing token at the platform is not refused yet",
  );

  const aiAtAbo = await fetch(`${ABO_URL}/v1/offers`, {
    headers: {
      authorization: `Bearer ${aiToken}`,
      host: BILLING_HOST,
    },
  });
  assert.equal(
    aiAtAbo.status,
    401,
    "AI token at the ABO is not refused yet",
  );
});

test("E2E-P5.1-06 New signing kid is accepted everywhere, old tokens stay valid, and the binding is unchanged", async () => {
  await assertRunnerWired();

  const epochBefore = runWrangler([
    "d1",
    "execute",
    "ai-platform-development",
    "--local",
    "--env",
    "development",
    "--config",
    PLATFORM_CONFIG,
    "--persist-to",
    PLATFORM_PERSIST,
    "--json",
    "--command",
    "SELECT epoch FROM tenant_binding LIMIT 1",
  ]);

  const oldAiToken = "<ai-token-before-switch>";
  const oldBillingToken = "<billing-token-before-switch>";

  const capabilitiesOld = await fetch(`${PLATFORM_URL}/v1/capabilities`, {
    headers: { authorization: `Bearer ${oldAiToken}` },
  });
  const offersOld = await fetch(`${ABO_URL}/v1/offers`, {
    headers: {
      authorization: `Bearer ${oldBillingToken}`,
      host: BILLING_HOST,
    },
  });

  const nextKidStatus = psqlQuery(
    "SELECT status FROM auth_internal.insert_issuer_kid()",
  );
  assert.equal(
    nextKidStatus,
    "next",
    "owner insert_issuer_kid did not create a next kid",
  );

  stack.abo = await stack.restartAbo(stack.issuerKeys);

  const register = await fetch(`${HARNESS_URL}/register-issuer-key`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({
      contract_version: 1,
      kid: "<next-kid-not-registered-yet>",
    }),
  });
  const registerBody = await register.json();
  assert.equal(
    registerBody.result,
    "ok",
    "registerIssuerKey for the next kid is not wired",
  );

  psqlQuery(
    "SELECT auth_internal.switch_issuer_signing_kid('<next-kid-not-switched-yet>')",
  );
  const signingKid = psqlQuery(
    "SELECT kid FROM ai_internal.issuer_key WHERE status = 'signing' LIMIT 1",
  );
  assert.equal(
    signingKid,
    "<next-kid-not-switched-yet>",
    "switch_issuer_signing_kid is not wired",
  );

  const capabilitiesNew = await fetch(`${PLATFORM_URL}/v1/capabilities`, {
    headers: { authorization: "Bearer <ai-token-after-switch>" },
  });
  const offersNew = await fetch(`${ABO_URL}/v1/offers`, {
    headers: {
      authorization: "Bearer <billing-token-after-switch>",
      host: BILLING_HOST,
    },
  });

  assert.equal(
    capabilitiesNew.status,
    200,
    "new AI token is not accepted on /v1/capabilities",
  );
  assert.equal(
    offersNew.status,
    200,
    "new billing token is not accepted on /v1/offers",
  );
  assert.equal(
    capabilitiesOld.status,
    200,
    "old AI token is not still accepted on /v1/capabilities",
  );
  assert.equal(
    offersOld.status,
    200,
    "old billing token is not still accepted on /v1/offers",
  );

  const epochAfter = runWrangler([
    "d1",
    "execute",
    "ai-platform-development",
    "--local",
    "--env",
    "development",
    "--config",
    PLATFORM_CONFIG,
    "--persist-to",
    PLATFORM_PERSIST,
    "--json",
    "--command",
    "SELECT epoch FROM tenant_binding LIMIT 1",
  ]);

  assert.equal(
    epochAfter,
    epochBefore,
    "tenant_binding.epoch changed after signing switch",
  );
});
