import { env } from "cloudflare:test";

export type StubSendEmailMessage = {
  from: string;
  to: string;
  subject: string;
  text: string;
};

/** Emails captured by the stub, for tests that want to assert on them. */
export const capturedStubEmails: StubSendEmailMessage[] = [];

/**
 * Replace the real wrangler `send_email` binding with a capturing stub.
 *
 * The `SEND_EMAIL` binding comes from wrangler.toml (`[env.development.send_email]`)
 * and is backed by workerd's local mail pipeline. That pipeline cannot parse the
 * plain-object messages our alert code passes (`{ from, to, subject, text }` — the
 * shape frozen by the vendor contract and mirrored in test/system/harness.ts
 * `vendorSendEmailBinding`). Each attempt fails inside workerd with
 * `Error: could not parse email: Cannot read properties of undefined (reading 'value')`
 * as an UNCAUGHT promise rejection — the rejection escapes workerd-internal
 * promises, so no `try/catch` around `env.SEND_EMAIL.send(...)` can observe it.
 * The resulting storm (~2000 per CI run) desyncs @cloudflare/vitest-pool-workers
 * per-test isolated-storage accounting and fails effectively random later tests
 * with "Isolated storage failed. There should be additional logs above."
 *
 * Stubbing the binding here mirrors the system harness (test/system/harness.ts)
 * and keeps local test runs entirely off workerd's mail sender. Production is
 * unchanged: `src/alert/email.ts` still calls the real binding when deployed.
 */
export function stubSendEmailBinding(): void {
  const bindings = env as {
    SEND_EMAIL?: { send(message: StubSendEmailMessage): Promise<void> };
  };
  const stub = {
    async send(message: StubSendEmailMessage): Promise<void> {
      capturedStubEmails.push({ ...message });
    },
  };
  if (bindings.SEND_EMAIL === undefined) {
    bindings.SEND_EMAIL = stub;
  } else {
    // Mutate the existing binding object in place: the worker, the Durable
    // Object class, and the tests all share this same global env object.
    Object.assign(bindings.SEND_EMAIL, stub);
  }
}

stubSendEmailBinding();
