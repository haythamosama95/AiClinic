import { readFile } from "node:fs/promises";

const FAILED_CONDITION_LINES = [
  "No `/control/*` route, `OPERATOR_BEARER_TOKEN`, `set_ai_availability`, or manual entitle path exists",
  "`workers_dev` and preview URLs are off",
  "Every channel runs contract version 1 on both sides, and the backend's `ai.contract_versions` matches the shared package",
  "AL-23 is clear. The ABO's key self-check passes.",
  "At least two operator credentials are active",
  "The issuer and service keys are registered. The issuer keys are pinned in the ABO's `ISSUER_KEYS`. The platform signing key is set.",
  "Platform D1 holds no terms or grants.",
  "The audit watcher and the heartbeat monitor are live.",
];

function evaluateRules(target) {
  const failures = [];

  if (
    target.control_route ||
    target.operator_bearer_token ||
    target.set_ai_availability ||
    target.manual_entitle_path
  ) {
    failures.push(FAILED_CONDITION_LINES[0]);
  }

  if (target.workers_dev || target.preview_urls) {
    failures.push(FAILED_CONDITION_LINES[1]);
  }

  if (target.channels_version !== 1 || target.backend_contract_versions_match !== true) {
    failures.push(FAILED_CONDITION_LINES[2]);
  }

  if (target.al_23_clear !== true || target.key_self_check_passes !== true) {
    failures.push(FAILED_CONDITION_LINES[3]);
  }

  if (target.active_operator_credentials < 2) {
    failures.push(FAILED_CONDITION_LINES[4]);
  }

  if (
    target.issuer_keys_registered !== true ||
    target.service_keys_registered !== true ||
    target.issuer_keys_pinned !== true ||
    target.platform_signing_key_set !== true
  ) {
    failures.push(FAILED_CONDITION_LINES[5]);
  }

  if (target.platform_d1_terms !== 0 || target.platform_d1_grants !== 0) {
    failures.push(FAILED_CONDITION_LINES[6]);
  }

  if (target.audit_watcher_live !== true || target.heartbeat_monitor_live !== true) {
    failures.push(FAILED_CONDITION_LINES[7]);
  }

  return failures;
}

async function main() {
  const fixturePath = process.argv[2];
  if (!fixturePath) {
    process.exit(1);
  }

  const target = JSON.parse(await readFile(fixturePath, "utf8"));
  const failures = evaluateRules(target);

  for (const line of failures) {
    console.log(line);
  }

  process.exit(failures.length === 0 ? 0 : 1);
}

main().catch(() => {
  process.exit(1);
});
