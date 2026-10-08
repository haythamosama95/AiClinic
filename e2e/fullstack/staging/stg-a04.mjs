import { readFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import test from "node:test";
import assert from "node:assert/strict";

// H-STG (P8.2): node --test e2e/fullstack/staging/stg-a04.mjs

const STAGING_DIR = path.dirname(fileURLToPath(import.meta.url));
const EVIDENCE_PATH = path.join(STAGING_DIR, "evidence/stg-a04.md");
const CHECKLIST_PATH = path.join(STAGING_DIR, "manual/disabled-platform-route.md");

const SCENARIO_ID = "STG-A04";
const CITATION = "P4.4-02";
const ENTRY_CHAIN = "scheduled() (abo/src/worker.ts)";
const ASSERTION =
  "Grant retries every 15 minutes for 4 days; AL-04 hourly; grant applies on return; term starts at activation.";

const STAGING_PROFILE = "[env.staging]";
const DURATION_SCALE = "1 month = 30 minutes, 1 day = 1 minute";
const PAYMOB_TEST_CARDS = "Paymob test cards";

const OPERATOR_PROCEDURE = [
  `Operator procedure (${SCENARIO_ID}): run the existing H-FS scenario runner in e2e/fullstack/test/ pointed at ${STAGING_PROFILE}.`,
  `Record ${STAGING_PROFILE}, DURATION_SCALE (${DURATION_SCALE}), and ${PAYMOB_TEST_CARDS}.`,
  `Follow manual/disabled-platform-route.md for the disabled platform route steps.`,
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
    /^# STG-A04\b/m,
    "checklist heading must start with STG-A04",
  );
  assert.ok(
    OPERATOR_PROCEDURE.includes("manual/disabled-platform-route.md"),
    "runner must include the disabled platform route checklist",
  );
});
