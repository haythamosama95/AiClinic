import { env } from "./env";

export type RateLimiterOutcome = {
  success: boolean;
  retryAfter?: number;
};

/**
 * Doubled CF `RateLimit` binding (Register 5 #31).
 * `{ success: false }` without `retryAfter` exercises the fallback-to-60 path.
 */
export function createRateLimiterDouble(
  outcome:
    | RateLimiterOutcome
    | ((key: string) => RateLimiterOutcome | Promise<RateLimiterOutcome>),
): RateLimit {
  return {
    async limit(options: { key: string }): Promise<RateLimitOutcome> {
      const result =
        typeof outcome === "function" ? await outcome(options.key) : outcome;
      return result as RateLimitOutcome;
    },
  };
}

export function allowAllRateLimiter(): RateLimit {
  return createRateLimiterDouble({ success: true });
}

export type D1FaultConfig = {
  /** Register 5 #19 — `batch()` throws a non-constraint error → `storage_error`. */
  batchThrow?: Error | (() => Error);
  /** Register 5 #10 — `batch()` throws UNIQUE constraint. */
  batchUniqueThrow?: Error;
  /** Throw from `prepare(sql)` when `sql` matches. */
  prepareThrow?: { match: RegExp; error: Error | (() => Error) };
  /** Throw from `statement.run()` when the originating SQL matches (Register 5 #29). */
  runThrow?: { match: RegExp; error: Error | (() => Error) };
  /** Throw from `exec()`. */
  execThrow?: Error | (() => Error);
};

function resolveError(error: Error | (() => Error)): Error {
  return typeof error === "function" ? error() : error;
}

function wrapStatement(
  statement: D1PreparedStatement,
  sql: string,
  faults: D1FaultConfig,
): D1PreparedStatement {
  return new Proxy(statement, {
    get(target, prop, receiver) {
      if (prop === "bind") {
        return (...values: unknown[]) =>
          wrapStatement(target.bind(...values), sql, faults);
      }
      if (prop === "run" && faults.runThrow?.match.test(sql)) {
        return async () => {
          throw resolveError(faults.runThrow!.error);
        };
      }
      const value = Reflect.get(target, prop, receiver);
      return typeof value === "function" ? value.bind(target) : value;
    },
  });
}

/** Fault-injecting `D1Database` proxy (Register 5 #19, #28, #29). */
export function wrapD1(db: D1Database, faults: D1FaultConfig): D1Database {
  return new Proxy(db, {
    get(target, prop, receiver) {
      if (prop === "batch") {
        return async (statements: D1PreparedStatement[]) => {
          if (faults.batchThrow) {
            throw resolveError(faults.batchThrow);
          }
          if (faults.batchUniqueThrow) {
            throw faults.batchUniqueThrow;
          }
          return target.batch(statements);
        };
      }
      if (prop === "prepare") {
        return (sql: string) => {
          if (faults.prepareThrow?.match.test(sql)) {
            throw resolveError(faults.prepareThrow.error);
          }
          return wrapStatement(target.prepare(sql), sql, faults);
        };
      }
      if (prop === "exec" && faults.execThrow) {
        return async (_query: string) => {
          throw resolveError(faults.execThrow!);
        };
      }
      const value = Reflect.get(target, prop, receiver);
      return typeof value === "function" ? value.bind(target) : value;
    },
  });
}

export type DoFetchScript =
  | { status: number; body?: unknown; throw?: Error }
  | ((request: Request) => Response | Promise<Response>);

export type DoNamespaceFaultConfig = {
  /** Register 5 #28 — stub.fetch throws (DO unavailable). */
  fetchThrow?: Error | (() => Error);
  /** Scripted Response instead of (or before) the real stub. */
  scriptedFetch?: DoFetchScript;
  /**
   * When true (default if `scriptedFetch`/`fetchThrow` unset), fall through
   * to the real namespace after fault hooks.
   */
  passthrough?: boolean;
};

function scriptedToResponse(script: DoFetchScript, request: Request): Promise<Response> {
  if (typeof script === "function") {
    return Promise.resolve(script(request));
  }
  if (script.throw) {
    return Promise.reject(script.throw);
  }
  const body =
    script.body === undefined
      ? null
      : typeof script.body === "string"
        ? script.body
        : JSON.stringify(script.body);
  return Promise.resolve(
    new Response(body, {
      status: script.status,
      headers: { "content-type": "application/json" },
    }),
  );
}

function wrapStub(
  stub: DurableObjectStub,
  faults: DoNamespaceFaultConfig,
): DurableObjectStub {
  return new Proxy(stub, {
    get(target, prop, receiver) {
      if (prop === "fetch") {
        return async (input: RequestInfo | URL, init?: RequestInit) => {
          if (faults.fetchThrow) {
            throw resolveError(faults.fetchThrow);
          }
          const request =
            input instanceof Request
              ? input
              : new Request(input, init);
          if (faults.scriptedFetch) {
            return scriptedToResponse(faults.scriptedFetch, request);
          }
          return target.fetch(input as never, init);
        };
      }
      const value = Reflect.get(target, prop, receiver);
      return typeof value === "function" ? value.bind(target) : value;
    },
  });
}

/**
 * Facade around `DurableObjectNamespace` (Register 5 #28).
 * `idFromName` still uses the real ids so passthrough hits the same object.
 */
export function wrapDurableObjectNamespace(
  ns: DurableObjectNamespace,
  faults: DoNamespaceFaultConfig,
): DurableObjectNamespace {
  return new Proxy(ns, {
    get(target, prop, receiver) {
      if (prop === "get") {
        return (id: DurableObjectId) => wrapStub(target.get(id), faults);
      }
      const value = Reflect.get(target, prop, receiver);
      return typeof value === "function" ? value.bind(target) : value;
    },
  });
}

export type DoStorageFaultConfig = {
  getThrow?: Error | (() => Error);
  putThrow?: Error | (() => Error);
  deleteThrow?: Error | (() => Error);
};

/**
 * DO `storage` double (Register 5 #45). Pass into `admissionRPC` /
 * `creditRPC` / `releaseRPC` — the in-pool GatewayObject cannot take
 * injected storage.
 */
export function wrapDoStorage(
  storage: DurableObjectStorage,
  faults: DoStorageFaultConfig,
): DurableObjectStorage {
  return new Proxy(storage, {
    get(target, prop, receiver) {
      if (prop === "get" && faults.getThrow) {
        return async () => {
          throw resolveError(faults.getThrow!);
        };
      }
      if (prop === "put" && faults.putThrow) {
        return async () => {
          throw resolveError(faults.putThrow!);
        };
      }
      if (prop === "delete" && faults.deleteThrow) {
        return async () => {
          throw resolveError(faults.deleteThrow!);
        };
      }
      const value = Reflect.get(target, prop, receiver);
      return typeof value === "function" ? value.bind(target) : value;
    },
  });
}

export type EnvBindingOverrides = {
  DB?: D1Database;
  DO?: DurableObjectNamespace;
  R2?: R2Bucket;
  RATE_LIMITER_INSTALLATION?: RateLimit;
  RATE_LIMITER_INSTALLATION_ACTOR?: RateLimit;
  RATE_LIMITER_INSTALLATION_CAPABILITY?: RateLimit;
};

function assignEnvBinding(key: string, value: unknown): unknown {
  const target = env as unknown as Record<string, unknown>;
  const previous = target[key];
  try {
    target[key] = value;
    if (target[key] === value) {
      return previous;
    }
  } catch {
    // fall through to defineProperty
  }
  try {
    Object.defineProperty(target, key, {
      configurable: true,
      enumerable: true,
      writable: true,
      value,
    });
    if (target[key] === value) {
      return previous;
    }
  } catch {
    // fall through
  }
  throw new Error(
    `Cannot override env.${key}: binding is not writable. Use dispatchControl() / invokeCron() / wrapDurableObjectNamespace() with explicit bindings instead of SELF.fetch.`,
  );
}

/**
 * Attempt to replace pool `env` bindings for a subsequent `SELF.fetch`.
 * Production `worker.fetch` reads `env` from `cloudflare:workers` at request
 * time (not the unused `_bindings` argument). Restore in `afterEach`.
 *
 * If the pool freezes a binding, this throws — then pass the wrapper into
 * `dispatchControl` / `invokeCron` / `gatewayObjectRpc({ namespace })`.
 */
export function installEnvOverrides(
  overrides: EnvBindingOverrides,
): () => void {
  const saved: Array<[string, unknown]> = [];
  for (const [key, value] of Object.entries(overrides)) {
    if (value === undefined) {
      continue;
    }
    const previous = assignEnvBinding(key, value);
    saved.push([key, previous]);
  }
  return () => {
    for (const [key, previous] of saved) {
      assignEnvBinding(key, previous);
    }
  };
}

export function uniqueConstraintError(
  target: "installation" | "installation_key" | "other" = "installation",
): Error {
  if (target === "installation_key") {
    return new Error("UNIQUE constraint failed: installation_key.key_id");
  }
  if (target === "installation") {
    return new Error("UNIQUE constraint failed: installation.installation_id");
  }
  return new Error("UNIQUE constraint failed");
}

export function diskIoError(): Error {
  return new Error("disk I/O error");
}
