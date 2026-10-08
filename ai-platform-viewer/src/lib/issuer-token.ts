const ISSUER_ID = 'issuer-test'
const ISSUER_AUDIENCE = 'ai-platform'
const TOKEN_VER = '2'
const CONTRACT_VERSION_HEADER = '1'

export interface IssuerKeyMaterial {
  kid: string
  privateKey: CryptoKey
}

export interface IssuerTokenClaims {
  sub?: string
  org?: string
  branch?: string
  role?: string
  scopes?: string[]
}

function base64urlEncode(data: Uint8Array | string): string {
  const bytes =
    typeof data === 'string'
      ? new TextEncoder().encode(data)
      : data
  let binary = ''
  for (const byte of bytes) {
    binary += String.fromCharCode(byte)
  }
  return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/u, '')
}

export async function importIssuerPrivateKey(
  kid: string,
  privateKeyBase64url: string,
): Promise<IssuerKeyMaterial> {
  const raw = Uint8Array.from(
    atob(privateKeyBase64url.replace(/-/g, '+').replace(/_/g, '/')),
    (char) => char.charCodeAt(0),
  )
  const privateKey = await crypto.subtle.importKey(
    'pkcs8',
    raw,
    { name: 'Ed25519' },
    false,
    ['sign'],
  )
  return { kid, privateKey }
}

export async function mintIssuerToken(
  key: IssuerKeyMaterial,
  claims: IssuerTokenClaims = {},
): Promise<string> {
  const now = Math.floor(Date.now() / 1000)
  const payload = {
    iss: ISSUER_ID,
    aud: ISSUER_AUDIENCE,
    sub: claims.sub ?? crypto.randomUUID(),
    org: claims.org ?? crypto.randomUUID(),
    branch: claims.branch ?? crypto.randomUUID(),
    role: claims.role ?? 'clinician',
    scopes: claims.scopes ?? ['ai.access'],
    jti: crypto.randomUUID(),
    iat: now - 30,
    exp: now + 300,
    ver: TOKEN_VER,
  }

  const header = { alg: 'EdDSA', kid: key.kid, typ: 'JWT' }
  const headerB64 = base64urlEncode(JSON.stringify(header))
  const payloadB64 = base64urlEncode(JSON.stringify(payload))
  const signingInput = `${headerB64}.${payloadB64}`
  const signature = await crypto.subtle.sign(
    { name: 'Ed25519' },
    key.privateKey,
    new TextEncoder().encode(signingInput),
  )

  return `${signingInput}.${base64urlEncode(new Uint8Array(signature))}`
}

export function issuerContractVersionHeader(): string {
  return CONTRACT_VERSION_HEADER
}
