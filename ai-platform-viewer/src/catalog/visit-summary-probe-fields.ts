import type { JourneyParamField } from '@/catalog/journey-types'
import {
  VISIT_SUMMARY_CAPABILITY,
  VISIT_SUMMARY_INTENT,
  VISIT_SUMMARY_VERSION,
  buildVisitSummaryContextJson,
} from '@/catalog/stage-8-ingress'

export const VISIT_SUMMARY_CONTEXT_JSON = buildVisitSummaryContextJson(
  '<match AAT org claim>',
  '<match AAT branch claim>',
)

export function visitSummaryIngressHeaders(
  overrides: Partial<Record<string, string>> = {},
): JourneyParamField[] {
  return [
    {
      name: 'x-idempotency-key',
      scope: 'header',
      defaultValue: overrides['x-idempotency-key'] ?? '',
      hint: 'Leave blank to generate a UUID on send',
      wide: true,
      required: false,
    },
    {
      name: 'x-capability-version',
      scope: 'header',
      defaultValue: overrides['x-capability-version'] ?? VISIT_SUMMARY_VERSION,
      hint: 'Manifest version — must match published clinic.visit_summary',
    },
    {
      name: 'x-trace-id',
      scope: 'header',
      defaultValue: overrides['x-trace-id'] ?? '',
      hint: 'Optional ULID; blank lets the server mint one',
      wide: true,
      required: false,
    },
  ]
}

export function visitSummaryBodyFields(
  overrides: Partial<Record<string, string>> = {},
): JourneyParamField[] {
  return [
    {
      name: 'capability_id',
      scope: 'body',
      defaultValue: overrides.capability_id ?? VISIT_SUMMARY_CAPABILITY,
      hint: 'Capability id from request body',
      wide: true,
    },
    {
      name: 'user_intent',
      scope: 'body',
      defaultValue: overrides.user_intent ?? VISIT_SUMMARY_INTENT,
      hint: 'User intent string (stage 7 token estimate includes this)',
      wide: true,
    },
    {
      name: 'context',
      scope: 'body',
      json: true,
      defaultValue: overrides.context ?? VISIT_SUMMARY_CONTEXT_JSON,
      hint: 'context.org and context.branch must match the AAT principal — synced from clinic Postgres',
      wide: true,
      clinicKey: 'org_id',
    },
  ]
}

export function visitSummaryPostFields(
  overrides: {
    body?: Partial<Record<string, string>>
    headers?: Partial<Record<string, string>>
    authorization?: string
  } = {},
): JourneyParamField[] {
  const fields: JourneyParamField[] = [
    ...visitSummaryBodyFields(overrides.body),
    ...visitSummaryIngressHeaders(overrides.headers),
  ]

  if (overrides.authorization !== undefined) {
    fields.unshift({
      name: 'Authorization',
      scope: 'header',
      defaultValue: overrides.authorization,
      hint: 'Override wire token — blank omits Authorization',
      wide: true,
      required: false,
    })
  }

  return fields
}
