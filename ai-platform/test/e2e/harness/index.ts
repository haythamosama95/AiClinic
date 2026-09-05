/**
 * Frozen E2E harness API. Stage writers import only from this barrel.
 * Do not add files next to this barrel and import them from tests.
 */

export {
  AAT_AUDIENCE,
  CAPABILITY_ID,
  CAPABILITY_VERSION,
  GATEWAY_ORIGIN,
  OPERATOR_BEARER,
  OPERATOR_ID,
  PLATFORM_TABLES,
  POLICY_ID,
  POLICY_REF,
  POLICY_VERSION,
  QUOTA_DO_RPC_URL,
  REQUEST_REFERENCE_PATTERN,
  TAXONOMY_BODY_KEYS,
  TOKEN_CONTRACT_VER,
  ULID_PATTERN,
  WRONG_OPERATOR_BEARER,
  emptyExecutionContext,
  env,
  flushBackgroundWork,
  jsonOf,
  readHttpResult,
  SELF,
  type HttpResult,
} from "./env";

export {
  applyAllMigrations,
  applySql,
  bootstrapE2e,
  clearConfigCache,
  count,
  d1,
  getAiRequest,
  getAttempts,
  getAudits,
  getEntitlement,
  getGrants,
  getR2Json,
  getRoutingPolicy,
  getUsageEvents,
  listTableNames,
  MIGRATION_SQL,
  queryAll,
  queryOne,
  resetE2eState,
  resetPlatformState,
  r2Exists,
  seedSql,
} from "./d1";

export {
  base64urlEncode,
  generateTestKeypair,
  nowSeconds,
  signBytes,
  signJwt,
  type TestKeypair,
} from "./crypto";

export {
  ensureInstallationKeyActive,
  mintAat,
  type AatClaims,
  type MintAatOptions,
} from "./aat";

export {
  canaryPolicy,
  controlBindingsFromEnv,
  controlFetch,
  controlHandlers,
  DEFAULT_ENTITLE_PAYLOAD,
  dispatchControl,
  enrollInstallation,
  enrollPayload,
  entitleInstallation,
  fakePolicyDocument,
  fakePolicyTarget,
  operatorAuthFromEnv,
  promotePolicy,
  publishPolicy,
  rollbackPolicy,
  type ControlAuth,
  type ControlFetchOptions,
  type EntitlePayload,
} from "./control";

export {
  clinicFetch,
  getCapabilities,
  getHealth,
  getRequestByRef,
  postRequest,
  visitSummaryInvokeBody,
  VISIT_CHIEF_COMPLAINT_V1,
  type ClinicFetchOptions,
  type InvokeResult,
} from "./clinic";

export { gatewayObjectJson, gatewayObjectRpc } from "./gateway-object";

export { CRON_RETENTION, CRON_ROLLUP, invokeCron } from "./cron";

export {
  assertSseSequence,
  parseSseEvents,
  parseSseText,
  sseEventNames,
  terminalEventTypes,
  type SseEvent,
  type SseSequenceMode,
} from "./sse";

export {
  allowAllRateLimiter,
  createRateLimiterDouble,
  diskIoError,
  installEnvOverrides,
  uniqueConstraintError,
  wrapD1,
  wrapDoStorage,
  wrapDurableObjectNamespace,
  type D1FaultConfig,
  type DoNamespaceFaultConfig,
  type DoStorageFaultConfig,
  type EnvBindingOverrides,
  type RateLimiterOutcome,
} from "./faults";

export { newScenario, provisionHappyPath, type Scenario } from "./scenario";

export {
  assertRequestReferenceShape,
  assertTaxonomyBody,
  assertUlidShape,
  type TaxonomyBody,
} from "./taxonomy";

export type { Scenario as E2eScenario } from "./types";

/** Registry seam for Register 5 #3 / #30. Production boot already installs the published set. */
export {
  createCapabilityRegistry,
  setCapabilityRegistry,
} from "../../../src/capability";
export { load as loadManifest, type Manifest } from "../../../src/manifest";
export { isolateConfigCache } from "../../../src/config-cache";

/** Direct handler / quota RPC seams (Register 5). Not for ordinary full-path tests. */
export { handleAdapterRequest } from "../../../src/adapter";
export {
  admissionRPC,
  creditRPC,
  inspectRPC,
  releaseRPC,
} from "../../../src/quota-do";
export { createSecretOperatorAuth, dispatchControlRequest } from "../../../src/control";
