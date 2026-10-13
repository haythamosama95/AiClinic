import { afterEach, beforeEach } from "vitest";
import { isolateConfigCache } from "../../src/config-cache";
import { drainGatewayObjects } from "./harness/do-drain";
import { env } from "./harness/env";

// Harness-only stub (mirrors test/system/harness.ts): wrangler.toml's
// development `send_email` binding maps to Miniflare's SendEmailBinding,
// which throws "could not parse email" on the plain {from,to,subject,text}
// shape the gateway sends. Each drained alert row produced an uncaught
// rejection (2,238 in run #38385948587) exactly during isolated-storage
// frame transitions. A resolving no-op removes that teardown noise; no
// test semantics change.
const sendEmailBinding = (env as { SEND_EMAIL?: unknown }).SEND_EMAIL;
if (sendEmailBinding !== undefined && typeof sendEmailBinding === "object") {
  Object.assign(sendEmailBinding, { send: async () => {} });
}

beforeEach(() => {
  isolateConfigCache.clear();
});

// Harness-only teardown guard (see ./harness/do-drain.ts): flush pending
// GatewayObject outbox rows and disarm wall-clock DO coverage alarms before
// the isolated-storage frame pops, so the next test's frame push cannot fail
// with "Expected .sqlite, got ....sqlite-journal". All drain writes happen in
// the current test's frame and roll back with it; no test semantics change.
afterEach(async () => {
  await drainGatewayObjects();
});