import { describe, expect, it } from "vitest";
import * as vendorContracts from "vendor-contracts";
import canonicalVectors from "../vectors/canonical.json";

function bytesToHex(bytes: Uint8Array): string {
  return Buffer.from(bytes).toString("hex");
}

describe("canonical", () => {
  it("E2E-P2.1-01 canonicalizes every vector object to the fixture bytes", () => {
    const { canonicalize } = vendorContracts;
    expect(canonicalize).toBeTypeOf("function");

    for (const case_ of canonicalVectors.cases) {
      const actual = canonicalize(case_.value);
      expect(bytesToHex(actual)).toBe(case_.canonical_hex);
    }
  });
});
