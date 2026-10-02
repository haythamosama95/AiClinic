import { describe, expect, it } from "vitest";
import * as vendorContracts from "vendor-contracts";
import identifierVectors from "../vectors/identifiers.json";

describe("identifiers", () => {
  it("E2E-P2.1-03 matches subscription ref and grant_id(paid) vectors", async () => {
    const { subscriptionRef, grantIdPaid } = vendorContracts;
    expect(subscriptionRef).toBeTypeOf("function");
    expect(grantIdPaid).toBeTypeOf("function");

    const { org_id, result: expectedSubRef } =
      identifierVectors.subscription_ref;
    expect(await subscriptionRef(org_id)).toBe(expectedSubRef);

    const { payment_id, result: expectedGrantIdPaid } =
      identifierVectors.grant_id_paid;
    expect(await grantIdPaid(payment_id)).toBe(expectedGrantIdPaid);
  });
});
