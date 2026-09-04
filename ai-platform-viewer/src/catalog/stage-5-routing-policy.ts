import type { JourneyOperationDefinition, JourneyStageMeta } from '@/catalog/journey-types'
import { DEFAULT_ROUTING_POLICY_DOCUMENT } from '@/lib/routing-policy-default'

export const STAGE5_META: JourneyStageMeta = {
  id: 'stage-5',
  navLabel: 'Stage 5',
  navNote: 'Routing policy',
  eyebrow: 'Stage 5 · Routing policy',
  title: 'Air traffic control playbook',
  lede:
    'Publish routing policy documents to R2 with a D1 index row, then canary, promote, or rollback lifecycle. The manifest routingPolicyRef (routing/standard@v1) resolves through D1 to the R2 playbook that selects provider/model chains at invoke time.',
  accentClass: 'stage-accent--routing',
  cardClass: 'operation-card--routing',
  buttonClass: 'routing-button',
}

export const STAGE5_OPERATIONS: JourneyOperationDefinition[] = [
  {
    id: 'publish',
    section: 'Publish policy',
    title: 'POST …/publish',
    method: 'POST',
    path: '/control/routing-policies/publish',
    auth: 'operator',
    bodyKind: 'json',
    fields: [
      {
        name: 'document',
        scope: 'body',
        json: true,
        defaultValue: DEFAULT_ROUTING_POLICY_DOCUMENT,
        hint: 'RoutingPolicyDocument JSON — identity via document.policy_id and document.policy_version (integer ≥ 1); default is platform-default/1.json',
        wide: true,
        jsonRows: 53,
      },
    ],
    summary:
      'Write the routing playbook to R2 and INSERT a D1 routing_policy row with status=published. Identity comes solely from document.policy_id (non-empty string) and document.policy_version (JSON integer ≥ 1).',
    successNote:
      '200 — {} or { warnings: ["latency_class_mismatch"] } (capability latency class matches no target) or { warnings: ["unreferenced_policy"] } (no published capability manifest references routing/{policy_id}@v{policy_version}). R2 key control/routing-policy/{policy_id}/{version}.json; D1 status=published.',
    failures: [
      { status: 401, error: 'unauthorized', trigger: 'Missing or wrong operator bearer' },
      { status: 400, error: 'invalid_json', trigger: 'Body is not valid JSON' },
      { status: 400, error: 'missing_document', trigger: 'document field absent from body' },
      {
        status: 400,
        error: 'invalid_policy_identity',
        trigger:
          'Missing/empty document.policy_id, or document.policy_version not an integer ≥ 1 (string "1" rejected)',
      },
      { status: 409, error: 'already_published', trigger: 'Same (policy_id, version) already in D1' },
      { status: 500, error: 'storage_error', trigger: 'D1 or R2 failure' },
    ],
  },
  {
    id: 'canary',
    section: 'Canary rollout',
    title: 'POST …/canary',
    method: 'POST',
    path: '/control/routing-policies/{policy_id}/versions/{version}/canary',
    auth: 'operator',
    bodyKind: 'json',
    fields: [
      {
        name: 'policy_id',
        scope: 'path',
        defaultValue: 'standard',
      },
      {
        name: 'version',
        scope: 'path',
        defaultValue: '1',
      },
      {
        name: 'installation_ids',
        scope: 'body',
        json: true,
        defaultValue: '[]',
        clinicKey: 'installation_id',
        hint: 'Non-empty JSON array — installations that receive this canary version',
        wide: true,
      },
      {
        name: 'cohort_name',
        scope: 'body',
        defaultValue: 'routing-pilot',
        hint: 'Optional operator label for audit',
        required: false,
      },
    ],
    summary:
      'Move a published policy version to canary for named installations. D1 UPDATE status=canary and canary_installation_ids JSON array.',
    successNote: '200 — {}. D1: routing_policy.status=canary, canary_installation_ids set.',
    failures: [
      { status: 401, error: 'unauthorized', trigger: 'Missing or wrong operator bearer' },
      { status: 400, error: 'invalid_json', trigger: 'Body is not valid JSON' },
      { status: 400, error: 'missing_installation_ids', trigger: 'Empty installation_ids array' },
      { status: 404, error: 'installation_not_found', trigger: 'Id not in installation table' },
      { status: 404, error: 'policy_not_found', trigger: 'No routing_policy row for policy_id+version' },
      { status: 409, error: 'illegal_policy_transition', trigger: 'e.g. canary on already-active version' },
      { status: 500, error: 'storage_error', trigger: 'D1 batch failure' },
    ],
  },
  {
    id: 'promote',
    section: 'Promote to active',
    title: 'POST …/promote',
    method: 'POST',
    path: '/control/routing-policies/{policy_id}/versions/{version}/promote',
    auth: 'operator',
    bodyKind: 'empty',
    fields: [
      {
        name: 'policy_id',
        scope: 'path',
        defaultValue: 'standard',
      },
      {
        name: 'version',
        scope: 'path',
        defaultValue: '1',
      },
    ],
    summary:
      'Supersede other active/canary rows and promote this version to active. Prior active row recorded in control_audit.before_pointer.',
    successNote: '200 — {}. D1: target status=active; other active/canary → superseded.',
    failures: [
      { status: 401, error: 'unauthorized', trigger: 'Missing or wrong operator bearer' },
      { status: 404, error: 'policy_not_found', trigger: 'No routing_policy row for policy_id+version' },
      { status: 409, error: 'illegal_policy_transition', trigger: 'Invalid lifecycle transition' },
      { status: 500, error: 'storage_error', trigger: 'D1 batch failure' },
    ],
  },
  {
    id: 'rollback',
    section: 'Rollback policy',
    title: 'POST …/rollback',
    method: 'POST',
    path: '/control/routing-policies/{policy_id}/versions/{version}/rollback',
    auth: 'operator',
    bodyKind: 'empty',
    fields: [
      {
        name: 'policy_id',
        scope: 'path',
        defaultValue: 'standard',
      },
      {
        name: 'version',
        scope: 'path',
        defaultValue: '1',
      },
    ],
    summary:
      'Revert canary → published or active → previous superseded version. Uses ORDER BY active_from DESC, rowid DESC for tie-break.',
    successNote: '200 — {}. D1: lifecycle rollback per control/routing-policy.ts.',
    failures: [
      { status: 401, error: 'unauthorized', trigger: 'Missing or wrong operator bearer' },
      { status: 404, error: 'policy_not_found', trigger: 'No routing_policy row for policy_id+version' },
      { status: 409, error: 'illegal_policy_transition', trigger: 'Nothing to roll back' },
      { status: 500, error: 'storage_error', trigger: 'D1 batch failure' },
    ],
  },
]
