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
  parts: [
    { role: "user", content: "Summarise the visit." },
    { role: "assistant", content: "Prior context." },
  ],
  formatDirective: { type: "json", schema: { type: "object" } },
  samplingConstraints: { temperature: 0.2, top_k: 40 },
  maxOutputTokens: 512,
  stopConditions: ["</s>", "END"],
  toolDeclarations: [],
  stream: true,
  "deadline": 30_000,
  correlationIds: {
    request_reference: "7QK4-2B9F",
    trace_id: "01ARZ3NDEKTSV4RRFFQ69G5FAV",
  },
};

const resultFixture: canonical.CanonicalResult = {
  finalContent: { text: "Visit summary complete." },
  usage: {
    input: 1200,
    output: 180,
    cached: 400,
  },
  providerModel: {
    provider: "gateway",
    model: "canonical-fixture",
  },
  finishReason: "stop",
  providerRequestId: "req-fixture-001",
  timing: {
    queue_ms: 12,
    provider_ms: 890,
    total_ms: 950,
  },
};

const errorFixture: canonical.CanonicalError = {
  taxonomyCode: "timeout",
  "retryability": true,
  providerNative: {
    code: "deadline_exceeded",
    message: "upstream timed out",
  },
  consumedBudget: false,
};

function chunkFixture(
  kind: typeof EXPECTED_CHUNK_KINDS[number],
  overrides: Partial<Record<string, unknown>> = {},
) {
  return {
    sequenceNumber: 1,
    kind,
    payload: { sample: kind },
    terminal: false,
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
      chunkFixture("text_delta", { sequenceNumber: 0, terminal: false }),
      chunkFixture("usage", { sequenceNumber: 1, terminal: false }),
    ];
    expect(() => canonical.assertExactlyOneTerminal!(sequence)).toThrow();
  });

  it("rejects a sequence with two terminal flags", () => {
    expect(canonical.assertExactlyOneTerminal).toBeTypeOf("function");
    const sequence = [
      chunkFixture("text_delta", { sequenceNumber: 0, terminal: true }),
      chunkFixture("provider_note", { sequenceNumber: 1, terminal: true }),
    ];
    expect(() => canonical.assertExactlyOneTerminal!(sequence)).toThrow();
  });

  it("accepts a sequence with exactly one terminal flag", () => {
    expect(canonical.assertExactlyOneTerminal).toBeTypeOf("function");
    const sequence = [
      chunkFixture("text_delta", { sequenceNumber: 0, terminal: false }),
      chunkFixture("text_delta", { sequenceNumber: 1, terminal: true }),
    ];
    expect(() => canonical.assertExactlyOneTerminal!(sequence)).not.toThrow();
  });
});

describe("T-A3-09 typed field schema (not unknown)", () => {
  it("decoded request fields expose typed shapes without cast-and-hope", () => {
    const decoded = canonical.decodeCanonicalRequest!(
      canonical.encodeCanonicalRequest!(requestFixture),
    );

    expect(Array.isArray(decoded.parts)).toBe(
      true,
    );
    expect(decoded.parts[0]?.role).toBe("user");
    expect(typeof decoded.maxOutputTokens).toBe("number");
    expect(typeof decoded.stream).toBe("boolean");
    expect(Array.isArray(decoded.stopConditions)).toBe(true);
    expect(decoded.correlationIds.request_reference).toBe(
      "7QK4-2B9F",
    );
    expect(decoded.correlationIds.trace_id).toMatch(/^[0-9A-HJKMNP-TV-Z]{26}$/i);
  });

  it("decoded result and error expose typed counters, provider+model, and taxonomy code", () => {
    const result = canonical.decodeCanonicalResult!(
      canonical.encodeCanonicalResult!(resultFixture),
    );
    expect(result.usage.input).toBe(1200);
    expect(result.usage.output).toBe(180);
    expect(result.providerModel.provider).toBe("gateway");
    expect(result.timing.total_ms).toBe(950);

    const error = canonical.decodeCanonicalError!(
      canonical.encodeCanonicalError!(errorFixture),
    );
    expect(error.taxonomyCode).toBe("timeout");
    expect(error.retryability).toBe(true);
    expect(error.providerNative.code).toBe(
      "deadline_exceeded",
    );
    expect(error.consumedBudget).toBe(false);
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

describe("T-A3-10 §5.3 field identifiers (not prose contents)", () => {
  const EXPECTED_IDENTIFIERS = {
    request: [
      "parts",
      "formatDirective",
      "samplingConstraints",
      "maxOutputTokens",
      "stopConditions",
      "toolDeclarations",
      "stream",
      "deadline",
      "correlationIds",
    ],
    streamChunk: ["sequenceNumber", "kind", "payload", "terminal"],
    result: [
      "finalContent",
      "usage",
      "providerModel",
      "finishReason",
      "providerRequestId",
      "timing",
    ],
    error: [
      "taxonomyCode",
      "retryability",
      "providerNative",
      "consumedBudget",
    ],
  } as const;

  const FORBIDDEN_PROSE_KEYS = [
    "ordered role-tagged message parts",
    "output format directive",
    "sampling constraints",
    "max output tokens",
    "stop conditions",
    "tool/function declarations (reserved for future)",
    "stream flag",
    "correlation ids",
    "sequence number",
    "terminal flag",
    "final content",
    "usage counters",
    "provider+model actually used",
    "finish reason",
    "provider request id",
    "timing breakdown",
    "taxonomy code",
    "provider-native code and message",
    "whether the attempt consumed budget",
  ];

  it("manifest uses camelCase identifiers from amended §5.3, not contents prose", () => {
    expect([...CANONICAL_FIELD_MANIFEST.request]).toEqual([
      ...EXPECTED_IDENTIFIERS.request,
    ]);
    expect([...CANONICAL_FIELD_MANIFEST.streamChunk]).toEqual([
      ...EXPECTED_IDENTIFIERS.streamChunk,
    ]);
    expect([...CANONICAL_FIELD_MANIFEST.result]).toEqual([
      ...EXPECTED_IDENTIFIERS.result,
    ]);
    expect([...CANONICAL_FIELD_MANIFEST.error]).toEqual([
      ...EXPECTED_IDENTIFIERS.error,
    ]);
  });

  it("no prose contents key remains in the frozen manifest", () => {
    for (const key of allManifestKeys()) {
      expect(FORBIDDEN_PROSE_KEYS).not.toContain(key);
    }
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
      taxonomyCode: "definitely_not_a_taxonomy_code",
    };
    const wire = canonical.encodeCanonicalError!(
      poisoned as unknown as canonical.CanonicalError,
    );
    expect(() => canonical.decodeCanonicalError!(wire)).toThrow();
  });

  it("optional retryAfterMs is a runtime CanonicalError field (not wire-manifest)", () => {
    const withRetry: canonical.CanonicalError = {
      ...errorFixture,
      retryAfterMs: 5_000,
    };
    expect(withRetry.retryAfterMs).toBe(5_000);
    // Wire codec still encodes only §5.3 manifest keys — omit retryAfterMs first.
    const { retryAfterMs: _omit, ...wireShape } = withRetry;
    const wire = canonical.encodeCanonicalError!(wireShape);
    assertWireKeysMatchManifest(wire, CANONICAL_FIELD_MANIFEST.error);
    expect(JSON.parse(wire)).not.toHaveProperty("retryAfterMs");
  });
});
