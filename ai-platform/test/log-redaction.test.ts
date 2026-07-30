import path from "node:path";
import { fileURLToPath } from "node:url";
import { unstable_dev, type Unstable_DevWorker } from "wrangler";
import { afterEach, describe, expect, it, vi } from "vitest";

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
  const workers: Unstable_DevWorker[] = [];
  const logSpy = vi.spyOn(console, "log");

  afterEach(async () => {
    logSpy.mockRestore();
    await Promise.all(workers.splice(0).map((worker) => worker.stop()));
  });

  it("never logs prompt text, context payload, or credentials from a request that contained them", async () => {
    const worker = await unstable_dev(SCRIPT_PATH, {
      ...DEV_OPTIONS,
      config: CONFIG_PATH,
      env: "development",
    });
    workers.push(worker);

    await worker.fetch("http://127.0.0.1/v1/requests", {
      method: "POST",
      headers: {
        "content-type": "application/json",
        authorization: `Bearer ${SENSITIVE_CREDENTIAL}`,
        "x-trace-id": "01ARZ3NDEKTSV4RRFFQ69G5FAV",
      },
      body: JSON.stringify({
        prompt: SENSITIVE_PROMPT,
        context: { note: SENSITIVE_CONTEXT },
        capability: "demo-capability",
        installation: "demo-installation",
      }),
    });

    const serializedLogs = logSpy.mock.calls
      .flat()
      .map((value) =>
        typeof value === "string" ? value : JSON.stringify(value),
      )
      .join("\n");

    expect(logSpy.mock.calls.length).toBeGreaterThan(0);
    expect(serializedLogs).not.toContain(SENSITIVE_PROMPT);
    expect(serializedLogs).not.toContain(SENSITIVE_CONTEXT);
    expect(serializedLogs).not.toContain(SENSITIVE_CREDENTIAL);
  }, 30_000);
});
