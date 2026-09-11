import { spawn } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { expect } from "vitest";
import { buildRawRequest, buildRawResponse } from "../../src/lib/raw-http.ts";
import type { HttpExchange } from "../../src/types.ts";

export const GATEWAY_ORIGIN = "http://127.0.0.1:8787";

const DEV_VARS_PATH = path.resolve(
  import.meta.dirname,
  "../../../ai-platform/.dev.vars",
);
const BACKEND_ENV_PATH = path.resolve(
  import.meta.dirname,
  "../../../backend/local/.env",
);

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

export function readOperatorBearer(): string {
  return readEnvFile(DEV_VARS_PATH).OPERATOR_BEARER_TOKEN ?? "";
}

export function readSupabaseSmokeConfig(): {
  supabaseUrl: string;
  anonKey: string;
  username: string;
  password: string;
} {
  const backendEnv = readEnvFile(BACKEND_ENV_PATH);
  const supabaseUrl =
    backendEnv.SUPABASE_URL ??
    backendEnv.VITE_SUPABASE_URL ??
    "http://127.0.0.1:54321";
  const anonKey =
    backendEnv.SUPABASE_ANON_KEY ?? backendEnv.VITE_SUPABASE_ANON_KEY ?? "";
  const username =
    backendEnv.BOOTSTRAP_ADMIN_USERNAME ??
    backendEnv.VITE_BOOTSTRAP_ADMIN_USERNAME ??
    "admin";
  const password =
    backendEnv.BOOTSTRAP_ADMIN_PASSWORD ??
    backendEnv.VITE_BOOTSTRAP_ADMIN_PASSWORD ??
    "admin";

  if (!anonKey) {
    throw new Error(
      "Supabase anon key missing from backend/local/.env for usage smoke",
    );
  }

  return { supabaseUrl, anonKey, username, password };
}

export function assertHttpExchangeRaw(exchange: HttpExchange): void {
  expect(exchange.request.raw.length).toBeGreaterThan(0);
  expect(exchange.response.raw.length).toBeGreaterThan(0);
}

export async function fetchHttpExchange(
  method: string,
  urlPath: string,
  headers: Record<string, string> = {},
  body?: Record<string, unknown>,
): Promise<HttpExchange> {
  const url = `${GATEWAY_ORIGIN}${urlPath}`;
  const requestHeaders = { ...headers };
  const fetchInit: RequestInit = { method, headers: requestHeaders };

  if (body !== undefined) {
    requestHeaders["Content-Type"] = "application/json";
    fetchInit.body = JSON.stringify(body);
  }

  const response = await fetch(url, fetchInit);
  const rawBody = await response.text();
  const responseHeaders: Record<string, string> = {};
  response.headers.forEach((value, name) => {
    responseHeaders[name] = value;
  });

  return {
    request: {
      method,
      url,
      headers: Object.entries(requestHeaders).map(([name, value]) => ({
        name,
        value,
      })),
      body: [],
      raw: buildRawRequest(method, url, requestHeaders, body),
    },
    response: {
      status: response.status,
      statusText: response.statusText,
      headers: Object.entries(responseHeaders).map(([name, value]) => ({
        name,
        value,
      })),
      body: [],
      rawBody,
      raw: buildRawResponse(
        response.status,
        response.statusText,
        responseHeaders,
        rawBody,
      ),
    },
    sentAt: new Date().toISOString(),
  };
}

type ClinicEnrollmentMaterial = {
  installation_id: string;
  kid: string;
  public_key: string;
  org_id: string;
  display_name: string;
  aat_ver: string;
};

const CLINIC_ENROLLMENT_MATERIAL_SQL = `
SELECT row_to_json(row) FROM (
  SELECT
    ik.installation_id::text AS installation_id,
    ik.kid,
    rtrim(
      translate(replace(encode(ik.public_key, 'base64'), E'\\n', ''), '+/', '-_'),
      '='
    ) AS public_key,
    o.id::text AS org_id,
    o.name AS display_name,
    coalesce(
      nullif(trim(both '"' from ver_setting.value_json::text), ''),
      '1'
    ) AS aat_ver
  FROM ai_internal.installation_keys ik
  CROSS JOIN LATERAL (
    SELECT id, name
    FROM public.organizations
    WHERE is_deleted = false
    ORDER BY created_at
    LIMIT 1
  ) o
  CROSS JOIN LATERAL (
    SELECT value_json
    FROM ai_internal.app_settings
    WHERE key = 'ai.aat.ver'
      AND is_deleted = false
    LIMIT 1
  ) ver_setting
  WHERE ik.is_deleted = false
    AND ik.revoked_at IS NULL
  ORDER BY ik.valid_from DESC, ik.kid DESC
  LIMIT 1
) row;
`.trim();

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

async function queryClinicEnrollmentMaterial(): Promise<ClinicEnrollmentMaterial | null> {
  const backendEnv = readEnvFile(BACKEND_ENV_PATH);
  const password = backendEnv.POSTGRES_PASSWORD ?? "postgres";
  const port = backendEnv.SUPABASE_DB_PORT ?? "54322";
  const repoRoot = path.resolve(import.meta.dirname, "../../..");

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
      CLINIC_ENROLLMENT_MATERIAL_SQL,
    ],
    repoRoot,
    { ...process.env, PGPASSWORD: password },
  );

  if (result.code !== 0) {
    throw new Error(result.stderr || result.stdout || "Clinic Postgres query failed");
  }

  const row = result.stdout.trim();
  if (!row) {
    return null;
  }

  return JSON.parse(row) as ClinicEnrollmentMaterial;
}

async function ensureAcceptedTokenVer(
  operatorBearer: string,
  ver: string,
): Promise<void> {
  const response = await fetch(
    `${GATEWAY_ORIGIN}/control/token-contract/begin-rotation`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${operatorBearer}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ ver }),
    },
  );

  if (response.ok) {
    return;
  }

  const rawBody = await response.text();
  let errorCode: string | undefined;
  try {
    errorCode = (JSON.parse(rawBody) as { error?: string }).error;
  } catch {
    // ignore parse failures
  }

  if (
    response.status === 409 &&
    (errorCode === "ver_already_exists" || errorCode === "rotation_already_open")
  ) {
    return;
  }

  throw new Error(
    `Platform token-contract sync failed (${response.status}${errorCode ? `: ${errorCode}` : ""}). ${rawBody}`,
  );
}

async function ensurePlatformEnrollment(operatorBearer: string): Promise<void> {
  if (!operatorBearer) {
    throw new Error(
      "Operator bearer missing from ai-platform/.dev.vars for usage smoke enrollment sync",
    );
  }

  const material = await queryClinicEnrollmentMaterial();
  if (!material) {
    throw new Error(
      "No clinic installation key found in local Supabase for usage smoke",
    );
  }

  const response = await fetch(
    `${GATEWAY_ORIGIN}/control/installations/${material.installation_id}/enroll`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${operatorBearer}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        org_id: material.org_id,
        display_name: material.display_name,
        region: "us-east-1",
        plan: "professional",
        public_key: material.public_key,
        algorithm: "EdDSA",
        kid: material.kid,
      }),
    },
  );

  if (!response.ok) {
    const rawBody = await response.text();
    let errorCode: string | undefined;
    try {
      errorCode = (JSON.parse(rawBody) as { error?: string }).error;
    } catch {
      // ignore parse failures
    }

    if (!(response.status === 409 && errorCode === "already_enrolled")) {
      throw new Error(
        `Platform enroll failed (${response.status}${errorCode ? `: ${errorCode}` : ""}). ${rawBody}`,
      );
    }
  }

  await ensureAcceptedTokenVer(operatorBearer, material.aat_ver);
}

export async function mintInstallationAat(): Promise<string> {
  const operatorBearer = readOperatorBearer();
  const config = readSupabaseSmokeConfig();
  const authResponse = await fetch(
    `${config.supabaseUrl}/auth/v1/token?grant_type=password`,
    {
      method: "POST",
      headers: {
        apikey: config.anonKey,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        email: config.username,
        password: config.password,
      }),
    },
  );

  const authPayload = (await authResponse.json()) as {
    access_token?: string;
    error_description?: string;
    msg?: string;
  };

  if (!authResponse.ok || !authPayload.access_token) {
    throw new Error(
      authPayload.error_description ??
        authPayload.msg ??
        "Supabase sign-in failed for usage smoke",
    );
  }

  const tokenResponse = await fetch(
    `${config.supabaseUrl}/rest/v1/rpc/issue_ai_token`,
    {
      method: "POST",
      headers: {
        apikey: config.anonKey,
        Authorization: `Bearer ${authPayload.access_token}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({}),
    },
  );

  const tokenBody = await tokenResponse.text();
  if (!tokenResponse.ok || tokenBody.length === 0) {
    throw new Error(tokenBody || "issue_ai_token failed for usage smoke");
  }

  await ensurePlatformEnrollment(operatorBearer);
  return tokenBody.replace(/^"|"$/g, "");
}
