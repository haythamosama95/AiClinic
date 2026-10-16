import { readFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import test from "node:test";
import assert from "node:assert/strict";

// H-STG (P8.2): node --test e2e/fullstack/staging/stg-a01.mjs

const STAGING_DIR = path.dirname(fileURLToPath(import.meta.url));
const EVIDENCE_PATH = path.join(STAGING_DIR, "evidence/stg-a01.md");
const CHECKLIST_PATH = path.join(STAGING_DIR, "manual/paymob-test-card.md");

const SCENARIO_ID = "STG-A01";
const CITATION = "P4.4-01 (full stack P6.3-01)";
const ENTRY_CHAIN =
  "POST /v1/checkouts → handlePostCheckout (abo/src/clinic-api/checkouts.ts, abo/src/worker.ts); POST /notify/paymob; GET /v1/payments; public.get_ai_status; public.request_ai_status_refresh";
const ASSERTION =
  "Three term lengths on the staging offers: Monthly (1 month, 30 minutes, grace about 7 minutes, 20 credits), Quarterly (3 months, 90 minutes, grace about 7 minutes, 60 credits), and Annual (12 months, 6 hours, grace about 7 minutes, 240 credits). AI on within about a minute; payment in history; full allowance; desktop Active; refresh called.";

const STAGING_PROFILE = "[env.staging]";
const DURATION_SCALE = "1 month = 30 minutes, 1 day = 1 minute";
const PAYMOB_TEST_CARDS = "Paymob test cards";

const OPERATOR_PROCEDURE = [
  `Operator procedure (${SCENARIO_ID}): run the existing H-FS scenario runner in e2e/fullstack/test/ pointed at ${STAGING_PROFILE}.`,
  `Record ${STAGING_PROFILE}, DURATION_SCALE (${DURATION_SCALE}), and ${PAYMOB_TEST_CARDS}.`,
  `Follow manual/paymob-test-card.md for Paymob test card steps on all three staging offers.`,
  "Do not copy startStack, do not call fetch, and do not spawn wrangler from this harness.",
  `Entry chain: ${ENTRY_CHAIN}`,
  `Assertion: ${ASSERTION}`,
].join("\n");

test(`${SCENARIO_ID} records the staging acceptance procedure and evidence template`, async () => {
  assert.ok(OPERATOR_PROCEDURE.includes(STAGING_PROFILE));
  assert.ok(OPERATOR_PROCEDURE.includes("DURATION_SCALE"));
  assert.ok(OPERATOR_PROCEDURE.includes(DURATION_SCALE));
  assert.ok(OPERATOR_PROCEDURE.includes(PAYMOB_TEST_CARDS));
  assert.ok(OPERATOR_PROCEDURE.includes(ENTRY_CHAIN));
  assert.ok(OPERATOR_PROCEDURE.includes(ASSERTION));

  let evidenceText;
  try {
    evidenceText = await readFile(EVIDENCE_PATH, "utf8");
  } catch {
    assert.fail(`evidence template missing: ${path.relative(STAGING_DIR, EVIDENCE_PATH)}`);
  }
  assert.ok(
    evidenceText.includes(CITATION),
    `evidence must cite ${CITATION}`,
  );
  assert.match(evidenceText, /^## Result\b/m, "evidence must include ## Result");

  let checklistText;
  try {
    checklistText = await readFile(CHECKLIST_PATH, "utf8");
  } catch {
    assert.fail(`checklist missing: ${path.relative(STAGING_DIR, CHECKLIST_PATH)}`);
  }
  assert.match(
    checklistText,
    /^# STG-A01\b/m,
    "checklist heading must start with STG-A01",
  );
  assert.ok(
    OPERATOR_PROCEDURE.includes("manual/paymob-test-card.md"),
    "runner must include the Paymob test card checklist",
  );
});
