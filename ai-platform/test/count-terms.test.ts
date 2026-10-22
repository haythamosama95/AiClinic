import { env, runInDurableObject } from "cloudflare:test";
import { describe, expect, it } from "vitest";
import { CHANNEL_VERSIONS } from "vendor-contracts";
import { countTermsRPC, sqlExec } from "../src/quota-do/coverage";

const CONTRACT_VERSION = CHANNEL_VERSIONS.platformDo;
const RPC_URL = "https://quota-do.internal/rpc";

describe("R9-RT1 count_terms", () => {
  it("R9-RT1 count_terms returns COUNT(*) of term rows and writes nothing", async () => {
    const statements: string[] = [];
    const storage = {
      sql: {
        exec(query: string) {
          statements.push(query);
          return [{ count: 3 }];
        },
      },
    } as unknown as DurableObjectStorage;

    const result = await countTermsRPC(storage, (fn) => fn(), {
      kind: "count_terms",
      contract_version: CONTRACT_VERSION,
      installationId: "inst-count-terms-fake",
    });

    expect(result).toEqual({ kind: "count_terms", terms: 3 });
    expect(statements).toEqual(["SELECT COUNT(*) AS count FROM term"]);
  });

  it("R9-RT1 count_terms fails when SQL storage is unavailable", async () => {
    const storage = {} as DurableObjectStorage;

    await expect(
      countTermsRPC(storage, (fn) => fn(), {
        kind: "count_terms",
        contract_version: CONTRACT_VERSION,
        installationId: "inst-count-terms-no-sql",
      }),
    ).rejects.toThrow(/SQL storage unavailable/);
  });

  it("R9-RT1 count_terms answers recovery_blocked while rebuilding", async () => {
    const installationId = "inst-count-terms-rebuild";
    const stub = env.DO.get(env.DO.idFromName(installationId));
    const request = () =>
      stub.fetch(RPC_URL, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          kind: "count_terms",
          contract_version: CONTRACT_VERSION,
          installationId,
        }),
      });

    // The first versioned fetch creates the per-clinic tables.
    const ready = await request();
    expect(ready.status).toBe(200);

    await runInDurableObject(stub, async (_instance, state) => {
      sqlExec(
        state,
        `INSERT INTO recovery_state (
          singleton, generation, installation_id, org_id, binding_epoch,
          anchor_event_id, status, updated_at
        ) VALUES (1, '${installationId}:1:evt-1', '${installationId}', 'org-count-terms',
          1, 'evt-1', 'building', '2026-10-21T00:00:00.000Z')`,
      );
    });

    const blocked = await request();
    expect(blocked.status).toBe(409);
    expect(await blocked.json()).toEqual(
      expect.objectContaining({
        kind: "count_terms",
        result: "recovery_blocked",
      }),
    );
  });
});
