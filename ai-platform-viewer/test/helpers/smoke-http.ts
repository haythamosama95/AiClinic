import fs from "node:fs";
import path from "node:path";
import { expect } from "vitest";
import { buildRawRequest, buildRawResponse } from "../src/lib/raw-http.ts";
import type { HttpExchange } from "../src/types.ts";

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

export async function mintInstallationAat(): Promise<string> {
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

  return tokenBody.replace(/^"|"$/g, "");
}
