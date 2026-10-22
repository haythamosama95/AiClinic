import { readFile } from "node:fs/promises";
import { pathToFileURL } from "node:url";
import { loadTargetDescriptor, TargetError } from "./target.mjs";
import { createLiveSources, missingCredentialNames } from "./live-sources.mjs";

// R9-RT1 (01 §3.8 D-6): launch-check is an operator-run, read-only command.
// - `--target <file>` is the live mode. Every observation is acquired in this run through GET
//   requests (Cloudflare read token, ABO and platform reads, backend read-only psql, monitor read).
//   It is evaluated only with target binding, MAX_AGE freshness and the Date-skew check.
// - `--offline <file>` evaluates a supplied JSON snapshot. It never reports a launch pass.

export const MAX_AGE_MS = 5 * 60 * 1000;

const FAILED_CONDITION_LINES = [
  "No `/control/*` route, `OPERATOR_BEARER_TOKEN`, `set_ai_availability`, or manual entitle path exists",
  "`workers_dev` and preview URLs are off",
  "Every channel runs contract version 1 on both sides, and the backend's `ai.contract_versions` matches the shared package",
  "AL-23 is clear. The ABO's key self-check passes.",
  "At least two operator credentials are active",
  "The issuer and service keys are registered. The issuer keys are pinned in the ABO's `ISSUER_KEYS`. The platform signing key is set.",
  "The platform holds no terms (clinic DOs) or grants (D1).",
  "The audit watcher and the heartbeat monitor are live.",
  "No published, canary or active routing policy row lacks a content digest.",
];

// FR06 / FV-P4 (RM33 R8-PUB1 step 3): the operator procedure for legacy routing rows.
const LEGACY_ROUTING_HINT =
  "Quarantine and republish each as a new digested version (docs/review/abo-remediation/RM33.md, operator checklist items 2-3).";

function legacyRoutingFailureLine(ids) {
  const named = Array.isArray(ids) && ids.length > 0 ? ids.join(", ") : "not readable";
  return `${FAILED_CONDITION_LINES[8]} Failing policy ids (policy_id@version): ${named}. ${LEGACY_ROUTING_HINT}`;
}

const OFFLINE_NOTICE =
  "launch-check offline evaluation: a supplied snapshot is evidence only and never reports a launch pass (01 §3.8 D-6).";
const LIVE_NOTICE =
  "launch-check live evaluation: every observation was acquired in this run from the target. Exit 0 only when all nine conditions pass.";
const NO_MODE_NOTICE =
  "launch-check: no evaluation mode was given (--target <file> for live, --offline <file> for supplied evidence). Launch success cannot be confirmed. No result was produced.";

// Only the exact value passes. Absent, null, string or truthy-but-not-false values fail closed.
function isExactFalse(value) {
  return value === false;
}

function isExactZeroCount(value) {
  return Number.isSafeInteger(value) && value === 0;
}

export function evaluateRules(input) {
  const failures = [];

  if (
    !isExactFalse(input.control_route) ||
    !isExactFalse(input.operator_bearer_token) ||
    !isExactFalse(input.set_ai_availability) ||
    !isExactFalse(input.manual_entitle_path)
  ) {
    failures.push(FAILED_CONDITION_LINES[0]);
  }

  if (!isExactFalse(input.workers_dev) || !isExactFalse(input.preview_urls)) {
    failures.push(FAILED_CONDITION_LINES[1]);
  }

  if (input.channels_version !== 1 || input.backend_contract_versions_match !== true) {
    failures.push(FAILED_CONDITION_LINES[2]);
  }

  if (input.al_23_clear !== true || input.key_self_check_passes !== true) {
    failures.push(FAILED_CONDITION_LINES[3]);
  }

  if (
    !Number.isSafeInteger(input.active_operator_credentials) ||
    input.active_operator_credentials < 2
  ) {
    failures.push(FAILED_CONDITION_LINES[4]);
  }

  if (
    input.issuer_keys_registered !== true ||
    input.service_keys_registered !== true ||
    input.issuer_keys_pinned !== true ||
    input.platform_signing_key_set !== true
  ) {
    failures.push(FAILED_CONDITION_LINES[5]);
  }

  if (!isExactZeroCount(input.platform_d1_terms) || !isExactZeroCount(input.platform_d1_grants)) {
    failures.push(FAILED_CONDITION_LINES[6]);
  }

  if (input.audit_watcher_live !== true || input.heartbeat_monitor_live !== true) {
    failures.push(FAILED_CONDITION_LINES[7]);
  }

  // Only an array of ids that is empty passes. Absent, null or a non-array fails closed.
  const legacy = input.legacy_routing_policy_ids;
  if (!Array.isArray(legacy) || legacy.length > 0 || !legacy.every((id) => typeof id === "string")) {
    failures.push(legacyRoutingFailureLine(legacy));
  }

  return failures;
}

// The identifier each source must report in target_id. It comes from the source's response (or
// the probe's pinned host), so an observation for another environment cannot satisfy the target.
const EXPECTED_TARGET_ID = Object.freeze({
  cloudflare: (target) => target.cloudflare_account_id,
  abo: (target) => target.ops_host,
  probe: (target) => target.platform_host,
  backend: (target) => target.backend_database,
  monitor: (target) => target.environment,
});

// control_route is not a single read: the probe and the Cloudflare route list are both required.
// Either one showing a route fails it. Missing either one leaves it absent, so it fails.
function combineControlRoute(values) {
  const probe = values.get("control_route");
  const cloudflare = values.get("control_route_cf");
  if (probe === true || cloudflare === true) {
    return true;
  }
  if (probe === false && cloudflare === false) {
    return false;
  }
  return undefined;
}

const RULE_KEYS = new Set([
  "control_route",
  "control_route_cf",
  "operator_bearer_token",
  "set_ai_availability",
  "manual_entitle_path",
  "workers_dev",
  "preview_urls",
  "channels_version",
  "backend_contract_versions_match",
  "al_23_clear",
  "key_self_check_passes",
  "active_operator_credentials",
  "issuer_keys_registered",
  "service_keys_registered",
  "issuer_keys_pinned",
  "platform_signing_key_set",
  "platform_d1_terms",
  "platform_d1_grants",
  "audit_watcher_live",
  "heartbeat_monitor_live",
  "legacy_routing_policy_ids",
]);

// Builds the rule input only from observations that pass target, freshness and key checks.
// A key observed twice with different values is a conflict and is treated as absent. An absent
// key fails its condition, so a missing or stale source can never produce a pass.
export function evaluateLive(observations, target, runStartMs, nowMs, maxAgeMs = MAX_AGE_MS) {
  const values = new Map();
  const conflicts = new Set();
  for (const item of Array.isArray(observations) ? observations : []) {
    if (item === null || typeof item !== "object") {
      continue;
    }
    if (!RULE_KEYS.has(item.key) || item.environment !== target.environment) {
      continue;
    }
    const expectedId = EXPECTED_TARGET_ID[item.source];
    if (expectedId === undefined || item.target_id !== expectedId(target)) {
      continue;
    }
    const observedMs = Date.parse(item.observed_at);
    if (!Number.isFinite(observedMs) || observedMs < runStartMs || observedMs > nowMs || nowMs - observedMs > maxAgeMs) {
      continue;
    }
    if (values.has(item.key) && values.get(item.key) !== item.value) {
      conflicts.add(item.key);
    }
    values.set(item.key, item.value);
  }

  const input = {};
  for (const [key, value] of values) {
    if (!conflicts.has(key) && key !== "control_route_cf") {
      input[key] = value;
    }
  }
  const controlRoute =
    conflicts.has("control_route") || conflicts.has("control_route_cf") ? undefined : combineControlRoute(values);
  if (controlRoute === undefined) {
    delete input.control_route;
  } else {
    input.control_route = controlRoute;
  }
  return evaluateRules(input);
}

// Runs every source. A source that throws contributes no observations at all. Its error is
// reported with a fixed reason code, never with a credential or response body.
export async function acquire(target, sources, clock) {
  const observations = [];
  const errors = [];
  for (const [name, source] of Object.entries(sources)) {
    try {
      const produced = await source.observe(target, clock);
      observations.push(...produced);
    } catch (error) {
      errors.push({ source: name, reason: typeof error?.reason === "string" ? error.reason : "source-error" });
    }
  }
  return { observations, errors };
}

async function runOffline(file) {
  const parsed = JSON.parse(await readFile(file, "utf8"));
  if (parsed === null || typeof parsed !== "object" || Array.isArray(parsed)) {
    console.error(OFFLINE_NOTICE);
    return 1;
  }
  for (const line of evaluateRules(parsed)) {
    console.log(line);
  }
  console.error(OFFLINE_NOTICE);
  return 1;
}

async function runLive(file, { env, fetchImpl, clock, runPsql }) {
  let target;
  try {
    target = await loadTargetDescriptor(file);
  } catch (error) {
    console.error(`launch-check: ${error instanceof TargetError ? error.message : "target descriptor could not be read"}`);
    return 1;
  }

  const missing = missingCredentialNames(env);
  if (missing.length > 0) {
    // Names only. No request is made when any credential is absent.
    console.error(`launch-check: missing credential environment variables: ${missing.join(", ")}. No result was produced.`);
    return 1;
  }

  const runStartMs = clock.now();
  const sources = createLiveSources({ env, fetchImpl, runPsql });
  const { observations, errors } = await acquire(target, sources, clock);
  const failures = evaluateLive(observations, target, runStartMs, clock.now());

  for (const line of failures) {
    console.log(line);
  }
  for (const error of errors) {
    console.error(`launch-check acquisition failed: ${error.source}: ${error.reason}`);
  }
  if (failures.length > 0 || errors.length > 0) {
    console.error(`${LIVE_NOTICE} Result: not passed.`);
    return 1;
  }
  console.error(`${LIVE_NOTICE} Result: all nine conditions passed for ${target.environment}.`);
  return 0;
}

export async function runCli(argv, { env = process.env, fetchImpl = globalThis.fetch, clock = { now: () => Date.now() }, runPsql } = {}) {
  try {
    if (argv[0] === "--offline" && argv[1]) {
      return await runOffline(argv[1]);
    }
    if (argv[0] === "--target" && argv[1]) {
      return await runLive(argv[1], { env, fetchImpl, clock, runPsql });
    }
  } catch {
    return 1;
  }
  console.error(NO_MODE_NOTICE);
  return 1;
}

const isMain = process.argv[1] !== undefined && import.meta.url === pathToFileURL(process.argv[1]).href;
if (isMain) {
  runCli(process.argv.slice(2)).then(
    (code) => process.exit(code),
    () => process.exit(1),
  );
}
