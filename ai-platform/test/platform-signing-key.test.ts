import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import { loadPlatformSigningKey } from "../src/quota-do/coverage";

const PUBLISHED_KEY =
  '{"kid":"platform-test","pkcs8":"MC4CAQAwBQYDK2VwBCIEIN2ndQQArm1dlsCuHaGGaUB8nnqfj7W2HaVbj_JJA9Lk","public_key":"GNzxZ6Gymues_aeJArGyb3wDESTOUJeqhuZBfTByni0"}';

function bytesToBase64Url(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/u, "");
}

describe("R9-RT3 platform receipt signing key", () => {
  it("keeps the published private key only in development configuration", () => {
    const config = readFileSync(new URL("../wrangler.toml", import.meta.url), "utf8");
    const staging = config.split("[env.staging.vars]")[1]?.split("[env.staging.send_email]")[0] ?? "";
    const production = config.split("[env.production.vars]")[1]?.split("[env.production.send_email]")[0] ?? "";
    const development = config.split("[env.development.vars]")[1]?.split("[env.development.send_email]")[0] ?? "";

    expect(development).toContain("PLATFORM_SIGNING_KEY");
    expect(staging).not.toContain("PLATFORM_SIGNING_KEY");
    expect(production).not.toContain("PLATFORM_SIGNING_KEY");
  });

  it("rejects the published key in staging even when its kid is renamed", async () => {
    const renamed = JSON.stringify({ ...JSON.parse(PUBLISHED_KEY), kid: "rotated-kid" });
    await expect(loadPlatformSigningKey(renamed, "staging")).resolves.toBeNull();
    await expect(loadPlatformSigningKey(renamed, "production")).resolves.toBeNull();
  });

  it("fails closed when non-development signing material is missing or unusable", async () => {
    await expect(loadPlatformSigningKey(undefined, "production")).resolves.toBeNull();
    await expect(loadPlatformSigningKey("not-json", "staging")).resolves.toBeNull();
  });

  it("accepts a separately generated key for non-development signing", async () => {
    const pair = await crypto.subtle.generateKey("Ed25519", true, ["sign", "verify"]);
    const pkcs8 = new Uint8Array(await crypto.subtle.exportKey("pkcs8", pair.privateKey));
    const json = JSON.stringify({ kid: "staging-2026-10", pkcs8: bytesToBase64Url(pkcs8) });
    const material = await loadPlatformSigningKey(json, "staging");

    expect(material?.kid).toBe("staging-2026-10");
    const payload = new TextEncoder().encode("R9-RT3 staging receipt");
    const signature = await crypto.subtle.sign("Ed25519", material!.privateKey, payload);
    await expect(
      crypto.subtle.verify("Ed25519", pair.publicKey, signature, payload),
    ).resolves.toBe(true);
  });
});
