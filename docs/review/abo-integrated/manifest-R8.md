# R8 bounded source manifest

Target: `db9244fddfddc1905335fb8c7105328c15a0cc5e`. Deletions use baseline coordinates. Inventory only; no source reviewed by preparation.

| Path | Lines | Symbol / region | Revision |
| --- | --- | --- | --- |
| `abo/migrations/0006_operator_action.sql` | 1–11 | preamble / imports / shared declarations | T |
| `abo/migrations/0006_operator_action.sql` | 12–17 | operator_action_abort_update | T |
| `abo/migrations/0006_operator_action.sql` | 18–22 | operator_action_abort_delete | T |
| `abo/migrations/0007_hp_actions.sql` | 1–4 | preamble / imports / shared declarations | T |
| `abo/migrations/0007_hp_actions.sql` | 5–10 | payment_release | T |
| `abo/migrations/0007_hp_actions.sql` | 11–16 | assertion_used_abort_update | T |
| `abo/migrations/0007_hp_actions.sql` | 17–22 | assertion_used_abort_delete | T |
| `abo/migrations/0007_hp_actions.sql` | 23–28 | payment_release_abort_update | T |
| `abo/migrations/0007_hp_actions.sql` | 29–33 | payment_release_abort_delete | T |
| `abo/src/ops/index.ts` | 1–34 | preamble / imports / shared declarations | T |
| `abo/src/ops/index.ts` | 37–160 | OpsEnv | T |
| `abo/src/ops/index.ts` | 161–184 | RelayPlatformMethod | T |
| `abo/src/ops/index.ts` | 191–199 | HpOperation | T |
| `abo/src/ops/index.ts` | 200–207 | VerifiedHpContext | T |
| `abo/src/ops/index.ts` | 297–313 | distinctOrgIds | T |
| `abo/src/ops/index.ts` | 314–398 | lookupOrgId | T |
| `abo/src/ops/index.ts` | 535–578 | insertOperatorAction | T |
| `abo/src/ops/index.ts` | 579–594 | recordPlatformOperatorAction | T |
| `abo/src/ops/index.ts` | 774–777 | isRecord | T |
| `abo/src/ops/index.ts` | 789–802 | latestPublishedOfferVersion | T |
| `abo/src/ops/index.ts` | 803–814 | nextOfferVersionNumber | T |
| `abo/src/ops/index.ts` | 815–821 | nextTermsVersionNumber | T |
| `abo/src/ops/index.ts` | 822–863 | appendOfferEvent | T |
| `abo/src/ops/index.ts` | 883–1078 | handleHpCatalogueAction | T |
| `abo/src/ops/index.ts` | 1404–1419 | handleGetLookup | T |
| `abo/src/ops/index.ts` | 1420–1432 | loadCheckoutEvents | T |
| `abo/src/ops/index.ts` | 1433–1613 | handleGetClinic | T |
| `abo/src/ops/index.ts` | 1614–1630 | handleGetParked | T |
| `abo/src/ops/index.ts` | 1698–1704 | newOpsId | T |
| `abo/src/ops/index.ts` | 1929–1940 | parsePlatformList | T |
| `abo/src/ops/index.ts` | 1941–1964 | handleGetRegistries | T |
| `abo/src/ops/index.ts` | 2110–2121 | operatorActionExists | T |
| `abo/src/ops/index.ts` | 2134–2143 | relayFactLogStatement | T |
| `abo/src/ops/index.ts` | 2163–2180 | relayGrantOutcomeCanonical | T |
| `abo/src/ops/index.ts` | 2199–2218 | insertRelayOperatorAction | T |
| `abo/src/ops/index.ts` | 2323–2357 | forwardPlatformRelay | T |
| `abo/src/ops/index.ts` | 2479–2491 | pickBodyFields | T |
| `abo/src/ops/index.ts` | 2492–2498 | planVersionSubject | T |
| `abo/src/ops/index.ts` | 2499–2504 | routingPolicySubject | T |
| `abo/src/ops/index.ts` | 2505–2518 | publishedRoutingPolicySubject | T |
| `abo/src/ops/index.ts` | 2519–2524 | killSwitchSubject | T |
| `abo/src/ops/index.ts` | 2525–2571 | handlePostConfigurationHpRelay | T |
| `abo/src/ops/index.ts` | 2572–2611 | handlePostConfigurationClassHRelay | T |
| `abo/src/ops/index.ts` | 2612–2632 | handleGetSupportLookup | T |
| `abo/src/ops/index.ts` | 2633–2652 | platformResponseJson | T |
| `abo/src/ops/index.ts` | 3303–3825 | handleOps | T |
| `ai-platform/migrations/20261003120000_operator_credential_and_platform_alert.sql` | 1–2 | preamble / imports / shared declarations | T |
| `ai-platform/migrations/20261003120000_operator_credential_and_platform_alert.sql` | 3–13 | operator_credential | T |
| `ai-platform/migrations/20261003120000_operator_credential_and_platform_alert.sql` | 14–19 | assertion_used | T |
| `ai-platform/migrations/20261003120000_operator_credential_and_platform_alert.sql` | 20–33 | platform_alert | T |
| `ai-platform/src/control/audit.ts` | 1–4 | preamble / imports / shared declarations | T |
| `ai-platform/src/control/audit.ts` | 5–8 | newId | T |
| `ai-platform/src/control/audit.ts` | 9–24 | writeAudit | T |
| `ai-platform/src/control/audit.ts` | 25–52 | writeEntrypointAudit | T |
| `ai-platform/src/control/auth.ts` | 1–3 | preamble / imports / shared declarations | B deleted |
| `ai-platform/src/control/auth.ts` | 4–25 | timingSafeEqualString | B deleted |
| `ai-platform/src/control/auth.ts` | 26–51 | createSecretOperatorAuth | B deleted |
| `ai-platform/src/control/capability-lifecycle.ts` | 1–9 | preamble / imports / shared declarations | T |
| `ai-platform/src/control/capability-lifecycle.ts` | 10–26 | loadGlobalOverlay | T |
| `ai-platform/src/control/capability-lifecycle.ts` | 27–36 | requireRegisteredVersion | T |
| `ai-platform/src/control/capability-lifecycle.ts` | 37–45 | overlapWindowStillActive | T |
| `ai-platform/src/control/capability-lifecycle.ts` | 46–57 | runControlBatch | T |
| `ai-platform/src/control/capability-lifecycle.ts` | 58–140 | deprecateCapabilityAction | T |
| `ai-platform/src/control/capability-lifecycle.ts` | 141–214 | retireCapabilityAction | T |
| `ai-platform/src/control/cohort.ts` | 1–7 | preamble / imports / shared declarations | T |
| `ai-platform/src/control/cohort.ts` | 8–30 | parseAllowedCapabilities | T |
| `ai-platform/src/control/cohort.ts` | 31–34 | parseTermSnapshotCapabilities | T |
| `ai-platform/src/control/cohort.ts` | 35–52 | assertInstallationsExist | T |
| `ai-platform/src/control/cohort.ts` | 53–64 | runControlBatch | T |
| `ai-platform/src/control/cohort.ts` | 65–87 | installationIdsWithCapability | T |
| `ai-platform/src/control/cohort.ts` | 88–107 | publishedPlansAllowingCapability | T |
| `ai-platform/src/control/cohort.ts` | 108–212 | activateCohortAction | T |
| `ai-platform/src/control/cohort.ts` | 213–403 | promoteCohortAction | T |
| `ai-platform/src/control/credit-price.ts` | 1–15 | preamble / imports / shared declarations | B deleted |
| `ai-platform/src/control/credit-price.ts` | 16–27 | runControlBatch | B deleted |
| `ai-platform/src/control/credit-price.ts` | 28–67 | validateCreditPricePayload | B deleted |
| `ai-platform/src/control/credit-price.ts` | 68–114 | handleCreditPriceActivate | B deleted |
| `ai-platform/src/control/entitle.ts` | 1–22 | preamble / imports / shared declarations | B deleted |
| `ai-platform/src/control/entitle.ts` | 23–29 | parseInstallationId | B deleted |
| `ai-platform/src/control/entitle.ts` | 30–36 | parseOverrideInstallationId | B deleted |
| `ai-platform/src/control/entitle.ts` | 37–48 | runControlBatch | B deleted |
| `ai-platform/src/control/entitle.ts` | 49–51 | ISO8601_INSTANT_RE | B deleted |
| `ai-platform/src/control/entitle.ts` | 52–62 | parseIsoInstant | B deleted |
| `ai-platform/src/control/entitle.ts` | 63–74 | validatePeriodBounds | B deleted |
| `ai-platform/src/control/entitle.ts` | 75–93 | validateGrantInput | B deleted |
| `ai-platform/src/control/entitle.ts` | 94–160 | validateEntitlePayload | B deleted |
| `ai-platform/src/control/entitle.ts` | 161–334 | handleEntitle | B deleted |
| `ai-platform/src/control/entitle.ts` | 335–405 | validateOverridePayload | B deleted |
| `ai-platform/src/control/entitle.ts` | 406–545 | handleOverride | B deleted |
| `ai-platform/src/control/http.ts` | 1–2 | preamble / imports / shared declarations | B deleted |
| `ai-platform/src/control/http.ts` | 3–9 | unauthorized | B deleted |
| `ai-platform/src/control/http.ts` | 10–16 | reject | B deleted |
| `ai-platform/src/control/http.ts` | 17–23 | ok | B deleted |
| `ai-platform/src/control/http.ts` | 24–27 | nowIso | B deleted |
| `ai-platform/src/control/http.ts` | 28–31 | newId | B deleted |
| `ai-platform/src/control/http.ts` | 32–42 | requireOperator | B deleted |
| `ai-platform/src/control/http.ts` | 43–50 | parseJsonBody | B deleted |
| `ai-platform/src/control/http.ts` | 51–56 | requireNonEmptyString | B deleted |
| `ai-platform/src/control/index.ts` | 1–4 | preamble / imports / shared declarations | T |
| `ai-platform/src/control/index.ts` | 5–8 | SupportLookupOperatorAuth | T |
| `ai-platform/src/control/index.ts` | 9–14 | SupportLookupControlBindings | T |
| `ai-platform/src/control/index.ts` | 15–48 | handleSupportLookup | T |
| `ai-platform/src/control/installation-lifecycle.ts` | 1–3 | preamble / imports / shared declarations | T |
| `ai-platform/src/control/installation-lifecycle.ts` | 4–35 | setInstallationSuspendedAction | T |
| `ai-platform/src/control/kill-switch.ts` | 1–5 | preamble / imports / shared declarations | T |
| `ai-platform/src/control/kill-switch.ts` | 6–7 | KillSwitchScope | T |
| `ai-platform/src/control/kill-switch.ts` | 8–12 | KillSwitchPayload | T |
| `ai-platform/src/control/kill-switch.ts` | 13–19 | KILL_SWITCH_SCOPES | T |
| `ai-platform/src/control/kill-switch.ts` | 20–23 | KillSwitchRow | T |
| `ai-platform/src/control/kill-switch.ts` | 24–27 | isKillSwitchScope | T |
| `ai-platform/src/control/kill-switch.ts` | 28–31 | auditTarget | T |
| `ai-platform/src/control/kill-switch.ts` | 32–35 | armAuditAction | T |
| `ai-platform/src/control/kill-switch.ts` | 36–41 | disarmAuditAction | T |
| `ai-platform/src/control/kill-switch.ts` | 42–45 | isKillSwitchRowActive | T |
| `ai-platform/src/control/kill-switch.ts` | 46–57 | runControlBatch | T |
| `ai-platform/src/control/kill-switch.ts` | 58–71 | assertInstallationExists | T |
| `ai-platform/src/control/kill-switch.ts` | 72–84 | loadKillSwitchRow | T |
| `ai-platform/src/control/kill-switch.ts` | 85–104 | payloadFromArgs | T |
| `ai-platform/src/control/kill-switch.ts` | 105–156 | armKillSwitchAction | T |
| `ai-platform/src/control/kill-switch.ts` | 157–197 | disarmKillSwitchAction | T |
| `ai-platform/src/control/lifecycle.ts` | 1–24 | preamble / imports / shared declarations | B deleted |
| `ai-platform/src/control/lifecycle.ts` | 25–25 | INSTALLATION_ACTIVE_STATUS | B deleted |
| `ai-platform/src/control/lifecycle.ts` | 26–26 | INSTALLATION_SUSPENDED_STATUS | B deleted |
| `ai-platform/src/control/lifecycle.ts` | 27–29 | INSTALLATION_DELETED_STATUS | B deleted |
| `ai-platform/src/control/lifecycle.ts` | 30–30 | INSTALLATION_KEY_TTL_DAYS | B deleted |
| `ai-platform/src/control/lifecycle.ts` | 31–32 | MS_PER_DAY | B deleted |
| `ai-platform/src/control/lifecycle.ts` | 33–38 | installationKeyValidUntil | B deleted |
| `ai-platform/src/control/lifecycle.ts` | 39–45 | parseInstallationId | B deleted |
| `ai-platform/src/control/lifecycle.ts` | 46–58 | requireValidInstallationId | B deleted |
| `ai-platform/src/control/lifecycle.ts` | 59–65 | requireValidPublicKey | B deleted |
| `ai-platform/src/control/lifecycle.ts` | 66–69 | RevokeKeyPayload | B deleted |
| `ai-platform/src/control/lifecycle.ts` | 70–85 | validateRevokeKeyPayload | B deleted |
| `ai-platform/src/control/lifecycle.ts` | 86–132 | validateEnrollPayload | B deleted |
| `ai-platform/src/control/lifecycle.ts` | 133–156 | validateRotatePayload | B deleted |
| `ai-platform/src/control/lifecycle.ts` | 157–163 | d1ErrorMessage | B deleted |
| `ai-platform/src/control/lifecycle.ts` | 164–169 | isUniqueConstraint | B deleted |
| `ai-platform/src/control/lifecycle.ts` | 170–182 | constraintTarget | B deleted |
| `ai-platform/src/control/lifecycle.ts` | 183–200 | runControlBatch | B deleted |
| `ai-platform/src/control/lifecycle.ts` | 201–295 | handleEnroll | B deleted |
| `ai-platform/src/control/lifecycle.ts` | 296–379 | handleRotate | B deleted |
| `ai-platform/src/control/lifecycle.ts` | 380–467 | handleRevokeKey | B deleted |
| `ai-platform/src/control/lifecycle.ts` | 468–520 | handleSuspend | B deleted |
| `ai-platform/src/control/lifecycle.ts` | 521–570 | handleResume | B deleted |
| `ai-platform/src/control/lifecycle.ts` | 571–619 | handleDelete | B deleted |
| `ai-platform/src/control/plan.ts` | 1–11 | preamble / imports / shared declarations | B deleted |
| `ai-platform/src/control/plan.ts` | 12–23 | runControlBatch | B deleted |
| `ai-platform/src/control/plan.ts` | 24–33 | parsePlanNameFromPath | B deleted |
| `ai-platform/src/control/plan.ts` | 34–88 | validatePlanPayload | B deleted |
| `ai-platform/src/control/plan.ts` | 89–139 | validatePlanUpdatePayload | B deleted |
| `ai-platform/src/control/plan.ts` | 140–191 | handlePlanCreate | B deleted |
| `ai-platform/src/control/plan.ts` | 192–255 | handlePlanUpdate | B deleted |
| `ai-platform/src/control/plan.ts` | 256–293 | handlePlanDelete | B deleted |
| `ai-platform/src/control/quota-inspect.ts` | 1–5 | preamble / imports / shared declarations | B deleted |
| `ai-platform/src/control/quota-inspect.ts` | 6–19 | capMap | B deleted |
| `ai-platform/src/control/quota-inspect.ts` | 20–145 | handleInstallationQuotaGet | B deleted |
| `ai-platform/src/control/routing-policy.ts` | 1–4 | preamble / imports / shared declarations | T |
| `ai-platform/src/control/routing-policy.ts` | 5–12 | RoutingPolicyRow | T |
| `ai-platform/src/control/routing-policy.ts` | 13–19 | PublishedCapabilityManifest | T |
| `ai-platform/src/control/routing-policy.ts` | 20–23 | PUBLISHED_CAPABILITY_MANIFESTS | T |
| `ai-platform/src/control/routing-policy.ts` | 24–34 | parseRoutingPolicyRef | T |
| `ai-platform/src/control/routing-policy.ts` | 35–70 | collectTargetLatencyClasses | T |
| `ai-platform/src/control/routing-policy.ts` | 71–75 | isUniqueConstraint | T |
| `ai-platform/src/control/routing-policy.ts` | 76–87 | runControlBatch | T |
| `ai-platform/src/control/routing-policy.ts` | 88–112 | latencyMismatchWarnings | T |
| `ai-platform/src/control/routing-policy.ts` | 113–130 | installationsExist | T |
| `ai-platform/src/control/routing-policy.ts` | 131–195 | publishRoutingPolicyAction | T |
| `ai-platform/src/control/routing-policy.ts` | 196–267 | canaryRoutingPolicyAction | T |
| `ai-platform/src/control/routing-policy.ts` | 268–334 | promoteRoutingPolicyAction | T |
| `ai-platform/src/control/routing-policy.ts` | 335–432 | rollbackRoutingPolicyAction | T |
| `ai-platform/src/control/support-purge.ts` | 1–14 | preamble / imports / shared declarations | B deleted |
| `ai-platform/src/control/support-purge.ts` | 15–16 | INSTALLATION_DELETED_STATUS | B deleted |
| `ai-platform/src/control/support-purge.ts` | 17–29 | runPurge | B deleted |
| `ai-platform/src/control/support-purge.ts` | 30–71 | handleSupportLookup | B deleted |
| `ai-platform/src/control/support-purge.ts` | 72–128 | handleInstallationPurge | B deleted |
| `ai-platform/src/control/token-contract.ts` | 1–4 | preamble / imports / shared declarations | T |
| `ai-platform/src/control/token-contract.ts` | 5–6 | ROTATION_TARGET_VER | T |
| `ai-platform/src/control/token-contract.ts` | 7–53 | beginTokenContractRotationAction | T |
| `ai-platform/src/control/token-contract.ts` | 54–105 | retireTokenContractAction | T |
| `ai-platform/src/control/types.ts` | 1–4 | preamble / imports / shared declarations | T |
| `ai-platform/src/control/types.ts` | 5–10 | ControlBindings | T |
| `ai-platform/src/control/types.ts` | 11–16 | requireNonEmptyString | T |
| `ai-platform/src/support/index.ts` | 1–9 | preamble / imports / shared declarations | T |
| `ai-platform/src/support/index.ts` | 10–27 | SupportLookupRequestTrace | T |
| `ai-platform/src/support/index.ts` | 28–40 | SupportLookupAttemptTrace | T |
| `ai-platform/src/support/index.ts` | 41–49 | SupportLookupResult | T |
| `ai-platform/src/support/index.ts` | 50–55 | SupportLookupListEntry | T |
| `ai-platform/src/support/index.ts` | 56–59 | SupportLookupListResult | T |
| `ai-platform/src/support/index.ts` | 60–67 | SupportLookupQuery | T |
| `ai-platform/src/support/index.ts` | 68–74 | SupportLookupBindings | T |
| `ai-platform/src/support/index.ts` | 75–102 | LookupRow | T |
| `ai-platform/src/support/index.ts` | 103–113 | LOOKUP_BY_REFERENCE_SQL | T |
| `ai-platform/src/support/index.ts` | 114–125 | LOOKUP_BY_INSTALLATION_SQL | T |
| `ai-platform/src/support/index.ts` | 126–129 | envelopeKey | T |
| `ai-platform/src/support/index.ts` | 130–149 | requestTraceFromRow | T |
| `ai-platform/src/support/index.ts` | 150–171 | attemptsFromRows | T |
| `ai-platform/src/support/index.ts` | 172–193 | loadEnvelopeIfWithinRetention | T |
| `ai-platform/src/support/index.ts` | 194–203 | groupRowsByRequest | T |
| `ai-platform/src/support/index.ts` | 204–230 | buildSingleLookupFromRows | T |
| `ai-platform/src/support/index.ts` | 231–263 | resolveInstallationId | T |
| `ai-platform/src/support/index.ts` | 264–280 | normalizeQuery | T |
| `ai-platform/src/support/index.ts` | 281–344 | supportLookup | T |
| `ai-platform/src/vendor/entrypoint.ts` | 79–79 | VENDOR_CHANNEL | T |
| `ai-platform/src/vendor/entrypoint.ts` | 80–80 | ACTIVATION_MS | T |
| `ai-platform/src/vendor/entrypoint.ts` | 129–130 | VendorMethod | T |
| `ai-platform/src/vendor/entrypoint.ts` | 131–134 | HpVendorMethod | T |
| `ai-platform/src/vendor/entrypoint.ts` | 137–149 | CeilingPolicyRow | T |
| `ai-platform/src/vendor/entrypoint.ts` | 150–156 | VendorResultEnvelope | T |
| `ai-platform/src/vendor/entrypoint.ts` | 172–173 | HEX64_RE | T |
| `ai-platform/src/vendor/entrypoint.ts` | 174–197 | VendorEnv | T |
| `ai-platform/src/vendor/entrypoint.ts` | 198–208 | OperatorCredentialRow | T |
| `ai-platform/src/vendor/entrypoint.ts` | 323–327 | isValidEd25519PublicKeyEncoding | T |
| `ai-platform/src/vendor/entrypoint.ts` | 748–764 | decodeAttestation | T |
| `ai-platform/src/vendor/entrypoint.ts` | 1048–1063 | ceilingPolicyRowToDetail | T |
| `ai-platform/src/vendor/entrypoint.ts` | 1064–1076 | readCurrentCeilingPolicy | T |
| `ai-platform/src/vendor/entrypoint.ts` | 1306–1313 | envelopeWithoutCeilingOverride | T |
| `ai-platform/src/vendor/entrypoint.ts` | 1314–1333 | buildCeilingOverrideOperation | T |
| `ai-platform/src/vendor/entrypoint.ts` | 1639–1642 | isHex64 | T |
| `ai-platform/src/vendor/entrypoint.ts` | 1643–1647 | PlatformSigningMaterial | T |
| `ai-platform/src/vendor/entrypoint.ts` | 1929–1929 | VendorEntrypoint | T |
| `ai-platform/src/vendor/entrypoint.ts` | 1930–2079 | registerOperatorCredential | T |
| `ai-platform/src/vendor/entrypoint.ts` | 2080–2164 | revokeOperatorCredential | T |
| `ai-platform/src/vendor/entrypoint.ts` | 2165–2192 | listOperatorCredentials | T |
| `ai-platform/src/vendor/entrypoint.ts` | 2999–3112 | setCeilingPolicy | T |
| `ai-platform/src/vendor/entrypoint.ts` | 4459–4462 | resume | T |
| `ai-platform/src/vendor/entrypoint.ts` | 4746–4764 | invokeClassH | T |
| `ai-platform/src/vendor/entrypoint.ts` | 4765–4781 | publishRoutingPolicy | T |
| `ai-platform/src/vendor/entrypoint.ts` | 4782–4808 | canaryRoutingPolicy | T |
| `ai-platform/src/vendor/entrypoint.ts` | 4809–4827 | promoteRoutingPolicy | T |
| `ai-platform/src/vendor/entrypoint.ts` | 4828–4846 | rollbackRoutingPolicy | T |
| `ai-platform/src/vendor/entrypoint.ts` | 4847–4865 | armKillSwitch | T |
| `ai-platform/src/vendor/entrypoint.ts` | 4866–4884 | disarmKillSwitch | T |
| `ai-platform/src/vendor/entrypoint.ts` | 4885–4897 | deprecateCapability | T |
| `ai-platform/src/vendor/entrypoint.ts` | 4898–4910 | retireCapability | T |
| `ai-platform/src/vendor/entrypoint.ts` | 4911–4922 | beginTokenContractRotation | T |
| `ai-platform/src/vendor/entrypoint.ts` | 4923–4935 | retireTokenContract | T |
| `ai-platform/src/vendor/entrypoint.ts` | 4936–4948 | activateCohort | T |
| `ai-platform/src/vendor/entrypoint.ts` | 4949–4961 | promoteCohort | T |
| `ai-platform/src/vendor/entrypoint.ts` | 5040–5071 | recordOperatorAction | T |
| `ai-platform/src/vendor/entrypoint.ts` | 5072–5125 | supportLookup | T |

## Unchanged supporting dependencies

- `ai-platform/src/capability` ← `ai-platform/src/control/capability-lifecycle.ts`: unchanged supporting dependency; read only as required by owned invariant
- `ai-platform/src/capability` ← `ai-platform/src/control/cohort.ts`: unchanged supporting dependency; read only as required by owned invariant
- `ai-platform/src/quota-do` ← `ai-platform/src/control/entitle.ts`: unchanged supporting dependency; read only as required by owned invariant
- `ai-platform/src/support` ← `ai-platform/src/control/index.ts`: unchanged supporting dependency; read only as required by owned invariant
- `ai-platform/src/retention` ← `ai-platform/src/control/index.ts`: unchanged supporting dependency; read only as required by owned invariant
- `ai-platform/src/reference.ts` ← `ai-platform/src/control/index.ts`: unchanged supporting dependency; read only as required by owned invariant
- `ai-platform/src/quota-do` ← `ai-platform/src/control/quota-inspect.ts`: unchanged supporting dependency; read only as required by owned invariant
- `ai-platform/manifests/published/clinic.visit_summary@1.0.0.json` ← `ai-platform/src/control/routing-policy.ts`: unchanged supporting dependency; read only as required by owned invariant
- `ai-platform/src/reference.ts` ← `ai-platform/src/control/support-purge.ts`: unchanged supporting dependency; read only as required by owned invariant
- `ai-platform/src/retention` ← `ai-platform/src/control/support-purge.ts`: unchanged supporting dependency; read only as required by owned invariant
- `ai-platform/src/support` ← `ai-platform/src/control/support-purge.ts`: unchanged supporting dependency; read only as required by owned invariant
- `ai-platform/src/journal` ← `ai-platform/src/support/index.ts`: unchanged supporting dependency; read only as required by owned invariant
- `ai-platform/src/reference.ts` ← `ai-platform/src/support/index.ts`: unchanged supporting dependency; read only as required by owned invariant
- `ai-platform/src/retention` ← `ai-platform/src/support/index.ts`: unchanged supporting dependency; read only as required by owned invariant
- `ai-platform/src/retention` ← `ai-platform/src/vendor/entrypoint.ts`: unchanged supporting dependency; read only as required by owned invariant
- `ai-platform/src/support` ← `ai-platform/src/vendor/entrypoint.ts`: unchanged supporting dependency; read only as required by owned invariant
