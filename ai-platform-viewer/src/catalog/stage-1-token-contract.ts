export type Stage1OperationId = 'begin-rotation' | 'retire' | 'get-capabilities'

export type Stage1Auth = 'operator' | 'aat'

export interface Stage1OperationDefinition {
  id: Stage1OperationId
  title: string
  method: 'POST' | 'GET'
  path: string
  auth: Stage1Auth
  summary: string
  defaultVer?: string
  verHint?: string
  successNote: string
  failures: Array<{ status: number; error: string; trigger: string }>
}

export const STAGE1_OPERATIONS: Stage1OperationDefinition[] = [
  {
    id: 'begin-rotation',
    title: 'Begin rotation',
    method: 'POST',
    path: '/control/token-contract/begin-rotation',
    auth: 'operator',
    summary:
      'Adds a new accepted AAT version while up to two non-retired versions may coexist. Inserts a token_contract row when fewer than two accepted versions exist.',
    defaultVer: '2',
    verHint: 'New version to accept (non-empty string)',
    successNote: '200 — returns { ver }. D1 INSERT into token_contract.',
    failures: [
      { status: 401, error: 'unauthorized', trigger: 'Missing or invalid operator bearer' },
      { status: 400, error: 'invalid_ver', trigger: 'Empty ver' },
      { status: 409, error: 'ver_already_exists', trigger: 'ver already in table' },
      { status: 409, error: 'rotation_already_open', trigger: 'Two accepted versions already exist' },
    ],
  },
  {
    id: 'retire',
    title: 'Retire version',
    method: 'POST',
    path: '/control/token-contract/retire',
    auth: 'operator',
    summary:
      'Stamps retired_at on an accepted version so AATs with that ver claim fail identity verify. Requires two accepted versions so one remains active.',
    defaultVer: '1',
    verHint: 'Version to retire (must be accepted and not already retired)',
    successNote: '200 — returns { ver, retired_at }. D1 UPDATE token_contract.',
    failures: [
      { status: 401, error: 'unauthorized', trigger: 'Missing or invalid operator bearer' },
      { status: 404, error: 'ver_not_found', trigger: 'ver not in table' },
      { status: 409, error: 'ver_already_retired', trigger: 'retired_at already set' },
      { status: 409, error: 'no_rotation_open', trigger: 'Only one accepted version left' },
    ],
  },
  {
    id: 'get-capabilities',
    title: 'Get capabilities',
    method: 'GET',
    path: '/v1/capabilities',
    auth: 'aat',
    summary:
      'Discovery probe using the clinic AAT from Secrets. Re-syncs platform enrollment and accepts the clinic ai.aat.ver on token_contract before calling discovery. To test retirement, mint while ver=1 is still accepted, begin rotation, retire ver=1, then send the same token (do not re-mint).',
    successNote:
      '200 with manifests while the AAT ver is accepted on token_contract. 401 after that ver is retired.',
    failures: [
      {
        status: 401,
        error: 'unauthenticated',
        trigger: 'Missing/invalid AAT, unknown ver on token_contract, or retired ver claim',
      },
      { status: 200, error: '(accepted)', trigger: 'AAT ver still active in token_contract' },
    ],
  },
]
