/**
 * Build gate entrypoint: npm run verify-manifests → this file.
 * Fails CI/build when a published manifest is edited in place.
 */
import { describe, expect, it } from "vitest";
import { readdir, readFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { verifyManifestTree } from "../src/manifest";

const root = path.join(path.dirname(fileURLToPath(import.meta.url)), "..");

describe("verify-manifests build gate", () => {
  it("checked-in published manifests match the append-only registry", async () => {
    await expect(
      verifyManifestTree({
        manifestsDir: path.join(root, "manifests", "published"),
        registryPath: path.join(root, "manifests", "published-registry.json"),
        readFile: (p) => readFile(p, "utf8"),
        readdir,
        join: path.join,
      }),
    ).resolves.toBeUndefined();
  });
});
