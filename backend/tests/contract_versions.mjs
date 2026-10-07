#!/usr/bin/env node
/**
 * E2E-P5.1-09: ai.contract_versions equals the package constants.
 * Run: node backend/tests/contract_versions.mjs
 */
import { readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { spawnSync } from "node:child_process";

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(scriptDir, "../..");
const versionTsPath = path.join(
  repoRoot,
  "packages/vendor-contracts/src/version.ts",
);

function parseChannelVersions(source) {
  const block = source.match(
    /export const CHANNEL_VERSIONS\s*=\s*\{([\s\S]*?)\}\s*as const/,
  );
  if (!block) {
    throw new Error("CHANNEL_VERSIONS not found in version.ts");
  }

  const versions = {};
  for (const line of block[1].split("\n")) {
    const match = line.match(/^\s*(\w+)\s*:\s*(\d+)\s*,?\s*$/);
    if (match) {
      versions[match[1]] = Number(match[2]);
    }
  }

  if (Object.keys(versions).length === 0) {
    throw new Error("No channel versions parsed from version.ts");
  }

  return versions;
}

const channelVersions = parseChannelVersions(
  readFileSync(versionTsPath, "utf8"),
);

const expected = Object.fromEntries(
  Object.entries(channelVersions).map(([key, current]) => [
    key,
    { current, minimum: current - 1 },
  ]),
);

const expectedJson = JSON.stringify(expected).replace(/'/g, "''");

const sql = `
BEGIN;
DO $check$
DECLARE
  v_stored jsonb;
  v_expected jsonb := '${expectedJson}'::jsonb;
  v_key text;
  v_spec jsonb;
  v_failures text[] := ARRAY[]::text[];
BEGIN
  SELECT value_json
  INTO v_stored
  FROM ai_internal.app_settings
  WHERE key = 'ai.contract_versions';

  IF v_stored IS NULL THEN
    RAISE EXCEPTION 'E2E-P5.1-09: ai.contract_versions is absent';
  END IF;

  FOR v_key, v_spec IN SELECT key, value FROM jsonb_each(v_expected)
  LOOP
    IF (v_stored -> v_key ->> 'current')::int IS DISTINCT FROM (v_spec ->> 'current')::int
       OR (v_stored -> v_key ->> 'minimum')::int IS DISTINCT FROM (v_spec ->> 'minimum')::int THEN
      v_failures := array_append(
        v_failures,
        v_key || ' expected current=' || (v_spec ->> 'current')
          || ' minimum=' || (v_spec ->> 'minimum')
          || ' got current=' || COALESCE(v_stored -> v_key ->> 'current', '<null>')
          || ' minimum=' || COALESCE(v_stored -> v_key ->> 'minimum', '<null>')
      );
    END IF;
  END LOOP;

  IF array_length(v_failures, 1) IS NOT NULL THEN
    RAISE EXCEPTION 'E2E-P5.1-09: contract version mismatch: %', array_to_string(v_failures, '; ');
  END IF;
END;
$check$;
ROLLBACK;
`;

const dbUrl =
  process.env.DATABASE_URL ??
  "postgresql://postgres:postgres@127.0.0.1:54322/postgres";

const result = spawnSync(
  "psql",
  [dbUrl, "-v", "ON_ERROR_STOP=1", "-c", sql],
  { encoding: "utf8", cwd: repoRoot },
);

if (result.status !== 0) {
  process.stderr.write(result.stderr ?? "");
  process.stderr.write(result.stdout ?? "");
  process.exit(result.status ?? 1);
}

console.log("E2E-P5.1-09: ai.contract_versions equals the package constants");
