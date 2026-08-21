import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { wallClockSleeper } from "../src/wall-clock-sleeper";

const ROOT = path.join(path.dirname(fileURLToPath(import.meta.url)), "..");
const WORKER_PATH = path.join(ROOT, "src", "worker.ts");

describe("production wall-clock sleeper wiring", () => {
  it("passes wallClockSleeper into runInvocation, not an inline no-op", () => {
    const source = fs.readFileSync(WORKER_PATH, "utf8");
    expect(source).toMatch(/sleeper:\s*wallClockSleeper\b/);
    expect(source).not.toMatch(/sleeper:\s*async\s*\(\s*\)\s*=>\s*\{\s*\}/);
  });

  describe("wallClockSleeper", () => {
    beforeEach(() => {
      vi.useFakeTimers();
    });

    afterEach(() => {
      vi.useRealTimers();
    });

    it("does not resolve until the requested delay has elapsed", async () => {
      let resolved = false;
      const pending = wallClockSleeper(250).then(() => {
        resolved = true;
      });

      await Promise.resolve();
      expect(resolved).toBe(false);

      await vi.advanceTimersByTimeAsync(249);
      expect(resolved).toBe(false);

      await vi.advanceTimersByTimeAsync(1);
      await pending;
      expect(resolved).toBe(true);
    });
  });
});
