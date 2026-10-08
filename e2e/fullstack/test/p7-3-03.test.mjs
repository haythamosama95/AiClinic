import test, { after, before } from "node:test";
import assert from "node:assert/strict";
import {
  psqlQuery,
  readClinicAiCoverage,
  rpc,
  startStack,
} from "./p7-3-stack.mjs";

// H-FS unit harness (P7.3 US2): node --import tsx --test test/p7-3-03.test.mjs

const PLATFORM_FEED_WINDOW = "test/variant/platform-feed-window.toml";
const PUBLISHED_FEED_VERSION = 1;

let stack = null;

before(async () => {
  stack = await startStack({
    platformConfig: PLATFORM_FEED_WINDOW,
  });
});

after(async () => {
  await stack?.stop();
  stack = null;
});

function readFeedState() {
  const row = psqlQuery(`
    SELECT row_to_json(t)::text
    FROM (
      SELECT
        cursor::text,
        consecutive_failures::text,
        last_success_at::text
      FROM ai_internal.feed_state
      WHERE singleton
      LIMIT 1
    ) t
  `);
  if (!row) {
    return null;
  }
  const parsed = JSON.parse(row);
  return {
    cursor: parsed.cursor,
    consecutive_failures: Number(parsed.consecutive_failures ?? "0"),
    last_success_at: parsed.last_success_at,
  };
}

function readPlatformFeedCurrent() {
  const row = psqlQuery(`
    SELECT (value_json->'platformFeed'->>'current')::int
    FROM ai_internal.app_settings
    WHERE key = 'ai.contract_versions'
    LIMIT 1
  `);
  return Number(row);
}

function countHttpResponses() {
  const row = psqlQuery(`SELECT COUNT(*)::text FROM net._http_response`);
  return Number(row || "0");
}

async function waitForPendingHttpResponse(pendingRequestId, { timeoutMs = 10_000 } = {}) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    const row = psqlQuery(`
      SELECT id::text
      FROM net._http_response
      WHERE id = ${pendingRequestId}
      LIMIT 1
    `);
    if (row) {
      return;
    }
    await new Promise((resolve) => setTimeout(resolve, 50));
  }
  throw new Error(`Timed out waiting for net._http_response id ${pendingRequestId}`);
}

function readFeedStatePendingRequestId() {
  return psqlQuery(`
    SELECT pending_request_id::text
    FROM ai_internal.feed_state
    WHERE singleton
    LIMIT 1
  `);
}

async function runTwoPhaseCoveragePull() {
  psqlQuery(`SELECT auth_internal.pull_coverage_feed()`);
  const pendingRequestId = readFeedStatePendingRequestId();
  if (pendingRequestId) {
    await waitForPendingHttpResponse(pendingRequestId);
  }
  psqlQuery(`SELECT auth_internal.pull_coverage_feed()`);
}

function setFeedStateLastSuccessAgo(seconds) {
  psqlQuery(`
    UPDATE ai_internal.feed_state
    SET last_success_at = now() - interval '${seconds} seconds'
    WHERE singleton
  `);
}

test("E2E-P7.3-03", async () => {
  const { orgId, administrator } = stack.clinics.orgA;
  const contractVersionsBefore = readPlatformFeedCurrent();
  assert.equal(contractVersionsBefore, PUBLISHED_FEED_VERSION);

  const projectionBefore = readClinicAiCoverage(orgId);
  assert.ok(projectionBefore, "baseline projection should exist");

  setFeedStateLastSuccessAgo(121);

  const feedStateBefore = readFeedState();
  assert.ok(feedStateBefore, "feed_state should exist");
  const cursorBefore = feedStateBefore.cursor;
  const failuresBefore = feedStateBefore.consecutive_failures;
  const httpResponsesBefore = countHttpResponses();

  await runTwoPhaseCoveragePull();

  const lastResponse = psqlQuery(`
    SELECT row_to_json(t)::text
    FROM (
      SELECT status_code, content
      FROM net._http_response
      ORDER BY created DESC
      LIMIT 1
    ) t
  `);
  assert.ok(lastResponse, "pull_coverage_feed should issue a pg_net request");
  const parsedResponse = JSON.parse(lastResponse);
  assert.equal(Number(parsedResponse.status_code), 400);

  const feedStateAfter = readFeedState();
  assert.equal(feedStateAfter.cursor, cursorBefore, "unsupported feed version should keep the cursor");
  assert.ok(
    feedStateAfter.consecutive_failures > failuresBefore,
    "unsupported feed version should increment consecutive_failures",
  );
  assert.ok(
    feedStateAfter.last_success_at === feedStateBefore.last_success_at,
    "feed refusal should not refresh last_success_at",
  );

  assert.deepEqual(readClinicAiCoverage(orgId), projectionBefore);
  assert.equal(readPlatformFeedCurrent(), PUBLISHED_FEED_VERSION);
  assert.equal(countHttpResponses(), httpResponsesBefore + 1);

  const status = await rpc(administrator, "get_ai_status", {
    p_contract_version: 1,
  });
  assert.equal(status.success, true);
  assert.equal(status.data.stale, true, "stale alert should follow feed refusal");
  const noticeCodes = (status.data.notices ?? []).map((notice) => notice.code);
  assert.ok(
    noticeCodes.includes("status_stale"),
    "feed refusal with stale last_success_at should surface status_stale",
  );
});
