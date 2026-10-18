import { describe, expect, it } from "vitest";
import { CHANNEL_VERSIONS } from "vendor-contracts";
import {
  requireAipContractVersion,
  withAipContractVersion,
} from "../src/vendor/contract-version";

describe("withAipContractVersion", () => {
  it("R2-C2: unsupported negotiation returns current version and accepted versions", async () => {
    const negotiation = requireAipContractVersion(
      new Request("https://platform.test/v1/coverage", {
        headers: { "Aip-Contract-Version": "999" },
      }),
    );

    expect(negotiation.ok).toBe(false);
    if (negotiation.ok) return;
    expect(negotiation.response.status).toBe(400);
    await expect(negotiation.response.json()).resolves.toEqual({
      contract_version: CHANNEL_VERSIONS.platformClinic,
      code: "contract_version_unsupported",
      accepted_versions: expect.any(Array),
    });
  });

  it("R2-C2: echoes the negotiated version in JSON body and header", async () => {
    const response = withAipContractVersion(
      Response.json({ code: "forbidden_role" }),
      0,
    );

    expect(response.headers.get("Aip-Contract-Version")).toBe("0");
    await expect(response.json()).resolves.toEqual({
      code: "forbidden_role",
      contract_version: 0,
    });
  });

  it("R2-C2: overwrites stale JSON metadata with the negotiated version", async () => {
    const response = withAipContractVersion(
      Response.json({
        contract_version: 99,
        code: "contract_version_unsupported",
        accepted_versions: [0, 1],
      }),
      1,
    );

    await expect(response.json()).resolves.toEqual({
      contract_version: 1,
      code: "contract_version_unsupported",
      accepted_versions: [0, 1],
    });
  });

  it("R2-C2: preserves empty and 304 response bodies", async () => {
    const empty = withAipContractVersion(new Response(null, { status: 204 }), 1);
    const notModified = withAipContractVersion(
      new Response(null, { status: 304, headers: { "content-type": "application/json" } }),
      1,
    );

    expect(empty.headers.get("Aip-Contract-Version")).toBe("1");
    expect(empty.body).toBeNull();
    expect(notModified.headers.get("Aip-Contract-Version")).toBe("1");
    expect(notModified.body).toBeNull();
  });

  it("R2-C2: leaves SSE bytes unchanged while adding the version header", async () => {
    const bytes = new TextEncoder().encode("data: {\"ok\":true}\n\n");
    const response = withAipContractVersion(
      new Response(bytes, { headers: { "content-type": "text/event-stream" } }),
      1,
    );

    expect(response.headers.get("Aip-Contract-Version")).toBe("1");
    expect(new Uint8Array(await response.arrayBuffer())).toEqual(bytes);
  });
});
