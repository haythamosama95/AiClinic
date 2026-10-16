/**
 * PLATFORM throw stub for E2E-P4.2-03 (vitest.platform-throw.config).
 * Plain JS syntax — Miniflare auxiliary workers are not TS-transpiled.
 */

import { WorkerEntrypoint } from "cloudflare:workers";

const TRANSIENT_UNAVAILABLE = {
  contract_version: 1,
  result: "transient",
  code: "transient",
  detail: "unavailable",
};

function throwUnlessTransient(method, args) {
  if (method === "getCoverage") {
    const orgId = args.org_id;
    if (typeof orgId === "string" && orgId.endsWith("aa")) {
      return;
    }
  }
  throw new Error(`${method} forced failure in platform-throw stub`);
}

export class VendorEntrypoint extends WorkerEntrypoint {
  async getCoverage(args) {
    throwUnlessTransient("getCoverage", args);
    const orgId = args.org_id;
    if (typeof orgId === "string" && orgId.endsWith("aa")) {
      return TRANSIENT_UNAVAILABLE;
    }
    throw new Error("getCoverage forced failure in platform-throw stub");
  }

  async publishPlanVersion() {
    throw new Error("publishPlanVersion forced failure in platform-throw stub");
  }

  async registerServiceKey() {
    throw new Error("registerServiceKey forced failure in platform-throw stub");
  }

  async grant() {
    throw new Error("grant forced failure in platform-throw stub");
  }

  async readCoverageEvents() {
    throw new Error("readCoverageEvents forced failure in platform-throw stub");
  }

  async listGrants() {
    throw new Error("listGrants forced failure in platform-throw stub");
  }
}
