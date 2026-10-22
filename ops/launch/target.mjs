import { readFile } from "node:fs/promises";

// R9-RT1 (01 §3.8 D-6): the target descriptor ops/launch/targets/<env>.json is checked in and
// holds identifiers only (non-secret). Unknown fields are rejected so that a credential cannot be
// stored in it by accident. Credentials come from environment variables only.

const ALLOWED_KEYS = Object.freeze([
  "environment",
  "cloudflare_account_id",
  "zone_id",
  "script_names",
  "d1_database_ids",
  "access_app_ids",
  "ops_host",
  "platform_host",
  "access_app_hostnames",
  "supabase_project_ref",
  "backend_database",
  "monitor_host",
  "abo_contract_version",
  "expected_contract_versions",
]);
const OPTIONAL_KEYS = Object.freeze(["expected_contract_versions"]);
const REQUIRED_KEYS = Object.freeze(ALLOWED_KEYS.filter((key) => !OPTIONAL_KEYS.includes(key)));

const ENVIRONMENT = /^[a-z][a-z0-9-]{1,31}$/u;
const HEX32 = /^[0-9a-f]{32}$/u;
const HOSTNAME = /^(?=.{1,253}$)[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?)+$/u;
const PROJECT_REF = /^[a-z0-9]{8,32}$/u;
const DATABASE_NAME = /^[A-Za-z0-9_][A-Za-z0-9_.-]{0,62}$/u;

export class TargetError extends Error {
  constructor(message) {
    super(message);
    this.name = "TargetError";
  }
}

function requireMatch(value, pattern, field) {
  if (typeof value !== "string" || !pattern.test(value)) {
    throw new TargetError(`target field ${field} is not valid`);
  }
  return value;
}

function requireStringList(value, field, { nonEmpty }) {
  if (!Array.isArray(value) || (nonEmpty && value.length === 0)) {
    throw new TargetError(`target field ${field} must be a list of strings`);
  }
  for (const item of value) {
    if (typeof item !== "string" || item.length === 0 || item.length > 128) {
      throw new TargetError(`target field ${field} must be a list of strings`);
    }
  }
  return Object.freeze([...value]);
}

export function validateTarget(input) {
  if (input === null || typeof input !== "object" || Array.isArray(input)) {
    throw new TargetError("target descriptor must be a JSON object");
  }
  for (const key of Object.keys(input)) {
    if (!ALLOWED_KEYS.includes(key)) {
      throw new TargetError(`unknown target field: ${key}`);
    }
  }
  for (const key of REQUIRED_KEYS) {
    if (!(key in input)) {
      throw new TargetError(`missing target field: ${key}`);
    }
  }

  const abo = input.abo_contract_version;
  if (!Number.isSafeInteger(abo) || abo < 1) {
    throw new TargetError("target field abo_contract_version is not valid");
  }

  let expected;
  if ("expected_contract_versions" in input) {
    const raw = input.expected_contract_versions;
    if (raw === null || typeof raw !== "object" || Array.isArray(raw)) {
      throw new TargetError("target field expected_contract_versions must be an object");
    }
    for (const value of Object.values(raw)) {
      if (!Number.isSafeInteger(value) || value < 1) {
        throw new TargetError("target field expected_contract_versions must hold integers");
      }
    }
    expected = Object.freeze({ ...raw });
  }

  const target = {
    environment: requireMatch(input.environment, ENVIRONMENT, "environment"),
    cloudflare_account_id: requireMatch(input.cloudflare_account_id, HEX32, "cloudflare_account_id"),
    zone_id: requireMatch(input.zone_id, HEX32, "zone_id"),
    script_names: requireStringList(input.script_names, "script_names", { nonEmpty: true }),
    d1_database_ids: requireStringList(input.d1_database_ids, "d1_database_ids", { nonEmpty: false }),
    access_app_ids: requireStringList(input.access_app_ids, "access_app_ids", { nonEmpty: false }),
    ops_host: requireMatch(input.ops_host, HOSTNAME, "ops_host"),
    platform_host: requireMatch(input.platform_host, HOSTNAME, "platform_host"),
    access_app_hostnames: requireStringList(input.access_app_hostnames, "access_app_hostnames", {
      nonEmpty: false,
    }),
    supabase_project_ref: requireMatch(input.supabase_project_ref, PROJECT_REF, "supabase_project_ref"),
    backend_database: requireMatch(input.backend_database, DATABASE_NAME, "backend_database"),
    monitor_host: requireMatch(input.monitor_host, HOSTNAME, "monitor_host"),
    abo_contract_version: abo,
  };
  if (expected !== undefined) {
    target.expected_contract_versions = expected;
  }
  return Object.freeze(target);
}

export async function loadTargetDescriptor(filePath) {
  let parsed;
  try {
    parsed = JSON.parse(await readFile(filePath, "utf8"));
  } catch {
    throw new TargetError("target descriptor is missing or is not valid JSON");
  }
  return validateTarget(parsed);
}
