import fs from 'node:fs'
import path from 'node:path'
import { spawn } from 'node:child_process'
import type { Plugin } from 'vite'

const AI_PLATFORM_DIR = path.resolve(import.meta.dirname, '../../ai-platform')
const BACKEND_ENV_PATH = path.resolve(import.meta.dirname, '../../backend/local/.env')
const DEV_VARS_PATH = path.join(AI_PLATFORM_DIR, '.dev.vars')

const TEST_ISSUER_KEY_SQL = `
SELECT row_to_json(row) FROM (
  SELECT
    ik.kid,
    ds.decrypted_secret AS secret_b64
  FROM ai_internal.issuer_key ik
  JOIN vault.decrypted_secrets ds ON ds.id = ik.secret_ref
  WHERE ik.status = 'signing'
  ORDER BY ik.not_before DESC
  LIMIT 1
) row;
`

const CLINIC_TENANT_SCOPE_SQL = `
SELECT row_to_json(row) FROM (
  SELECT
    ''::text AS installation_id,
    ''::text AS kid,
    ''::text AS public_key,
    o.id::text AS org_id,
    o.name AS display_name,
    b.id::text AS branch_id,
    '2' AS aat_ver
  FROM public.organizations o
  JOIN public.branches b
    ON b.organization_id = o.id
   AND b.is_deleted = false
  WHERE o.is_deleted = false
  ORDER BY o.created_at, b.created_at
  LIMIT 1
) row;
`

function readEnvFile(filePath: string): Record<string, string> {
  if (!fs.existsSync(filePath)) {
    return {}
  }

  const values: Record<string, string> = {}
  for (const line of fs.readFileSync(filePath, 'utf8').split('\n')) {
    const trimmed = line.trim()
    if (!trimmed || trimmed.startsWith('#')) continue
    const separator = trimmed.indexOf('=')
    if (separator === -1) continue
    values[trimmed.slice(0, separator).trim()] = trimmed.slice(separator + 1).trim()
  }
  return values
}

function runCommand(
  command: string,
  args: string[],
  cwd: string,
  env: Record<string, string> = {},
): Promise<{ stdout: string; stderr: string; code: number | null }> {
  return new Promise((resolve, reject) => {
    const child = spawn(command, args, {
      cwd,
      shell: false,
      env: { ...process.env, ...env },
    })
    let stdout = ''
    let stderr = ''

    child.stdout.on('data', (chunk: Buffer) => {
      stdout += chunk.toString()
    })
    child.stderr.on('data', (chunk: Buffer) => {
      stderr += chunk.toString()
    })
    child.on('error', reject)
    child.on('close', (code) => resolve({ stdout, stderr, code }))
  })
}

function pkcs8Base64urlFromEd25519Secret(secretBytes: Uint8Array): string {
  const seed = secretBytes.slice(0, 32)
  const prefix = new Uint8Array([
    0x30, 0x2e, 0x02, 0x01, 0x00, 0x30, 0x05, 0x06, 0x03, 0x2b, 0x65, 0x70,
    0x04, 0x22, 0x04, 0x20,
  ])
  const pkcs8 = new Uint8Array(prefix.length + seed.length)
  pkcs8.set(prefix)
  pkcs8.set(seed, prefix.length)
  let binary = ''
  for (const byte of pkcs8) {
    binary += String.fromCharCode(byte)
  }
  return btoa(binary)
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=+$/u, '')
}

async function queryPostgresJson<T>(sql: string): Promise<T | null> {
  const backendEnv = readEnvFile(BACKEND_ENV_PATH)
  const password = backendEnv.POSTGRES_PASSWORD ?? 'postgres'
  const port = backendEnv.SUPABASE_DB_PORT ?? '54322'

  const result = await runCommand(
    'psql',
    [
      '-h',
      '127.0.0.1',
      '-p',
      port,
      '-U',
      'postgres',
      '-d',
      'postgres',
      '-t',
      '-A',
      '-c',
      sql,
    ],
    process.cwd(),
    { PGPASSWORD: password },
  )

  if (result.code !== 0) {
    throw new Error(result.stderr || result.stdout || 'Postgres query failed')
  }

  const row = result.stdout.trim()
  if (!row) {
    return null
  }

  return JSON.parse(row) as T
}

async function resolveTestIssuerKey(
  devVars: Record<string, string>,
): Promise<{ kid: string; privateKeyPkcs8: string; source: string }> {
  const kidFromVars = devVars.TEST_ISSUER_KID?.trim()
  const pkcs8FromVars = devVars.TEST_ISSUER_PRIVATE_KEY_PKCS8?.trim()
  if (kidFromVars && pkcs8FromVars) {
    return {
      kid: kidFromVars,
      privateKeyPkcs8: pkcs8FromVars,
      source: DEV_VARS_PATH,
    }
  }

  const row = await queryPostgresJson<{ kid: string; secret_b64: string }>(
    TEST_ISSUER_KEY_SQL,
  )
  if (!row?.kid || !row.secret_b64) {
    return { kid: '', privateKeyPkcs8: '', source: '' }
  }

  const secretBytes = Uint8Array.from(atob(row.secret_b64), (char) =>
    char.charCodeAt(0),
  )
  return {
    kid: row.kid,
    privateKeyPkcs8: pkcs8Base64urlFromEd25519Secret(secretBytes),
    source: 'ai_internal.issuer_key (local Supabase)',
  }
}

async function queryClinicTenantScope(): Promise<Record<string, string> | null> {
  const backendEnv = readEnvFile(BACKEND_ENV_PATH)
  const password = backendEnv.POSTGRES_PASSWORD ?? 'postgres'
  const port = backendEnv.SUPABASE_DB_PORT ?? '54322'

  const result = await runCommand(
    'psql',
    [
      '-h',
      '127.0.0.1',
      '-p',
      port,
      '-U',
      'postgres',
      '-d',
      'postgres',
      '-t',
      '-A',
      '-c',
      CLINIC_TENANT_SCOPE_SQL,
    ],
    process.cwd(),
    { PGPASSWORD: password },
  )

  if (result.code !== 0) {
    throw new Error(result.stderr || result.stdout || 'Clinic Postgres query failed')
  }

  const row = result.stdout.trim()
  if (!row) {
    return null
  }

  return JSON.parse(row) as Record<string, string>
}

function sendJson(res: import('node:http').ServerResponse, status: number, body: unknown) {
  res.statusCode = status
  res.setHeader('Content-Type', 'application/json')
  res.end(JSON.stringify(body))
}

export function devApiPlugin(): Plugin {
  return {
    name: 'ai-platform-viewer-dev-api',
    configureServer(server) {
      server.middlewares.use(async (req, res, next) => {
        if (!req.url?.startsWith('/api/dev/')) {
          next()
          return
        }

        if (req.method === 'GET' && req.url === '/api/dev/config') {
          try {
            const devVars = readEnvFile(DEV_VARS_PATH)
            const backendEnv = readEnvFile(BACKEND_ENV_PATH)
            const issuerKey = await resolveTestIssuerKey(devVars)
            sendJson(res, 200, {
              testIssuerKid: issuerKey.kid,
              testIssuerPrivateKeyPkcs8: issuerKey.privateKeyPkcs8,
              testIssuerSource: issuerKey.source,
              devVarsPath: DEV_VARS_PATH,
              supabaseUrl:
                backendEnv.SUPABASE_PUBLIC_URL ?? 'http://127.0.0.1:54321',
              supabaseAnonKey: backendEnv.SUPABASE_ANON_KEY ?? '',
              backendEnvPath: BACKEND_ENV_PATH,
              bootstrapAdminUsername: 'admin',
              bootstrapAdminPassword: 'admin',
              bootstrapAdminSource: 'bootstrap defaults (admin/admin)',
            })
          } catch (error) {
            sendJson(res, 500, {
              error:
                error instanceof Error
                  ? error.message
                  : 'Test issuer key lookup failed',
            })
          }
          return
        }

        if (req.method === 'GET' && req.url === '/api/dev/clinic-enrollment-material') {
          try {
            const material = await queryClinicTenantScope()
            if (!material) {
              sendJson(res, 404, { error: 'No clinic tenant scope found in local Supabase' })
              return
            }
            sendJson(res, 200, material)
          } catch (error) {
            sendJson(res, 500, {
              error:
                error instanceof Error
                  ? error.message
                  : 'Clinic tenant scope query failed',
            })
          }
          return
        }

        sendJson(res, 404, { error: 'Not found' })
      })
    },
  }
}
