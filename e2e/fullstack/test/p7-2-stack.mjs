import { readFile } from "node:fs/promises";
import { spawn, spawnSync } from "node:child_process";
import { mkdir } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { createClient } from "@supabase/supabase-js";
import { MockAgent } from "undici";
import {
  closeLocalVirtualHostDispatchers,
  fetchLocalVirtualHost,
} from "./local-virtual-host.mjs";
import { unstable_startWorker as startWorker } from "wrangler";
import {
  CHANNEL_VERSIONS,
  canonicalize,
  grantIdPaid,
  sha256Hex,
  signCompactJws,
} from "vendor-contracts";
import {
  createAccessTeam,
  createSoftwareAuthenticator,
} from "vendor-contracts/testkit";
import {
  ABO_PERSIST,
  ABO_D1_SEED_PERSIST,
  HARNESS_PERSIST,
  PAYMOB_PERSIST,
  PLATFORM_PERSIST,
  REGISTRY_DIR,
  preparePlatformD1,
  prepareAboD1,
  execPlatformD1Sql,
  queryPlatformD1One as queryPlatformD1Row,
  runWranglerSync,
  wranglerLocalEnv,
  PLATFORM_BIND_HOST,
} from "./wrangler-persist.mjs";

// H-FS shared boot for P7.2: imported by p7-2-*.test.mjs

export { ABO_PERSIST, ABO_D1_SEED_PERSIST, HARNESS_PERSIST, PAYMOB_PERSIST, PLATFORM_PERSIST, REGISTRY_DIR };

export const REPO_ROOT = path.resolve(
  path.dirname(fileURLToPath(import.meta.url)),
  "../../..",
);
export const FULLSTACK_ROOT = path.join(REPO_ROOT, "e2e/fullstack");
export const PLATFORM_CONFIG = path.join(REPO_ROOT, "ai-platform/wrangler.toml");
export const HARNESS_CONFIG = path.join(FULLSTACK_ROOT, "wrangler.toml");
export const ABO_CONFIG = path.join(REPO_ROOT, "abo/wrangler.toml");
export const PAYMOB_WORKER = path.join(REPO_ROOT, "abo/test/stubs/paymob/worker.ts");

export const SUPABASE_URL = process.env.SUPABASE_URL ?? "http://127.0.0.1:54321";
export const SUPABASE_ANON_KEY =
  process.env.SUPABASE_ANON_KEY ??
  process.env.ANON_KEY ??
  "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0";
export const DB_URL =
  process.env.DB_URL ??
  "postgresql://postgres:postgres@127.0.0.1:54322/postgres";
export const PLATFORM_URL = process.env.PLATFORM_URL ?? "http://127.0.0.1:8787";
export const ABO_URL = process.env.ABO_URL ?? "http://127.0.0.1:8788";
export const HARNESS_URL = process.env.HARNESS_URL ?? "http://127.0.0.1:8790";
export const PAYMOB_URL = process.env.PAYMOB_URL ?? "http://127.0.0.1:8789";

export const ACCESS_TEAM_DOMAIN = "access.test";
export const ACCESS_AUD = "vendor-access-aud";
export const WEBAUTHN_RP_ID = "ops.vendor.test";
export const WEBAUTHN_ORIGIN = "https://ops.vendor.test";
export const OPERATOR_EMAIL = "operator@clinic.test";
export const BILLING_HOST = "billing.vendor.test";
export const OPS_HOST = "ops.vendor.test";
export const PAYMOB_HMAC_SECRET = "paymob-hmac-unconfigured";
export const ABO_GRANT_KEY = {
  kid: "abo-grant-test",
  pkcs8:
    "MC4CAQAwBQYDK2VwBCIEINhOOYX0jTZi98KVn0iV7iqQ4v29ImVy_tKTMfFESzxK",
  public_key: "u5sqB8SGC8m0kpu1R4R-CbF41y6-7pZuaBT_Iecbuhw",
};
export const PLATFORM_PUBLIC_KEYS = [
  {
    kid: "platform-prev-test",
    public_key: "wTfd0sQ8ylrdkYt5C0bYzxiZGlr-XtEqlbzwgq0-WXQ",
  },
  {
    kid: "platform-test",
    public_key: "GNzxZ6Gymues_aeJArGyb3wDESTOUJeqhuZBfTByni0",
  },
];
export const OFFER_ID = "01JHARNESSOFFERPUBLISH001";
export const OFFER_VERSION = 2;
export const TERMS_VERSION = 1;
export const PLAN_ID = "plan-pro";
export const PLAN_VERSION = 1;
export const CAPABILITY_ID = "clinic.visit_summary";
export const ALLOWANCE_CREDITS = 100;
export const PAYMOB_HMAC_FIELDS = [
  "amount_cents",
  "created_at",
  "currency",
  "error_occured",
  "has_parent_transaction",
  "id",
  "integration_id",
  "is_3d_secure",
  "is_auth",
  "is_capture",
  "is_refunded",
  "is_standalone_payment",
  "is_voided",
  "order.id",
  "owner",
  "pending",
  "source_data.pan",
  "source_data.sub_type",
  "source_data.type",
  "success",
];

const platformLogBuffer = [];

function captureLogChunk(chunk) {
  const text = typeof chunk === "string" ? chunk : chunk.toString();
  platformLogBuffer.push(text);
}

const originalStdoutWrite = process.stdout.write.bind(process.stdout);
process.stdout.write = (chunk, ...args) => {
  captureLogChunk(chunk);
  return originalStdoutWrite(chunk, ...args);
};

const originalStderrWrite = process.stderr.write.bind(process.stderr);
process.stderr.write = (chunk, ...args) => {
  captureLogChunk(chunk);
  return originalStderrWrite(chunk, ...args);
};

export function getPlatformLogBuffer() {
  return platformLogBuffer;
}

export function clearPlatformLogBuffer() {
  platformLogBuffer.length = 0;
}

export function parseSendEmailCaptures(logText = platformLogBuffer.join("")) {
  const captures = [];
  const linePattern =
    /send_email binding called with MessageBuilder[\s\S]*?([^\s'"]+\.txt)/g;
  for (const match of logText.matchAll(linePattern)) {
    captures.push({ textFilePath: match[1] });
  }
  return captures;
}

export async function readSendEmailTextFile(filePath) {
  return await readFile(filePath, "utf8");
}

export async function readLatestSendEmailText() {
  const captures = parseSendEmailCaptures();
  if (captures.length === 0) {
    return null;
  }
  const latest = captures[captures.length - 1];
  return await readSendEmailTextFile(latest.textFilePath);
}

function base64urlEncode(bytes) {
  return Buffer.from(bytes).toString("base64url");
}

export function runWrangler(args, { cwd = REPO_ROOT, env = {} } = {}) {
  return runWranglerSync(args, { cwd, env });
}

export function psqlQuery(sql) {
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

export async function waitForHttp(
  url,
  {
    timeoutMs = 120_000,
    accept = [200],
    headers,
    authorityHost,
    targetDescription = "local Wrangler listener",
    stable404Attempts = 3,
    child,
    childLabel = "worker",
  } = {},
) {
  const deadline = Date.now() + timeoutMs;
  let lastStatus = "none";
  let lastBody = "none";
  let consecutive404s = 0;
  while (Date.now() < deadline) {
    if (child?.spawnError) {
      throw new Error(
        `Could not start ${childLabel} while waiting for ${url}: ${child.spawnError.message}${formatChildOutput(child)}`,
      );
    }
    if (child?.exitResult) {
      const { code, signal } = child.exitResult;
      throw new Error(
        `${childLabel} exited before ${url} became ready (code=${code}, signal=${signal ?? "none"})${formatChildOutput(child)}`,
      );
    }
    try {
      const response = authorityHost
        ? await fetchLocalVirtualHost(url, authorityHost, { headers })
        : await fetch(url, { headers });
      lastStatus = String(response.status);
      if (accept.includes(response.status)) {
        return response;
      }
      lastBody = (await response.text()).slice(0, 1_200) || "[empty response body]";
      consecutive404s = response.status === 404 ? consecutive404s + 1 : 0;
      if (consecutive404s >= stable404Attempts) {
        throw new Error(
          `${childLabel} returned stable HTTP 404 while waiting for ${url}; ` +
            `authority=${authorityHost ?? new URL(url).host}; target=${targetDescription}; ` +
            `last body=${lastBody}${formatChildOutput(child)}`,
        );
      }
    } catch (error) {
      if (error.message?.includes("returned stable HTTP 404")) throw error;
      lastBody = `${error.code ?? error.cause?.code ?? error.name ?? "Error"}: request failed`;
    }
    await new Promise((resolve) => setTimeout(resolve, 500));
  }
  throw new Error(
    `Timed out waiting for ${url}; authority=${authorityHost ?? new URL(url).host}; ` +
      `target=${targetDescription}; last status=${lastStatus}; ` +
      `last body=${lastBody}${formatChildOutput(child)}`,
  );
}

function formatChildOutput(child) {
  const output = child.startupOutput?.trim();
  return output ? `\n${child.startupLabel ?? "Worker"} output:\n${output}` : "";
}

function spawnDevProcess(args, env = {}) {
  const wranglerCli = path.join(
    FULLSTACK_ROOT,
    "node_modules/wrangler/bin/wrangler.js",
  );
  const child = spawn(process.execPath, [wranglerCli, ...args], {
    cwd: REPO_ROOT,
    env: wranglerLocalEnv(env),
    detached: process.platform !== "win32",
    stdio: ["ignore", "pipe", "pipe"],
  });
  child.startupLabel = args.includes(PAYMOB_WORKER) ? "Paymob worker" : "ABO worker";
  child.startupOutput = "";
  child.spawnError = null;
  child.exitResult = null;
  const captureChildOutput = (chunk) => {
    const text = chunk.toString();
    captureLogChunk(text);
    child.startupOutput = `${child.startupOutput}${text}`.slice(-12_000);
  };
  child.stdout.on("data", captureChildOutput);
  child.stderr.on("data", captureChildOutput);
  child.once("error", (error) => {
    child.spawnError = error;
  });
  child.once("exit", (code, signal) => {
    child.exitResult = { code, signal };
  });
  return child;
}

async function stopChild(child) {
  if (!child) return;

  if (process.platform === "win32" || !child.pid) {
    if (child.exitCode !== null || child.signalCode !== null) return;
    child.kill("SIGTERM");
    await new Promise((resolve) => {
      const timer = setTimeout(() => {
        child.kill("SIGKILL");
        resolve();
      }, 5_000);
      child.once("exit", () => {
        clearTimeout(timer);
        resolve();
      });
    });
    return;
  }

  const signalGroup = (signal) => {
    try {
      process.kill(-child.pid, signal);
      return true;
    } catch (error) {
      if (error.code === "ESRCH") return false;
      throw error;
    }
  };
  const groupExists = () => {
    try {
      process.kill(-child.pid, 0);
      return true;
    } catch (error) {
      if (error.code === "ESRCH") return false;
      throw error;
    }
  };
  const waitForGroupExit = async (timeoutMs) => {
    const deadline = Date.now() + timeoutMs;
    while (groupExists() && Date.now() < deadline) {
      await new Promise((resolve) => setTimeout(resolve, 100));
    }
    return !groupExists();
  };

  if (!signalGroup("SIGTERM")) return;
  if (await waitForGroupExit(5_000)) return;
  signalGroup("SIGKILL");
  if (!(await waitForGroupExit(1_000))) {
    throw new Error(`Process group ${child.pid} did not exit after SIGKILL`);
  }
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
  execPlatformD1Sql(sql);
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

export function encodeVendorAssertion(assertion) {
  return {
    alg: assertion.alg,
    authenticator_data: base64urlEncode(assertion.authenticatorData),
    client_data_json: base64urlEncode(assertion.clientDataJSON),
    signature: base64urlEncode(assertion.signature),
  };
}

export async function mintAccessJwt(accessTeam) {
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

export function queryPlatformD1One(sql) {
  return queryPlatformD1Row(sql);
}

export function runPlatformD1Command(sql) {
  execPlatformD1Sql(sql);
}

export function queryAboD1One(sql) {
  const stdout = runWrangler([
    "d1",
    "execute",
    "abo-development",
    "--local",
    "--env",
    "development",
    "--config",
    ABO_CONFIG,
    "--persist-to",
    ABO_PERSIST,
    "--json",
    "--command",
    sql,
  ]);
  const batches = JSON.parse(stdout);
  const results = batches[0]?.results ?? [];
  return results[0] ?? null;
}

export function runAboD1Command(sql) {
  runWrangler([
    "d1",
    "execute",
    "abo-development",
    "--local",
    "--env",
    "development",
    "--config",
    ABO_CONFIG,
    "--persist-to",
    ABO_PERSIST,
    "--command",
    sql,
  ]);
}

export function countAboTable(table) {
  const row = queryAboD1One(`SELECT COUNT(*) AS n FROM ${table}`);
  return Number(row?.n ?? 0);
}

export function countAboWork() {
  return countAboTable("work");
}

export async function rpc(client, fn, args = {}) {
  const { data, error } = await client.rpc(fn, args);
  if (error) {
    throw new Error(`${fn} failed: ${error.message}`);
  }
  return data;
}

export async function signIn(email, password) {
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

export function sqlLiteral(value) {
  return `'${String(value).replace(/'/g, "''")}'`;
}

function findTestOrganizationId(orgName) {
  return psqlQuery(
    `SELECT id FROM public.organizations
     WHERE name = ${sqlLiteral(orgName)} AND is_deleted = false
     LIMIT 1`,
  );
}

function insertTestOrganization(orgName) {
  const adminUserId = psqlQuery(
    "SELECT id FROM auth.users WHERE email = 'admin' LIMIT 1",
  );
  if (!adminUserId) {
    throw new Error("Cannot seed a test organization without the bootstrap admin user");
  }
  return psqlQuery(
    `WITH inserted AS (
       INSERT INTO public.organizations (
         name, currency_code, timezone, settings_json, created_by, updated_by
       ) VALUES (
         ${sqlLiteral(orgName)}, 'EGP', 'UTC', '{}'::jsonb,
         ${sqlLiteral(adminUserId)}::uuid, ${sqlLiteral(adminUserId)}::uuid
       ) RETURNING id
     )
     SELECT id FROM inserted`,
  );
}

function findTestBranchId(orgId, branchCode) {
  return psqlQuery(
    `SELECT id FROM public.branches
     WHERE organization_id = ${sqlLiteral(orgId)}::uuid
       AND code = ${sqlLiteral(branchCode)}
       AND is_deleted = false
     LIMIT 1`,
  );
}

function seedStaffMembership(orgId, username, role) {
  psqlQuery(`
    INSERT INTO ai_internal.membership (user_id, organization_id, role)
    SELECT u.id, '${orgId}', '${role}'::public.staff_role
    FROM auth.users u
    WHERE u.email = '${username}'
    ON CONFLICT (user_id, organization_id) DO NOTHING
  `);
}

async function createOrgClinic({ prefix, orgName, branchCode, branchName }) {
  psqlQuery(`
    DELETE FROM ai_internal.user_active_organization uao
    USING auth.users u
    WHERE uao.user_id = u.id
      AND u.email LIKE '${prefix}-%';
    DELETE FROM ai_internal.membership m
    USING auth.users u
    WHERE m.user_id = u.id
      AND u.email LIKE '${prefix}-%';
    DELETE FROM public.staff_branch_assignments sba
    USING public.staff_members sm
    WHERE sba.staff_member_id = sm.id
      AND sm.auth_user_id IN (SELECT id FROM auth.users WHERE email LIKE '${prefix}-%');
    DELETE FROM public.staff_members sm
    WHERE sm.auth_user_id IN (SELECT id FROM auth.users WHERE email LIKE '${prefix}-%');
    DELETE FROM auth.users WHERE email LIKE '${prefix}-%';
  `);

  const bootstrap = await signIn("admin", "admin");

  let orgId = findTestOrganizationId(orgName);
  if (!orgId) {
    const orgResult = await rpc(bootstrap, "bootstrap_create_organization", {
      p_name: orgName,
      p_settings_json: {},
      p_currency_code: "EGP",
      p_timezone: "UTC",
    });
    if (orgResult?.success) {
      orgId = orgResult.data.organization_id;
    } else if (orgResult?.error_code === "ORG_ALREADY_EXISTS") {
      // Bootstrap is intentionally single-organization per installation. The
      // cross-tenant E2E fixture needs a second organization, so seed it through
      // the privileged local test database connection.
      orgId = insertTestOrganization(orgName);
    } else {
      throw new Error(
        `bootstrap_create_organization failed for ${prefix}: ${orgResult?.error_code ?? "unknown"} ${orgResult?.error_message ?? ""}`,
      );
    }
  }

  let branchId = findTestBranchId(orgId, branchCode);
  if (!branchId) {
    const branchResult = await rpc(bootstrap, "bootstrap_create_branch", {
      p_organization_id: orgId,
      p_name: branchName,
      p_code: branchCode,
    });
    if (!branchResult?.success) {
      throw new Error(
        `bootstrap_create_branch failed for ${prefix}: ${branchResult?.error_code ?? "unknown"} ${branchResult?.error_message ?? ""}`,
      );
    }
    branchId = branchResult.data.branch_id;
  }

  const activeOrganization = await rpc(
    bootstrap,
    "set_active_organization",
    { p_organization_id: orgId },
  );
  if (!activeOrganization?.success) {
    throw new Error(
      `set_active_organization failed for ${prefix}: ${activeOrganization?.error_code ?? "unknown"}`,
    );
  }
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
    seedStaffMembership(orgId, username, role);
    return signIn(username, password);
  };

  const administrator = await createStaff(
    `${prefix}-admin`,
    "P72AdminPass!",
    `${orgName} Administrator`,
    "administrator",
  );
  const staff = await createStaff(
    `${prefix}-staff`,
    "P72StaffPass!",
    `${orgName} Staff`,
    "doctor",
  );

  return {
    orgId,
    branchId,
    installationId: crypto.randomUUID(),
    administrator,
    staff,
  };
}

export async function createTwoOrgClinics() {
  const orgA = await createOrgClinic({
    prefix: "p7-2-a",
    orgName: "H-FS P7.2 Org A",
    branchCode: "P72A",
    branchName: "H-FS P7.2 Org A Main",
  });
  const orgB = await createOrgClinic({
    prefix: "p7-2-b",
    orgName: "H-FS P7.2 Org B",
    branchCode: "P72B",
    branchName: "H-FS P7.2 Org B Main",
  });
  return { orgA, orgB };
}

function spawnAboProcess(issuerKeys) {
  return spawnDevProcess(
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
      "--var",
      `PAYMOB_BASE_URL:${PAYMOB_URL}`,
      "--var",
      `ISSUER_KEYS:${JSON.stringify(issuerKeys)}`,
      "--var",
      `ABO_GRANT_KEY:${JSON.stringify(ABO_GRANT_KEY)}`,
      "--var",
      `PLATFORM_PUBLIC_KEYS:${JSON.stringify(PLATFORM_PUBLIC_KEYS)}`,
      "--test-scheduled",
    ],
  );
}

export async function startStack() {
  const startupCleanups = [];
  const cleanupStartup = async () => {
    const errors = [];
    for (const cleanup of startupCleanups.reverse()) {
      try {
        await cleanup();
      } catch (error) {
        errors.push(error.message);
      }
    }
    await closeLocalVirtualHostDispatchers();
    if (errors.length) throw new Error(errors.join("; "));
  };
  try {
  clearPlatformLogBuffer();
  await mkdir(PLATFORM_PERSIST, { recursive: true });
  await mkdir(HARNESS_PERSIST, { recursive: true });
  await mkdir(REGISTRY_DIR, { recursive: true });
  await mkdir(ABO_PERSIST, { recursive: true });
  await mkdir(ABO_D1_SEED_PERSIST, { recursive: true });
  await mkdir(PAYMOB_PERSIST, { recursive: true });
  await preparePlatformD1({ platformConfig: PLATFORM_CONFIG });

  const accessTeam = await createAccessTeam({
    issuer: `https://${ACCESS_TEAM_DOMAIN}`,
  });
  const authenticator = await createSoftwareAuthenticator("EdDSA");
  const attestation = await authenticator.attest();
  const credentialId = crypto.randomUUID();
  const publicKeyCose = base64urlEncode(attestation.publicKey);

  const mockFetch = new MockAgent();
  startupCleanups.push(() => mockFetch.close());
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

  await insertActiveOperatorCredential({
    credentialId,
    operatorEmail: OPERATOR_EMAIL,
    publicKeyCose,
  });

  const platformWorker = await startWorker({
    config: PLATFORM_CONFIG,
    env: "development",
    dev: {
      server: { hostname: PLATFORM_BIND_HOST, port: 8787 },
      inspector: false,
      persist: PLATFORM_PERSIST,
      registry: REGISTRY_DIR,
      mockFetch,
    },
  });
  startupCleanups.push(() => platformWorker.dispose());
  await platformWorker.ready;

  const harnessWorker = await startWorker({
    config: HARNESS_CONFIG,
    env: undefined,
    dev: {
      server: { hostname: "127.0.0.1", port: 8790 },
      inspector: false,
      persist: HARNESS_PERSIST,
      registry: REGISTRY_DIR,
    },
  });
  startupCleanups.push(() => harnessWorker.dispose());
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
    "--persist-to",
    PAYMOB_PERSIST,
    "--ip",
    "127.0.0.1",
    "--inspector-port",
    "9230",
  ]);
  startupCleanups.push(() => stopChild(paymob));
  await waitForHttp(`${PAYMOB_URL}/`, {
    accept: [200, 404],
    child: paymob,
    childLabel: "Paymob worker",
  });

  await prepareAboD1({ aboConfig: ABO_CONFIG });
  const abo = spawnAboProcess(issuerKeys);
  startupCleanups.push(() => stopChild(abo));
  await waitForHttp(`${ABO_URL}/v1/offers`, {
    accept: [401, 403, 400],
    authorityHost: BILLING_HOST,
    targetDescription: `127.0.0.1:8788 (${ABO_CONFIG})`,
    child: abo,
    childLabel: "ABO worker",
  });

  const clinics = await createTwoOrgClinics();

  let stackStopped = false;
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
    clinics,
    async stop() {
      if (stackStopped) return;
      await stopChild(paymob);
      await stopChild(stackRef.abo);
      await harnessWorker.dispose();
      await platformWorker.dispose();
      await mockFetch.close();
      await closeLocalVirtualHostDispatchers();
      stackStopped = true;
    },
    async restartAbo(nextIssuerKeys = issuerKeys) {
      if (stackStopped) {
        throw new Error("Cannot restart ABO after the P7.2 stack has stopped");
      }
      await stopChild(stackRef.abo);
      const restarted = spawnAboProcess(nextIssuerKeys);
      startupCleanups.push(() => stopChild(restarted));
      try {
        await waitForHttp(`${ABO_URL}/v1/offers`, {
          accept: [401, 403, 400],
          authorityHost: BILLING_HOST,
          targetDescription: `127.0.0.1:8788 (${ABO_CONFIG})`,
          child: restarted,
          childLabel: "restarted ABO worker",
        });
      } catch (error) {
        await stopChild(restarted);
        throw error;
      }
      stackRef.abo = restarted;
      stackRef.issuerKeys = nextIssuerKeys;
      return restarted;
    },
  };

  await registerIssuerKey(stackRef, signingKey);
  await stackRef.restartAbo(issuerKeys);

  return stackRef;
  } catch (error) {
    try {
      await cleanupStartup();
    } catch (cleanupError) {
      console.error(`[P7.2 startup rollback] ${cleanupError.message}`);
    }
    throw error;
  }
}

export async function billingFetch(pathname, init = {}) {
  const headers = new Headers(init.headers ?? {});
  if (!headers.has("Abo-Contract-Version")) {
    headers.set("Abo-Contract-Version", "1");
  }
  return fetchLocalVirtualHost(`${ABO_URL}${pathname}`, BILLING_HOST, { ...init, headers });
}

export async function platformFetch(pathname, init = {}) {
  const headers = new Headers(init.headers ?? {});
  if (!headers.has("Aip-Contract-Version")) {
    headers.set("Aip-Contract-Version", "1");
  }
  return fetch(`${PLATFORM_URL}${pathname}`, { ...init, headers });
}

export async function triggerAboScheduled(cron = "0 6 * * *") {
  const response = await fetch(
    `${ABO_URL}/__scheduled?cron=${encodeURIComponent(cron)}`,
  );
  return response;
}

export function readClinicAiCoverage(orgId) {
  const row = psqlQuery(`
    SELECT row_to_json(t)::text
    FROM (
      SELECT
        binding_epoch::text,
        clinic_seq::text,
        state,
        plan_display_name,
        term_ref
      FROM ai_internal.clinic_ai_coverage
      WHERE organization_id = '${orgId}'
      LIMIT 1
    ) t
  `);
  return row ? JSON.parse(row) : null;
}

export function readStatusRefreshRequestedAt(orgId) {
  return psqlQuery(`
    SELECT requested_at::text
    FROM ai_internal.status_refresh
    WHERE organization_id = '${orgId}'
    LIMIT 1
  `);
}

export function issueFeedToken() {
  return psqlQuery("SELECT auth_internal.issue_feed_token()");
}

export function countAboFindings(kind) {
  const row = queryAboD1One(
    `SELECT COUNT(*) AS n FROM finding WHERE kind = ${sqlLiteral(kind)}`,
  );
  return Number(row?.n ?? 0);
}

export function seedAboOffers() {
  runAboD1Command(`
    INSERT OR IGNORE INTO terms_version (
      terms_version, locale, text_r2_key, text_sha256, published_by, contract_version
    ) VALUES (
      ${TERMS_VERSION}, 'en', 'terms/en/1.txt',
      'dbb6d8870e5636c8da062789e912326c66eacd68838980a81bf6ad9484677753',
      'fixture', 1
    );
    INSERT OR IGNORE INTO offer (offer_id, code, contract_version)
    VALUES ('${OFFER_ID}', 'harness-pro-monthly', 1);
    INSERT OR REPLACE INTO offer_version (
      offer_id, version, plan_id, plan_version, term_unit, term_count,
      price_minor, currency, allowance_credits, grace_days, grace_cap_rule,
      copy, terms_version, published_by, assertion_sha256, contract_version
    ) VALUES (
      '${OFFER_ID}', ${OFFER_VERSION}, '${PLAN_ID}', ${PLAN_VERSION},
      'month', 1, 1000, 'EGP', ${ALLOWANCE_CREDITS}, 7, 'proportional',
      '{"en":{"name":"Clinic Pro Monthly","summary":"Monthly clinic subscription"}}',
      ${TERMS_VERSION}, 'fixture', 'fixture-assertion-v2', 1
    );
    INSERT OR IGNORE INTO offer_event (
      offer_id, kind, version, actor, at, contract_version
    ) VALUES (
      '${OFFER_ID}', 'published', ${OFFER_VERSION}, 'fixture',
      '2026-02-01T00:00:00.000Z', 1
    );
  `);
}

export function ensurePlatformGrantPrerequisites(orgId, installationId) {
  const createdAt = new Date().toISOString();
  runPlatformD1Command(`
    INSERT OR IGNORE INTO installation (
      installation_id, org_id, status, display_name, region, enrolled_at
    ) VALUES (
      ${sqlLiteral(installationId)},
      ${sqlLiteral(orgId)},
      'active', '', '', ${sqlLiteral(createdAt)}
    );
    INSERT OR REPLACE INTO tenant_binding (
      org_id, installation_id, epoch, status, retired_at, reason, created_at
    ) VALUES (
      ${sqlLiteral(orgId)},
      ${sqlLiteral(installationId)},
      1, 'active', NULL, NULL, ${sqlLiteral(createdAt)}
    );
    INSERT OR REPLACE INTO service_key (
      kid, service, public_key, status, not_before, not_after,
      registered_by, assertion_sha256
    ) VALUES (
      ${sqlLiteral(ABO_GRANT_KEY.kid)},
      'abo',
      ${sqlLiteral(ABO_GRANT_KEY.public_key)},
      'active',
      '2020-01-01T00:00:00.000Z',
      '2099-01-01T00:00:00.000Z',
      ${sqlLiteral(OPERATOR_EMAIL)},
      'harness'
    );
    INSERT OR IGNORE INTO plan_version (
      plan_id, version, display_name, capabilities, max_cost_class,
      concurrency_limit, max_allowance_per_month, status, published_by,
      assertion_sha256
    ) VALUES (
      '${PLAN_ID}', ${PLAN_VERSION}, 'Clinic Pro',
      ${sqlLiteral(JSON.stringify([CAPABILITY_ID]))},
      '2', 4, ${ALLOWANCE_CREDITS}, 'published',
      ${sqlLiteral(OPERATOR_EMAIL)}, 'harness'
    );
  `);
}

export async function ensurePlatformActiveCoverage(
  stackRef,
  orgId,
  installationId,
) {
  const paymentRef = crypto.randomUUID().replace(/-/g, "");
  const privateKey = await crypto.subtle.importKey(
    "pkcs8",
    Buffer.from(ABO_GRANT_KEY.pkcs8, "base64url"),
    { name: "Ed25519" },
    false,
    ["sign"],
  );
  const envelope = {
    contract_version: CHANNEL_VERSIONS.vendorEntrypoint,
    grant_id: await grantIdPaid(paymentRef),
    org_id: orgId,
    kind: "term",
    placement: "queue",
    source: { kind: "paid", ref: paymentRef },
    plan: { plan_id: PLAN_ID, plan_version: PLAN_VERSION },
    duration: { unit: "month", count: 1 },
    allowance_credits: ALLOWANCE_CREDITS,
    grace: { days: 7, cap_rule: "proportional" },
    paid_at: new Date().toISOString(),
    evidence: {
      content_sha256: await sha256Hex(new TextEncoder().encode(paymentRef)),
      approvals: [{ credential_id: stackRef.credentialId, assertion: "stub" }],
    },
  };
  const signature = await signCompactJws({
    payload: canonicalize(envelope),
    privateKey,
    kid: ABO_GRANT_KEY.kid,
  });
  const response = await fetch(`${HARNESS_URL}/vendor-call`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({
      method: "grant",
      args: {
        contract_version: CHANNEL_VERSIONS.vendorEntrypoint,
        abo_kid: ABO_GRANT_KEY.kid,
        abo_signature: signature,
        envelope_b64: Buffer.from(canonicalize(envelope)).toString("base64"),
      },
    }),
  });
  const result = await response.json();
  if (response.status !== 200 || result.result !== "applied") {
    throw new Error(`Could not seed Org AI coverage: ${JSON.stringify(result)}`);
  }
}

export async function putBillingContact(billingToken) {
  const response = await billingFetch("/v1/billing-contact", {
    method: "PUT",
    headers: {
      authorization: `Bearer ${billingToken}`,
      "content-type": "application/json",
    },
    body: JSON.stringify({
      client_request_id: `p72-contact-${crypto.randomUUID()}`,
      name: "P7.2 Administrator",
      email: "p7-2-admin@clinic.test",
      phone: "+201001234567",
    }),
  });
  if (response.status !== 200) {
    throw new Error(`billing contact failed: ${response.status}`);
  }
}

export async function openCheckout(billingToken, clientRequestId = null) {
  const response = await billingFetch("/v1/checkouts", {
    method: "POST",
    headers: {
      authorization: `Bearer ${billingToken}`,
      "content-type": "application/json",
    },
    body: JSON.stringify({
      client_request_id: clientRequestId ?? `p72-checkout-${crypto.randomUUID()}`,
      offer_id: OFFER_ID,
      offer_version: OFFER_VERSION,
      terms_version: TERMS_VERSION,
    }),
  });
  if (response.status !== 201) {
    throw new Error(`checkout create failed: ${response.status}`);
  }
  const body = await response.json();
  return {
    checkoutId: String(body.checkout_id),
    reference: String(body.reference),
  };
}

function paymobFieldValue(obj, field) {
  if (field === "order.id") {
    return String(obj.order?.id ?? "");
  }
  if (field.startsWith("source_data.")) {
    const key = field.slice("source_data.".length);
    return String(obj.source_data?.[key] ?? "");
  }
  const value = obj[field];
  if (typeof value === "boolean") {
    return value ? "true" : "false";
  }
  return String(value ?? "");
}

export async function signPaymobObj(obj, secret = PAYMOB_HMAC_SECRET) {
  const concatenated = PAYMOB_HMAC_FIELDS.map((field) =>
    paymobFieldValue(obj, field),
  ).join("");
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-512" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign(
    "HMAC",
    key,
    new TextEncoder().encode(concatenated),
  );
  return [...new Uint8Array(signature)]
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

export async function scriptPaymobAmount(amountMinor, orderId = "9001") {
  await fetch(`${PAYMOB_URL}/__script`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({
      amount_cents: String(amountMinor),
      intention_order_id: orderId,
    }),
  });
}

export async function syncPaymobForCheckout(checkoutId) {
  const row = queryAboD1One(
    `SELECT c.charged_price_minor, pi.order_id
     FROM checkout c
     LEFT JOIN paymob_intention pi ON pi.checkout_id = c.checkout_id
     WHERE c.checkout_id = ${sqlLiteral(checkoutId)}`,
  );
  const amountMinor = row?.charged_price_minor ?? 1000;
  const orderId = row?.order_id ?? "9001";
  await scriptPaymobAmount(amountMinor, orderId);
}

export async function postPaymobNotify({
  paymobObj,
  hmac,
  connectingIp = "203.0.113.10",
}) {
  const body = JSON.stringify({ type: "TRANSACTION", obj: paymobObj });
  return billingFetch(`/notify/paymob?hmac=${encodeURIComponent(hmac)}`, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "cf-connecting-ip": connectingIp,
    },
    body,
  });
}
