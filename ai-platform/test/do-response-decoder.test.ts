import { describe, expect, it } from "vitest";
import { decodeDoResponse } from "../src/quota-do/response-decoder";

describe("R2-C3 decodeDoResponse", () => {
  it("R2-C3 accepts an object carrying the sent version", () => {
    expect(decodeDoResponse({ contract_version: 1, outcome: "admitted" }, 1))
      .toEqual({ contract_version: 1, outcome: "admitted" });
    expect(decodeDoResponse({ contract_version: 0, outcome: "admitted" }, 0))
      .toEqual({ contract_version: 0, outcome: "admitted" });
  });

  it.each([
    [undefined, 1],
    [{ outcome: "admitted" }, 1],
    [{ contract_version: "1" }, 1],
    [{ contract_version: 2 }, 1],
    [{ contract_version: 1, code: "contract_version_unsupported" }, 1],
    [[{ contract_version: 1 }], 1],
    [null, 1],
  ])("R2-C3 rejects an invalid or refused response %j", (response, sentVersion) => {
    expect(decodeDoResponse(response, sentVersion)).toBeUndefined();
  });
});
