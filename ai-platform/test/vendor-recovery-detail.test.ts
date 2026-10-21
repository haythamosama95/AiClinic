import { describe, expect, it } from "vitest";
import { recoveryBlockedOperatorDetail } from "../src/vendor/recovery-detail";

describe("vendor recovery blocker operator details", () => {
  it("R9-PDO1: gives actionable detail for void-evidence recovery stops", () => {
    for (const reason of [
      "grant_void_recovery_evidence_missing:grant-123",
      "grant_void_recovery_evidence_invalid:grant-456",
      "grant_void_recovery_receipt_conflict:grant-789",
    ]) {
      const detail = recoveryBlockedOperatorDetail(reason);

      expect(detail).toContain(reason);
      expect(detail).toContain("do not synthesize receipts or state");
      expect(detail).toContain("original retained signed evidence");
      expect(detail).toContain("maintainer/frontier adjudication");
    }
  });

  it("R9-PDO1: leaves unrelated recovery reasons unmapped", () => {
    expect(recoveryBlockedOperatorDetail("some_other_recovery_stop")).toBe("");
  });
});
