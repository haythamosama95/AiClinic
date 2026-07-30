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

const requestFixture = {
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

const resultFixture = {
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

const errorFixture = {
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
    const wire = canonical.encodeCanonicalError!(poisoned);
    expect(() => canonical.decodeCanonicalError!(wire)).toThrow();
  });
});
