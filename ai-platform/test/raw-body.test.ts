import { describe, expect, it } from "vitest";
import {
  ENVELOPE_RAW_BODY_BYTE_LIMIT,
  captureRawProviderBody,
} from "../src/provider/raw-body";

describe("captureRawProviderBody", () => {
  it("parses JSON under the cap without truncating", () => {
    const payload = { id: "ds-1", choices: [{ message: { content: "ok" } }] };
    expect(captureRawProviderBody(JSON.stringify(payload))).toEqual({
      payload,
      truncated: false,
    });
  });

  it("keeps non-JSON text under the cap", () => {
    expect(captureRawProviderBody("not-json")).toEqual({
      payload: "not-json",
      truncated: false,
    });
  });

  it("truncates at 16 KB and sets the truncated flag", () => {
    const text = "H".repeat(ENVELOPE_RAW_BODY_BYTE_LIMIT + 50);
    const captured = captureRawProviderBody(text);
    expect(captured.truncated).toBe(true);
    expect(typeof captured.payload).toBe("string");
    const bytes = new TextEncoder().encode(String(captured.payload));
    expect(bytes.byteLength).toBeLessThanOrEqual(ENVELOPE_RAW_BODY_BYTE_LIMIT);
  });
});
