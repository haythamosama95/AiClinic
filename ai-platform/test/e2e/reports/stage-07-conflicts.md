# Stage 07 catalog-vs-code conflicts

## S07-051

- **Catalog claim:** After an S07-042-style warm `GET /v1/capabilities`, invoke `handleDiscoveryRequest` with an injectable `new ConfigCache(30000)` (production `DEFAULT_CONFIG_CACHE_TTL_MS`). Revoke the installation-scope grant in D1 without clearing the cache. The next GET within 30 s still lists `clinic.visit_summary@1.0.0`. After `cache.clear()` (TTL-expiry analogue), the same request returns `{"manifests":[]}`.
- **Code behavior:** Register 5 #7 / frozen barrel: tests cannot construct `new ConfigCache(30000)` or import `handleDiscoveryRequest` from src. The E2E pool binds `CONFIG_CACHE_TTL_MS: "100"` (README §6; TTL `"0"` is unsafe). Clinic GETs hit `isolateConfigCache`. Tests follow harness/code: keep the still-listed / then-empty assertions; tighten warm → D1 revoke (`env.DB.prepare`…`run()`, not `seedSql`) → stale GET inside 100 ms; `clearConfigCache()` stands in for TTL expiry.
- **File:line:** `ai-platform/src/discovery/index.ts:36-40` (`handleDiscoveryRequest` injectable `cache`); `ai-platform/src/config-cache/index.ts:26-28` (`DEFAULT_CONFIG_CACHE_TTL_MS = 30_000`); `ai-platform/src/config-cache/index.ts:89-115` (`consult` / `remember` TTL); `ai-platform/src/config-cache/index.ts:153` (`isolateConfigCache`); `ai-platform/vitest.e2e.config.ts:42` (`CONFIG_CACHE_TTL_MS: "100"`); `ai-platform/test/e2e/harness/d1.ts:142-154` (`seedSql`).

### Iteration 2 (S07-051 TTL analogue)

- **Catalog claim:** Construct `new ConfigCache(30000)` and inject it into `handleDiscoveryRequest` so the warm GET’s `remember()` uses production `DEFAULT_CONFIG_CACHE_TTL_MS`. A separate cache instance that discovery never sees would not exercise the isolate.
- **Code behavior:** Pool `CONFIG_CACHE_TTL_MS` is `"100"`. Tests cannot import `handleDiscoveryRequest` or inject a private `ConfigCache`. Honest analogue without extending the harness: barrel `isolateConfigCache.setTtlMs(30_000)` before the warm GET (`remember` stamps `now + 30_000`); `finally` restores `isolateConfigCache.getTtlMs()` previous value and `clearConfigCache()` so later tests keep harness TTL 100. Assertions stay: warm listed → post-revoke still listed / same ETag → after `clearConfigCache()` empty.
- **File:line:** `ai-platform/src/config-cache/index.ts:72-78` (`getTtlMs` / `setTtlMs`); `ai-platform/src/config-cache/index.ts:89-115` (`consult` / `remember`); `ai-platform/src/config-cache/index.ts:153` (`isolateConfigCache`); `ai-platform/src/config-cache/index.ts:26` (`DEFAULT_CONFIG_CACHE_TTL_MS`).
