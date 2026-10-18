import { describe, expect, it } from "vitest";
import { validateResultEnvelope } from "../src/result-envelope.js";

describe("R2-C2 validateResultEnvelope", () => {
  it("R2-C2 accepts accepted_versions only on an unsupported-version refusal", () => {
    expect(validateResultEnvelope({
      contract_version: 1,
      result: "rejected",
      code: "contract_version_unsupported",
      detail: "",
      accepted_versions: [0, 1],
    })).toEqual({ ok: true });
  });

  it("R2-C2 rejects accepted_versions on other results or with invalid values", () => {
    for (const envelope of [
      {
        contract_version: 1,
        result: "rejected",
        code: "bad_signature",
        detail: "",
        accepted_versions: [1, 2],
      },
      {
        contract_version: 1,
        result: "rejected",
        code: "contract_version_unsupported",
        detail: "",
        accepted_versions: [1, 1],
      },
      {
        contract_version: 1,
        result: "rejected",
        code: "contract_version_unsupported",
        detail: "",
        accepted_versions: [-1, 1],
      },
      {
        contract_version: 1,
        result: "rejected",
        code: "contract_version_unsupported",
        detail: "",
        accepted_versions: [0, 1.5],
      },
      {
        contract_version: 1,
        result: "ok",
        code: "",
        detail: "",
        accepted_versions: [1, 2],
      },
    ]) {
      expect(validateResultEnvelope(envelope)).toEqual({ ok: false });
    }
  });
});
