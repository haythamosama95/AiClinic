import fs from 'node:fs'
import path from 'node:path'
import { spawn } from 'node:child_process'
import type { Plugin } from 'vite'
import { VIEWER_AAT_LIFETIME_MINUTES } from '../src/lib/viewer-aat-config.ts'

const AI_PLATFORM_DIR = path.resolve(import.meta.dirname, '../../ai-platform')
const BACKEND_ENV_PATH = path.resolve(import.meta.dirname, '../../backend/local/.env')
const DEV_VARS_PATH = path.join(AI_PLATFORM_DIR, '.dev.vars')
const RESET_SQL_PATH = path.join(import.meta.dirname, 'reset-platform.sql')
const RESET_INSTALLATIONS_SQL_PATH = path.join(
  import.meta.dirname,
  'reset-installations.sql',
)
const RESET_CLINIC_SQL_PATH = path.join(import.meta.dirname, 'reset-clinic-ai-internal.sql')

const CLINIC_ENROLLMENT_MATERIAL_SQL = `
SELECT row_to_json(row) FROM (
  SELECT
    ik.installation_id::text AS installation_id,
    ik.kid,
    rtrim(
      translate(replace(encode(ik.public_key, 'base64'), E'\\n', ''), '+/', '-_'),
      '='
    ) AS public_key,
    o.id::text AS org_id,
    o.name AS display_name,
    coalesce(
      (
        SELECT b.id::text
        FROM public.staff_members sm
        JOIN public.staff_branch_assignments sba
          ON sba.staff_member_id = sm.id
         AND sba.is_deleted = false
         AND sba.is_primary = true
        JOIN public.branches b
          ON b.id = sba.branch_id
         AND b.is_deleted = false
        WHERE sm.is_bootstrap_admin = true
          AND sm.is_deleted = false
        ORDER BY sba.created_at
        LIMIT 1
      ),
      (
        SELECT b.id::text
        FROM public.branches b
        WHERE b.organization_id = o.id
          AND b.is_deleted = false
        ORDER BY b.created_at
        LIMIT 1
      )
    ) AS branch_id,
    coalesce(
      nullif(trim(both '"' from ver_setting.value_json::text), ''),
      '1'
    ) AS aat_ver
  FROM ai_internal.installation_keys ik
  CROSS JOIN LATERAL (
    SELECT id, name
    FROM public.organizations
    WHERE is_deleted = false
    ORDER BY created_at
    LIMIT 1
  ) o
  CROSS JOIN LATERAL (
    SELECT value_json
    FROM ai_internal.app_settings
    WHERE key = 'ai.aat.ver'
      AND is_deleted = false
    LIMIT 1
  ) ver_setting
  WHERE ik.is_deleted = false
    AND ik.revoked_at IS NULL
  ORDER BY ik.valid_from DESC, ik.kid DESC
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

async function resetLocalClinicAiInternal(): Promise<string> {
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
      '-v',
      'ON_ERROR_STOP=1',
      '-f',
      RESET_CLINIC_SQL_PATH,
    ],
    process.cwd(),
    { PGPASSWORD: password },
  )

  if (result.code !== 0) {
    throw new Error(
      result.stderr || result.stdout || 'Supabase ai_internal reset failed',
    )
  }

  return `Reset Supabase ai_internal: cleared installation_keys and ai_token_issuance; restored app_settings defaults (ai.aat.lifetime_minutes=${VIEWER_AAT_LIFETIME_MINUTES}, ai.aat.ver=1, ai.availability enrolled=false)`
}

async function ensureViewerAatLifetime(): Promise<void> {
  const backendEnv = readEnvFile(BACKEND_ENV_PATH)
  const password = backendEnv.POSTGRES_PASSWORD ?? 'postgres'
  const port = backendEnv.SUPABASE_DB_PORT ?? '54322'

  const sql = `
INSERT INTO ai_internal.app_settings (key, value_json, is_deleted)
VALUES ('ai.aat.lifetime_minutes', '${VIEWER_AAT_LIFETIME_MINUTES}'::jsonb, false)
ON CONFLICT (key) DO UPDATE SET
  value_json = EXCLUDED.value_json,
  updated_at = NULL,
  updated_by = NULL,
  is_deleted = false,
  deleted_at = NULL,
  deleted_by = NULL;
`

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
      '-v',
      'ON_ERROR_STOP=1',
      '-c',
      sql,
    ],
    process.cwd(),
    { PGPASSWORD: password },
  )

  if (result.code !== 0) {
    throw new Error(
      result.stderr || result.stdout || 'Clinic AAT lifetime update failed',
    )
  }
}

async function clearLocalR2Objects(): Promise<string> {
  const r2List = await runCommand(
    'npx',
    [
      'wrangler',
      'r2',
      'object',
      'list',
      'ai-platform-development',
      '--local',
      '--env',
      'development',
      '--json',
    ],
    AI_PLATFORM_DIR,
  )

  if (r2List.code === 0 && r2List.stdout.trim()) {
    try {
      const payload = JSON.parse(r2List.stdout) as {
        objects?: Array<{ key: string }>
      }
      for (const object of payload.objects ?? []) {
        await runCommand(
          'npx',
          [
            'wrangler',
            'r2',
            'object',
            'delete',
            'ai-platform-development',
            object.key,
            '--local',
            '--env',
            'development',
          ],
          AI_PLATFORM_DIR,
        )
      }
      return `Removed ${payload.objects?.length ?? 0} local R2 objects`
    } catch {
      return 'R2 list returned no JSON payload; skipped object deletion'
    }
  }

  return 'No local R2 objects found (or bucket empty)'
}

async function resetLocalInstallations(): Promise<{ steps: string[] }> {
  const steps: string[] = []

  const d1 = await runCommand(
    'npx',
    [
      'wrangler',
      'd1',
      'execute',
      'ai-platform-development',
      '--local',
      '--env',
      'development',
      '--file',
      RESET_INSTALLATIONS_SQL_PATH,
    ],
    AI_PLATFORM_DIR,
  )

  if (d1.code !== 0) {
    throw new Error(d1.stderr || d1.stdout || 'D1 installation reset failed')
  }

  steps.push(
    'Cleared D1 installation tables (installation, installation_key, entitlement, journal, ledger, grants, audit, counters)',
  )
  steps.push(await clearLocalR2Objects())
  steps.push('Restart wrangler dev if quota counters still look stale')
  return { steps }
}

async function resetLocalPlatform(): Promise<{ steps: string[] }> {
  const steps: string[] = []

  steps.push(await resetLocalClinicAiInternal())

  const d1 = await runCommand(
    'npx',
    [
      'wrangler',
      'd1',
      'execute',
      'ai-platform-development',
      '--local',
      '--env',
      'development',
      '--file',
      RESET_SQL_PATH,
    ],
    AI_PLATFORM_DIR,
  )

  if (d1.code !== 0) {
    throw new Error(d1.stderr || d1.stdout || 'D1 reset failed')
  }
  steps.push('Cleared local D1 tables and re-seeded token_contract ver=1')

  steps.push(await clearLocalR2Objects())

  const doStateDir = path.join(AI_PLATFORM_DIR, '.wrangler/state/v3/do')
  if (fs.existsSync(doStateDir)) {
    fs.rmSync(doStateDir, { recursive: true, force: true })
    steps.push('Cleared local Durable Object state (.wrangler/state/v3/do)')
  } else {
    steps.push('No local DO state directory to clear')
  }

  steps.push('Restart wrangler dev if quota counters still look stale')
  return { steps }
}

async function queryClinicEnrollmentMaterial(): Promise<Record<string, string> | null> {
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
      CLINIC_ENROLLMENT_MATERIAL_SQL,
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
          const devVars = readEnvFile(DEV_VARS_PATH)
          const backendEnv = readEnvFile(BACKEND_ENV_PATH)
          sendJson(res, 200, {
            operatorBearerToken: devVars.OPERATOR_BEARER_TOKEN ?? '',
            devVarsPath: DEV_VARS_PATH,
            supabaseUrl:
              backendEnv.SUPABASE_PUBLIC_URL ?? 'http://127.0.0.1:54321',
            supabaseAnonKey: backendEnv.SUPABASE_ANON_KEY ?? '',
            backendEnvPath: BACKEND_ENV_PATH,
            bootstrapAdminUsername: 'admin',
            bootstrapAdminPassword: 'admin',
            bootstrapAdminSource: 'bootstrap defaults (admin/admin)',
          })
          return
        }

        if (req.method === 'POST' && req.url === '/api/dev/reset') {
          try {
            const result = await resetLocalPlatform()
            sendJson(res, 200, result)
          } catch (error) {
            sendJson(res, 500, {
              error: error instanceof Error ? error.message : 'Reset failed',
            })
          }
          return
        }

        if (req.method === 'POST' && req.url === '/api/dev/reset-installations') {
          try {
            const result = await resetLocalInstallations()
            sendJson(res, 200, result)
          } catch (error) {
            sendJson(res, 500, {
              error:
                error instanceof Error
                  ? error.message
                  : 'Installation reset failed',
            })
          }
          return
        }

        if (req.method === 'POST' && req.url === '/api/dev/ensure-aat-lifetime') {
          try {
            await ensureViewerAatLifetime()
            sendJson(res, 200, {
              lifetime_minutes: VIEWER_AAT_LIFETIME_MINUTES,
            })
          } catch (error) {
            sendJson(res, 500, {
              error:
                error instanceof Error
                  ? error.message
                  : 'Clinic AAT lifetime update failed',
            })
          }
          return
        }

        if (req.method === 'GET' && req.url === '/api/dev/clinic-enrollment-material') {
          try {
            const material = await queryClinicEnrollmentMaterial()
            if (!material) {
              sendJson(res, 404, { error: 'No active clinic installation key found' })
              return
            }
            sendJson(res, 200, material)
          } catch (error) {
            sendJson(res, 500, {
              error:
                error instanceof Error
                  ? error.message
                  : 'Clinic enrollment material query failed',
            })
          }
          return
        }

        sendJson(res, 404, { error: 'Not found' })
      })
    },
  }
}
