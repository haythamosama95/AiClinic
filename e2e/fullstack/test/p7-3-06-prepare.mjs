/**
 * P7.3 desktop-window prepare for E2E-P7.3-06.
 * Starts ABO and platform on desktop-window variants, applies (2, 3) RPC gates,
 * and restores published (0, 1) gates before exit.
 */

import { readFile } from "node:fs/promises";
import path from "node:path";
import { spawnSync } from "node:child_process";
import {
  ABO_URL,
  DB_URL,
  PLATFORM_URL,
  REPO_ROOT,
  startStack,
} from "./p7-3-stack.mjs";

const ABO_DESKTOP_CONFIG = "test/variant/abo-desktop-window.toml";
const PLATFORM_DESKTOP_CONFIG = "test/variant/platform-desktop-window.toml";

let stack = null;
let cleanedUp = false;

function runPsql(sql) {
  const result = spawnSync(
    "psql",
    [DB_URL, "-v", "ON_ERROR_STOP=1", "-c", sql],
    { encoding: "utf8" },
  );
  if (result.status !== 0) {
    throw new Error(`psql failed: ${result.stderr || result.stdout}`);
  }
}

function extractSqlBlock(source, startMarker, endMarker) {
  const start = source.indexOf(startMarker);
  const end = source.indexOf(endMarker, start);
  if (start < 0 || end < 0) {
    throw new Error(`Could not locate SQL block: ${startMarker}`);
  }
  return source.slice(start, end);
}

async function desktopRpcGatesSql() {
  const matrixSql = await readFile(
    path.join(REPO_ROOT, "backend/tests/contract_version_matrix.sql"),
    "utf8",
  );
  const gateSql = extractSqlBlock(
    matrixSql,
    "CREATE OR REPLACE FUNCTION public.get_ai_status(p_contract_version integer DEFAULT NULL)",
    "-- E2E-P7.3-01: RPC receiver at N+1 accepts 1 and 2 and refuses before auth or write.",
  );
  return gateSql
    .replaceAll("NOT IN (1, 2)", "NOT IN (2, 3)")
    .replaceAll("jsonb_build_array(1, 2)", "jsonb_build_array(2, 3)")
    .replaceAll('"accepted_versions":[1,2]', '"accepted_versions":[2,3]')
    .replaceAll(
      "'Contract version is not supported.',\n      2\n    )::public.rpc_result;",
      "'Contract version is not supported.',\n      3\n    )::public.rpc_result;",
    );
}

async function publishedRpcGatesSql() {
  const noticesSql = await readFile(
    path.join(
      REPO_ROOT,
      "backend/supabase/migrations/20261008010000_read_time_status_notices.sql",
    ),
    "utf8",
  );
  const custodySql = await readFile(
    path.join(
      REPO_ROOT,
      "backend/supabase/migrations/20261007180000_issuer_key_custody.sql",
    ),
    "utf8",
  );
  const feedSql = await readFile(
    path.join(
      REPO_ROOT,
      "backend/supabase/migrations/20261007230000_coverage_feed_puller_status.sql",
    ),
    "utf8",
  );

  const getAiStatus = extractSqlBlock(
    noticesSql,
    "CREATE OR REPLACE FUNCTION public.get_ai_status(p_contract_version integer DEFAULT NULL)",
    "REVOKE ALL ON FUNCTION auth_internal.get_ai_status(integer)",
  );
  const getAiBillingStatus = extractSqlBlock(
    noticesSql,
    "CREATE OR REPLACE FUNCTION public.get_ai_billing_status(p_contract_version integer DEFAULT NULL)",
    "REVOKE ALL ON FUNCTION public.get_ai_billing_status(integer)",
  );
  const issueAiToken = extractSqlBlock(
    custodySql,
    "CREATE OR REPLACE FUNCTION public.issue_ai_token(p_contract_version integer DEFAULT NULL)",
    "REVOKE EXECUTE ON FUNCTION auth_internal.issue_ai_token(integer)",
  );
  const issueBillingToken = extractSqlBlock(
    custodySql,
    "CREATE OR REPLACE FUNCTION public.issue_billing_token(p_contract_version integer DEFAULT NULL)",
    "REVOKE EXECUTE ON FUNCTION auth_internal.issue_billing_token(integer)",
  );
  const requestRefresh = extractSqlBlock(
    feedSql,
    "CREATE OR REPLACE FUNCTION public.request_ai_status_refresh(p_contract_version integer DEFAULT NULL)",
    "REVOKE ALL ON FUNCTION auth_internal.request_ai_status_refresh(integer)",
  );

  return [
    getAiStatus,
    requestRefresh,
    issueBillingToken,
    issueAiToken,
    getAiBillingStatus,
  ].join("\n");
}

async function applyDesktopRpcGates() {
  runPsql(await desktopRpcGatesSql());
}

async function restorePublishedRpcGates() {
  runPsql(await publishedRpcGatesSql());
}

async function cleanup() {
  if (cleanedUp) {
    return;
  }
  cleanedUp = true;
  try {
    await restorePublishedRpcGates();
  } catch (error) {
    console.error("Failed to restore published RPC gates:", error);
  }
  if (stack) {
    await stack.stop();
    stack = null;
  }
}

async function main() {
  const onSignal = async () => {
    await cleanup();
    process.exit(0);
  };
  process.on("SIGINT", onSignal);
  process.on("SIGTERM", onSignal);

  stack = await startStack({
    aboConfig: ABO_DESKTOP_CONFIG,
    platformConfig: PLATFORM_DESKTOP_CONFIG,
  });
  await applyDesktopRpcGates();

  console.log(
    `P7.3 desktop-window stack ready (ABO ${ABO_URL}, platform ${PLATFORM_URL}).`,
  );
  console.log("Run the Flutter fullstack test, then press Ctrl+C to stop.");
  await new Promise(() => {});
}

main().catch(async (error) => {
  console.error(error);
  await cleanup();
  process.exit(1);
});
