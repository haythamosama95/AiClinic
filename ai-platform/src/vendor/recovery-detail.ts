export function recoveryBlockedOperatorDetail(reason?: string): string {
  if (typeof reason !== "string" || reason.length === 0) {
    return "recovery_blocked: recovery is fenced because retained recovery evidence could not be verified. Preserve existing Durable Object and D1 state unchanged; do not synthesize evidence or receipts. Operator checklist: retain the original evidence and request maintainer/frontier adjudication.";
  }

  if (reason === "transfer_replay_evidence_missing") {
    return "transfer_replay_evidence_missing: recovery is fenced because a D1 transfer step has no byte-verifiable Durable Object replay. Preserve existing transfer_replay and D1 transfer_step rows unchanged; do not synthesize request hashes or response_json. Operator checklist: compare each transfer_id/step receipt against its Durable Object replay, retain the original evidence, then request maintainer/frontier adjudication for missing historical bytes.";
  }

  if (reason === "grant_route_seal_evidence_missing") {
    return "grant_route_seal_evidence_missing: recovery is fenced because a routed grant claim has no exact Durable Object route seal. Preserve the D1 claim and any existing route seal unchanged; do not synthesize a seal. Operator checklist: compare the claim envelope hash and route generation to the original Durable Object seal, retain the evidence, then request maintainer/frontier adjudication for missing historical bytes.";
  }

  if (reason.startsWith("grant_void_recovery_")) {
    return `${reason}: recovery is blocked because the grant-void evidence could not be verified or reconciled. Preserve the existing grant ledger, void state, and receipts unchanged; do not synthesize receipts or state. Operator checklist: retrieve and retain the original signed void evidence and its provenance, compare it with the grant ledger and stored receipt, then request maintainer/frontier adjudication using that original retained signed evidence.`;
  }

  if (reason.startsWith("usage_accounting_")) {
    return `Recovery blocked by ${reason}; maintainer adjudication is needed.`;
  }

  return "";
}
