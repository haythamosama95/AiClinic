/**
 * Counting spies wrapping D1 / R2 / Quota DO bindings under workers-pool Miniflare.
 *
 * Counts execute at run/batch (D1) and Class A op time (R2), not at prepare.
 * Request/installation tagging supports per-request maxima under load.
 *
 * Request scope uses AsyncLocalStorage so Promise.all concurrency does not
 * overwrite a shared mutable active-request id.
 */

import { AsyncLocalStorage } from "node:async_hooks";

export type D1Spy = D1Database & {
  hotPathWriteCount: () => number;
  resetCounts: () => void;
};

export type R2Spy = R2Bucket & {
  /** PutObject calls only (backward-compatible). */
  putCallCount: () => number;
  putKeys: () => string[];
  /** Class A ops: put + list + multipart create/upload/complete. */
  classAOpCount: () => number;
  classAOpsPerRequest: () => ReadonlyMap<string, number>;
  maxR2ClassAOpsPerRequest: () => number;
  beginRequest: (requestId: string) => void;
  endRequest: (requestId?: string) => void;
  withRequest: <T>(requestId: string, fn: () => T | Promise<T>) => Promise<T>;
  activeRequestId: () => string | null;
  resetCounts: () => void;
};

export type DoFetchTiming = {
  installationId: string | null;
  requestId: string | null;
  durationMs: number;
};

export type DoSpy = DurableObjectNamespace & {
  fetchCount: () => number;
  fetchesPerRequest: () => ReadonlyMap<string, number>;
  maxDoFetchesPerRequest: () => number;
  fetchesPerInstallation: () => ReadonlyMap<string, number>;
  installationFetchCount: (installationId: string) => number;
  fetchTimings: () => readonly DoFetchTiming[];
  beginRequest: (requestId: string) => void;
  endRequest: (requestId?: string) => void;
  withRequest: <T>(requestId: string, fn: () => T | Promise<T>) => Promise<T>;
  activeRequestId: () => string | null;
  resetCounts: () => void;
};

export type BindingSpies = {
  db: D1Spy;
  r2: R2Spy;
  do: DoSpy;
};

/** Hot-path write = stage-9 request-row INSERT only (terminal UPDATEs are post-guard). */
const HOT_PATH_WRITE = /^insert\s+into\s+ai_request\b/;

const ENVELOPE_KEY = /^request\/([^/]+)\/envelope$/;

function normalizeSql(sql: string): string {
  return sql.replace(/\s+/g, " ").trim().toLowerCase();
}

function isHotPathWrite(sql: string): boolean {
  return HOT_PATH_WRITE.test(normalizeSql(sql));
}

function maxMapValue(counts: ReadonlyMap<string, number>): number {
  let max = 0;
  for (const value of counts.values()) {
    if (value > max) {
      max = value;
    }
  }
  return max;
}

function incrementMap(counts: Map<string, number>, key: string, by = 1): void {
  counts.set(key, (counts.get(key) ?? 0) + by);
}

/** Shared across R2 and DO spies so nested withRequest tags the same context. */
const requestIdAls = new AsyncLocalStorage<string>();

function createRequestScope() {
  return {
    beginRequest(requestId: string): void {
      requestIdAls.enterWith(requestId);
    },
    endRequest(_requestId?: string): void {
      // ALS exits via withRequest's run(); enterWith has no paired clear.
    },
    activeRequestId(): string | null {
      return requestIdAls.getStore() ?? null;
    },
    async withRequest<T>(requestId: string, fn: () => T | Promise<T>): Promise<T> {
      return await requestIdAls.run(requestId, fn);
    },
  };
}

function createProxyWithExtras<T extends object, E extends object>(
  target: T,
  extras: E,
): T & E {
  return new Proxy(target, {
    get(obj, prop, receiver) {
      if (prop in extras) {
        const value = Reflect.get(extras, prop as PropertyKey, extras);
        return typeof value === "function" ? (value as Function).bind(extras) : value;
      }
      const value = Reflect.get(obj, prop, receiver);
      return typeof value === "function" ? (value as Function).bind(obj) : value;
    },
    has(obj, prop) {
      return prop in extras || Reflect.has(obj, prop);
    },
  }) as T & E;
}

export function createD1Spy(realDb: D1Database): D1Spy {
  let hotPathWrites = 0;
  const statementSql = new WeakMap<object, string>();
  const wrappedToReal = new WeakMap<object, D1PreparedStatement>();

  const countIfWrite = (sql: string): void => {
    if (isHotPathWrite(sql)) {
      hotPathWrites += 1;
    }
  };

  const wrapStatement = (real: D1PreparedStatement, sql: string): D1PreparedStatement => {
    // Count only at run()/batch() execution — not prepare, first, all, or raw.
    const wrapped = {
      bind(...values: unknown[]) {
        return wrapStatement(real.bind(...values), sql);
      },
      first(colName?: string) {
        return colName === undefined ? real.first() : real.first(colName);
      },
      run() {
        countIfWrite(sql);
        return real.run();
      },
      all() {
        return real.all();
      },
      raw(options?: { columnNames?: boolean }) {
        if (options?.columnNames === true) {
          return real.raw({ columnNames: true });
        }
        return real.raw();
      },
    } as D1PreparedStatement;

    statementSql.set(wrapped, sql);
    statementSql.set(real, sql);
    wrappedToReal.set(wrapped, real);
    return wrapped;
  };

  const extras = {
    prepare(query: string) {
      return wrapStatement(realDb.prepare(query), query);
    },
    batch<T = unknown>(statements: D1PreparedStatement[]) {
      for (const statement of statements) {
        const sql = statementSql.get(statement);
        if (sql !== undefined) {
          countIfWrite(sql);
        }
      }
      const realStatements = statements.map(
        (statement) => wrappedToReal.get(statement) ?? statement,
      );
      return realDb.batch<T>(realStatements);
    },
    hotPathWriteCount() {
      return hotPathWrites;
    },
    resetCounts() {
      hotPathWrites = 0;
    },
  };

  return createProxyWithExtras(realDb, extras);
}

function requestIdFromR2Key(key: string): string | null {
  const match = ENVELOPE_KEY.exec(key);
  return match?.[1] ?? null;
}

function wrapMultipartUpload(
  real: R2MultipartUpload,
  recordClassA: (requestId: string | null) => void,
  resolveRequestId: () => string | null,
): R2MultipartUpload {
  return {
    get key() {
      return real.key;
    },
    get uploadId() {
      return real.uploadId;
    },
    async uploadPart(partNumber, value, options) {
      recordClassA(resolveRequestId() ?? requestIdFromR2Key(real.key));
      return real.uploadPart(partNumber, value, options);
    },
    async abort() {
      return real.abort();
    },
    async complete(uploadedParts) {
      recordClassA(resolveRequestId() ?? requestIdFromR2Key(real.key));
      return real.complete(uploadedParts);
    },
  };
}

export function createR2Spy(realR2: R2Bucket): R2Spy {
  const putKeys: string[] = [];
  let classAOps = 0;
  const perRequest = new Map<string, number>();
  const scope = createRequestScope();

  const recordClassA = (requestId: string | null): void => {
    classAOps += 1;
    if (requestId !== null) {
      incrementMap(perRequest, requestId);
    }
  };

  const resolveRequestId = (key?: string): string | null =>
    scope.activeRequestId() ?? (key !== undefined ? requestIdFromR2Key(key) : null);

  const extras = {
    async put(
      key: string,
      value: ReadableStream | ArrayBuffer | ArrayBufferView | string | null | Blob,
      options?: R2PutOptions,
    ) {
      putKeys.push(key);
      recordClassA(resolveRequestId(key));
      return realR2.put(key, value, options);
    },
    async list(options?: R2ListOptions) {
      recordClassA(scope.activeRequestId());
      return realR2.list(options);
    },
    async createMultipartUpload(key: string, options?: R2MultipartOptions) {
      recordClassA(resolveRequestId(key));
      const upload = await realR2.createMultipartUpload(key, options);
      return wrapMultipartUpload(upload, recordClassA, () => resolveRequestId(key));
    },
    resumeMultipartUpload(key: string, uploadId: string) {
      const upload = realR2.resumeMultipartUpload(key, uploadId);
      return wrapMultipartUpload(upload, recordClassA, () => resolveRequestId(key));
    },
    putCallCount() {
      return putKeys.length;
    },
    putKeys() {
      return [...putKeys];
    },
    classAOpCount() {
      return classAOps;
    },
    classAOpsPerRequest() {
      return new Map(perRequest);
    },
    maxR2ClassAOpsPerRequest() {
      return maxMapValue(perRequest);
    },
    beginRequest: scope.beginRequest,
    endRequest: scope.endRequest,
    withRequest: scope.withRequest,
    activeRequestId: scope.activeRequestId,
    resetCounts() {
      putKeys.length = 0;
      classAOps = 0;
      perRequest.clear();
      scope.endRequest();
    },
  };

  return createProxyWithExtras(realR2, extras);
}

function peekRequestTagFromInit(init?: RequestInit): string | null {
  const body = init?.body;
  if (typeof body !== "string") {
    return null;
  }
  try {
    const parsed = JSON.parse(body) as {
      requestId?: unknown;
      requestReference?: unknown;
      idempotencyKey?: unknown;
    };
    if (typeof parsed.requestReference === "string") {
      return parsed.requestReference;
    }
    if (typeof parsed.requestId === "string") {
      return parsed.requestId;
    }
    if (typeof parsed.idempotencyKey === "string") {
      return parsed.idempotencyKey;
    }
    return null;
  } catch {
    return null;
  }
}

function installationFromId(id: DurableObjectId): string | null {
  return typeof id.name === "string" && id.name.length > 0 ? id.name : null;
}

export function createDoSpy(realDo: DurableObjectNamespace): DoSpy {
  let fetches = 0;
  const perRequest = new Map<string, number>();
  const perInstallation = new Map<string, number>();
  const timings: DoFetchTiming[] = [];
  const scope = createRequestScope();
  const idToInstallation = new Map<string, string>();

  const rememberId = (id: DurableObjectId, installationId?: string): DurableObjectId => {
    const name = installationId ?? installationFromId(id);
    if (name !== null) {
      idToInstallation.set(id.toString(), name);
    }
    return id;
  };

  const wrapStub = (stub: DurableObjectStub): DurableObjectStub => {
    const installationId =
      installationFromId(stub.id) ?? idToInstallation.get(stub.id.toString()) ?? null;

    const wrappedFetch = async (
      input: RequestInfo | URL,
      init?: RequestInit,
    ): Promise<Response> => {
      const requestId =
        scope.activeRequestId() ?? peekRequestTagFromInit(init) ?? null;

      fetches += 1;
      if (requestId !== null) {
        incrementMap(perRequest, requestId);
      }
      if (installationId !== null) {
        incrementMap(perInstallation, installationId);
      }

      const started = performance.now();
      try {
        return await stub.fetch(input, init);
      } finally {
        timings.push({
          installationId,
          requestId,
          durationMs: performance.now() - started,
        });
      }
    };

    return createProxyWithExtras(stub, { fetch: wrappedFetch });
  };

  const extras = {
    idFromName(name: string) {
      return rememberId(realDo.idFromName(name), name);
    },
    idFromString(id: string) {
      return rememberId(realDo.idFromString(id));
    },
    newUniqueId(options?: DurableObjectNamespaceNewUniqueIdOptions) {
      return rememberId(realDo.newUniqueId(options));
    },
    get(id: DurableObjectId, options?: DurableObjectNamespaceGetDurableObjectOptions) {
      rememberId(id);
      return wrapStub(realDo.get(id, options));
    },
    getByName(name: string, options?: DurableObjectNamespaceGetDurableObjectOptions) {
      const stub = realDo.getByName(name, options);
      rememberId(stub.id, name);
      return wrapStub(stub);
    },
    fetchCount() {
      return fetches;
    },
    fetchesPerRequest() {
      return new Map(perRequest);
    },
    maxDoFetchesPerRequest() {
      return maxMapValue(perRequest);
    },
    fetchesPerInstallation() {
      return new Map(perInstallation);
    },
    installationFetchCount(installationId: string) {
      return perInstallation.get(installationId) ?? 0;
    },
    fetchTimings() {
      return [...timings];
    },
    beginRequest: scope.beginRequest,
    endRequest: scope.endRequest,
    withRequest: scope.withRequest,
    activeRequestId: scope.activeRequestId,
    resetCounts() {
      fetches = 0;
      perRequest.clear();
      perInstallation.clear();
      timings.length = 0;
      idToInstallation.clear();
      scope.endRequest();
    },
  };

  return createProxyWithExtras(realDo, extras);
}

export function createBindingSpies(env: {
  DB: D1Database;
  R2: R2Bucket;
  DO: DurableObjectNamespace;
}): BindingSpies {
  return {
    db: createD1Spy(env.DB),
    r2: createR2Spy(env.R2),
    do: createDoSpy(env.DO),
  };
}
