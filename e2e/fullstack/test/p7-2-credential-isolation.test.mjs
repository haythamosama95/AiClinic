import { readFile } from "node:fs/promises";
import { spawn } from "node:child_process";
import { spawnSync } from "node:child_process";
import path from "node:path";
import test, { after, before } from "node:test";
import assert from "node:assert/strict";
import { createClient } from "@supabase/supabase-js";
import {
  ABO_CONFIG,
  DB_URL,
  FULLSTACK_ROOT,
  PLATFORM_CONFIG,
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

async function signInSessionJwt(email, password) {
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
  return data.session.access_token;
}

function parseCaptureLines(stdout) {
  return stdout
    .split("\n")
    .map((line) => line.trim())
    .filter((line) => line.startsWith("{"))
    .map((line) => JSON.parse(line));
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
  const sessionJwt = await signInSessionJwt("p7-2-a-admin", "P72AdminPass!");
  const stdout = await runDartSessionCapture({
    SUPABASE_URL,
    SUPABASE_ANON_KEY,
    P7_2_SESSION_EMAIL: "p7-2-a-admin",
    P7_2_SESSION_PASSWORD: "P72AdminPass!",
  });
  const captures = parseCaptureLines(stdout);
  assert.ok(captures.length > 0, "dart driver should record outbound calls");

  const externalCalls = captures.filter((entry) => {
    const url = String(entry.url ?? "");
    return (
      url.startsWith("http://127.0.0.1:8787") ||
      url.startsWith("http://127.0.0.1:8788")
    );
  });
  assert.ok(
    externalCalls.length > 0,
    "dart driver should call the platform and/or ABO",
  );

  for (const entry of externalCalls) {
    const token = bearerToken(entry.authorization);
    assert.ok(token, `${entry.url} should include Authorization`);
    assert.notEqual(
      token,
      sessionJwt,
      "ABO and platform Authorization must not be the Supabase session JWT",
    );
    assert.ok(
      !token.includes(sessionJwt),
      "Authorization must not embed the Supabase session JWT",
    );
  }
});
