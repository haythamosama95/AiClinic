/**
 * Counting spies wrapping D1 / R2 / Quota DO bindings under workers-pool Miniflare.
 */

export type D1Spy = D1Database & {
  hotPathWriteCount: () => number;
  resetCounts: () => void;
};

export type R2Spy = R2Bucket & {
  putCallCount: () => number;
  putKeys: () => string[];
  resetCounts: () => void;
};

export type DoSpy = DurableObjectNamespace & {
  fetchCount: () => number;
  resetCounts: () => void;
};

export type BindingSpies = {
  db: D1Spy;
  r2: R2Spy;
  do: DoSpy;
};

function normalizeSql(sql: string): string {
  return sql.replace(/\s+/g, " ").trim().toLowerCase();
}

export function createD1Spy(realDb: D1Database): D1Spy {
  let hotPathWrites = 0;

  const spy: D1Spy = {
    ...realDb,
    prepare(query: string) {
      const normalized = normalizeSql(query);
      if (normalized.startsWith("insert into ai_request")) {
        hotPathWrites += 1;
      }
      return realDb.prepare(query);
    },
    batch(statements: D1PreparedStatement[]) {
      return realDb.batch(statements);
    },
    hotPathWriteCount() {
      return hotPathWrites;
    },
    resetCounts() {
      hotPathWrites = 0;
    },
  };

  return spy;
}

export function createR2Spy(realR2: R2Bucket): R2Spy {
  const putKeys: string[] = [];

  const spy: R2Spy = {
    ...realR2,
    async put(
      key: string,
      value: ReadableStream | ArrayBuffer | ArrayBufferView | string | null | Blob,
      options?: R2PutOptions,
    ) {
      putKeys.push(key);
      return realR2.put(key, value, options);
    },
    putCallCount() {
      return putKeys.length;
    },
    putKeys() {
      return [...putKeys];
    },
    resetCounts() {
      putKeys.length = 0;
    },
  };

  return spy;
}

export function createDoSpy(realDo: DurableObjectNamespace): DoSpy {
  let fetchCount = 0;

  const spy = {
    idFromString: realDo.idFromString.bind(realDo),
    idFromName: realDo.idFromName?.bind(realDo),
    newUniqueId: realDo.newUniqueId?.bind(realDo),
    get: (id: DurableObjectId) => {
      const stub = realDo.get(id);
      return {
        fetch: async (...args: Parameters<typeof stub.fetch>) => {
          fetchCount += 1;
          return stub.fetch(...args);
        },
      };
    },
    fetchCount: () => fetchCount,
    resetCounts: () => {
      fetchCount = 0;
    },
  };

  return spy as DoSpy;
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
