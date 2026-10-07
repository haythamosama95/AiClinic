import { spawn, spawnSync } from "node:child_process";
import { mkdir } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import test, { after, before } from "node:test";
import assert from "node:assert/strict";
import { createClient } from "@supabase/supabase-js";
import { MockAgent } from "undici";
import { unstable_startWorker as startWorker } from "wrangler";
import { CHANNEL_VERSIONS } from "vendor-contracts";
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

function readIssuerKeyByStatus(status) {
  const row = psqlQuery(
    `SELECT kid, public_key, not_before::text, not_after::text FROM ai_internal.issuer_key WHERE status = '${status}' LIMIT 1`,
  );
  if (!row) {
    return null;
  }
  const [kid, publicKey, notBefore, notAfter] = row.split("|");
  return {
    kid,
    public_key: publicKey,
    not_before: notBefore,
    not_after: notAfter,
  };
}

function readIssuerKeysForAbo(statuses) {
  const statusList = statuses.map((status) => `'${status}'`).join(", ");
  const rows = psqlQuery(
    `SELECT kid, public_key FROM ai_internal.issuer_key WHERE status IN (${statusList}) ORDER BY kid`,
  );
  if (!rows) {
    return [];
  }
  return rows.split("\n").filter(Boolean).map((row) => {
    const [kid, publicKey] = row.split("|");
    return { kid, public_key: publicKey };
  });
}

function encodeVendorAssertion(assertion) {
  return {
    alg: assertion.alg,
    authenticator_data: base64urlEncode(assertion.authenticatorData),
    client_data_json: base64urlEncode(assertion.clientDataJSON),
    signature: base64urlEncode(assertion.signature),
  };
}

async function mintAccessJwt(accessTeam) {
  const now = Math.floor(Date.now() / 1000);
  return accessTeam.mint({
    email: OPERATOR_EMAIL,
    aud: ACCESS_AUD,
    iat: now - 60,
    exp: now + 3600,
  });
}

function buildRegisterIssuerKeyOperation({
  kid,
  publicKey,
  notBefore,
  notAfter,
  accessJwt,
  issuedAt,
}) {
  const contractVersion = CHANNEL_VERSIONS.vendorEntrypoint;
  return {
    op: "registerIssuerKey",
    params: {
      contract_version: contractVersion,
      access_jwt: accessJwt,
      kid,
      public_key: publicKey,
      not_before: notBefore,
      not_after: notAfter,
    },
    actor_email: OPERATOR_EMAIL,
    issued_at: issuedAt,
    nonce: crypto.randomUUID(),
    contract_version: contractVersion,
  };
}

async function registerIssuerKey(stackRef, issuerKey) {
  const accessJwt = await mintAccessJwt(stackRef.accessTeam);
  const issuedAt = new Date().toISOString();
  const operation = buildRegisterIssuerKeyOperation({
    kid: issuerKey.kid,
    publicKey: issuerKey.public_key,
    notBefore: issuerKey.not_before,
    notAfter: issuerKey.not_after,
    accessJwt,
    issuedAt,
  });
  const assertion = encodeVendorAssertion(
    await stackRef.authenticator.assert({
      operation,
      rpId: WEBAUTHN_RP_ID,
      origin: WEBAUTHN_ORIGIN,
      up: true,
      uv: true,
    }),
  );
  const response = await fetch(`${HARNESS_URL}/register-issuer-key`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({
      contract_version: CHANNEL_VERSIONS.vendorEntrypoint,
      kid: issuerKey.kid,
      public_key: issuerKey.public_key,
      not_before: issuerKey.not_before,
      not_after: issuerKey.not_after,
      access_jwt: accessJwt,
      signer_credential_id: stackRef.credentialId,
      operation,
      assertion,
    }),
  });
  const envelope = await response.json();
  if (envelope.result !== "ok") {
    throw new Error(`registerIssuerKey failed: ${envelope.code || response.status}`);
  }
  return envelope;
}

function queryD1One(sql) {
  const stdout = runWrangler([
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
    sql,
  ]);
  const batches = JSON.parse(stdout);
  const results = batches[0]?.results ?? [];
  return results[0] ?? null;
}

function ownerSwitchSigningKid(kid) {
  psqlQuery(`SELECT auth_internal.switch_issuer_signing_kid('${kid}')`);
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
      AND sm.auth_user_id IN (SELECT id FROM auth.users WHERE email LIKE 'p5-2-%');
    DELETE FROM public.staff_members sm
    WHERE sm.auth_user_id IN (SELECT id FROM auth.users WHERE email LIKE 'p5-2-%');
    DELETE FROM auth.users WHERE email LIKE 'p5-2-%';
  `);

  const bootstrap = await signIn("admin", "admin");

  let orgResult = await rpc(bootstrap, "bootstrap_create_organization", {
    p_name: "H-FS P5.2 Org",
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
    p_name: "H-FS P5.2 Main",
    p_code: "P522",
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

  const administrator = await createStaff(
    "p5-2-admin",
    "P5AdminPass2!",
    "P5.2 Administrator",
    "administrator",
  );

  return {
    orgId,
    branchId,
    installationId: crypto.randomUUID(),
    administrator,
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

  const signingKey = readIssuerKeyByStatus("signing");
  if (!signingKey) {
    throw new Error("No signing issuer key row found");
  }
  const issuerKeys = [{ kid: signingKey.kid, public_key: signingKey.public_key }];

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

  const stackRef = {
    accessTeam,
    authenticator,
    credentialId,
    publicKeyCose,
    platformWorker,
    harnessWorker,
    paymob,
    abo,
    issuerKeys,
    signingKey,
    clinic,
    async stop() {
      await stopChild(paymob);
      await stopChild(abo);
      await harnessWorker.dispose();
      await platformWorker.dispose();
      await mockFetch.close();
    },
    async restartAbo(nextIssuerKeys = issuerKeys) {
      await stopChild(stackRef.abo);
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
      stackRef.abo = restarted;
      stackRef.issuerKeys = nextIssuerKeys;
      return restarted;
    },
  };

  await registerIssuerKey(stackRef, signingKey);
  await stackRef.restartAbo(issuerKeys);

  return stackRef;
}

function sqlLiteral(value) {
  return `'${String(value).replace(/'/g, "''")}'`;
}

function insertGrantAppliedEvent({
  orgId,
  installationId,
  bindingEpoch = 1,
  clinicSeq = 1,
}) {
  const eventId = `${installationId}:${clinicSeq}`;
  const at = new Date().toISOString();
  const endsAt = new Date(Date.now() + 30 * 24 * 60 * 60 * 1000).toISOString();
  const graceEndsAt = new Date(
    Date.now() + 37 * 24 * 60 * 60 * 1000,
  ).toISOString();
  const snapshot = {
    contract_version: 1,
    state: "active",
    reason: "none",
    suspended: false,
    term: {
      ref: "TERM-P52-01",
      plan_display_name: "P5.2 Test Plan",
      starts_at: at,
      ends_at: endsAt,
      grace_ends_at: graceEndsAt,
      allowance: 10000,
      used: 0,
      band: "ok",
      capabilities: [],
    },
    queued_count: 0,
    held_count: 0,
    coverage_through: endsAt,
    binding_epoch: bindingEpoch,
    clinic_seq: clinicSeq,
  };
  const snapshotJson = sqlLiteral(JSON.stringify(snapshot));
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
    `INSERT INTO coverage_event (
       event_id, org_id, installation_id, binding_epoch, clinic_seq, kind, snapshot, at
     ) VALUES (
       ${sqlLiteral(eventId)},
       ${sqlLiteral(orgId)},
       ${sqlLiteral(installationId)},
       ${bindingEpoch},
       ${clinicSeq},
       'grant_applied',
       ${snapshotJson},
       ${sqlLiteral(at)}
     )`,
  ]);
}

function readPlatformFeedCurrent() {
  const row = psqlQuery(`
    SELECT (value_json->'platformFeed'->>'current')::int
    FROM ai_internal.app_settings
    WHERE key = 'ai.contract_versions'
    LIMIT 1
  `);
  return Number(row);
}

function readCronJobSchedule() {
  return psqlQuery(`
    SELECT schedule
    FROM cron.job
    WHERE jobname = 'ai_coverage_feed_pull'
    LIMIT 1
  `);
}

function countHttpResponses() {
  const row = psqlQuery(`SELECT COUNT(*)::text FROM net._http_response`);
  return Number(row || "0");
}

function readFeedStatePendingRequestId() {
  return psqlQuery(`
    SELECT pending_request_id::text
    FROM ai_internal.feed_state
    WHERE singleton
    LIMIT 1
  `);
}

function readLastHttpResponse() {
  const row = psqlQuery(`
    SELECT row_to_json(t)::text
    FROM (
      SELECT status_code, headers, content
      FROM net._http_response
      ORDER BY created DESC
      LIMIT 1
    ) t
  `);
  if (!row) {
    return null;
  }
  const parsed = JSON.parse(row);
  const content =
    typeof parsed.content === "string"
      ? JSON.parse(parsed.content)
      : parsed.content;
  return {
    statusCode: Number(parsed.status_code),
    headers: parsed.headers,
    content,
  };
}

async function waitForPendingHttpResponse(pendingRequestId, { timeoutMs = 10_000 } = {}) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    const row = psqlQuery(`
      SELECT id::text
      FROM net._http_response
      WHERE id = ${pendingRequestId}
      LIMIT 1
    `);
    if (row) {
      return;
    }
    await new Promise((resolve) => setTimeout(resolve, 50));
  }
  throw new Error(
    `Timed out waiting for net._http_response id ${pendingRequestId}`,
  );
}

async function runTwoPhaseCoveragePull() {
  psqlQuery(`SELECT auth_internal.pull_coverage_feed()`);
  const pendingRequestId = readFeedStatePendingRequestId();
  if (pendingRequestId) {
    await waitForPendingHttpResponse(pendingRequestId);
  }
  psqlQuery(`SELECT auth_internal.pull_coverage_feed()`);
}

function readStatusRefreshRequestedAt(orgId) {
  return psqlQuery(`
    SELECT requested_at::text
    FROM ai_internal.status_refresh
    WHERE organization_id = '${orgId}'
    LIMIT 1
  `);
}

function countStatusRefreshRows(orgId) {
  const row = psqlQuery(`
    SELECT COUNT(*)::text
    FROM ai_internal.status_refresh
    WHERE organization_id = '${orgId}'
  `);
  return Number(row || "0");
}

function setStatusRefreshRequestedAtAgo(orgId, seconds) {
  psqlQuery(`
    UPDATE ai_internal.status_refresh
    SET requested_at = now() - interval '${seconds} seconds'
    WHERE organization_id = '${orgId}'
  `);
}

function clearStatusRefresh(orgId) {
  psqlQuery(`
    DELETE FROM ai_internal.status_refresh
    WHERE organization_id = '${orgId}'
  `);
}

function readHeaderValue(headers, name) {
  const target = name.toLowerCase();
  for (const [key, value] of Object.entries(headers ?? {})) {
    if (key.toLowerCase() === target) {
      return Array.isArray(value) ? value[0] : value;
    }
  }
  return undefined;
}

before(async () => {
  stack = await startStack();
});

after(async () => {
  await stack?.stop();
  stack = null;
});

test("E2E-P5.2-01 Grant applied on the platform reaches get_ai_status available and active", async () => {
  const { orgId, installationId, administrator } = stack.clinic;
  const sentFeedVersion = readPlatformFeedCurrent();
  assert.equal(sentFeedVersion, 1, "platformFeed.current should be 1");

  insertGrantAppliedEvent({ orgId, installationId });

  const cronSchedule = readCronJobSchedule();
  assert.equal(
    cronSchedule,
    "30 seconds",
    "ai_coverage_feed_pull cron schedule should be 30 seconds",
  );

  const responsesBefore = countHttpResponses();
  await runTwoPhaseCoveragePull();
  assert.ok(
    countHttpResponses() > responsesBefore,
    "pull_coverage_feed should issue a pg_net request",
  );

  const httpResponse = readLastHttpResponse();
  assert.ok(httpResponse, "expected a feed page response in net._http_response");
  assert.equal(httpResponse.statusCode, 200);
  assert.equal(
    readHeaderValue(httpResponse.headers, "aip-contract-version"),
    String(sentFeedVersion),
    "Aip-Contract-Version should echo the sent feed version",
  );
  assert.equal(
    httpResponse.content.contract_version,
    sentFeedVersion,
    "response contract_version should echo the sent feed version",
  );

  const status = await rpc(administrator, "get_ai_status", {
    p_contract_version: 1,
  });
  assert.equal(status.contract_version, 1);
  assert.equal(status.success, true);
  assert.equal(status.data.available, true);
  assert.equal(status.data.state, "active");
});

test("E2E-P5.2-02 Refresh starts a pull and a second call within 10 seconds is RATE_LIMITED", async () => {
  const { orgId, administrator } = stack.clinic;
  clearStatusRefresh(orgId);

  const responsesBefore = countHttpResponses();
  const first = await rpc(administrator, "request_ai_status_refresh", {
    p_contract_version: 1,
  });
  assert.equal(first.contract_version, 1);
  assert.equal(first.success, true);
  assert.ok(first.data?.requested_at, "accepted refresh should return requested_at");
  assert.ok(
    countHttpResponses() > responsesBefore ||
      readFeedStatePendingRequestId(),
    "accepted refresh should request a pull",
  );

  const requestedAfterFirst = readStatusRefreshRequestedAt(orgId);
  assert.ok(requestedAfterFirst, "status_refresh should store requested_at");

  const second = await rpc(administrator, "request_ai_status_refresh", {
    p_contract_version: 1,
  });
  assert.equal(second.contract_version, 1);
  assert.equal(second.success, false);
  assert.equal(second.error_code, "RATE_LIMITED");
  assert.equal(
    readStatusRefreshRequestedAt(orgId),
    requestedAfterFirst,
    "RATE_LIMITED should leave requested_at unchanged",
  );

  setStatusRefreshRequestedAtAgo(orgId, 10);
  const third = await rpc(administrator, "request_ai_status_refresh", {
    p_contract_version: 1,
  });
  assert.equal(third.contract_version, 1);
  assert.equal(third.success, true);
  assert.ok(third.data?.requested_at);
  assert.notEqual(
    third.data.requested_at,
    requestedAfterFirst,
    "accepted refresh after 10 seconds should update requested_at",
  );

  clearStatusRefresh(orgId);
  const responsesBeforeUnsupported = countHttpResponses();

  const missingVersion = await rpc(administrator, "request_ai_status_refresh", {});
  assert.equal(missingVersion.success, false);
  assert.equal(missingVersion.error_code, "CONTRACT_VERSION_UNSUPPORTED");
  assert.equal(countStatusRefreshRows(orgId), 0);
  assert.equal(
    countHttpResponses(),
    responsesBeforeUnsupported,
    "unsupported version should not request a pull",
  );

  const unsupportedVersion = await rpc(administrator, "request_ai_status_refresh", {
    p_contract_version: 2,
  });
  assert.equal(unsupportedVersion.success, false);
  assert.equal(unsupportedVersion.error_code, "CONTRACT_VERSION_UNSUPPORTED");
  assert.equal(countStatusRefreshRows(orgId), 0);
  assert.equal(
    countHttpResponses(),
    responsesBeforeUnsupported,
    "unsupported version should not request a pull",
  );

  const anonClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const noSessionMissing = await rpc(anonClient, "request_ai_status_refresh", {});
  assert.equal(noSessionMissing.success, false);
  assert.equal(noSessionMissing.error_code, "CONTRACT_VERSION_UNSUPPORTED");
  assert.equal(countStatusRefreshRows(orgId), 0);
  assert.equal(
    countHttpResponses(),
    responsesBeforeUnsupported,
    "no-session missing version should not request a pull",
  );

  const noSession = await rpc(anonClient, "request_ai_status_refresh", {
    p_contract_version: 2,
  });
  assert.equal(noSession.success, false);
  assert.equal(noSession.error_code, "CONTRACT_VERSION_UNSUPPORTED");
  assert.equal(countStatusRefreshRows(orgId), 0);
  assert.equal(
    countHttpResponses(),
    responsesBeforeUnsupported,
    "no-session unsupported version should not request a pull",
  );
});
