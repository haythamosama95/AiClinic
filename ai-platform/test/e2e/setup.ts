import { beforeEach } from "vitest";
import { isolateConfigCache } from "../../src/config-cache";
// Import for its side effect: stub the real `send_email` binding so workerd's
// local mail pipeline is never exercised in e2e (its parse failures become
// uncaught promise rejections that desync isolated-storage accounting).
// See test/stub-send-email-binding.ts for the full rationale.
import "../stub-send-email-binding";

beforeEach(() => {
  isolateConfigCache.clear();
});
