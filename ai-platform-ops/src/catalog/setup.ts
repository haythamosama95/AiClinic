import type { EntityDef } from "./types";

/**
 * Ordered bootstrap sequence for a usable AI platform.
 *
 * Sources: architecture §8.1 (enrollment), §4.5 (control plane),
 * §5.6/§5.7 (token contract), routing publish→canary→promote,
 * and catalog gaps (no entitlement HTTP writer yet).
 */
export type SetupStep = {
  id: string;
  order: number;
  title: string;
  /** Why this step exists in the sequence */
  why: string;
  /** What to do / prerequisites */
  doThis: string;
  /** Platform gap or caveat — shown plainly, not as a verdict */
  note?: string;
  /** Control/clinic/e2e entity ids to embed (from ALL_ENTITIES) */
  entityIds: string[];
  /** Optional field seeds applied to each embedded entity form */
  fieldSeeds?: Record<string, Record<string, string>>;
};

const SAMPLE_ROUTING_DOCUMENT = `{
  "schema_version": 1,
  "policy_id": "standard",
  "policy_version": 1,
  "defaults": { "cost_class": "standard", "max_parallel_attempts": 1 },
  "rules": [
    {
      "rule_id": "catch-all",
      "match": {},
      "requires": {
        "structured_output": false,
        "min_context_window": 0,
        "languages": ["en"]
      },
      "targets": [
        {
          "provider_id": "deepseek",
          "model_id": "deepseek-chat",
          "features": {
            "structured_output": false,
            "min_context_window": 128000,
            "languages": ["en"],
            "latency_class": "interactive",
            "cost_class": "standard"
          },
          "max_attempts": 2,
          "timeout_ms": 30000
        }
      ]
    }
  ],
  "overrides": []
}`;

export const SETUP_STEPS: SetupStep[] = [
  {
    id: "setup.reach",
    order: 1,
    title: "Reach the Worker",
    why: "Every later control call needs a live gateway and an operator bearer in the connection strip.",
    doThis:
      "Set Platform URL and Operator bearer above, then run Health. You want a 200 with build + environment identity.",
    entityIds: ["e2e.health"],
  },
  {
    id: "setup.token-contract",
    order: 2,
    title: "Token contract baseline",
    why: "AAT verification checks the token's `ver` against the global accepted set. Fresh D1 already seeds `ver=1` from migration — you do not enroll a clinic to create this.",
    doThis:
      "Skip unless you are rotating the contract. Use begin-rotation only to add a second accepted `ver` (overlap). Retire only after clinics mint the new `ver`.",
    note: "Seed row: token_contract ver='1'. Retiring the sole accepted ver is refused (409).",
    entityIds: [
      "control.token-begin-rotation",
      "control.token-retire",
    ],
  },
  {
    id: "setup.enroll",
    order: 3,
    title: "Enroll the installation",
    why: "§8.1 trust bootstrap: the platform only verifies clinics it has explicitly enrolled. This is the first per-clinic control mutation.",
    doThis:
      "On the clinic side, generate an Ed25519 keypair (pgsodium) and keep the secret in clinic DB. Paste installation_id, org, display name, region, plan, kid, algorithm (EdDSA), and the public key here, then Run enroll.",
    note: "Enroll creates installation + key + entitlement row in status pending with zero quota/budget and empty allowed capabilities. Trust exists; spend rights do not.",
    entityIds: ["control.enroll"],
    fieldSeeds: {
      "control.enroll": {
        algorithm: "EdDSA",
        region: "local",
        plan: "enterprise",
      },
    },
  },
  {
    id: "setup.entitlement-gap",
    order: 4,
    title: "Entitlement economics (gap)",
    why: "Architecture splits identity (enroll) from economics (entitlement management). Guard reads pending as “nothing allowed”.",
    doThis:
      "There is no Worker HTTP writer for entitlement assignment yet (catalog gap). For local play, the next step (cohort activate) is the available control path that writes capability_grant rows.",
    note: "Not available: plan quota, budget, period bounds, soft threshold → active. Do not expect submit to succeed on economics alone until that API exists or you patch D1 in tests.",
    entityIds: [],
  },
  {
    id: "setup.cohort-activate",
    order: 5,
    title: "Grant a capability (cohort activate)",
    why: "Without a capability_grant (or plan grant), resolve/discover treat the capability as unavailable for the installation.",
    doThis:
      "Activate clinic.visit_summary @ 1.0.0 for your enrolled installation_ids. Optional cohort_name labels the audit target.",
    entityIds: ["control.cohort-activate"],
    fieldSeeds: {
      "control.cohort-activate": {
        capability_id: "clinic.visit_summary",
        version: "1.0.0",
        installation_ids: '["REPLACE_WITH_INSTALLATION_ID"]',
      },
    },
  },
  {
    id: "setup.cohort-promote",
    order: 6,
    title: "Promote capability grants (optional)",
    why: "Promote lifts the version across live installation and plan grants and upserts plan grants for entitled plans — broader than a single cohort activate.",
    doThis:
      "Run only after activate looks right for a pilot cohort. This is a dangerous control.",
    entityIds: ["control.cohort-promote"],
    fieldSeeds: {
      "control.cohort-promote": {
        capability_id: "clinic.visit_summary",
        version: "1.0.0",
      },
    },
  },
  {
    id: "setup.routing-publish",
    order: 7,
    title: "Publish a routing policy",
    why: "Inference needs an active routing policy document (R2 + D1). Publish writes the version; it is not live until canary/promote.",
    doThis:
      "Use policy_id standard, version 1, and the sample document (edit provider_id/model_id to match wired adapters). policy_id and policy_version inside the JSON must match the path fields.",
    entityIds: ["control.routing-publish"],
    fieldSeeds: {
      "control.routing-publish": {
        policy_id: "standard",
        version: "1",
        document: SAMPLE_ROUTING_DOCUMENT,
      },
    },
  },
  {
    id: "setup.routing-canary",
    order: 8,
    title: "Canary the routing policy",
    why: "Canary scopes the new policy version to listed installations before global promote — highest-leverage surface; stage it first.",
    doThis:
      "Pass the same policy_id/version you published and installation_ids containing the enrolled installation.",
    entityIds: ["control.routing-canary"],
    fieldSeeds: {
      "control.routing-canary": {
        policy_id: "standard",
        version: "1",
        installation_ids: '["REPLACE_WITH_INSTALLATION_ID"]',
      },
    },
  },
  {
    id: "setup.routing-promote",
    order: 9,
    title: "Promote routing to global active",
    why: "Promote makes the version the single active policy for the policy_id. Required for non-canary installations to route.",
    doThis: "Confirm canary evidence first, then promote. Dangerous.",
    entityIds: ["control.routing-promote"],
    fieldSeeds: {
      "control.routing-promote": {
        policy_id: "standard",
        version: "1",
      },
    },
  },
  {
    id: "setup.clinic-closeout",
    order: 10,
    title: "Clinic closeout & play",
    why: "Platform trust is one-way: after enroll, the clinic stores platform base URL + AI-enabled and mints AATs. Then Clinic / Debug / E2E tabs are meaningful.",
    doThis:
      "On clinic Supabase: persist platform URL and enrolled flag. Mint an AAT (issue_ai_token), paste it into the connection strip, decode claims, then try get-request / submit. Live submit may still 503 until the Worker injects an orchestrator.",
    note: "Decode AAT and get-request are safe smoke checks. Submit is transport-ready but inference may be unwired.",
    entityIds: [
      "clinic.decode-aat",
      "clinic.get-request",
      "clinic.submit",
      "clinic.discovery",
    ],
  },
];

/** Setup is guided UI, not a flat entity list — empty for entitiesForCategory. */
export const SETUP_ENTITIES: EntityDef[] = [];
