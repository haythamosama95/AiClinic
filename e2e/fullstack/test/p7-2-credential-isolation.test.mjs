import { readFile } from "node:fs/promises";
import { spawn } from "node:child_process";
import { spawnSync } from "node:child_process";
import path from "node:path";
import test, { after, before } from "node:test";
import assert from "node:assert/strict";
import {
  ABO_CONFIG,
  ABO_URL,
  DB_URL,
  FULLSTACK_ROOT,
  PLATFORM_CONFIG,
  PLATFORM_URL,
  SUPABASE_ANON_KEY,
  SUPABASE_URL,
  rpc,
  startStack,
} from "./p7-2-stack.mjs";

// H-FS unit harness (P7.2 US3): node --import tsx --test test/p7-2-credential-isolation.test.mjs

const DEMO_ANON_KEY =
  "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0";

const SUPABASE_CREDENTIAL_PATTERNS = [
  /SUPABASE_/i,
  /service_role/i,
  /postgres:\/\//i,
  /SUPABASE_SERVICE_ROLE_KEY/i,
  /SUPABASE_JWT_SECRET/i,
  DEMO_ANON_KEY,
];

let stack = null;

before(async () => {
  stack = await startStack();
});

after(async () => {
  await stack?.stop();
  stack = null;
});

function psqlScalar(sql) {
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

function assertNoSupabaseCredential(tomlText, label) {
  for (const line of tomlText.split("\n")) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith("#")) {
      continue;
    }
    for (const pattern of SUPABASE_CREDENTIAL_PATTERNS) {
      assert.ok(
        !pattern.test(trimmed),
        `${label} must not hold a Supabase credential (${trimmed})`,
      );
    }
  }
}

async function postgrestRpc(token, functionName, body = { p_contract_version: 1 }) {
  const base = SUPABASE_URL.endsWith("/")
    ? SUPABASE_URL.slice(0, -1)
    : SUPABASE_URL;
  return fetch(`${base}/rest/v1/rpc/${functionName}`, {
    method: "POST",
    headers: {
      apikey: SUPABASE_ANON_KEY,
      authorization: `Bearer ${token}`,
      "content-type": "application/json",
      accept: "application/json",
    },
    body: JSON.stringify(body),
  });
}

function parseCaptureLines(stdout) {
  const lines = stdout
    .split("\n")
    .map((line) => line.trim())
    .filter((line) => line.startsWith("{"))
    .map((line) => JSON.parse(line));
  const sessionLine = lines.find((entry) => typeof entry.session_jwt === "string");
  const captures = lines.filter((entry) => typeof entry.url === "string");
  return {
    sessionJwt: sessionLine?.session_jwt ?? null,
    captures,
  };
}

function bearerToken(authorization) {
  if (!authorization) {
    return null;
  }
  const match = /^Bearer\s+(.+)$/i.exec(authorization);
  return match?.[1] ?? authorization;
}

async function runDartSessionCapture(env) {
  return await new Promise((resolve, reject) => {
    const child = spawn("dart", ["run", "bin/session_jwt_capture.dart"], {
      cwd: path.join(FULLSTACK_ROOT, "dart"),
      env: { ...process.env, ...env },
      stdio: ["ignore", "pipe", "pipe"],
    });
    let stdout = "";
    let stderr = "";
    child.stdout.on("data", (chunk) => {
      stdout += chunk.toString();
    });
    child.stderr.on("data", (chunk) => {
      stderr += chunk.toString();
    });
    child.on("close", (code) => {
      if (code !== 0) {
        reject(new Error(stderr || `dart exited ${code}`));
        return;
      }
      resolve(stdout);
    });
  });
}

test("E2E-P7.2-07", async () => {
  const aboToml = await readFile(ABO_CONFIG, "utf8");
  const platformToml = await readFile(PLATFORM_CONFIG, "utf8");
  assertNoSupabaseCredential(aboToml, "abo/wrangler.toml");
  assertNoSupabaseCredential(platformToml, "ai-platform/wrangler.toml");

  const { administrator } = stack.clinics.orgA;
  const billing = await rpc(administrator, "issue_billing_token", {
    p_contract_version: 1,
  });
  assert.equal(billing.success, true);
  const aiToken = await rpc(administrator, "issue_ai_token", {
    p_contract_version: 1,
  });
  const feedToken = psqlScalar("SELECT auth_internal.issue_feed_token()");

  for (const [label, token] of [
    ["billing token", billing.data.token],
    ["AI token", aiToken],
    ["feed token", feedToken],
  ]) {
    const response = await postgrestRpc(token, "get_ai_status");
    assert.ok(
      response.status === 401 || response.status === 403,
      `${label} must be rejected by PostgREST (got ${response.status})`,
    );
  }
});

test("E2E-P7.2-08", async () => {
  const stdout = await runDartSessionCapture({
    SUPABASE_URL,
    SUPABASE_ANON_KEY,
    PLATFORM_URL,
    ABO_URL,
    P7_2_SESSION_EMAIL: "p7-2-a-admin",
    P7_2_SESSION_PASSWORD: "P72AdminPass!",
  });
  const { sessionJwt, captures } = parseCaptureLines(stdout);
  assert.ok(sessionJwt, "dart driver should publish the desktop session JWT");
  assert.ok(captures.length > 0, "dart driver should record outbound calls");

  const platformCalls = captures.filter((entry) => entry.service === "platform");
  const aboCalls = captures.filter((entry) => entry.service === "abo");
  assert.ok(platformCalls.length > 0, "dart driver should call the platform");
  assert.ok(aboCalls.length > 0, "dart driver should call the ABO");

  for (const entry of [...platformCalls, ...aboCalls]) {
    const url = String(entry.url ?? "");
    assert.ok(
      entry.service === "platform"
        ? url.startsWith(PLATFORM_URL)
        : url.startsWith(ABO_URL),
      `${entry.service} capture must target the expected service base URL`,
    );
    const token = bearerToken(entry.authorization);
    assert.ok(token, `${url} should include Authorization`);
    assert.notEqual(
      token,
      sessionJwt,
      `${entry.service} Authorization must not be the Supabase session JWT`,
    );
    assert.ok(
      !token.includes(sessionJwt),
      `${entry.service} Authorization must not embed the Supabase session JWT`,
    );
  }
});
