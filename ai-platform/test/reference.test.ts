import { describe, expect, it } from "vitest";
import {
  generateRequestReference,
  normalizeRequestReference,
} from "../src/reference";

const REFERENCE_PATTERN = /^[0-9A-HJKMNP-TV-Z]{4}-[0-9A-HJKMNP-TV-Z]{4}$/;
const FORBIDDEN_CHARS = /[ILOU]/;
const GENERATION_RUN = 1_000_000;

describe("request reference generator (T21)", () => {
  it("produces format-valid, uppercase, Crockford-base32 references unique across 1,000,000 draws", () => {
    const seen = new Set<string>();

    for (let index = 0; index < GENERATION_RUN; index += 1) {
      const reference = generateRequestReference();

      expect(reference).toMatch(REFERENCE_PATTERN);
      expect(reference).toBe(reference.toUpperCase());
      expect(reference).not.toMatch(FORBIDDEN_CHARS);
      expect(seen.has(reference)).toBe(false);
      seen.add(reference);
    }

    expect(seen.size).toBe(GENERATION_RUN);
  });
});

describe("request reference normalisation (T28)", () => {
  it("normalises lowercase and I/L/O-confused input to the stored reference form", () => {
    expect(normalizeRequestReference("7qk4-2b9f")).toBe("7QK4-2B9F");
    expect(normalizeRequestReference("7QK4-2B9F")).toBe("7QK4-2B9F");
    expect(normalizeRequestReference("7IK4-2O9F")).toBe("71K4-209F");
    expect(normalizeRequestReference("ilil-oilo")).toBe("1111-0110");
  });
});
