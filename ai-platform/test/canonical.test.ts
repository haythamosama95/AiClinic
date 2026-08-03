import { describe, expect, it } from "vitest";
import { CANONICAL_FIELD_MANIFEST } from "../src/contracts/canonical";
import * as canonical from "../src/contracts/canonical";

const PROVIDER_SHAPED_FIELD_NAMES = [
  "messages",
  "completion",
  "n",
  "frequency_penalty",
  "top_p",
  "logprobs",
] as const;

const EXPECTED_CHUNK_KINDS = [
  "text_delta",
  "partial_structured",
  "usage",
  "provider_note",
] as const;

function allManifestKeys(): string[] {
  return Object.values(CANONICAL_FIELD_MANIFEST).flat();
}

const requestFixture: canonical.CanonicalRequest = {
  "ordered role-tagged message parts": [
    { role: "user", content: "Summarise the visit." },
    { role: "assistant", content: "Prior context." },
  ],
  "output format directive": { type: "json", schema: { type: "object" } },
  "sampling constraints": { temperature: 0.2, top_k: 40 },
  "max output tokens": 512,
  "stop conditions": ["</s>", "END"],
  "tool/function declarations (reserved for future)": [],
  "stream flag": true,
  "deadline": 30_000,
  "correlation ids": {
    request_reference: "7QK4-2B9F",
    trace_id: "01ARZ3NDEKTSV4RRFFQ69G5FAV",
  },
};

const resultFixture: canonical.CanonicalResult = {
  "final content": { text: "Visit summary complete." },
  "usage counters": {
    input: 1200,
    output: 180,
    cached: 400,
  },
  "provider+model actually used": {
    provider: "gateway",
    model: "canonical-fixture",
  },
  "finish reason": "stop",
  "provider request id": "req-fixture-001",
  "timing breakdown": {
    queue_ms: 12,
    provider_ms: 890,
    total_ms: 950,
  },
};

const errorFixture: canonical.CanonicalError = {
  "taxonomy code": "timeout",
  "retryability": true,
  "provider-native code and message": {
    code: "deadline_exceeded",
    message: "upstream timed out",
  },
  "whether the attempt consumed budget": false,
};

function chunkFixture(
  kind: typeof EXPECTED_CHUNK_KINDS[number],
  overrides: Partial<Record<string, unknown>> = {},
) {
  return {
    "sequence number": 1,
    kind,
    payload: { sample: kind },
    "terminal flag": false,
    ...overrides,
  };
}

function assertWireKeysMatchManifest(
  wire: string,
  manifestKeys: readonly string[],
): Record<string, unknown> {
  const parsed = JSON.parse(wire) as Record<string, unknown>;
  expect(Object.keys(parsed).sort()).toEqual([...manifestKeys].sort());
  return parsed;
}

describe("T-A3-05 provider-shaped field name rejected", () => {
  it("manifest contains no key equal to a known provider-shaped token", () => {
    for (const key of allManifestKeys()) {
      expect(PROVIDER_SHAPED_FIELD_NAMES).not.toContain(key);
    }
  });

  it("introducing a provider-shaped key makes the guard fail", () => {
    expect(canonical.assertNoProviderShapedFieldNames).toBeTypeOf("function");

    const poisonedKeys = [...allManifestKeys(), "messages"];
    expect(() => canonical.assertNoProviderShapedFieldNames!(poisonedKeys)).toThrow();
  });

  it("decode rejects a provider-shaped extra key on the wire (fail closed)", () => {
    const wire = JSON.stringify({
      ...requestFixture,
      messages: [{ role: "user", content: "provider leak" }],
    });
    expect(() => canonical.decodeCanonicalRequest!(wire)).toThrow(
      /Provider-shaped field name rejected: messages/,
    );
  });

  it("encode rejects a provider-shaped extra key on the value (fail closed)", () => {
    const poisoned = {
      ...requestFixture,
      messages: [{ role: "user", content: "provider leak" }],
    };
    expect(() =>
      canonical.encodeCanonicalRequest!(
        poisoned as unknown as canonical.CanonicalRequest,
      ),
    ).toThrow(/Provider-shaped field name rejected: messages/);
  });
});

describe("T-A3-08 unknown keys rejected on decode", () => {
  it("decode rejects an unknown non-provider extra key rather than stripping it", () => {
    const wire = JSON.stringify({
      ...requestFixture,
      unexpected_canonical_field: true,
    });
    expect(() => canonical.decodeCanonicalRequest!(wire)).toThrow(
      /Unknown canonical field rejected: unexpected_canonical_field/,
    );
  });

  it("decode rejects unknown extra keys on stream chunk, result, and error", () => {
    const chunkWire = JSON.stringify({
      ...chunkFixture("text_delta"),
      extra_chunk_key: 1,
    });
    expect(() => canonical.decodeCanonicalChunk!(chunkWire)).toThrow(
      /Unknown canonical field rejected: extra_chunk_key/,
    );

    const resultWire = JSON.stringify({
      ...resultFixture,
      extra_result_key: "x",
    });
    expect(() => canonical.decodeCanonicalResult!(resultWire)).toThrow(
      /Unknown canonical field rejected: extra_result_key/,
    );

    const errorWire = JSON.stringify({
      ...errorFixture,
      extra_error_key: "x",
    });
    expect(() => canonical.decodeCanonicalError!(errorWire)).toThrow(
      /Unknown canonical field rejected: extra_error_key/,
    );
  });
});

describe("T-A3-06 chunk kinds exhaustive", () => {
  it("chunk-kind set is exactly the four §5.3 kinds", () => {
    expect(canonical.CANONICAL_CHUNK_KINDS).toEqual([...EXPECTED_CHUNK_KINDS]);
  });

  it("rejects any chunk kind outside the closed set", () => {
    expect(canonical.isCanonicalChunkKind).toBeTypeOf("function");
    expect(canonical.isCanonicalChunkKind!("not_a_kind")).toBe(false);
    expect(canonical.isCanonicalChunkKind!("text_completion")).toBe(false);
  });
});

describe("T-A3-07 terminal flag exactly once per sequence", () => {
  it("rejects an empty chunk sequence", () => {
    expect(canonical.assertExactlyOneTerminal).toBeTypeOf("function");
    expect(() => canonical.assertExactlyOneTerminal!([])).toThrow();
  });

  it("rejects a sequence with zero terminal flags", () => {
    expect(canonical.assertExactlyOneTerminal).toBeTypeOf("function");
    const sequence = [
      chunkFixture("text_delta", { "sequence number": 0, "terminal flag": false }),
      chunkFixture("usage", { "sequence number": 1, "terminal flag": false }),
    ];
    expect(() => canonical.assertExactlyOneTerminal!(sequence)).toThrow();
  });

  it("rejects a sequence with two terminal flags", () => {
    expect(canonical.assertExactlyOneTerminal).toBeTypeOf("function");
    const sequence = [
      chunkFixture("text_delta", { "sequence number": 0, "terminal flag": true }),
      chunkFixture("provider_note", { "sequence number": 1, "terminal flag": true }),
    ];
    expect(() => canonical.assertExactlyOneTerminal!(sequence)).toThrow();
  });

  it("accepts a sequence with exactly one terminal flag", () => {
    expect(canonical.assertExactlyOneTerminal).toBeTypeOf("function");
    const sequence = [
      chunkFixture("text_delta", { "sequence number": 0, "terminal flag": false }),
      chunkFixture("text_delta", { "sequence number": 1, "terminal flag": true }),
    ];
    expect(() => canonical.assertExactlyOneTerminal!(sequence)).not.toThrow();
  });
});

describe("T-A3-09 typed field schema (not unknown)", () => {
  it("decoded request fields expose typed shapes without cast-and-hope", () => {
    const decoded = canonical.decodeCanonicalRequest!(
      canonical.encodeCanonicalRequest!(requestFixture),
    );

    expect(Array.isArray(decoded["ordered role-tagged message parts"])).toBe(
      true,
    );
    expect(decoded["ordered role-tagged message parts"][0]?.role).toBe("user");
    expect(typeof decoded["max output tokens"]).toBe("number");
    expect(typeof decoded["stream flag"]).toBe("boolean");
    expect(Array.isArray(decoded["stop conditions"])).toBe(true);
    expect(decoded["correlation ids"].request_reference).toBe(
      "7QK4-2B9F",
    );
    expect(decoded["correlation ids"].trace_id).toMatch(/^[0-9A-HJKMNP-TV-Z]{26}$/i);
  });

  it("decoded result and error expose typed counters, provider+model, and taxonomy code", () => {
    const result = canonical.decodeCanonicalResult!(
      canonical.encodeCanonicalResult!(resultFixture),
    );
    expect(result["usage counters"].input).toBe(1200);
    expect(result["usage counters"].output).toBe(180);
    expect(result["provider+model actually used"].provider).toBe("gateway");
    expect(result["timing breakdown"].total_ms).toBe(950);

    const error = canonical.decodeCanonicalError!(
      canonical.encodeCanonicalError!(errorFixture),
    );
    expect(error["taxonomy code"]).toBe("timeout");
    expect(error.retryability).toBe(true);
    expect(error["provider-native code and message"].code).toBe(
      "deadline_exceeded",
    );
    expect(error["whether the attempt consumed budget"]).toBe(false);
  });

  it("message-part role tags are the closed §5.3 set", () => {
    expect(canonical.CANONICAL_MESSAGE_ROLES).toEqual([
      "system",
      "user",
      "assistant",
      "data",
    ]);
  });
});

describe("T-A3-01 round-trip canonical request", () => {
  it("encodes and decodes preserving every §5.3 field with no extra keys", () => {
    expect(canonical.encodeCanonicalRequest).toBeTypeOf("function");
    expect(canonical.decodeCanonicalRequest).toBeTypeOf("function");

    const wire = canonical.encodeCanonicalRequest!(requestFixture);
    assertWireKeysMatchManifest(wire, CANONICAL_FIELD_MANIFEST.request);

    const roundTripped = canonical.decodeCanonicalRequest!(wire);
    expect(roundTripped).toEqual(requestFixture);
  });
});

describe("T-A3-02 round-trip canonical stream chunk", () => {
  for (const kind of EXPECTED_CHUNK_KINDS) {
    it(`round-trips a ${kind} chunk preserving sequence number, kind, payload, and terminal flag`, () => {
      expect(canonical.encodeCanonicalChunk).toBeTypeOf("function");
      expect(canonical.decodeCanonicalChunk).toBeTypeOf("function");

      const fixture = chunkFixture(kind);
      const wire = canonical.encodeCanonicalChunk!(fixture);
      assertWireKeysMatchManifest(wire, CANONICAL_FIELD_MANIFEST.streamChunk);

      const roundTripped = canonical.decodeCanonicalChunk!(wire);
      expect(roundTripped).toEqual(fixture);
    });
  }
});

describe("T-A3-03 round-trip canonical result", () => {
  it("encodes and decodes preserving final content, usage, provider+model, finish reason, provider request id, and timing", () => {
    expect(canonical.encodeCanonicalResult).toBeTypeOf("function");
    expect(canonical.decodeCanonicalResult).toBeTypeOf("function");

    const wire = canonical.encodeCanonicalResult!(resultFixture);
    assertWireKeysMatchManifest(wire, CANONICAL_FIELD_MANIFEST.result);

    const roundTripped = canonical.decodeCanonicalResult!(wire);
    expect(roundTripped).toEqual(resultFixture);
  });
});

describe("T-A3-04 round-trip canonical error", () => {
  it("round-trips taxonomy code, retryability, provider-native diagnostics, and consumed-budget flag", () => {
    expect(canonical.encodeCanonicalError).toBeTypeOf("function");
    expect(canonical.decodeCanonicalError).toBeTypeOf("function");

    const wire = canonical.encodeCanonicalError!(errorFixture);
    assertWireKeysMatchManifest(wire, CANONICAL_FIELD_MANIFEST.error);

    const roundTripped = canonical.decodeCanonicalError!(wire);
    expect(roundTripped).toEqual(errorFixture);
  });

  it("rejects an unrecognised taxonomy code on decode", () => {
    const poisoned = {
      ...errorFixture,
      "taxonomy code": "definitely_not_a_taxonomy_code",
    };
    const wire = canonical.encodeCanonicalError!(
      poisoned as unknown as canonical.CanonicalError,
    );
    expect(() => canonical.decodeCanonicalError!(wire)).toThrow();
  });
});
