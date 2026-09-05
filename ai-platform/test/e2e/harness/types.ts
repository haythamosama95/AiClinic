import type { TestKeypair } from "./crypto";

export type Scenario = {
  installationId: string;
  orgId: string;
  branchId: string;
  actorId: string;
  kid: string;
  keypair: TestKeypair;
};
