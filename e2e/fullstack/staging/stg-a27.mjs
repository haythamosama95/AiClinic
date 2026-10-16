import { readFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import test from "node:test";
import assert from "node:assert/strict";

// H-STG (P8.2): node --test e2e/fullstack/staging/stg-a27.mjs

const STAGING_DIR = path.dirname(fileURLToPath(import.meta.url));
const EVIDENCE_PATH = path.join(STAGING_DIR, "evidence/stg-a27.md");

const SCENARIO_ID = "STG-A27";
const CITATION = "P3.6-02, P4.8-02, P7.2-06";
const ENTRY_CHAIN = "Ops host HP complimentary grant (abo/src/worker.ts)";
const ASSERTION =
  "No grant without the passkey; 31-day ceiling blocks a year; override needs a second assertion and raises AL-12; AL-11 within minutes; grants listable and voidable.";

const STAGING_PROFILE = "[env.staging]";
const DURATION_SCALE = "1 month = 30 minutes, 1 day = 1 minute";
const PAYMOB_TEST_CARDS = "Paymob test cards";

const OPERATOR_PROCEDURE = [
  `Operator procedure (${SCENARIO_ID}): run the existing H-FS scenario runner in e2e/fullstack/test/ pointed at ${STAGING_PROFILE}.`,
  `Record ${STAGING_PROFILE}, DURATION_SCALE (${DURATION_SCALE}), and ${PAYMOB_TEST_CARDS}.`,
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
});
