import { spawn, spawnSync } from "node:child_process";
import { mkdir } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import test, { after, before } from "node:test";
import assert from "node:assert/strict";
import { createClient } from "@supabase/supabase-js";
import {
  closeLocalVirtualHostDispatchers,
  fetchLocalVirtualHost,
} from "./local-virtual-host.mjs";
import { unstable_startWorker as startWorker } from "wrangler";
import { CHANNEL_VERSIONS } from "vendor-contracts";
import {
  createAccessTeam,
  createSoftwareAuthenticator,
} from "vendor-contracts/testkit";
import {
  ABO_PERSIST,
  HARNESS_PERSIST,
  PLATFORM_PERSIST,
  REGISTRY_DIR,
  preparePlatformD1,
  execPlatformD1Sql,
  queryPlatformD1One,
  runWranglerSync,
  wranglerLocalEnv,
  WRANGLER_CLI,
  PLATFORM_BIND_HOST,
} from "./wrangler-persist.mjs";

const REPO_ROOT = path.resolve(
  path.dirname(fileURLToPath(import.meta.url)),
  "../../..",
);
const FULLSTACK_ROOT = path.join(REPO_ROOT, "e2e/fullstack");
const PLATFORM_CONFIG = path.join(REPO_ROOT, "ai-platform/wrangler.toml");
const HARNESS_CONFIG = path.join(FULLSTACK_ROOT, "wrangler.toml");
const ABO_CONFIG = path.join(REPO_ROOT, "abo/wrangler.toml");
const PAYMOB_WORKER = path.join(REPO_ROOT, "abo/test/stubs/paymob/worker.ts");

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
const STARTUP_LOG_TAIL_CHARS = 4_000;
const MAX_DIAGNOSTIC_CHILDREN = 4;
const PORT_BINDINGS = [
  `platform ${PLATFORM_BIND_HOST}:8787 (ai-platform/wrangler.toml, inspector disabled)`,
  "harness 127.0.0.1:8790 (e2e/fullstack/wrangler.toml, inspector disabled)",
  "paymob 127.0.0.1:8789 (abo/test/stubs/paymob/worker.ts), inspector 9230",
  "abo 127.0.0.1:8788 (abo/wrangler.toml, development), inspector 9231",
];

let stack = null;

function base64urlEncode(bytes) {
  return Buffer.from(bytes).toString("base64url");
}

function runWrangler(args, { cwd = REPO_ROOT, env = {} } = {}) {
  return runWranglerSync(args, { cwd, env });
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

function createStartupScope() {
  const cleanups = [];
  let stopPromise = null;

  return {
    defer(label, dispose) {
      const entry = { label, dispose, active: true };
      cleanups.push(entry);
      return () => {
        entry.active = false;
      };
    },
    stop() {
      if (stopPromise) return stopPromise;
      stopPromise = (async () => {
        const errors = [];
        for (const entry of cleanups.reverse()) {
          if (!entry.active) continue;
          entry.active = false;
          try {
            await entry.dispose();
          } catch (error) {
            errors.push(`${entry.label}: ${error.message}`);
          }
        }
        if (errors.length) {
          throw new Error(`P5.1 cleanup errors: ${errors.join("; ")}`);
        }
      })();
      return stopPromise;
    },
  };
}

function safeDiagnosticText(value) {
  return String(value)
    .replace(/\bBearer\s+[^\s"']+/gi, "Bearer [redacted]")
    .replace(/\beyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\b/g, "[redacted-jwt]")
    .replace(/("?(?:access[_-]?jwt|access[_-]?token|api[_-]?key|secret|password|private[_-]?key|pkcs8|issuer[_-]?keys|abo[_-]?grant[_-]?key|platform[_-]?public[_-]?keys)"?\s*[:=]\s*)("[^"]*"|'[^']*'|[^,\s}\]]+)/gi, "$1[redacted]");
}

function tail(value) {
  const safe = safeDiagnosticText(value);
  return safe.length > STARTUP_LOG_TAIL_CHARS
    ? `[earlier output truncated]\n${safe.slice(-STARTUP_LOG_TAIL_CHARS)}`
    : safe;
}

function safeUrl(url) {
  try {
    const parsed = new URL(url);
    return `${parsed.protocol}//${parsed.host}${parsed.pathname}`;
  } catch {
    return "[invalid readiness URL]";
  }
}

async function waitForHttp(
  url,
  {
    timeoutMs = 120_000,
    accept = [200],
    headers = {},
    authorityHost = null,
    label = "HTTP readiness",
    diagnostics = () => "",
  } = {},
) {
  const deadline = Date.now() + timeoutMs;
  let lastStatus = "none";
  let lastError = "none";
  while (Date.now() < deadline) {
    try {
      const response = authorityHost
        ? await fetchLocalVirtualHost(url, authorityHost, { headers })
        : await fetch(url, { headers });
      lastStatus = String(response.status);
      if (accept.includes(response.status)) {
        return response;
      }
    } catch (error) {
      lastError = `${error.code ?? error.cause?.code ?? error.name ?? "Error"}: ` +
        `${error.message === "fetch failed" ? "fetch failed" : "request failed"}`;
    }
    await new Promise((resolve) => setTimeout(resolve, 500));
  }
  const authority = authorityHost ? `, authority: ${authorityHost}` : "";
  const hostHeader = headers.Host ? `, Host: ${headers.Host}` : "";
  throw new Error(
    `${label} timed out after ${timeoutMs}ms at ${safeUrl(url)}${authority}${hostHeader}; ` +
      `accepted status: ${accept.join(",")}; last status: ${lastStatus}; ` +
      `last fetch error: ${safeDiagnosticText(lastError)}; ` +
      `ports: ${PORT_BINDINGS.join("; ")}${diagnostics()}`,
  );
}

function spawnDevProcess(args, env = {}, { label = "wrangler dev" } = {}) {
  const child = spawn(process.execPath, [WRANGLER_CLI, ...args], {
    cwd: REPO_ROOT,
    env: wranglerLocalEnv(env),
    stdio: ["ignore", "pipe", "pipe"],
    detached: process.platform !== "win32",
  });
  child.diagnostic = { label, stdout: "", stderr: "", spawnError: "none" };
  child.on("error", (error) => {
    child.diagnostic.spawnError = `${error.code ?? error.name ?? "Error"}: ` +
      safeDiagnosticText(error.message);
  });
  child.stdout?.on("data", (chunk) => {
    child.diagnostic.stdout = tail(child.diagnostic.stdout + chunk.toString());
  });
  child.stderr?.on("data", (chunk) => {
    child.diagnostic.stderr = tail(child.diagnostic.stderr + chunk.toString());
  });
  return child;
}

function childDiagnostics(child) {
  if (!child) return "";
  return (
    `\nchild ${child.diagnostic?.label ?? "wrangler dev"}: pid=${child.pid ?? "none"}, ` +
    `exitCode=${child.exitCode ?? "running/unknown"}, signal=${child.signalCode ?? "none"}, ` +
    `spawnError=${child.diagnostic?.spawnError ?? "none"}; ` +
    `stdout tail:\n${child.diagnostic?.stdout || "[empty]"}; stderr tail:\n${child.diagnostic?.stderr || "[empty]"}`
  );
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

  // The Wrangler leader may already have exited while workerd descendants
  // remain in this dedicated process group, so signal the group regardless.
  if (!signalGroup("SIGTERM")) return;
  if (await waitForGroupExit(5_000)) return;
  signalGroup("SIGKILL");
  if (!(await waitForGroupExit(1_000))) {
    throw new Error(`Process group ${child.pid} did not exit after SIGKILL`);
  }
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

async function registerIssuerKey(stack, issuerKey) {
  const accessJwt = await mintAccessJwt(stack.accessTeam);
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
    await stack.authenticator.assert({
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
      signer_credential_id: stack.credentialId,
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
  return queryPlatformD1One(sql);
}

function getTenantBindingEpoch(orgId) {
  const row = queryD1One(
    `SELECT epoch FROM tenant_binding WHERE org_id = '${orgId}' LIMIT 1`,
  );
  return row?.epoch ?? null;
}

function ownerInsertIssuerKid() {
  const row = psqlQuery(
    "SELECT kid, public_key, status, not_before::text, not_after::text FROM auth_internal.insert_issuer_kid()",
  );
  const [kid, publicKey, status, notBefore, notAfter] = row.split("|");
  return {
    kid,
    public_key: publicKey,
    status,
    not_before: notBefore,
    not_after: notAfter,
  };
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
      AND sm.auth_user_id IN (SELECT id FROM auth.users WHERE email LIKE 'p5-1-%');
    DELETE FROM public.staff_members sm
    WHERE sm.auth_user_id IN (SELECT id FROM auth.users WHERE email LIKE 'p5-1-%');
    DELETE FROM auth.users WHERE email LIKE 'p5-1-%';
  `);

  const bootstrap = await signIn("admin", "admin");

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
  const scope = createStartupScope();
  const children = new Set();
  let phase = "prepare persistence";
  const diagnostics = () => {
    const allChildren = [...children];
    const shownChildren = allChildren.slice(-MAX_DIAGNOSTIC_CHILDREN);
    const childDetails = shownChildren.map(childDiagnostics).join("\n");
    const omitted = allChildren.length - shownChildren.length;
    return childDetails
      ? `\n${omitted ? `[${omitted} earlier child diagnostics omitted]\n` : ""}${childDetails}`
      : "";
  };

  try {
    await mkdir(PLATFORM_PERSIST, { recursive: true });
    await mkdir(HARNESS_PERSIST, { recursive: true });
    await mkdir(REGISTRY_DIR, { recursive: true });
    await mkdir(ABO_PERSIST, { recursive: true });
    await preparePlatformD1({ platformConfig: PLATFORM_CONFIG });

    const accessTeam = await createAccessTeam({
      issuer: `https://${ACCESS_TEAM_DOMAIN}`,
    });
    const authenticator = await createSoftwareAuthenticator("EdDSA");
    const attestation = await authenticator.attest();
    const credentialId = crypto.randomUUID();
    const publicKeyCose = base64urlEncode(attestation.publicKey);

    await insertActiveOperatorCredential({
      credentialId,
      operatorEmail: OPERATOR_EMAIL,
      publicKeyCose,
    });

    phase = "start platform worker on 8787";
    const platformWorker = await startWorker({
      config: PLATFORM_CONFIG,
      env: "development",
      dev: {
        server: { hostname: PLATFORM_BIND_HOST, port: 8787 },
        inspector: false,
        persist: PLATFORM_PERSIST,
        registry: REGISTRY_DIR,
        vars: {
          ACCESS_CERTS_JSON: JSON.stringify({ keys: accessTeam.certs.keys }),
        },
      },
    });
    scope.defer("platform worker", () => platformWorker.dispose());
    await platformWorker.ready;

    phase = "start harness worker on 8790";
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
    scope.defer("harness worker", () => harnessWorker.dispose());
    await harnessWorker.ready;

    phase = "wait for platform /health";
    await waitForHttp(`${PLATFORM_URL}/health`, {
      label: "platform worker readiness",
      diagnostics,
    });
    phase = "probe harness /register-issuer-key";
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
    let issuerKeys = [{ kid: signingKey.kid, public_key: signingKey.public_key }];

    phase = "spawn paymob worker on 8789";
    const paymob = spawnDevProcess([
      "dev",
      PAYMOB_WORKER,
      "--port",
      "8789",
      "--ip",
      "127.0.0.1",
      "--inspector-port",
      "9230",
    ], {}, { label: "wrangler dev paymob (abo/test/stubs/paymob/worker.ts)" });
    children.add(paymob);
    scope.defer("paymob child process", () => stopChild(paymob));
    phase = "wait for paymob /";
    await waitForHttp(`${PAYMOB_URL}/`, {
      accept: [200, 404],
      label: "paymob worker readiness",
      diagnostics,
    });

    phase = "apply ABO migrations";
    await applyAboMigrations();
    phase = "spawn ABO worker on 8788";
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
        "--var",
        `PAYMOB_BASE_URL:${PAYMOB_URL}`,
        "--var",
        `ISSUER_KEYS:${JSON.stringify(issuerKeys)}`,
      ],
      {},
      { label: "wrangler dev ABO (abo/wrangler.toml, development)" },
    );
    children.add(abo);
    let deactivateAbo = scope.defer("ABO child process", () => stopChild(abo));
    phase = "wait for ABO /v1/offers with billing host";
    await waitForHttp(`${ABO_URL}/v1/offers`, {
      accept: [401, 403, 400],
      authorityHost: BILLING_HOST,
      label: "ABO offers readiness",
      diagnostics,
    });

    phase = "create clinic users";
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
      aiToken: null,
      billingToken: null,
      async stop() {
        await scope.stop();
      },
      async restartAbo(nextIssuerKeys = issuerKeys) {
        await stopChild(stackRef.abo);
        deactivateAbo();
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
            "--var",
            `PAYMOB_BASE_URL:${PAYMOB_URL}`,
            "--var",
            `ISSUER_KEYS:${JSON.stringify(nextIssuerKeys)}`,
          ],
          {},
          { label: "wrangler dev restarted ABO (abo/wrangler.toml, development)" },
        );
        children.add(restarted);
        deactivateAbo = scope.defer("restarted ABO child process", () => stopChild(restarted));
        stackRef.abo = restarted;
        phase = "wait for restarted ABO /v1/offers with billing host";
        await waitForHttp(`${ABO_URL}/v1/offers`, {
          accept: [401, 403, 400],
          authorityHost: BILLING_HOST,
          label: "restarted ABO offers readiness",
          diagnostics,
        });
        stackRef.issuerKeys = nextIssuerKeys;
        return restarted;
      },
    };

    await registerIssuerKey(stackRef, signingKey);
    await stackRef.restartAbo(issuerKeys);

    return stackRef;
  } catch (error) {
    try {
      await scope.stop();
    } catch (cleanupError) {
      console.error(`[P5.1 startup cleanup] ${safeDiagnosticText(cleanupError.message)}`);
    }
    const detail = diagnostics();
    console.error(
      `[P5.1 startup failure] phase=${phase}; ports: ${PORT_BINDINGS.join("; ")}${detail}`,
    );
    throw error;
  }
}

before(async () => {
  stack = await startStack();
});

after(async () => {
  try {
    await stack?.stop();
  } finally {
    stack = null;
    await closeLocalVirtualHostDispatchers();
  }
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

  const aiToken = await rpc(stack.clinic.member, "issue_ai_token", {
    p_contract_version: 1,
  });
  assert.ok(aiToken, "issue_ai_token(1) returned no token");
  stack.aiToken = aiToken;

  const capabilities = await fetch(`${PLATFORM_URL}/v1/capabilities`, {
    headers: {
      authorization: `Bearer ${aiToken}`,
      "Aip-Contract-Version": "1",
    },
  });

  assert.equal(capabilities.status, 200);

  const epoch = getTenantBindingEpoch(stack.clinic.orgId);
  assert.equal(epoch, 1);
});

test("E2E-P5.1-02 Administrator issue_billing_token(1) is accepted by the local ABO and a doctor receives FORBIDDEN_ROLE", async () => {
  await assertRunnerWired();

  const billing = await rpc(stack.clinic.administrator, "issue_billing_token", {
    p_contract_version: 1,
  });
  assert.equal(billing.contract_version, 1);
  assert.equal(billing.success, true);
  const billingToken = billing.data.token;
  assert.ok(billingToken);
  stack.billingToken = billingToken;

  const offers = await fetchLocalVirtualHost(`${ABO_URL}/v1/offers`, BILLING_HOST, {
    headers: {
      authorization: `Bearer ${billingToken}`,
      "Abo-Contract-Version": "1",
    },
  });

  assert.equal(offers.status, 200);

  const doctorBilling = await rpc(stack.clinic.doctor, "issue_billing_token", {
    p_contract_version: 1,
  });

  assert.equal(doctorBilling.success, false);
  assert.equal(doctorBilling.error_code, "FORBIDDEN_ROLE");
});

test("E2E-P5.1-03 Billing token at the platform and AI token at the ABO are 401", async () => {
  await assertRunnerWired();

  assert.ok(stack.billingToken, "billing token missing from E2E-P5.1-02");
  assert.ok(stack.aiToken, "AI token missing from E2E-P5.1-01");

  const billingAtPlatform = await fetch(`${PLATFORM_URL}/v1/capabilities`, {
    headers: {
      authorization: `Bearer ${stack.billingToken}`,
      "Aip-Contract-Version": "1",
    },
  });
  assert.equal(billingAtPlatform.status, 401);

  const aiAtAbo = await fetchLocalVirtualHost(`${ABO_URL}/v1/offers`, BILLING_HOST, {
    headers: {
      authorization: `Bearer ${stack.aiToken}`,
      "Abo-Contract-Version": "1",
    },
  });
  assert.equal(aiAtAbo.status, 401);
});

test("E2E-P5.1-06 New signing kid is accepted everywhere, old tokens stay valid, and the binding is unchanged", async () => {
  await assertRunnerWired();

  assert.ok(stack.aiToken, "AI token missing from E2E-P5.1-01");
  assert.ok(stack.billingToken, "billing token missing from E2E-P5.1-02");

  const epochBefore = getTenantBindingEpoch(stack.clinic.orgId);
  assert.equal(epochBefore, 1);

  const oldAiToken = stack.aiToken;
  const oldBillingToken = stack.billingToken;

  const capabilitiesOld = await fetch(`${PLATFORM_URL}/v1/capabilities`, {
    headers: {
      authorization: `Bearer ${oldAiToken}`,
      "Aip-Contract-Version": "1",
    },
  });
  const offersOld = await fetchLocalVirtualHost(`${ABO_URL}/v1/offers`, BILLING_HOST, {
    headers: {
      authorization: `Bearer ${oldBillingToken}`,
      "Abo-Contract-Version": "1",
    },
  });
  assert.equal(capabilitiesOld.status, 200);
  assert.equal(offersOld.status, 200);

  const nextKey = ownerInsertIssuerKid();
  assert.equal(nextKey.status, "next");

  const pinnedKeys = readIssuerKeysForAbo(["signing", "next"]);
  await stack.restartAbo(pinnedKeys);

  const registerBody = await registerIssuerKey(stack, nextKey);
  assert.equal(registerBody.result, "ok");

  ownerSwitchSigningKid(nextKey.kid);
  const signingKid = psqlQuery(
    "SELECT kid FROM ai_internal.issuer_key WHERE status = 'signing' LIMIT 1",
  );
  assert.equal(signingKid, nextKey.kid);

  const newAiToken = await rpc(stack.clinic.member, "issue_ai_token", {
    p_contract_version: 1,
  });
  const newBilling = await rpc(stack.clinic.administrator, "issue_billing_token", {
    p_contract_version: 1,
  });
  assert.equal(newBilling.success, true);
  const newBillingToken = newBilling.data.token;

  const capabilitiesNew = await fetch(`${PLATFORM_URL}/v1/capabilities`, {
    headers: {
      authorization: `Bearer ${newAiToken}`,
      "Aip-Contract-Version": "1",
    },
  });
  const offersNew = await fetchLocalVirtualHost(`${ABO_URL}/v1/offers`, BILLING_HOST, {
    headers: {
      authorization: `Bearer ${newBillingToken}`,
      "Abo-Contract-Version": "1",
    },
  });

  assert.equal(capabilitiesNew.status, 200);
  assert.equal(offersNew.status, 200);

  const capabilitiesOldAfter = await fetch(`${PLATFORM_URL}/v1/capabilities`, {
    headers: {
      authorization: `Bearer ${oldAiToken}`,
      "Aip-Contract-Version": "1",
    },
  });
  const offersOldAfter = await fetchLocalVirtualHost(`${ABO_URL}/v1/offers`, BILLING_HOST, {
    headers: {
      authorization: `Bearer ${oldBillingToken}`,
      "Abo-Contract-Version": "1",
    },
  });
  assert.equal(capabilitiesOldAfter.status, 200);
  assert.equal(offersOldAfter.status, 200);

  const epochAfter = getTenantBindingEpoch(stack.clinic.orgId);
  assert.equal(epochAfter, epochBefore);
});
