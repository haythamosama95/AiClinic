import { afterEach, beforeEach } from "vitest";
import { isolateConfigCache } from "../../src/config-cache";
import { drainGatewayObjects } from "./harness/do-drain";

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