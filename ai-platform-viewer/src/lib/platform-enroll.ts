import { fetchClinicEnrollmentMaterial } from '@/lib/dev-api'

const GATEWAY_PREFIX = '/gateway'

async function ensureAcceptedTokenVer(
  operatorBearer: string,
  ver: string,
): Promise<void> {
  const response = await fetch(
    `${GATEWAY_PREFIX}/control/token-contract/begin-rotation`,
    {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${operatorBearer}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ ver }),
    },
  )

  if (response.ok) {
    return
  }

  const rawBody = await response.text()
  let errorCode: string | undefined
  try {
    errorCode = (JSON.parse(rawBody) as { error?: string }).error
  } catch {
    // ignore parse failures
  }

  if (
    response.status === 409 &&
    (errorCode === 'ver_already_exists' || errorCode === 'rotation_already_open')
  ) {
    return
  }

  throw new Error(
    `Platform token-contract sync failed (${response.status}${errorCode ? `: ${errorCode}` : ''}). ${rawBody}`,
  )
}

export async function ensurePlatformEnrollment(
  operatorBearer: string,
): Promise<string> {
  if (!operatorBearer) {
    throw new Error(
      'Operator bearer not loaded. Open Secrets or check ai-platform/.dev.vars.',
    )
  }

  const material = await fetchClinicEnrollmentMaterial()
  if (!material) {
    throw new Error(
      'No clinic installation key found in local Supabase. Mint an AAT from Secrets first.',
    )
  }

  const response = await fetch(
    `${GATEWAY_PREFIX}/control/installations/${material.installation_id}/enroll`,
    {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${operatorBearer}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        org_id: material.org_id,
        display_name: material.display_name,
        region: 'us-east-1',
        plan: 'professional',
        public_key: material.public_key,
        algorithm: 'EdDSA',
        kid: material.kid,
      }),
    },
  )

  if (!response.ok) {
    const rawBody = await response.text()
    let errorCode: string | undefined
    try {
      errorCode = (JSON.parse(rawBody) as { error?: string }).error
    } catch {
      // ignore parse failures
    }

    if (!(response.status === 409 && errorCode === 'already_enrolled')) {
      throw new Error(
        `Platform enroll failed (${response.status}${errorCode ? `: ${errorCode}` : ''}). ${rawBody}`,
      )
    }
  }

  await ensureAcceptedTokenVer(operatorBearer, material.aat_ver)
  return material.aat_ver
}
