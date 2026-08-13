import fs from "node:fs/promises";
import path from "node:path";
import { loadLocalSupabaseEnv } from "./env";

export type BootstrapCredentialsInput = {
  username?: string;
  password?: string;
  supabaseUrl?: string;
  anonKey?: string;
  operatorBearer?: boolean;
  aat?: boolean;
};

export type BootstrapCredentialsResult = {
  operatorBearer?: string;
  aat?: string;
  notes: string[];
  errors: string[];
};

const DEFAULT_USERNAME = "admin";
const DEFAULT_PASSWORD = "admin";

export async function bootstrapDevCredentials(
  repoRoot: string,
  input: BootstrapCredentialsInput = {},
): Promise<BootstrapCredentialsResult> {
  const wantOperator = input.operatorBearer !== false;
  const wantAat = input.aat !== false;
  const notes: string[] = [];
  const errors: string[] = [];
  const result: BootstrapCredentialsResult = { notes, errors };

  if (wantOperator) {
    try {
      const token = await writeOperatorBearerDevVar(repoRoot);
      result.operatorBearer = token;
      notes.push(
        "Wrote OPERATOR_BEARER_TOKEN to ai-platform/.dev.vars.development. Restart `npm run dev` in ai-platform if it is already running.",
      );
    } catch (error) {
      errors.push(
        `operator bearer: ${error instanceof Error ? error.message : String(error)}`,
      );
    }
  }

  if (wantAat) {
    try {
      const env = await loadLocalSupabaseEnv(repoRoot);
      const supabaseUrl = input.supabaseUrl?.trim() || env.supabaseUrl;
      const anonKey = input.anonKey?.trim() || env.anonKey;
      const username = input.username?.trim() || DEFAULT_USERNAME;
      const password = input.password ?? DEFAULT_PASSWORD;

      const accessToken = await signInSupabase(
        supabaseUrl,
        anonKey,
        username,
        password,
      );
      result.aat = await mintAat(supabaseUrl, anonKey, accessToken);
      notes.push(
        `Minted AAT via public.issue_ai_token as ${username}@${supabaseUrl}.`,
      );
    } catch (error) {
      errors.push(
        `AAT: ${error instanceof Error ? error.message : String(error)}`,
      );
      notes.push(
        "AAT mint needs local Supabase, bootstrap admin (admin/admin), clinic org+branch, and enroll_installation_keypair on clinic DB.",
      );
    }
  }

  return result;
}

async function writeOperatorBearerDevVar(repoRoot: string): Promise<string> {
  const token = generateOperatorBearer();
  const aiPlatformDir = path.join(repoRoot, "ai-platform");
  await fs.mkdir(aiPlatformDir, { recursive: true });

  const targets = [
    path.join(aiPlatformDir, ".dev.vars.development"),
    path.join(aiPlatformDir, ".dev.vars"),
  ];

  for (const filePath of targets) {
    await upsertDevVar(filePath, "OPERATOR_BEARER_TOKEN", token);
  }

  return token;
}

function generateOperatorBearer(): string {
  const bytes = new Uint8Array(32);
  crypto.getRandomValues(bytes);
  return Buffer.from(bytes).toString("base64url");
}

async function upsertDevVar(
  filePath: string,
  key: string,
  value: string,
): Promise<void> {
  let content = "";
  try {
    content = await fs.readFile(filePath, "utf8");
  } catch {
    // new file
  }

  const lines = content
    .split("\n")
    .filter((line) => line.trim() && !line.startsWith(`${key}=`));
  lines.push(`${key}=${value}`);
  await fs.writeFile(filePath, `${lines.join("\n")}\n`, "utf8");
}

async function signInSupabase(
  supabaseUrl: string,
  anonKey: string,
  email: string,
  password: string,
): Promise<string> {
  const base = supabaseUrl.replace(/\/$/, "");
  const res = await fetch(`${base}/auth/v1/token?grant_type=password`, {
    method: "POST",
    headers: {
      apikey: anonKey,
      Authorization: `Bearer ${anonKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ email, password }),
  });

  const bodyText = await res.text();
  let payload: { access_token?: string; error_description?: string; msg?: string };
  try {
    payload = JSON.parse(bodyText) as typeof payload;
  } catch {
    throw new Error(
      `Supabase sign-in failed (${res.status}): ${bodyText.slice(0, 200)}`,
    );
  }

  if (!res.ok || !payload.access_token) {
    const detail =
      payload.error_description ?? payload.msg ?? bodyText.slice(0, 200);
    throw new Error(`Supabase sign-in failed (${res.status}): ${detail}`);
  }

  return payload.access_token;
}

async function mintAat(
  supabaseUrl: string,
  anonKey: string,
  accessToken: string,
): Promise<string> {
  const base = supabaseUrl.replace(/\/$/, "");
  const res = await fetch(`${base}/rest/v1/rpc/issue_ai_token`, {
    method: "POST",
    headers: {
      apikey: anonKey,
      Authorization: `Bearer ${accessToken}`,
      "Content-Type": "application/json",
    },
    body: "{}",
  });

  const bodyText = await res.text();
  if (!res.ok) {
    let detail = bodyText.slice(0, 300);
    try {
      const parsed = JSON.parse(bodyText) as {
        message?: string;
        hint?: string;
        code?: string;
      };
      detail = [parsed.message, parsed.hint, parsed.code]
        .filter(Boolean)
        .join(" — ");
    } catch {
      // keep raw slice
    }
    throw new Error(`issue_ai_token failed (${res.status}): ${detail}`);
  }

  const token = parseRpcTextResult(bodyText);
  if (!token) {
    throw new Error("issue_ai_token returned an empty token");
  }
  return token;
}

function parseRpcTextResult(bodyText: string): string {
  const trimmed = bodyText.trim();
  if (!trimmed) {
    return "";
  }
  try {
    const parsed = JSON.parse(trimmed) as unknown;
    if (typeof parsed === "string") {
      return parsed;
    }
  } catch {
    // scalar text body
  }
  if (trimmed.startsWith('"') && trimmed.endsWith('"')) {
    try {
      return JSON.parse(trimmed) as string;
    } catch {
      return trimmed.slice(1, -1);
    }
  }
  return trimmed;
}
