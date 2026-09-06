import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import {
  CACHE_TTL_MS,
  ConfigCache,
  ConfigCacheMissError,
  DEFAULT_CONFIG_CACHE_TTL_MS,
  configureIsolateConfigCache,
  isolateConfigCache,
  loadConfig,
  resolveConfigCacheTtlMs,
  type ConfigEntityKind,
  type D1Reader,
} from "../src/config-cache";
import { collectKilledProviderIds } from "../src/router";

const ROOT = path.join(path.dirname(fileURLToPath(import.meta.url)), "..");
const WRANGLER_PATH = path.join(ROOT, "wrangler.toml");
const TEST_INSTALLATION_KEY = "installation:test-001";

const CACHED_ENTITY_KINDS = [
  "installations",
  "keys",
  "entitlements",
  "grants",
  "kill_switches",
  "active_routing_policy",
] as const satisfies readonly ConfigEntityKind[];

type D1Row = Record<string, unknown>;

type ReaderSource =
  | D1Row
  | "miss"
  | Record<string, D1Row | "miss">
  | (() => D1Row | "miss");

export type ReaderSpy = D1Reader & {
  read: ReturnType<typeof vi.fn<(key: string) => Promise<D1Row | "miss">>>;
  readCount: () => number;
};

/** T019 — D1Reader spy substrate (Clarification Q3). */
export function makeReader(source: ReaderSource): ReaderSpy {
  const read = vi.fn(async (key: string): Promise<D1Row | "miss"> => {
    if (source === "miss") {
      return "miss";
    }
    if (typeof source === "function") {
      return source();
    }
    if (key in source) {
      return source[key];
    }
    return source as D1Row;
  });

  return {
    read,
    readCount: () => read.mock.calls.length,
  };
}

function sampleRow(kind: ConfigEntityKind): D1Row {
  return { kind, installationId: TEST_INSTALLATION_KEY, value: `${kind}-row` };
}

async function warmEntry(
  cache: ConfigCache,
  reader: ReaderSpy,
  kind: ConfigEntityKind,
  key: string = TEST_INSTALLATION_KEY,
): Promise<void> {
  await loadConfig(cache, reader, kind, key);
  reader.read.mockClear();
}

describe("resolveConfigCacheTtlMs", () => {
  it("defaults to 30_000 when unset or invalid", () => {
    expect(resolveConfigCacheTtlMs(undefined)).toBe(DEFAULT_CONFIG_CACHE_TTL_MS);
    expect(resolveConfigCacheTtlMs("")).toBe(DEFAULT_CONFIG_CACHE_TTL_MS);
    expect(resolveConfigCacheTtlMs("nope")).toBe(DEFAULT_CONFIG_CACHE_TTL_MS);
    expect(resolveConfigCacheTtlMs("-1")).toBe(DEFAULT_CONFIG_CACHE_TTL_MS);
  });

  it("parses wrangler string vars", () => {
    expect(resolveConfigCacheTtlMs("0")).toBe(0);
    expect(resolveConfigCacheTtlMs("5000")).toBe(5000);
  });
});

describe("configureIsolateConfigCache", () => {
  afterEach(() => {
    configureIsolateConfigCache(DEFAULT_CONFIG_CACHE_TTL_MS);
    isolateConfigCache.clear();
  });

  it("updates isolate TTL used by remember()", () => {
    configureIsolateConfigCache(5_000);
    expect(isolateConfigCache.getTtlMs()).toBe(5_000);
    const cache = new ConfigCache(1_000);
    expect(cache.getTtlMs()).toBe(1_000);
  });
});

describe("T-A5-17 config_cache_cold_isolate_one_d1_read", () => {
  it("performs exactly one reader.read on a cold cache miss", async () => {
    const cache = new ConfigCache();
    const reader = makeReader(sampleRow("installations"));

    await loadConfig(cache, reader, "installations", TEST_INSTALLATION_KEY);

    expect(reader.readCount()).toBe(1);
  });
});

describe("T-A5-18 config_cache_warm_isolate_zero_io", () => {
  it("performs zero reader.read when the entry is already warm", async () => {
    const cache = new ConfigCache();
    const reader = makeReader(sampleRow("installations"));

    await warmEntry(cache, reader, "installations");
    await loadConfig(cache, reader, "installations", TEST_INSTALLATION_KEY);

    expect(reader.readCount()).toBe(0);
  });
});

describe("T-A5-19 config_cache_ttl_expiry_one_refetch", () => {
  beforeEach(() => {
    vi.useFakeTimers();
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  it("triggers exactly one reader.read after TTL expiry", async () => {
    const cache = new ConfigCache();
    const reader = makeReader(sampleRow("installations"));

    await loadConfig(cache, reader, "installations", TEST_INSTALLATION_KEY);
    expect(reader.readCount()).toBe(1);
    reader.read.mockClear();

    await loadConfig(cache, reader, "installations", TEST_INSTALLATION_KEY);
    expect(reader.readCount()).toBe(0);

    vi.advanceTimersByTime(CACHE_TTL_MS + 1);
    await loadConfig(cache, reader, "installations", TEST_INSTALLATION_KEY);

    expect(reader.readCount()).toBe(1);
  });

  it("TTL 0 still serves a same-timestamp consult after remember", () => {
    const cache = new ConfigCache(0);
    const now = 1_000;
    const row = sampleRow("installations");
    cache.remember("installations", TEST_INSTALLATION_KEY, row, now);

    expect(cache.consult("installations", TEST_INSTALLATION_KEY, now)).toEqual(
      row,
    );
    expect(
      cache.consult("installations", TEST_INSTALLATION_KEY, now + 1),
    ).toBeUndefined();
  });

  it("positive TTL remains live at expiresAt and misses on the next millisecond", () => {
    const cache = new ConfigCache(30_000);
    const row = sampleRow("installations");
    cache.remember("installations", TEST_INSTALLATION_KEY, row, 0);

    expect(cache.consult("installations", TEST_INSTALLATION_KEY, 30_000)).toEqual(
      row,
    );
    expect(
      cache.consult("installations", TEST_INSTALLATION_KEY, 30_001),
    ).toBeUndefined();
  });

  it("TTL 0 loadConfig hits on the same tick and refetches after the clock ticks", async () => {
    const cache = new ConfigCache(0);
    const reader = makeReader(sampleRow("installations"));

    await loadConfig(cache, reader, "installations", TEST_INSTALLATION_KEY);
    expect(reader.readCount()).toBe(1);
    reader.read.mockClear();

    await loadConfig(cache, reader, "installations", TEST_INSTALLATION_KEY);
    expect(reader.readCount()).toBe(0);

    vi.advanceTimersByTime(1);
    await loadConfig(cache, reader, "installations", TEST_INSTALLATION_KEY);
    expect(reader.readCount()).toBe(1);
  });
});

describe("T-A5-20 config_cache_entity_kind_<kind>", () => {
  for (const kind of CACHED_ENTITY_KINDS) {
    describe(kind, () => {
      it("answers from warm isolate memory with zero reader.read", async () => {
        const cache = new ConfigCache();
        const reader = makeReader(sampleRow(kind));

        await warmEntry(cache, reader, kind);
        await loadConfig(cache, reader, kind, TEST_INSTALLATION_KEY);

        expect(reader.readCount()).toBe(0);
      });
    });
  }
});

describe("T-A5-21 config_cache_d1_miss_typed_failure", () => {
  it("throws a typed failure on miss and does not cache an empty entry", async () => {
    const cache = new ConfigCache();
    const missReader = makeReader("miss");

    await expect(
      loadConfig(cache, missReader, "installations", TEST_INSTALLATION_KEY),
    ).rejects.toBeInstanceOf(ConfigCacheMissError);
    expect(missReader.readCount()).toBe(1);

    const hitReader = makeReader(sampleRow("installations"));
    await loadConfig(cache, hitReader, "installations", TEST_INSTALLATION_KEY);

    expect(hitReader.readCount()).toBe(1);
  });
});

describe("T-A5-21b config_cache_cold_load_single_flight", () => {
  it("coalesces concurrent cold loads for the same kind+key into one reader.read", async () => {
    let resolveRead!: (row: D1Row) => void;
    const pending = new Promise<D1Row>((resolve) => {
      resolveRead = resolve;
    });
    const read = vi.fn(async (): Promise<D1Row | "miss"> => pending);
    const reader: ReaderSpy = {
      read,
      readCount: () => read.mock.calls.length,
    };
    const cache = new ConfigCache();
    const row = sampleRow("installations");

    const first = loadConfig(cache, reader, "installations", TEST_INSTALLATION_KEY);
    const second = loadConfig(cache, reader, "installations", TEST_INSTALLATION_KEY);

    expect(reader.readCount()).toBe(1);
    resolveRead(row);

    const [a, b] = await Promise.all([first, second]);
    expect(a).toEqual(row);
    expect(b).toEqual(row);
    expect(reader.readCount()).toBe(1);

    reader.read.mockClear();
    const warm = await loadConfig(
      cache,
      reader,
      "installations",
      TEST_INSTALLATION_KEY,
    );
    expect(reader.readCount()).toBe(0);
    expect(warm).toEqual(row);
  });
});

describe("T-A5-22 config_cache_owns_nothing", () => {
  beforeEach(() => {
    vi.useFakeTimers();
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  it("observes D1 updates after TTL without a cache flush", async () => {
    let currentRow: D1Row = { installationId: TEST_INSTALLATION_KEY, status: "active" };
    const cache = new ConfigCache();
    const reader = makeReader(() => currentRow);

    const first = await loadConfig(
      cache,
      reader,
      "installations",
      TEST_INSTALLATION_KEY,
    );
    expect(first.status).toBe("active");
    expect(reader.readCount()).toBe(1);
    reader.read.mockClear();

    currentRow = { installationId: TEST_INSTALLATION_KEY, status: "suspended" };
    vi.advanceTimersByTime(CACHE_TTL_MS + 1);

    const second = await loadConfig(
      cache,
      reader,
      "installations",
      TEST_INSTALLATION_KEY,
    );

    expect(reader.readCount()).toBe(1);
    expect(second.status).toBe("suspended");

    reader.read.mockClear();
    const warm = await loadConfig(
      cache,
      reader,
      "installations",
      TEST_INSTALLATION_KEY,
    );
    expect(reader.readCount()).toBe(0);
    expect(warm.status).toBe("suspended");

    (warm as { status: string }).status = "mutated";
    reader.read.mockClear();
    const again = await loadConfig(
      cache,
      reader,
      "installations",
      TEST_INSTALLATION_KEY,
    );
    expect(reader.readCount()).toBe(0);
    expect(again.status).toBe("suspended");
  });
});

describe("T-A5-23 config_cache_uses_in_isolate_memory_not_kv", () => {
  it("exports no KV surface and wrangler.toml has no KV binding", async () => {
    const moduleExports = await import("../src/config-cache");

    for (const exportName of Object.keys(moduleExports)) {
      expect(exportName.toLowerCase()).not.toMatch(/kv/);
    }

    const wrangler = fs.readFileSync(WRANGLER_PATH, "utf8");
    expect(wrangler).not.toMatch(/\[\[.*kv_namespaces.*\]\]/i);
    expect(wrangler).not.toMatch(/binding\s*=\s*"KV"/i);
  });

  it("declares the three FR-006 Rate Limiting bindings in wrangler.toml", () => {
    const wrangler = fs.readFileSync(WRANGLER_PATH, "utf8");
    expect(wrangler).toContain('name = "RATE_LIMITER_INSTALLATION"');
    expect(wrangler).toContain('name = "RATE_LIMITER_INSTALLATION_ACTOR"');
    expect(wrangler).toContain('name = "RATE_LIMITER_INSTALLATION_CAPABILITY"');
  });
});

describe("T-B3 worker_scheduled_flushes_rejection_counters", () => {
  it("worker scheduled handler imports and calls flushRejectionCounters", () => {
    const worker = fs.readFileSync(path.join(ROOT, "src/worker.ts"), "utf8");
    expect(worker).toContain('from "./rate-limit"');
    expect(worker).toContain("flushRejectionCounters");
    expect(worker).toMatch(/async scheduled\([\s\S]*flushRejectionCounters/);
  });
});

describe("T-A5-24 no_per_request_state_introduced", () => {
  it("exports only installation-scoped cache API without per-request handles", async () => {
    const moduleExports = await import("../src/config-cache");
    const exportNames = Object.keys(moduleExports).sort();

    const allowedRuntimeExports = [
      "CACHE_TTL_MS",
      "ConfigCache",
      "ConfigCacheMissError",
      "DEFAULT_CONFIG_CACHE_TTL_MS",
      "configureIsolateConfigCache",
      "createD1ConfigReader",
      "isolateConfigCache",
      "loadConfig",
      "resolveConfigCacheTtlMs",
    ].sort();

    expect(exportNames).toEqual(allowedRuntimeExports);

    for (const exportName of exportNames) {
      expect(exportName.toLowerCase()).not.toMatch(/request/);
      expect(exportName.toLowerCase()).not.toMatch(/session/);
      expect(exportName.toLowerCase()).not.toMatch(/handle/);
    }
  });
});

describe("T-5.5 config_cache_isolate_scoped_ttl", () => {
  const isolateKey = "installation:isolate-ttl-5-5";
  const killedProviderId = "isolate-killed-provider-5-5";

  it("exports one ConfigCache instance per isolate, not a per-request constructor", () => {
    expect(isolateConfigCache).toBeInstanceOf(ConfigCache);
    expect(isolateConfigCache).toBe(isolateConfigCache);
  });

  it("dedupes D1 across sequential lookups on the isolate cache within the 30 s TTL", async () => {
    const reader = makeReader(sampleRow("installations"));

    await loadConfig(isolateConfigCache, reader, "installations", isolateKey);
    expect(reader.readCount()).toBe(1);
    reader.read.mockClear();

    await loadConfig(isolateConfigCache, reader, "installations", isolateKey);
    expect(reader.readCount()).toBe(0);
  });

  it("lets the router kill-switch consult hit warm isolate entries", () => {
    isolateConfigCache.remember("kill_switches", `provider:${killedProviderId}`, {
      active: true,
      scope: "provider",
      target: killedProviderId,
    });

    const killed = collectKilledProviderIds(isolateConfigCache, [
      killedProviderId,
      "gemini",
    ]);
    expect(killed).toEqual([killedProviderId]);
  });

  it("clear() drops warm entries so the next lookup refetches D1", async () => {
    const reader = makeReader(sampleRow("installations"));
    const key = "installation:isolate-clear-5-5";

    await loadConfig(isolateConfigCache, reader, "installations", key);
    expect(reader.readCount()).toBe(1);
    reader.read.mockClear();

    isolateConfigCache.clear();
    await loadConfig(isolateConfigCache, reader, "installations", key);
    expect(reader.readCount()).toBe(1);
  });

  it("does not construct a per-request ConfigCache on production POST, GET, invoke, or discovery paths", () => {
    const worker = fs.readFileSync(path.join(ROOT, "src/worker.ts"), "utf8");
    const journal = fs.readFileSync(path.join(ROOT, "src/journal/index.ts"), "utf8");
    const discovery = fs.readFileSync(
      path.join(ROOT, "src/discovery/index.ts"),
      "utf8",
    );

    expect(worker).toContain("isolateConfigCache");
    expect(worker).not.toMatch(/new ConfigCache\s*\(/);
    expect(journal).toContain("isolateConfigCache");
    expect(journal).not.toMatch(/new ConfigCache\s*\(/);
    expect(discovery).toContain("isolateConfigCache");
    expect(discovery).not.toMatch(/new ConfigCache\s*\(/);
  });
});
