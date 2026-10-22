import { execFile } from "node:child_process";
import { checkMonitorSnapshot } from "../staging/heartbeat-monitor.mjs";
import { httpGet, REQUEST_TIMEOUT_MS, SourceError, schemaError } from "./live-http.mjs";

// R9-RT1 (01 §3.8 D-6): read-only observation sources for the live launch-check. Each source
// exposes observe(target, clock) -> Observation[] and either returns all of its observations or
// throws a SourceError (a partial read is discarded). Base URLs are pinned here, not taken from
// the CLI. Every request is a GET (the backend read is a read-only psql transaction).
//
// Exact Cloudflare paths and response fields are external facts. They are confirmed during
// operator acceptance, and a shape mismatch fails closed (schema-mismatch).

export const CF_API_BASE = "https://api.cloudflare.com/client/v4";
export const CREDENTIAL_ENV = Object.freeze({
  cloudflare: "LAUNCH_CHECK_CF_TOKEN",
  access: "LAUNCH_CHECK_ACCESS_TOKEN",
  database: "LAUNCH_CHECK_DB_URL",
  monitorKey: "LAUNCH_CHECK_MONITOR_KEY",
});
// The keys that ai_internal.launch_state() returns (migration 20261022120000_rm35_launch_state_reader.sql).
// The migration-key test compares this list with the jsonb_build_object keys in that file.
export const BACKEND_STATE_KEYS = Object.freeze([
  "database_name",
  "contract_versions",
  "set_ai_availability_present",
]);
// R9-RT1 (a): the nine channel names of CHANNEL_VERSIONS in packages/vendor-contracts/src/version.ts.
// The parity test in launch-live.test.mjs reads that file and compares it with this list.
export const CHANNEL_KEYS = Object.freeze([
  "aboClinic",
  "aboConsole",
  "backendRpc",
  "platformClinic",
  "platformFeed",
  "vendorEntrypoint",
  "platformDo",
  "paymobReturn",
  "paymobAdapter",
]);
// The unauthenticated manual-entitle probe uses the nil installation id (the removed /control routes).
const NIL_INSTALLATION_ID = "00000000-0000-0000-0000-000000000000";
const CF_PAGE_SIZE = 100;
const CF_MAX_PAGES = 1000;
const PSQL_SQL = "SELECT ai_internal.launch_state()";

export function missingCredentialNames(env) {
  return Object.values(CREDENTIAL_ENV).filter(
    (name) => typeof env[name] !== "string" || env[name].length === 0,
  );
}

export function observation({ key, value, source, targetId, target, clock }) {
  return {
    key,
    value,
    environment: target.environment,
    target_id: targetId,
    observed_at: new Date(clock.now()).toISOString(),
    source,
  };
}

function isObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

// R9-RT1 (a): the single shared channel version, or null. The 18 values (9 ABO, 9 platform) must
// have the CHANNEL_KEYS key set on both sides, be safe integers, and be exactly one distinct value.
function sharedChannelVersion(aboChannels, platformChannels) {
  if (!isObject(aboChannels) || !isObject(platformChannels)) {
    return null;
  }
  const expected = [...CHANNEL_KEYS].sort();
  for (const map of [aboChannels, platformChannels]) {
    const keys = Object.keys(map).sort();
    if (keys.length !== expected.length || keys.some((key, index) => key !== expected[index])) {
      return null;
    }
  }
  const values = [...Object.values(aboChannels), ...Object.values(platformChannels)];
  if (!values.every((value) => Number.isSafeInteger(value))) {
    return null;
  }
  if (new Set(values).size !== 1) {
    return null;
  }
  return values[0];
}

function cfResult(body, source) {
  if (!isObject(body) || body.success !== true || !("result" in body)) {
    throw schemaError(source);
  }
  return body.result;
}

// Lists every page of a Cloudflare collection. A response without result_info is a single page.
// A page count that does not reach the reported total fails as incomplete-pagination.
async function cfList({ fetchImpl, clock, token, path }) {
  const items = [];
  for (let page = 1; page <= CF_MAX_PAGES; page += 1) {
    const { body } = await httpGet({
      source: "cloudflare",
      fetchImpl,
      url: `${CF_API_BASE}${path}?per_page=${CF_PAGE_SIZE}&page=${page}`,
      headers: { authorization: `Bearer ${token}` },
      clock,
    });
    const result = cfResult(body, "cloudflare");
    if (!Array.isArray(result)) {
      throw schemaError("cloudflare");
    }
    items.push(...result);
    const info = body.result_info;
    if (info === undefined) {
      return items;
    }
    if (!isObject(info) || !Number.isSafeInteger(info.total_pages) || !Number.isSafeInteger(info.total_count)) {
      throw schemaError("cloudflare");
    }
    if (page >= info.total_pages) {
      if (items.length !== info.total_count) {
        throw new SourceError("cloudflare", "incomplete-pagination");
      }
      return items;
    }
  }
  throw new SourceError("cloudflare", "incomplete-pagination");
}

async function cfGet({ fetchImpl, clock, token, path }) {
  const { body } = await httpGet({
    source: "cloudflare",
    fetchImpl,
    url: `${CF_API_BASE}${path}`,
    headers: { authorization: `Bearer ${token}` },
    clock,
  });
  return cfResult(body, "cloudflare");
}

export function createCloudflareSource({ env, fetchImpl }) {
  return {
    async observe(target, clock) {
      const token = env[CREDENTIAL_ENV.cloudflare];
      const account = await cfGet({
        fetchImpl,
        clock,
        token,
        path: `/accounts/${target.cloudflare_account_id}`,
      });
      if (!isObject(account) || typeof account.id !== "string") {
        throw schemaError("cloudflare");
      }
      // The account id comes from the response. evaluateLive drops everything if it differs.
      const targetId = account.id;
      const out = [];
      const emit = (key, value) =>
        out.push(observation({ key, value, source: "cloudflare", targetId, target, clock }));

      let workersDev = false;
      let previews = false;
      let bearerToken = false;
      for (const script of target.script_names) {
        const subdomain = await cfGet({
          fetchImpl,
          clock,
          token,
          path: `/accounts/${target.cloudflare_account_id}/workers/scripts/${script}/subdomain`,
        });
        if (!isObject(subdomain) || typeof subdomain.enabled !== "boolean" || typeof subdomain.previews_enabled !== "boolean") {
          throw schemaError("cloudflare");
        }
        workersDev = workersDev || subdomain.enabled;
        previews = previews || subdomain.previews_enabled;

        const secrets = await cfList({
          fetchImpl,
          clock,
          token,
          path: `/accounts/${target.cloudflare_account_id}/workers/scripts/${script}/secrets`,
        });
        for (const secret of secrets) {
          if (!isObject(secret) || typeof secret.name !== "string") {
            throw schemaError("cloudflare");
          }
          bearerToken = bearerToken || secret.name === "OPERATOR_BEARER_TOKEN";
        }
      }
      emit("workers_dev", workersDev);
      emit("preview_urls", previews);
      emit("operator_bearer_token", bearerToken);

      const routes = await cfList({
        fetchImpl,
        clock,
        token,
        path: `/zones/${target.zone_id}/workers/routes`,
      });
      let controlRoute = false;
      for (const route of routes) {
        if (!isObject(route) || typeof route.pattern !== "string") {
          throw schemaError("cloudflare");
        }
        controlRoute = controlRoute || route.pattern.includes("/control");
      }
      // A separate key from the probe: the condition needs both sources to agree (see evaluateLive).
      emit("control_route_cf", controlRoute);
      return out;
    },
  };
}

function aboHeaders(env, target) {
  return {
    "cf-access-token": env[CREDENTIAL_ENV.access],
    "Abo-Contract-Version": String(target.abo_contract_version),
  };
}

export function createAboSource({ env, fetchImpl }) {
  return {
    async observe(target, clock) {
      const base = `https://${target.ops_host}`;
      const headers = aboHeaders(env, target);
      const get = async (path) =>
        (
          await httpGet({ source: "abo", fetchImpl, url: `${base}${path}`, headers, clock })
        ).body;

      const context = await get("/ops/ceremony-context");
      if (!isObject(context) || typeof context.rp_id !== "string") {
        throw schemaError("abo");
      }
      // The RP id comes from the response. evaluateLive drops everything if it is not the target host.
      const targetId = context.rp_id;

      const registries = await get("/ops/registries");
      if (
        !isObject(registries) ||
        !Array.isArray(registries.issuer_keys) ||
        !Array.isArray(registries.service_keys) ||
        !Array.isArray(registries.operator_credentials)
      ) {
        throw schemaError("abo");
      }
      let activeCredentials = 0;
      for (const credential of registries.operator_credentials) {
        if (!isObject(credential) || typeof credential.active !== "boolean") {
          throw schemaError("abo");
        }
        if (credential.active) {
          activeCredentials += 1;
        }
      }

      const state = await get("/ops/launch-state");
      if (
        !isObject(state) ||
        typeof state.abo_signing_kid !== "string" ||
        state.abo_signing_kid.length === 0 ||
        typeof state.issuer_keys_pinned !== "boolean" ||
        typeof state.al_23_active !== "boolean" ||
        !Number.isSafeInteger(state.term_count) ||
        state.term_count < 0 ||
        !Number.isSafeInteger(state.grant_count) ||
        state.grant_count < 0
      ) {
        throw schemaError("abo");
      }
      // R9-RT1 (a)-(c): the channel map, the self-check and the platform signing key fields. A wrong
      // type drops the whole ABO source. A channel map that is not the shared CHANNEL_KEYS set is
      // not a schema error; it is reported as null and fails the channels condition.
      if (
        !isObject(state.channel_versions) ||
        (state.platform_channel_versions !== null && !isObject(state.platform_channel_versions)) ||
        typeof state.key_self_check_passes !== "boolean" ||
        (state.key_self_check_checked_at !== null && typeof state.key_self_check_checked_at !== "string") ||
        typeof state.platform_signing_key_set !== "boolean" ||
        (state.platform_signing_kid !== null && typeof state.platform_signing_kid !== "string")
      ) {
        throw schemaError("abo");
      }

      // Issuer keys: at least one key, and every entry carries the kid and public_key that the ABO
      // compares with ISSUER_KEYS. The comparison itself runs in the ABO and is reported as
      // issuer_keys_pinned from /ops/launch-state. The checker does not hold ISSUER_KEYS, so it
      // cannot compare the pinned list directly.
      const issuerKeysWellFormed =
        registries.issuer_keys.length > 0 &&
        registries.issuer_keys.every(
          (key) =>
            isObject(key) &&
            typeof key.kid === "string" &&
            key.kid.length > 0 &&
            typeof key.public_key === "string" &&
            key.public_key.length > 0,
        );
      const emit = (key, value) =>
        observation({ key, value, source: "abo", targetId, target, clock });
      return [
        emit("issuer_keys_registered", issuerKeysWellFormed),
        // Count-only check: /ops/registries gives no kid or public_key for service keys, and no
        // existing read exposes a pinned service-key list. Known limitation (R9-RT1 Fix 3).
        emit("service_keys_registered", registries.service_keys.length > 0),
        emit("active_operator_credentials", activeCredentials),
        emit("issuer_keys_pinned", state.issuer_keys_pinned),
        emit("al_23_clear", state.al_23_active === false),
        emit("platform_d1_terms", state.term_count),
        emit("platform_d1_grants", state.grant_count),
        emit(
          "channels_version",
          sharedChannelVersion(state.channel_versions, state.platform_channel_versions),
        ),
        emit("key_self_check_passes", state.key_self_check_passes),
        emit("platform_signing_key_set", state.platform_signing_key_set),
      ];
    },
  };
}

// The unauthenticated /control/ probe must answer 404. A 2xx answer means a control route exists.
// Any other status is not evidence either way, so it fails the source.
// R9-RT1 (d): the manual-entitle probe. The removed /control/installations/{id}/entitle and
// /override routes are GET-probed with the nil UUID. Any answer from 200 to 499 counts as a route
// (true). Both 404 is false. A 5xx or a network error throws and the whole probe source drops.
export function createProbeSource({ fetchImpl }) {
  return {
    async observe(target, clock) {
      const { status } = await httpGet({
        source: "probe",
        fetchImpl,
        url: `https://${target.platform_host}/control/`,
        clock,
        acceptStatus: (code) => code === 404 || (code >= 200 && code < 300),
        expectJson: false,
      });
      const installationBase = `https://${target.platform_host}/control/installations/${NIL_INSTALLATION_ID}`;
      const acceptProbeAnswer = (code) => code >= 200 && code <= 499;
      const entitle = await httpGet({
        source: "probe",
        fetchImpl,
        url: `${installationBase}/entitle`,
        clock,
        acceptStatus: acceptProbeAnswer,
        expectJson: false,
      });
      const override = await httpGet({
        source: "probe",
        fetchImpl,
        url: `${installationBase}/override`,
        clock,
        acceptStatus: acceptProbeAnswer,
        expectJson: false,
      });
      return [
        observation({
          key: "control_route",
          value: status !== 404,
          source: "probe",
          targetId: target.platform_host,
          target,
          clock,
        }),
        observation({
          key: "manual_entitle_path",
          value: entitle.status !== 404 || override.status !== 404,
          source: "probe",
          targetId: target.platform_host,
          target,
          clock,
        }),
      ];
    },
  };
}

function canonicalJson(value) {
  if (Array.isArray(value)) {
    return `[${value.map(canonicalJson).join(",")}]`;
  }
  if (isObject(value)) {
    return `{${Object.keys(value)
      .sort()
      .map((key) => `${JSON.stringify(key)}:${canonicalJson(value[key])}`)
      .join(",")}}`;
  }
  return JSON.stringify(value);
}

// Runs one read-only SQL statement through psql. The session is forced read-only through PGOPTIONS,
// and the connection string comes from LAUNCH_CHECK_DB_URL. Output is the function's JSON text.
export function runPsqlReadonly(dbUrl, { execFileImpl = execFile } = {}) {
  return new Promise((resolve, reject) => {
    execFileImpl(
      "psql",
      ["--no-psqlrc", "--tuples-only", "--no-align", "--set", "ON_ERROR_STOP=1", "--dbname", dbUrl, "--command", PSQL_SQL],
      {
        timeout: REQUEST_TIMEOUT_MS,
        maxBuffer: 1024 * 1024,
        env: { ...process.env, PGOPTIONS: "-c default_transaction_read_only=on" },
      },
      (error, stdout) => {
        if (error) {
          reject(new SourceError("backend", "backend-error"));
          return;
        }
        resolve(stdout);
      },
    );
  });
}

// Supabase names every project's database "postgres", so the database name cannot tell projects
// apart. The connection URL must name the target's project ref, either as host db.<ref>.supabase.co
// or as user postgres.<ref>. Both comparisons are exact. Any URL that does not parse does not match.
export function dbUrlNamesProject(dbUrl, ref) {
  let url;
  try {
    url = new URL(String(dbUrl));
  } catch {
    return false;
  }
  let user;
  try {
    user = decodeURIComponent(url.username);
  } catch {
    return false;
  }
  return url.hostname === `db.${ref}.supabase.co` || user === `postgres.${ref}`;
}

export function createBackendSource({ env, runPsql }) {
  return {
    async observe(target, clock) {
      const dbUrl = env[CREDENTIAL_ENV.database];
      if (!dbUrlNamesProject(dbUrl, target.supabase_project_ref)) {
        throw new SourceError("backend", "target-mismatch");
      }
      let raw;
      try {
        raw = await runPsql(dbUrl);
      } catch (error) {
        throw error instanceof SourceError ? error : new SourceError("backend", "backend-error");
      }
      let parsed;
      try {
        parsed = JSON.parse(String(raw).trim());
      } catch {
        throw schemaError("backend");
      }
      if (
        !isObject(parsed) ||
        typeof parsed.database_name !== "string" ||
        typeof parsed.set_ai_availability_present !== "boolean" ||
        !isObject(parsed.contract_versions)
      ) {
        throw schemaError("backend");
      }
      // The database name comes from the response. evaluateLive drops everything if it differs
      // from the target descriptor's backend_database.
      const targetId = parsed.database_name;
      const emit = (key, value) =>
        observation({ key, value, source: "backend", targetId, target, clock });
      const out = [emit("set_ai_availability", parsed.set_ai_availability_present)];
      if (target.expected_contract_versions !== undefined) {
        out.push(
          emit(
            "backend_contract_versions_match",
            canonicalJson(parsed.contract_versions) === canonicalJson(target.expected_contract_versions),
          ),
        );
      }
      return out;
    },
  };
}

// The monitor adapter contract is in heartbeat-monitor.mjs (checkMonitorSnapshot). The vendor is
// not chosen in the repository. The host is pinned in the target descriptor (monitor_host), and
// only the key comes from the environment. The base URL is never taken from the environment.
export function createMonitorSource({ env, fetchImpl }) {
  return {
    async observe(target, clock) {
      if (missingCredentialNames(env).includes(CREDENTIAL_ENV.monitorKey)) {
        throw new SourceError("monitor", "not-configured");
      }
      const url = `https://${target.monitor_host}/snapshot`;
      if (new URL(url).hostname !== target.monitor_host) {
        throw new SourceError("monitor", "host-mismatch");
      }
      const { body } = await httpGet({
        source: "monitor",
        fetchImpl,
        url,
        headers: { authorization: `Bearer ${env[CREDENTIAL_ENV.monitorKey]}` },
        clock,
      });
      const verdict = checkMonitorSnapshot(body);
      if (verdict.environment === null) {
        throw schemaError("monitor");
      }
      const emit = (key) =>
        observation({
          key,
          value: verdict.live,
          source: "monitor",
          targetId: verdict.environment,
          target,
          clock,
        });
      return [emit("heartbeat_monitor_live"), emit("audit_watcher_live")];
    },
  };
}

export function createLiveSources({ env, fetchImpl = globalThis.fetch, runPsql }) {
  const psql = runPsql ?? ((url) => runPsqlReadonly(url));
  return {
    probe: createProbeSource({ fetchImpl }),
    cloudflare: createCloudflareSource({ env, fetchImpl }),
    abo: createAboSource({ env, fetchImpl }),
    backend: createBackendSource({ env, runPsql: psql }),
    monitor: createMonitorSource({ env, fetchImpl }),
  };
}
