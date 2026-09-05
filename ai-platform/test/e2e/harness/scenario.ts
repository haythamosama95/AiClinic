import { generateTestKeypair } from "./crypto";
import {
  canaryPolicy,
  DEFAULT_ENTITLE_PAYLOAD,
  enrollInstallation,
  entitleInstallation,
  fakePolicyDocument,
  promotePolicy,
  publishPolicy,
  type EntitlePayload,
} from "./control";
import { CAPABILITY_ID, POLICY_ID, POLICY_VERSION } from "./env";
import type { Scenario } from "./types";

export type { Scenario };

export async function newScenario(): Promise<Scenario> {
  const kid = crypto.randomUUID();
  const keypair = await generateTestKeypair(kid);
  return {
    installationId: crypto.randomUUID(),
    orgId: crypto.randomUUID(),
    branchId: crypto.randomUUID(),
    actorId: crypto.randomUUID(),
    kid,
    keypair,
  };
}

/**
 * Real enroll path (POST `/control/installations/{id}/enroll`) + entitle +
 * publish/promote a fake-provider routing policy. Use this to build prior
 * state for clinic-facing journeys. Not `[SEED]`.
 */
export async function provisionHappyPath(
  scenario?: Scenario,
  entitle: EntitlePayload = DEFAULT_ENTITLE_PAYLOAD,
): Promise<Scenario> {
  const ready = scenario ?? (await newScenario());
  const enrolled = await enrollInstallation(ready);
  if (enrolled.status !== 200) {
    throw new Error(
      `provisionHappyPath: enroll failed (${enrolled.status}): ${enrolled.text}`,
    );
  }
  const entitled = await entitleInstallation(ready, entitle);
  if (entitled.status !== 200) {
    throw new Error(
      `provisionHappyPath: entitle failed (${entitled.status}): ${entitled.text}`,
    );
  }
  const document = fakePolicyDocument(POLICY_ID, POLICY_VERSION);
  const published = await publishPolicy(POLICY_ID, POLICY_VERSION, document);
  if (published.status !== 200) {
    throw new Error(
      `provisionHappyPath: publish failed (${published.status}): ${published.text}`,
    );
  }
  const promoted = await promotePolicy(POLICY_ID, POLICY_VERSION);
  if (promoted.status !== 200) {
    throw new Error(
      `provisionHappyPath: promote failed (${promoted.status}): ${promoted.text}`,
    );
  }
  return ready;
}

export { CAPABILITY_ID, canaryPolicy };
