import path from "node:path";
import { fileURLToPath } from "node:url";
import { unstable_dev, type Unstable_DevWorker } from "wrangler";
import { afterEach, describe, expect, it, vi } from "vitest";
import {
  writePostResponseDetail,
  type PostResponseInput,
} from "../src/journal";
import { createLogger } from "../src/logger";

const ROOT = path.join(path.dirname(fileURLToPath(import.meta.url)), "..");
const CONFIG_PATH = path.join(ROOT, "wrangler.toml");
const SCRIPT_PATH = path.join(ROOT, "src", "worker.ts");

const DEV_OPTIONS = {
  compatibilityDate: "2026-05-03",
  local: true,
  inspect: false,
  logLevel: "log" as const,
  experimental: { disableExperimentalWarning: true, disableDevRegistry: true },
};

const SENSITIVE_PROMPT = "SECRET_PROMPT_TEXT_DO_NOT_LOG";
const SENSITIVE_CONTEXT = "SECRET_CONTEXT_PAYLOAD_DO_NOT_LOG";
const SENSITIVE_CREDENTIAL = "SECRET_CREDENTIAL_VALUE_DO_NOT_LOG";
const STAGE16_FAILURE_CANARY = "stage16_post_response_detail_failed";

type ConsoleSpy = ReturnType<typeof vi.spyOn>;

function serializeConsoleCalls(...spies: ConsoleSpy[]): string {
  return spies
    .flatMap((spy) => spy.mock.calls)
    .flat()
    .map((value) => {
      if (typeof value === "string") {
        return value;
      }
      if (value instanceof Error) {
        return `${value.name}: ${value.message}\n${value.stack ?? ""}`;
      }
      try {
        return JSON.stringify(value);
      } catch {
        return String(value);
      }
    })
    .join("\n");
}

function createFakeCtx(): {
  waitUntil: (promise: Promise<unknown>) => void;
  drainWaitUntil: () => Promise<void>;
} {
  const pending: Promise<unknown>[] = [];
  return {
    waitUntil(promise: Promise<unknown>) {
      pending.push(promise);
    },
    async drainWaitUntil() {
      await Promise.all(pending);
      pending.length = 0;
    },
  };
}

function buildSensitivePostResponseInput(): PostResponseInput {
  return {
    requestId: "01REDATREQ00000000000001",
    installationId: "inst-redaction-001",
    period: "2026-08",
    quotaWeight: 1,
    totalTokens: 100,
    totalCost: 0.01,
    filteredContext: {
      note: SENSITIVE_CONTEXT,
      authorization: `Bearer ${SENSITIVE_CREDENTIAL}`,
    },
    composedPrompt: {
      system: SENSITIVE_PROMPT,
      messages: [{ role: "user", content: SENSITIVE_PROMPT }],
    },
    attempts: [
      {
        attemptNo: 1,
        provider: "deepseek",
        model: "redaction-fixture",
        outcome: "success",
        latencyMs: 10,
        tokensIn: 50,
        tokensOut: 50,
        cost: 0.01,
        providerRequestId: "prov-1",
        rawBody: {
          prompt: SENSITIVE_PROMPT,
          credential: SENSITIVE_CREDENTIAL,
        },
      },
    ],
    validatedResult: {
      finalContent: { text: SENSITIVE_PROMPT },
      usage: { input: 50, output: 50, cached: 0 },
      providerModel: { provider: "deepseek", model: "redaction-fixture" },
      finishReason: "stop",
      providerRequestId: "prov-1",
      timing: { queue_ms: 0, provider_ms: 10, total_ms: 10 },
    },
    recordedAt: "2026-08-05T00:00:00.000Z",
  };
}

describe("adapter malformed body rejection (T25)", () => {
  const workers: Unstable_DevWorker[] = [];

  afterEach(async () => {
    await Promise.all(workers.splice(0).map((worker) => worker.stop()));
  });

  it("rejects a malformed body without producing a taxonomy-coded error body or bare 400", async () => {
    const worker = await unstable_dev(SCRIPT_PATH, {
      ...DEV_OPTIONS,
      config: CONFIG_PATH,
      env: "development",
    });
    workers.push(worker);

    const response = await worker.fetch("http://127.0.0.1/v1/requests", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: "{not-valid-json",
    });

    expect(response.status).not.toBe(404);
    expect(response.status).not.toBe(400);

    const text = await response.text();
    let parsed: unknown = text;
    try {
      parsed = JSON.parse(text);
    } catch {
      parsed = text;
    }

    if (parsed && typeof parsed === "object" && "code" in parsed) {
      const code = (parsed as { code?: string }).code;
      const taxonomyCodes = new Set([
        "unauthenticated",
        "installation_suspended",
        "forbidden_capability",
        "rate_limited",
        "quota_exhausted",
        "request_too_large",
        "context_required",
        "context_invalid",
        "conversation_budget_exhausted",
        "capability_unknown",
        "capability_retired",
        "capability_disabled",
        "provider_unavailable",
        "provider_rejected",
        "validation_failed",
        "cancelled",
        "timeout",
        "internal_error",
      ]);
      expect(taxonomyCodes.has(code ?? "")).toBe(false);
    }
  }, 30_000);
});

describe("structured log redaction (T27)", () => {
  it("never logs prompt text, context payload, or credentials on a forced stage-16 failure path", async () => {
    const capturedLines: string[] = [];
    const logger = createLogger({
      file: "journal/index.ts",
      verbosity: 0,
      sink: { write: (line) => capturedLines.push(line) },
    });

    const failingDb = {
      prepare() {
        throw new Error("injected stage-16 D1 failure");
      },
      async batch() {
        throw new Error("injected stage-16 D1 failure");
      },
    } as unknown as D1Database;

    const failingR2 = {
      async put() {
        throw new Error("injected stage-16 R2 failure");
      },
    } as unknown as R2Bucket;

    const ctx = createFakeCtx();
    writePostResponseDetail(
      buildSensitivePostResponseInput(),
      {
        db: failingDb,
        r2: failingR2,
        ctx,
      },
      logger,
    );
    await ctx.drainWaitUntil();

    const serializedLogs = capturedLines.join("\n");

    // Canary: a real worker failure-path log site was captured (not wrangler noise).
    expect(serializedLogs).toContain(STAGE16_FAILURE_CANARY);
    expect(capturedLines.length).toBeGreaterThan(0);

    expect(serializedLogs).not.toContain(SENSITIVE_PROMPT);
    expect(serializedLogs).not.toContain(SENSITIVE_CONTEXT);
    expect(serializedLogs).not.toContain(SENSITIVE_CREDENTIAL);
  });
});
