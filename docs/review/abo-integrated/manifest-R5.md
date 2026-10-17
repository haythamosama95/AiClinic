# R5 bounded source manifest

Target: `db9244fddfddc1905335fb8c7105328c15a0cc5e`. Deletions use baseline coordinates. Inventory only; no source reviewed by preparation.

| Path | Lines | Symbol / region | Revision |
| --- | --- | --- | --- |
| `ai-platform/migrations/20261006120000_usage_term.sql` | 1–4 | preamble / imports / shared declarations | T |
| `ai-platform/migrations/20261006120000_usage_term.sql` | 5–31 | usage_event_new | T |
| `ai-platform/migrations/20261006120000_usage_term.sql` | 32–35 | idx_usage_event_installation_id | T |
| `ai-platform/migrations/20261006120000_usage_term.sql` | 36–36 | idx_usage_rollup_term_id | T |
| `ai-platform/migrations/20261006160000_fallback_admission_feed.sql` | 1–2 | preamble / imports / shared declarations | T |
| `ai-platform/migrations/20261006160000_fallback_admission_feed.sql` | 3–14 | fallback_admission | T |
| `ai-platform/migrations/20261006160000_fallback_admission_feed.sql` | 15–17 | fallback_admission_state | T |
| `ai-platform/migrations/20261006160000_fallback_admission_feed.sql` | 18–24 | feed_consumer | T |
| `ai-platform/migrations/20261014120000_ai_request_idempotency_fingerprint.sql` | 1–3 | preamble / imports / shared declarations | T |
| `ai-platform/src/adapter.ts` | 1–14 | preamble / imports / shared declarations | T |
| `ai-platform/src/adapter.ts` | 15–16 | INGRESS_BODY_SIZE_LIMIT | T |
| `ai-platform/src/adapter.ts` | 17–24 | TERMINAL_EVENT_KINDS | T |
| `ai-platform/src/adapter.ts` | 25–26 | TerminalEventKind | T |
| `ai-platform/src/adapter.ts` | 27–32 | AdapterSseEvent | T |
| `ai-platform/src/adapter.ts` | 33–34 | AdapterDisconnectReason | T |
| `ai-platform/src/adapter.ts` | 35–46 | AdapterStreamContext | T |
| `ai-platform/src/adapter.ts` | 47–54 | AdapterEventSink | T |
| `ai-platform/src/adapter.ts` | 55–63 | AdapterEventSourceHandle | T |
| `ai-platform/src/adapter.ts` | 64–68 | AdapterEventSourceFactory | T |
| `ai-platform/src/adapter.ts` | 69–83 | PreAcceptResult | T |
| `ai-platform/src/adapter.ts` | 84–95 | PreAcceptInput | T |
| `ai-platform/src/adapter.ts` | 96–97 | PreAcceptGate | T |
| `ai-platform/src/adapter.ts` | 98–103 | HandleAdapterRequestOptions | T |
| `ai-platform/src/adapter.ts` | 104–109 | AcceptedSseEventInput | T |
| `ai-platform/src/adapter.ts` | 110–126 | buildAcceptedSseEvent | T |
| `ai-platform/src/adapter.ts` | 127–130 | isTerminalEventType | T |
| `ai-platform/src/adapter.ts` | 131–134 | isTerminalEventKind | T |
| `ai-platform/src/adapter.ts` | 135–201 | pushTerminalEvent | T |
| `ai-platform/src/adapter.ts` | 202–205 | encodeSseEvent | T |
| `ai-platform/src/adapter.ts` | 206–219 | ingressTooLargeResponse | T |
| `ai-platform/src/adapter.ts` | 220–227 | adapterParseFailureResponse | T |
| `ai-platform/src/adapter.ts` | 228–254 | preAcceptFailureResponse | T |
| `ai-platform/src/adapter.ts` | 255–261 | eventSourceRequiredResponse | T |
| `ai-platform/src/adapter.ts` | 262–267 | ParsedHeaders | T |
| `ai-platform/src/adapter.ts` | 268–295 | parseRequiredHeaders | T |
| `ai-platform/src/adapter.ts` | 296–303 | isPlainObject | T |
| `ai-platform/src/adapter.ts` | 304–306 | ADAPTER_ROUTING_BODY_FIELDS | T |
| `ai-platform/src/adapter.ts` | 307–312 | parseAdapterRequestBody | T |
| `ai-platform/src/adapter.ts` | 313–325 | parseRequestBody | T |
| `ai-platform/src/adapter.ts` | 326–335 | concatUint8Arrays | T |
| `ai-platform/src/adapter.ts` | 336–343 | BodyReadResult | T |
| `ai-platform/src/adapter.ts` | 344–384 | readBodyWithinLimit | T |
| `ai-platform/src/adapter.ts` | 385–397 | safeCloseController | T |
| `ai-platform/src/adapter.ts` | 398–597 | handleAdapterRequest | T |
| `ai-platform/src/admission/index.ts` | 1–27 | preamble / imports / shared declarations | T |
| `ai-platform/src/admission/index.ts` | 28–29 | ADMISSION_DEADLINE_MS | T |
| `ai-platform/src/admission/index.ts` | 30–31 | ADMISSION_CLOCK_SKEW_SECONDS | T |
| `ai-platform/src/admission/index.ts` | 32–44 | AdmissionInput | T |
| `ai-platform/src/admission/index.ts` | 45–49 | AdmissionBindings | T |
| `ai-platform/src/admission/index.ts` | 50–58 | AdmissionContext | T |
| `ai-platform/src/admission/index.ts` | 59–78 | AdmissionSuccess | T |
| `ai-platform/src/admission/index.ts` | 79–99 | AdmissionFailure | T |
| `ai-platform/src/admission/index.ts` | 100–102 | AdmissionResult | T |
| `ai-platform/src/admission/index.ts` | 103–115 | PendingGraceAdmission | T |
| `ai-platform/src/admission/index.ts` | 116–117 | GraceQueueStatus | T |
| `ai-platform/src/admission/index.ts` | 118–129 | JournaledRequestRow | T |
| `ai-platform/src/admission/index.ts` | 130–135 | AdmissionDoTransportResult | T |
| `ai-platform/src/admission/index.ts` | 136–142 | CoverageMirrorRow | T |
| `ai-platform/src/admission/index.ts` | 143–155 | mapJournalState | T |
| `ai-platform/src/admission/index.ts` | 156–171 | idempotentFromJournal | T |
| `ai-platform/src/admission/index.ts` | 172–190 | selectAiRequestByKey | T |
| `ai-platform/src/admission/index.ts` | 191–208 | selectAiRequestById | T |
| `ai-platform/src/admission/index.ts` | 209–224 | fallbackEntitlementSnapshot | T |
| `ai-platform/src/admission/index.ts` | 225–231 | currentClockMs | T |
| `ai-platform/src/admission/index.ts` | 232–237 | yieldForTestClock | T |
| `ai-platform/src/admission/index.ts` | 238–247 | waitUntilAdmissionDeadline | T |
| `ai-platform/src/admission/index.ts` | 248–253 | listPendingGraceAdmissions | T |
| `ai-platform/src/admission/index.ts` | 254–259 | markGraceAdmissionStatus | T |
| `ai-platform/src/admission/index.ts` | 260–265 | stampGraceReconcileRetry | T |
| `ai-platform/src/admission/index.ts` | 266–269 | drainPendingGraceAdmissions | T |
| `ai-platform/src/admission/index.ts` | 270–275 | peekPendingGraceAdmissions | T |
| `ai-platform/src/admission/index.ts` | 276–284 | attachGraceUsage | T |
| `ai-platform/src/admission/index.ts` | 285–286 | resetGraceAdmissionCounter | T |
| `ai-platform/src/admission/index.ts` | 287–320 | callAdmissionDo | T |
| `ai-platform/src/admission/index.ts` | 321–326 | bandDegraded | T |
| `ai-platform/src/admission/index.ts` | 327–430 | mapDoOutcome | T |
| `ai-platform/src/admission/index.ts` | 431–442 | coverageUnknown | T |
| `ai-platform/src/admission/index.ts` | 443–457 | pendingFallbackWeight | T |
| `ai-platform/src/admission/index.ts` | 458–567 | tryMirrorFallbackAdmission | T |
| `ai-platform/src/admission/index.ts` | 568–601 | raceAdmissionDo | T |
| `ai-platform/src/admission/index.ts` | 602–779 | runAdmission | T |
| `ai-platform/src/capability/index.ts` | 1–17 | preamble / imports / shared declarations | T |
| `ai-platform/src/capability/index.ts` | 18–19 | CapabilityRegistry | T |
| `ai-platform/src/capability/index.ts` | 20–30 | ResolveResult | T |
| `ai-platform/src/capability/index.ts` | 31–39 | PublicManifest | T |
| `ai-platform/src/capability/index.ts` | 40–45 | DiscoveryResult | T |
| `ai-platform/src/capability/index.ts` | 46–47 | OVERLAP_WINDOW_MS | T |
| `ai-platform/src/capability/index.ts` | 48–54 | LifecycleOverlay | T |
| `ai-platform/src/capability/index.ts` | 55–62 | EffectiveLifecycle | T |
| `ai-platform/src/capability/index.ts` | 63–86 | effectiveLifecycle | T |
| `ai-platform/src/capability/index.ts` | 87–117 | loadLifecycleOverlay | T |
| `ai-platform/src/capability/index.ts` | 118–139 | manifestWithEffectiveIdentity | T |
| `ai-platform/src/capability/index.ts` | 140–143 | registryKey | T |
| `ai-platform/src/capability/index.ts` | 144–148 | isKillSwitchActive | T |
| `ai-platform/src/capability/index.ts` | 149–163 | loadKillSwitch | T |
| `ai-platform/src/capability/index.ts` | 164–167 | MirrorPlanSnapshot | T |
| `ai-platform/src/capability/index.ts` | 168–187 | loadPlanSnapshotFromMirror | T |
| `ai-platform/src/capability/index.ts` | 188–221 | assertPlanIncludesCapability | T |
| `ai-platform/src/capability/index.ts` | 222–255 | assertManifestAccess | T |
| `ai-platform/src/capability/index.ts` | 256–289 | providerIdsFromPolicyRow | T |
| `ai-platform/src/capability/index.ts` | 290–335 | resolveProviderIds | T |
| `ai-platform/src/capability/index.ts` | 336–357 | collectActiveProviderKillSwitches | T |
| `ai-platform/src/capability/index.ts` | 358–394 | evaluateCapabilityKillSwitches | T |
| `ai-platform/src/capability/index.ts` | 395–398 | manifestToHashInput | T |
| `ai-platform/src/capability/index.ts` | 399–406 | sortManifests | T |
| `ai-platform/src/capability/index.ts` | 407–417 | deepFreeze | T |
| `ai-platform/src/capability/index.ts` | 418–421 | freezeManifest | T |
| `ai-platform/src/capability/index.ts` | 422–437 | toPublicManifest | T |
| `ai-platform/src/capability/index.ts` | 438–454 | unmodifiableRegistry | T |
| `ai-platform/src/capability/index.ts` | 455–469 | createCapabilityRegistry | T |
| `ai-platform/src/capability/index.ts` | 470–488 | setCapabilityRegistry | T |
| `ai-platform/src/capability/index.ts` | 489–499 | isCapabilityVersionRegistered | T |
| `ai-platform/src/capability/index.ts` | 500–510 | getRegisteredManifest | T |
| `ai-platform/src/capability/index.ts` | 511–522 | isSuccessorRegistered | T |
| `ai-platform/src/capability/index.ts` | 523–626 | resolve | T |
| `ai-platform/src/capability/index.ts` | 627–635 | computeDiscoveryEtag | T |
| `ai-platform/src/capability/index.ts` | 636–725 | discover | T |
| `ai-platform/src/capability/index.ts` | 726–801 | getGrantedCapabilityVersion | T |
| `ai-platform/src/capability/index.ts` | 802–812 | opaqueTagEquals | T |
| `ai-platform/src/capability/index.ts` | 813–828 | ifNoneMatchMatches | T |
| `ai-platform/src/capability/index.ts` | 829–858 | buildDiscoveryResponse | T |
| `ai-platform/src/capability/index.ts` | 859–877 | publishedQuotaWeightMax | T |
| `ai-platform/src/clock.ts` | 1–2 | preamble / imports / shared declarations | T |
| `ai-platform/src/clock.ts` | 3–7 | ClockEnv | T |
| `ai-platform/src/clock.ts` | 8–32 | harnessClockMs | T |
| `ai-platform/src/clock.ts` | 33–37 | clockNowMs | T |
| `ai-platform/src/clock.ts` | 38–41 | clockNowIso | T |
| `ai-platform/src/clock.ts` | 42–44 | clockNowSeconds | T |
| `ai-platform/src/config-cache/index.ts` | 1–8 | preamble / imports / shared declarations | T |
| `ai-platform/src/config-cache/index.ts` | 9–19 | ConfigEntityKind | T |
| `ai-platform/src/config-cache/index.ts` | 20–22 | D1Row | T |
| `ai-platform/src/config-cache/index.ts` | 23–27 | D1Reader | T |
| `ai-platform/src/config-cache/index.ts` | 28–30 | DEFAULT_CONFIG_CACHE_TTL_MS | T |
| `ai-platform/src/config-cache/index.ts` | 31–32 | CACHE_TTL_MS | T |
| `ai-platform/src/config-cache/index.ts` | 33–43 | resolveConfigCacheTtlMs | T |
| `ai-platform/src/config-cache/index.ts` | 44–48 | CacheEntry | T |
| `ai-platform/src/config-cache/index.ts` | 49–59 | ConfigCacheMissError | T |
| `ai-platform/src/config-cache/index.ts` | 60–63 | cloneRow | T |
| `ai-platform/src/config-cache/index.ts` | 64–162 | ConfigCache | T |
| `ai-platform/src/config-cache/index.ts` | 163–165 | isolateConfigCache | T |
| `ai-platform/src/config-cache/index.ts` | 166–169 | configureIsolateConfigCache | T |
| `ai-platform/src/config-cache/index.ts` | 170–184 | parseCanaryIds | T |
| `ai-platform/src/config-cache/index.ts` | 185–211 | loadRoutingPolicyDocument | T |
| `ai-platform/src/config-cache/index.ts` | 212–420 | createD1ConfigReader | T |
| `ai-platform/src/config-cache/index.ts` | 421–450 | loadConfig | T |
| `ai-platform/src/credit/index.ts` | 1–7 | preamble / imports / shared declarations | T |
| `ai-platform/src/credit/index.ts` | 8–9 | QUOTA_DO_RPC_URL | T |
| `ai-platform/src/credit/index.ts` | 10–21 | CreditInput | T |
| `ai-platform/src/credit/index.ts` | 22–26 | CreditBindings | T |
| `ai-platform/src/credit/index.ts` | 27–30 | CreditResult | T |
| `ai-platform/src/credit/index.ts` | 31–34 | ReconcileGraceResult | T |
| `ai-platform/src/credit/index.ts` | 35–39 | ReconcileGraceContext | T |
| `ai-platform/src/credit/index.ts` | 40–43 | CreditWireResponse | T |
| `ai-platform/src/credit/index.ts` | 44–47 | CreditRpcOutcome | T |
| `ai-platform/src/credit/index.ts` | 48–52 | SettleFallbackWireResponse | T |
| `ai-platform/src/credit/index.ts` | 53–62 | FallbackAdmissionRow | T |
| `ai-platform/src/credit/index.ts` | 63–116 | invokeCreditRpc | T |
| `ai-platform/src/credit/index.ts` | 117–145 | invokeSettleFallback | T |
| `ai-platform/src/credit/index.ts` | 146–176 | creditUsage | T |
| `ai-platform/src/credit/index.ts` | 177–247 | reconcileGraceUsage | T |
| `ai-platform/src/discovery/index.ts` | 1–19 | preamble / imports / shared declarations | T |
| `ai-platform/src/discovery/index.ts` | 20–26 | DiscoveryEnv | T |
| `ai-platform/src/discovery/index.ts` | 27–38 | unauthenticatedResponse | T |
| `ai-platform/src/discovery/index.ts` | 39–134 | handleDiscoveryRequest | T |
| `ai-platform/src/entitlement/index.ts` | 1–17 | preamble / imports / shared declarations | T |
| `ai-platform/src/entitlement/index.ts` | 18–24 | EntitlementContext | T |
| `ai-platform/src/entitlement/index.ts` | 25–33 | EntitlementRejectionPath | T |
| `ai-platform/src/entitlement/index.ts` | 34–45 | EntitlementResult | T |
| `ai-platform/src/entitlement/index.ts` | 46–64 | parseAllowedCapabilities | T |
| `ai-platform/src/entitlement/index.ts` | 65–81 | rejectForbidden | T |
| `ai-platform/src/entitlement/index.ts` | 82–103 | rejectKillSwitch | T |
| `ai-platform/src/entitlement/index.ts` | 104–118 | loadKillSwitchOrInactive | T |
| `ai-platform/src/entitlement/index.ts` | 119–122 | isKillSwitchActive | T |
| `ai-platform/src/entitlement/index.ts` | 123–148 | loadMatchingGrant | T |
| `ai-platform/src/entitlement/index.ts` | 149–201 | evaluateEntitlement | T |
| `ai-platform/src/entitlement/index.ts` | 202–205 | CoveragePrecheckContext | T |
| `ai-platform/src/entitlement/index.ts` | 206–216 | CoveragePrecheckResult | T |
| `ai-platform/src/entitlement/index.ts` | 217–294 | evaluateCoveragePrecheck | T |
| `ai-platform/src/errors.ts` | 1–26 | preamble / imports / shared declarations | T |
| `ai-platform/src/errors.ts` | 27–33 | TaxonomyEntry | T |
| `ai-platform/src/errors.ts` | 34–181 | TAXONOMY | T |
| `ai-platform/src/errors.ts` | 182–183 | ALL_TAXONOMY_CODES | T |
| `ai-platform/src/errors.ts` | 184–185 | TAXONOMY_CODE_SET | T |
| `ai-platform/src/errors.ts` | 186–189 | isTaxonomyCode | T |
| `ai-platform/src/errors.ts` | 190–196 | classifyErrorCode | T |
| `ai-platform/src/errors.ts` | 197–200 | getTaxonomyEntry | T |
| `ai-platform/src/errors.ts` | 201–204 | isRetrySafe | T |
| `ai-platform/src/errors.ts` | 205–212 | liveHttpStatusForCode | T |
| `ai-platform/src/errors.ts` | 213–220 | CoverageLapseReason | T |
| `ai-platform/src/errors.ts` | 221–227 | SupplementaryFieldInput | T |
| `ai-platform/src/errors.ts` | 228–230 | DEFAULT_RATE_LIMITED_RETRY_AFTER_SECONDS | T |
| `ai-platform/src/errors.ts` | 231–237 | retryAfterSecondsForRateLimited | T |
| `ai-platform/src/errors.ts` | 238–260 | supplementaryFieldsForCode | T |
| `ai-platform/src/errors.ts` | 261–266 | ErrorBodyInput | T |
| `ai-platform/src/errors.ts` | 267–273 | ErrorBody | T |
| `ai-platform/src/errors.ts` | 274–287 | buildErrorBody | T |
| `ai-platform/src/manifest/index.ts` | 1–6 | preamble / imports / shared declarations | T |
| `ai-platform/src/manifest/index.ts` | 7–19 | MANIFEST_FIELD_GROUPS | T |
| `ai-platform/src/manifest/index.ts` | 20–21 | ManifestFieldGroup | T |
| `ai-platform/src/manifest/index.ts` | 22–76 | MANIFEST_FIELD_MANIFEST | T |
| `ai-platform/src/manifest/index.ts` | 77–83 | ECONOMICS_TOKEN_CEILING_FIELD | T |
| `ai-platform/src/manifest/index.ts` | 84–94 | ECONOMICS_TOKEN_CEILING_LEGACY_ALIAS | T |
| `ai-platform/src/manifest/index.ts` | 95–97 | ECONOMICS_TOKEN_CEILING_SCHEMA_NOTE | T |
| `ai-platform/src/manifest/index.ts` | 98–104 | CONVERSATIONAL_ONLY_INTERACTION_FIELDS | T |
| `ai-platform/src/manifest/index.ts` | 105–106 | PROVIDER_SHAPED_KEY_ALLOWLIST | T |
| `ai-platform/src/manifest/index.ts` | 107–107 | LIFECYCLE_STATES | T |
| `ai-platform/src/manifest/index.ts` | 108–108 | OUTPUT_MODES | T |
| `ai-platform/src/manifest/index.ts` | 109–114 | ACCEPTANCE_MODES | T |
| `ai-platform/src/manifest/index.ts` | 115–116 | InteractionMode | T |
| `ai-platform/src/manifest/index.ts` | 117–120 | ManifestGroupRecord | T |
| `ai-platform/src/manifest/index.ts` | 121–123 | IdentityGroup | T |
| `ai-platform/src/manifest/index.ts` | 124–124 | AccessGroup | T |
| `ai-platform/src/manifest/index.ts` | 125–130 | InteractionGroup | T |
| `ai-platform/src/manifest/index.ts` | 131–131 | InputGroup | T |
| `ai-platform/src/manifest/index.ts` | 132–135 | ContextRequirementEntry | T |
| `ai-platform/src/manifest/index.ts` | 136–139 | ConversationalContextRequirements | T |
| `ai-platform/src/manifest/index.ts` | 140–142 | ContextRequirementsGroup | T |
| `ai-platform/src/manifest/index.ts` | 143–145 | PromptBindingGroup | T |
| `ai-platform/src/manifest/index.ts` | 146–146 | OutputGroup | T |
| `ai-platform/src/manifest/index.ts` | 147–149 | RoutingGroup | T |
| `ai-platform/src/manifest/index.ts` | 150–152 | EconomicsGroup | T |
| `ai-platform/src/manifest/index.ts` | 153–157 | GovernanceGroup | T |
| `ai-platform/src/manifest/index.ts` | 158–171 | Manifest | T |
| `ai-platform/src/manifest/index.ts` | 172–177 | PublishedRegistryEntry | T |
| `ai-platform/src/manifest/index.ts` | 178–185 | ManifestTreeIo | T |
| `ai-platform/src/manifest/index.ts` | 186–189 | isPlainObject | T |
| `ai-platform/src/manifest/index.ts` | 190–193 | isFiniteNumber | T |
| `ai-platform/src/manifest/index.ts` | 194–210 | deepFreeze | T |
| `ai-platform/src/manifest/index.ts` | 211–229 | assertExactKeys | T |
| `ai-platform/src/manifest/index.ts` | 230–240 | isForbiddenProviderOrModelKey | T |
| `ai-platform/src/manifest/index.ts` | 241–263 | assertNeverNamesProviderOrModel | T |
| `ai-platform/src/manifest/index.ts` | 264–275 | validateObjectGroup | T |
| `ai-platform/src/manifest/index.ts` | 276–299 | validateAccessGroup | T |
| `ai-platform/src/manifest/index.ts` | 300–335 | validateSingleShotContextRequirements | T |
| `ai-platform/src/manifest/index.ts` | 336–349 | assertEconomicsTypes | T |
| `ai-platform/src/manifest/index.ts` | 350–369 | normalizeEconomicsGroup | T |
| `ai-platform/src/manifest/index.ts` | 370–414 | validateConversationalContextRequirements | T |
| `ai-platform/src/manifest/index.ts` | 415–418 | isPositiveInteger | T |
| `ai-platform/src/manifest/index.ts` | 419–433 | assertConversationalInteractionFields | T |
| `ai-platform/src/manifest/index.ts` | 434–450 | assertInteractionExactKeys | T |
| `ai-platform/src/manifest/index.ts` | 451–463 | resolveInteractionMode | T |
| `ai-platform/src/manifest/index.ts` | 464–491 | assertNoConversationalFieldsOnSingleShot | T |
| `ai-platform/src/manifest/index.ts` | 492–492 | DIAGNOSTIC_HORIZON_MIN_DAYS | T |
| `ai-platform/src/manifest/index.ts` | 493–493 | DIAGNOSTIC_HORIZON_MAX_DAYS | T |
| `ai-platform/src/manifest/index.ts` | 494–496 | DIAGNOSTIC_RETENTION_CLASS | T |
| `ai-platform/src/manifest/index.ts` | 497–518 | assertRetentionClassBand | T |
| `ai-platform/src/manifest/index.ts` | 519–535 | assertContentEnums | T |
| `ai-platform/src/manifest/index.ts` | 536–622 | validate | T |
| `ai-platform/src/manifest/index.ts` | 623–638 | canonicalStringify | T |
| `ai-platform/src/manifest/index.ts` | 639–644 | bufferToHex | T |
| `ai-platform/src/manifest/index.ts` | 645–648 | load | T |
| `ai-platform/src/manifest/index.ts` | 649–655 | hashManifest | T |
| `ai-platform/src/manifest/index.ts` | 656–661 | hashCanonicalJson | T |
| `ai-platform/src/manifest/index.ts` | 662–685 | verifyPublishedRegistry | T |
| `ai-platform/src/manifest/index.ts` | 686–724 | verifyManifestTree | T |
| `ai-platform/src/period-close/index.ts` | 1–5 | preamble / imports / shared declarations | B deleted |
| `ai-platform/src/period-close/index.ts` | 6–9 | periodStartIso | B deleted |
| `ai-platform/src/period-close/index.ts` | 10–25 | resolveCreditPrice | B deleted |
| `ai-platform/src/period-close/index.ts` | 26–42 | creditsConsumedForInstallation | B deleted |
| `ai-platform/src/period-close/index.ts` | 43–94 | runPeriodClose | B deleted |
| `ai-platform/src/pipeline/index.ts` | 1–49 | preamble / imports / shared declarations | T |
| `ai-platform/src/pipeline/index.ts` | 50–52 | GuardStage | T |
| `ai-platform/src/pipeline/index.ts` | 53–71 | ComposeRequestFn | T |
| `ai-platform/src/pipeline/index.ts` | 72–116 | GuardInput | T |
| `ai-platform/src/pipeline/index.ts` | 117–122 | GuardBindings | T |
| `ai-platform/src/pipeline/index.ts` | 123–154 | GuardFreshSuccess | T |
| `ai-platform/src/pipeline/index.ts` | 155–164 | GuardIdempotentSuccess | T |
| `ai-platform/src/pipeline/index.ts` | 165–166 | GuardSuccess | T |
| `ai-platform/src/pipeline/index.ts` | 167–177 | GuardFailure | T |
| `ai-platform/src/pipeline/index.ts` | 178–184 | TermAdmissionFields | T |
| `ai-platform/src/pipeline/index.ts` | 185–186 | GuardResult | T |
| `ai-platform/src/pipeline/index.ts` | 187–199 | SettleHappyPathInput | T |
| `ai-platform/src/pipeline/index.ts` | 200–209 | SettleHappyPathBindings | T |
| `ai-platform/src/pipeline/index.ts` | 210–213 | SettleHappyPathResult | T |
| `ai-platform/src/pipeline/index.ts` | 214–245 | fail | T |
| `ai-platform/src/pipeline/index.ts` | 246–250 | isPlainObject | T |
| `ai-platform/src/pipeline/index.ts` | 251–263 | extractUserIntent | T |
| `ai-platform/src/pipeline/index.ts` | 264–273 | extractSuppliedContext | T |
| `ai-platform/src/pipeline/index.ts` | 274–283 | extractConversationId | T |
| `ai-platform/src/pipeline/index.ts` | 284–292 | extractTurnOrdinal | T |
| `ai-platform/src/pipeline/index.ts` | 293–299 | extractTranscript | T |
| `ai-platform/src/pipeline/index.ts` | 300–327 | releaseAdmissionReservation | T |
| `ai-platform/src/pipeline/index.ts` | 328–674 | runGuard | T |
| `ai-platform/src/pipeline/index.ts` | 675–694 | buildAttempt | T |
| `ai-platform/src/pipeline/index.ts` | 695–773 | settleHappyPath | T |
| `ai-platform/src/platform-vocabulary.ts` | 1–1 | preamble / imports / shared declarations | T |
| `ai-platform/src/platform-vocabulary.ts` | 2–8 | PLAN_TIERS | T |
| `ai-platform/src/platform-vocabulary.ts` | 9–11 | PlanTier | T |
| `ai-platform/src/platform-vocabulary.ts` | 12–14 | ISSUER_KEY_ALGORITHM | T |
| `ai-platform/src/platform-vocabulary.ts` | 15–17 | MAX_IDENTIFIER_LENGTH | T |
| `ai-platform/src/platform-vocabulary.ts` | 18–19 | ED25519_PUBLIC_KEY_BYTE_LENGTH | T |
| `ai-platform/src/platform-vocabulary.ts` | 20–22 | CANONICAL_UUID_RE | T |
| `ai-platform/src/platform-vocabulary.ts` | 23–26 | isWithinIdentifierLength | T |
| `ai-platform/src/platform-vocabulary.ts` | 27–30 | isKnownPlanTier | T |
| `ai-platform/src/platform-vocabulary.ts` | 31–34 | isSupportedInstallationKeyAlgorithm | T |
| `ai-platform/src/platform-vocabulary.ts` | 35–39 | isCanonicalUuid | T |
| `ai-platform/src/platform-vocabulary.ts` | 40–43 | toCanonicalUuid | T |
| `ai-platform/src/platform-vocabulary.ts` | 44–57 | decodeBase64url | T |
| `ai-platform/src/platform-vocabulary.ts` | 58–67 | isEd25519PublicKeyByteLength | T |
| `ai-platform/src/platform-vocabulary.ts` | 68–91 | isImportableEd25519PublicKeyBase64url | T |
| `ai-platform/src/platform-vocabulary.ts` | 92–99 | planTierMeetsMinimum | T |
| `ai-platform/src/quota-do/coverage.ts` | 1–13 | preamble / imports / shared declarations | T |
| `ai-platform/src/quota-do/coverage.ts` | 165–169 | PlatformSigningMaterial | T |
| `ai-platform/src/quota-do/coverage.ts` | 170–180 | base64UrlToBytes | T |
| `ai-platform/src/quota-do/coverage.ts` | 223–230 | loadHot | T |
| `ai-platform/src/quota-do/coverage.ts` | 704–704 | ONE_DAY_MS | T |
| `ai-platform/src/quota-do/coverage.ts` | 705–705 | ONE_HOUR_MS | T |
| `ai-platform/src/quota-do/coverage.ts` | 706–707 | MS_PER_DAY | T |
| `ai-platform/src/quota-do/coverage.ts` | 738–753 | resolveOrgIdFromStorage | T |
| `ai-platform/src/quota-do/coverage.ts` | 754–771 | resolveInstallationIdFromStorage | T |
| `ai-platform/src/quota-do/coverage.ts` | 1005–1022 | syncAlarm | T |
| `ai-platform/src/quota-do/coverage.ts` | 1043–1069 | computeNextAlarmAt | T |
| `ai-platform/src/quota-do/coverage.ts` | 1070–1073 | isEnvelopeRecord | T |
| `ai-platform/src/quota-do/coverage.ts` | 1074–1080 | complimentaryDurationDays | T |
| `ai-platform/src/quota-do/index.ts` | 1–20 | preamble / imports / shared declarations | T |
| `ai-platform/src/quota-do/index.ts` | 21–21 | EPHEMERAL_HORIZON_MS | T |
| `ai-platform/src/quota-do/index.ts` | 22–22 | CONCURRENCY_LIMIT | T |
| `ai-platform/src/quota-do/index.ts` | 23–24 | STALE_RESERVATION_MS | T |
| `ai-platform/src/quota-do/index.ts` | 25–26 | STATE_KEY | T |
| `ai-platform/src/quota-do/index.ts` | 27–31 | PerRequestWriteCounts | T |
| `ai-platform/src/quota-do/index.ts` | 32–33 | perRequestWriteCounts | T |
| `ai-platform/src/quota-do/index.ts` | 34–39 | getPerRequestWriteCounts | T |
| `ai-platform/src/quota-do/index.ts` | 40–47 | readTotalChanges | T |
| `ai-platform/src/quota-do/index.ts` | 48–57 | recordHotWrites | T |
| `ai-platform/src/quota-do/index.ts` | 58–67 | write | T |
| `ai-platform/src/quota-do/index.ts` | 68–77 | recordEventWrites | T |
| `ai-platform/src/quota-do/index.ts` | 78–87 | write | T |
| `ai-platform/src/quota-do/index.ts` | 88–91 | EphemeralEntry | T |
| `ai-platform/src/quota-do/index.ts` | 94–100 | IDEMPOTENCY_STATES | T |
| `ai-platform/src/quota-do/index.ts` | 101–102 | IdempotencyRequestState | T |
| `ai-platform/src/quota-do/index.ts` | 103–111 | IdempotencyEntry | T |
| `ai-platform/src/quota-do/index.ts` | 112–128 | EntitlementSnapshot | T |
| `ai-platform/src/quota-do/index.ts` | 129–136 | PeriodCounters | T |
| `ai-platform/src/quota-do/index.ts` | 137–150 | QuotaDoState | T |
| `ai-platform/src/quota-do/index.ts` | 151–177 | AdmissionRequest | T |
| `ai-platform/src/quota-do/index.ts` | 178–185 | SettleFallbackRequest | T |
| `ai-platform/src/quota-do/index.ts` | 186–189 | SettleFallbackResponse | T |
| `ai-platform/src/quota-do/index.ts` | 190–197 | IdempotencyPriorState | T |
| `ai-platform/src/quota-do/index.ts` | 198–208 | AdmissionAdmitted | T |
| `ai-platform/src/quota-do/index.ts` | 209–225 | AdmissionTermRefusal | T |
| `ai-platform/src/quota-do/index.ts` | 231–236 | AdmissionIdempotent | T |
| `ai-platform/src/quota-do/index.ts` | 237–241 | AdmissionIdempotencyConflict | T |
| `ai-platform/src/quota-do/index.ts` | 242–247 | AdmissionQuotaExhausted | T |
| `ai-platform/src/quota-do/index.ts` | 248–252 | AdmissionConcurrencyExhausted | T |
| `ai-platform/src/quota-do/index.ts` | 253–261 | AdmissionResponse | T |
| `ai-platform/src/quota-do/index.ts` | 262–266 | UsageActual | T |
| `ai-platform/src/quota-do/index.ts` | 267–271 | CreditIdempotencyState | T |
| `ai-platform/src/quota-do/index.ts` | 272–285 | CreditRequest | T |
| `ai-platform/src/quota-do/index.ts` | 286–291 | CreditAcknowledged | T |
| `ai-platform/src/quota-do/index.ts` | 292–297 | CreditUnknownRequest | T |
| `ai-platform/src/quota-do/index.ts` | 298–300 | CreditResponse | T |
| `ai-platform/src/quota-do/index.ts` | 322–331 | initialPeriodCounters | T |
| `ai-platform/src/quota-do/index.ts` | 332–341 | initialState | T |
| `ai-platform/src/quota-do/index.ts` | 342–346 | loadState | T |
| `ai-platform/src/quota-do/index.ts` | 347–355 | assertInstallationBound | T |
| `ai-platform/src/quota-do/index.ts` | 403–423 | maybeResetPeriod | T |
| `ai-platform/src/quota-do/index.ts` | 424–433 | isQuotaExhausted | T |
| `ai-platform/src/quota-do/index.ts` | 438–441 | usesLegacyEntitlementAdmission | T |
| `ai-platform/src/quota-do/index.ts` | 442–445 | usesLegacyEntitlementCredit | T |
| `ai-platform/src/quota-do/index.ts` | 446–459 | shouldUseLegacyCredit | T |
| `ai-platform/src/quota-do/index.ts` | 460–465 | mirrorProductionCreditToLegacy | T |
| `ai-platform/src/quota-do/index.ts` | 476–485 | applyFallbackWeightToLegacy | T |
| `ai-platform/src/quota-do/index.ts` | 486–502 | admissionOnLegacyState | T |
| `ai-platform/src/quota-do/index.ts` | 503–503 | assertInstallationBound | T |
| `ai-platform/src/quota-do/index.ts` | 505–650 | maybeResetPeriod | T |
| `ai-platform/src/quota-do/index.ts` | 651–669 | creditOnLegacyState | T |
| `ai-platform/src/quota-do/index.ts` | 702–733 | markIdempotencyOnCredit | T |
| `ai-platform/src/quota-do/index.ts` | 734–738 | isSoftThresholdFraction | T |
| `ai-platform/src/quota-do/index.ts` | 739–743 | coerceSoftThreshold | T |
| `ai-platform/src/quota-do/index.ts` | 744–765 | isSoftThresholdCrossed | T |
| `ai-platform/src/quota-do/index.ts` | 766–788 | markIdempotencyOnCredit | T |
| `ai-platform/src/quota-do/index.ts` | 789–798 | ReservationRow | T |
| `ai-platform/src/quota-do/index.ts` | 799–802 | AdmissionIdempotencyBinding | T |
| `ai-platform/src/quota-do/index.ts` | 803–808 | StoredAnswerEntry | T |
| `ai-platform/src/quota-do/index.ts` | 817–825 | ParsedHot | T |
| `ai-platform/src/quota-do/index.ts` | 826–838 | parseHotRow | T |
| `ai-platform/src/quota-do/index.ts` | 839–853 | parseBandEmitted | T |
| `ai-platform/src/quota-do/index.ts` | 861–861 | persistParsedHot | T |
| `ai-platform/src/quota-do/index.ts` | 862–876 | updateHot | T |
| `ai-platform/src/quota-do/index.ts` | 893–907 | sameIdempotencyBinding | T |
| `ai-platform/src/quota-do/index.ts` | 908–924 | storeAnswer | T |
| `ai-platform/src/quota-do/index.ts` | 925–931 | returnStoredAdmission | T |
| `ai-platform/src/quota-do/index.ts` | 932–932 | storeAnswer | T |
| `ai-platform/src/quota-do/index.ts` | 933–938 | recordHotWrites | T |
| `ai-platform/src/quota-do/index.ts` | 944–953 | sqlExecLocal | T |
| `ai-platform/src/quota-do/index.ts` | 979–989 | resolveCapabilityId | T |
| `ai-platform/src/quota-do/index.ts` | 990–994 | resolveQuotaWeight | T |
| `ai-platform/src/quota-do/index.ts` | 1030–1076 | chargeStaleReservations | T |
| `ai-platform/src/quota-do/index.ts` | 1077–1098 | endGraceIfExhausted | T |
| `ai-platform/src/quota-do/index.ts` | 1099–1114 | sqlExecLocal | T |
| `ai-platform/src/quota-do/index.ts` | 1115–1127 | insertOutbox | T |
| `ai-platform/src/quota-do/index.ts` | 1128–1184 | emitBandCrossedIfNeeded | T |
| `ai-platform/src/quota-do/index.ts` | 1203–1212 | sqlExecLocal | T |
| `ai-platform/src/quota-do/index.ts` | 1213–1216 | SqlStorage | T |
| `ai-platform/src/quota-do/index.ts` | 1217–1221 | sqlExecLocal | T |
| `ai-platform/src/quota-do/index.ts` | 1222–1225 | sqlStringLocal | T |
| `ai-platform/src/quota-do/index.ts` | 1226–1241 | admitOnHotRow | T |
| `ai-platform/src/quota-do/index.ts` | 1319–1437 | applyDueBoundaries | T |
| `ai-platform/src/quota-do/index.ts` | 1438–1553 | emitBandCrossedIfNeeded | T |
| `ai-platform/src/quota-do/index.ts` | 1554–1554 | storeAnswer | T |
| `ai-platform/src/quota-do/index.ts` | 1555–1567 | recordHotWrites | T |
| `ai-platform/src/quota-do/index.ts` | 1568–1574 | hotRowInstallationMismatch | T |
| `ai-platform/src/quota-do/index.ts` | 1575–1585 | settleReservationOnHot | T |
| `ai-platform/src/quota-do/index.ts` | 1644–1653 | recordHotWrites | T |
| `ai-platform/src/quota-do/index.ts` | 1654–1663 | legacyCountersFromHot | T |
| `ai-platform/src/quota-do/index.ts` | 1664–1668 | hotReservationCount | T |
| `ai-platform/src/quota-do/index.ts` | 1669–1675 | admittedRequestIdFromAnswer | T |
| `ai-platform/src/quota-do/index.ts` | 1676–1687 | hotStillHoldsRequestId | T |
| `ai-platform/src/quota-do/index.ts` | 1688–1724 | settleFallbackRPC | T |
| `ai-platform/src/quota-do/index.ts` | 1725–1746 | admissionRPC | T |
| `ai-platform/src/quota-do/index.ts` | 1747–1794 | creditRPC | T |
| `ai-platform/src/quota-do/index.ts` | 1828–1835 | persistParsedHot | T |
| `ai-platform/src/quota-do/index.ts` | 1895–1898 | InspectRequest | T |
| `ai-platform/src/quota-do/index.ts` | 1899–1907 | InspectResponse | T |
| `ai-platform/src/quota-do/index.ts` | 1908–1913 | inspectRPC | T |
| `ai-platform/src/quota-do/index.ts` | 1918–1921 | SqlExecStorage | T |
| `ai-platform/src/router/index.ts` | 1–14 | preamble / imports / shared declarations | T |
| `ai-platform/src/router/index.ts` | 15–15 | RoutingTier | T |
| `ai-platform/src/router/index.ts` | 16–16 | CostClass | T |
| `ai-platform/src/router/index.ts` | 17–21 | CostClassSource | T |
| `ai-platform/src/router/index.ts` | 22–28 | CapabilityRequirements | T |
| `ai-platform/src/router/index.ts` | 29–44 | RouterContext | T |
| `ai-platform/src/router/index.ts` | 45–52 | ExcludedReasonCode | T |
| `ai-platform/src/router/index.ts` | 53–61 | ChainEntry | T |
| `ai-platform/src/router/index.ts` | 62–67 | ExcludedEntry | T |
| `ai-platform/src/router/index.ts` | 68–79 | RoutingDecision | T |
| `ai-platform/src/router/index.ts` | 80–83 | RouterOutcome | T |
| `ai-platform/src/router/index.ts` | 84–89 | RoutingPolicyErrorCode | T |
| `ai-platform/src/router/index.ts` | 90–99 | RoutingPolicyError | T |
| `ai-platform/src/router/index.ts` | 100–107 | TargetFeatures | T |
| `ai-platform/src/router/index.ts` | 108–115 | PolicyTarget | T |
| `ai-platform/src/router/index.ts` | 116–124 | PolicyRuleMatch | T |
| `ai-platform/src/router/index.ts` | 125–130 | PolicyRuleRequires | T |
| `ai-platform/src/router/index.ts` | 131–142 | PolicyRule | T |
| `ai-platform/src/router/index.ts` | 143–149 | PolicyOverride | T |
| `ai-platform/src/router/index.ts` | 150–169 | RoutingPolicyDocument | T |
| `ai-platform/src/router/index.ts` | 170–176 | ActiveRoutingPolicyRow | T |
| `ai-platform/src/router/index.ts` | 177–192 | normalizePolicyRow | T |
| `ai-platform/src/router/index.ts` | 193–198 | COST_CLASS_ORDER | T |
| `ai-platform/src/router/index.ts` | 199–202 | isKnownCostClass | T |
| `ai-platform/src/router/index.ts` | 203–206 | isFiniteNumber | T |
| `ai-platform/src/router/index.ts` | 207–212 | SOURCE_PRIORITY | T |
| `ai-platform/src/router/index.ts` | 213–214 | SUPPORTED_SCHEMA_VERSIONS | T |
| `ai-platform/src/router/index.ts` | 215–218 | matchClause | T |
| `ai-platform/src/router/index.ts` | 219–228 | matchAllLanguages | T |
| `ai-platform/src/router/index.ts` | 229–242 | isCatchAllMatch | T |
| `ai-platform/src/router/index.ts` | 243–272 | validatePolicyDocument | T |
| `ai-platform/src/router/index.ts` | 273–307 | ruleMatches | T |
| `ai-platform/src/router/index.ts` | 308–350 | resolveEffectiveCostClass | T |
| `ai-platform/src/router/index.ts` | 351–370 | mergeRequirementFloors | T |
| `ai-platform/src/router/index.ts` | 371–426 | applyInstallationOverride | T |
| `ai-platform/src/router/index.ts` | 427–437 | isKillSwitchRowActive | T |
| `ai-platform/src/router/index.ts` | 438–451 | collectKilledProviderIds | T |
| `ai-platform/src/router/index.ts` | 452–469 | mergeKilledProviderIds | T |
| `ai-platform/src/router/index.ts` | 470–588 | filterTargets | T |
| `ai-platform/src/router/index.ts` | 589–702 | selectCandidateChain | T |
| `ai-platform/src/router/index.ts` | 703–715 | preloadRoutingPolicyForInstallation | T |
| `ai-platform/src/soft-threshold/index.ts` | 1–2 | preamble / imports / shared declarations | T |
| `ai-platform/src/soft-threshold/index.ts` | 3–14 | AdmissionAllowResult | T |
| `ai-platform/src/soft-threshold/index.ts` | 15–20 | CLIENT_ROUTING_INJECTION_KEYS | T |
| `ai-platform/src/soft-threshold/index.ts` | 21–23 | ClientRoutingInjectionKey | T |
| `ai-platform/src/soft-threshold/index.ts` | 24–29 | routingTierFromAdmission | T |
| `ai-platform/src/soft-threshold/index.ts` | 30–47 | degradedNoticeFromAdmission | T |
| `ai-platform/src/soft-threshold/index.ts` | 48–52 | resolveRoutingTier | T |
| `ai-platform/src/usage-summary/index.ts` | 1–17 | preamble / imports / shared declarations | B deleted |
| `ai-platform/src/usage-summary/index.ts` | 18–19 | QUOTA_DO_RPC_URL | B deleted |
| `ai-platform/src/usage-summary/index.ts` | 20–25 | UsageSummaryEnv | B deleted |
| `ai-platform/src/usage-summary/index.ts` | 26–37 | UsageSummarySuccessBody | B deleted |
| `ai-platform/src/usage-summary/index.ts` | 38–41 | periodFromIso | B deleted |
| `ai-platform/src/usage-summary/index.ts` | 42–53 | unauthenticatedResponse | B deleted |
| `ai-platform/src/usage-summary/index.ts` | 54–73 | inspectQuotaDo | B deleted |
| `ai-platform/src/usage-summary/index.ts` | 74–209 | handleUsageSummaryRequest | B deleted |
| `ai-platform/src/worker.ts` | 1–154 | preamble / imports / shared declarations | T |
| `ai-platform/src/worker.ts` | 155–170 | Env | T |
| `ai-platform/src/worker.ts` | 171–176 | createWorkerLogFactory | T |
| `ai-platform/src/worker.ts` | 177–190 | assertRequiredBindings | T |
| `ai-platform/src/worker.ts` | 191–193 | resolveConfigCacheTtlMs | T |
| `ai-platform/src/worker.ts` | 194–195 | bootLog | T |
| `ai-platform/src/worker.ts` | 196–210 | setCapabilityRegistry | T |
| `ai-platform/src/worker.ts` | 211–212 | HEARTBEAT_INTERVAL_MS | T |
| `ai-platform/src/worker.ts` | 213–225 | PRODUCTION_GUARD_THRESHOLDS | T |
| `ai-platform/src/worker.ts` | 226–229 | AcceptContext | T |
| `ai-platform/src/worker.ts` | 230–231 | AcceptContextStore | T |
| `ai-platform/src/worker.ts` | 232–233 | BrokerTerminalState | T |
| `ai-platform/src/worker.ts` | 234–243 | admissionAllowFromGuard | T |
| `ai-platform/src/worker.ts` | 244–244 | createPushableInvocationEvents | T |
| `ai-platform/src/worker.ts` | 245–245 | push | T |
| `ai-platform/src/worker.ts` | 246–288 | end | T |
| `ai-platform/src/worker.ts` | 289–292 | isPlainObject | T |
| `ai-platform/src/worker.ts` | 293–301 | extractBearerToken | T |
| `ai-platform/src/worker.ts` | 302–311 | extractCapabilityId | T |
| `ai-platform/src/worker.ts` | 312–321 | extractUserIntent | T |
| `ai-platform/src/worker.ts` | 322–330 | extractSuppliedContext | T |
| `ai-platform/src/worker.ts` | 331–334 | termIdFromGuard | T |
| `ai-platform/src/worker.ts` | 335–338 | periodFromIso | T |
| `ai-platform/src/worker.ts` | 339–363 | createProductionHeartbeatTicker | T |
| `ai-platform/src/worker.ts` | 364–364 | createWorkerExecutionContext | T |
| `ai-platform/src/worker.ts` | 365–365 | waitUntil | T |
| `ai-platform/src/worker.ts` | 366–379 | drainWaitUntil | T |
| `ai-platform/src/worker.ts` | 380–380 | allowAllRateLimit | T |
| `ai-platform/src/worker.ts` | 381–392 | limit | T |
| `ai-platform/src/worker.ts` | 393–414 | stableTestRateLimit | T |
| `ai-platform/src/worker.ts` | 415–415 | testInstallationRateLimit | T |
| `ai-platform/src/worker.ts` | 416–416 | testActorRateLimit | T |
| `ai-platform/src/worker.ts` | 417–418 | testCapabilityRateLimit | T |
| `ai-platform/src/worker.ts` | 419–438 | productionRateLimitBindings | T |
| `ai-platform/src/worker.ts` | 439–456 | resolveProviderPort | T |
| `ai-platform/src/worker.ts` | 457–477 | buildAttemptInput | T |
| `ai-platform/src/worker.ts` | 478–508 | attemptsForFailedSettlement | T |
| `ai-platform/src/worker.ts` | 509–525 | EMPTY_ROUTING_DECISION | T |
| `ai-platform/src/worker.ts` | 526–545 | placeholderComposedRequest | T |
| `ai-platform/src/worker.ts` | 546–557 | PostAcceptInternalErrorInput | T |
| `ai-platform/src/worker.ts` | 558–591 | settlePostAcceptInternalError | T |
| `ai-platform/src/worker.ts` | 592–679 | settleMissingHandoffInternalError | T |
| `ai-platform/src/worker.ts` | 680–693 | placeholderTerminalResult | T |
| `ai-platform/src/worker.ts` | 694–720 | buildPostResponseInput | T |
| `ai-platform/src/worker.ts` | 721–733 | SettlementJournalInput | T |
| `ai-platform/src/worker.ts` | 734–751 | writeSettlementJournal | T |
| `ai-platform/src/worker.ts` | 752–759 | writePostResponseDetail | T |
| `ai-platform/src/worker.ts` | 760–816 | settleTerminal | T |
| `ai-platform/src/worker.ts` | 817–866 | settleCompletedRequest | T |
| `ai-platform/src/worker.ts` | 867–880 | pushFailedTerminal | T |
| `ai-platform/src/worker.ts` | 881–947 | replayIdempotentTerminal | T |
| `ai-platform/src/worker.ts` | 948–950 | pushFailedTerminal | T |
| `ai-platform/src/worker.ts` | 951–1062 | createProductionEventSource | T |
| `ai-platform/src/worker.ts` | 1063–1225 | runFreshEventSource | T |
| `ai-platform/src/worker.ts` | 1226–1392 | onBrokerReady | T |
| `ai-platform/src/worker.ts` | 1393–1518 | createProductionPreAccept | T |
| `ai-platform/src/worker.ts` | 1519–1524 | handleLivePostRequest | T |
| `ai-platform/src/worker.ts` | 1525–1543 | makeLog | T |
| `ai-platform/src/worker.ts` | 1544–1545 | ArgValidationError | T |
| `ai-platform/src/worker.ts` | 1546–1550 | constructor | T |
| `ai-platform/src/worker.ts` | 1551–1564 | isArgValidationError | T |
| `ai-platform/src/worker.ts` | 1565–1604 | assertAdmissionArgs | T |
| `ai-platform/src/worker.ts` | 1605–1637 | assertCreditArgs | T |
| `ai-platform/src/worker.ts` | 1638–1649 | assertReleaseArgs | T |
| `ai-platform/src/worker.ts` | 1650–1673 | logGatewayRpcFailure | T |
| `ai-platform/src/worker.ts` | 1674–1684 | requestedPlatformDoContractVersion | T |
| `ai-platform/src/worker.ts` | 1685–1698 | platformDoContractRefusal | T |
| `ai-platform/src/worker.ts` | 1699–1717 | readHarnessAdmissionFault | T |
| `ai-platform/src/worker.ts` | 1718–1718 | GatewayObject | T |
| `ai-platform/src/worker.ts` | 1719–2023 | fetch | T |
| `ai-platform/src/worker.ts` | 2024–2048 | alarm | T |
| `ai-platform/src/worker.ts` | 2049–2077 | persistShippedCoverageAlerts | T |
| `ai-platform/src/worker.ts` | 2078–2078 | AIP_CONTRACT_VERSION_HEADER | T |
| `ai-platform/src/worker.ts` | 2079–2080 | FEED_CONSUMER | T |
| `ai-platform/src/worker.ts` | 2081–2091 | parseRequestedFeedVersion | T |
| `ai-platform/src/worker.ts` | 2092–2106 | base64UrlDecode | T |
| `ai-platform/src/worker.ts` | 2107–2127 | parseJwtKid | T |
| `ai-platform/src/worker.ts` | 2128–2150 | importIssuerPublicKey | T |
| `ai-platform/src/worker.ts` | 2151–2182 | issuerKeyUsable | T |
| `ai-platform/src/worker.ts` | 2183–2186 | feedUnauthorizedResponse | T |
| `ai-platform/src/worker.ts` | 2187–2247 | verifyFeedBearerToken | T |
| `ai-platform/src/worker.ts` | 2248–2345 | handleFeedCoverageRequest | T |
| `ai-platform/src/worker.ts` | 2346–2514 | fetch | T |

## Unchanged supporting dependencies

- `ai-platform/src/context/validator.ts` ← `ai-platform/src/adapter.ts`: unchanged supporting dependency; read only as required by owned invariant
- `ai-platform/src/logger.ts` ← `ai-platform/src/adapter.ts`: unchanged supporting dependency; read only as required by owned invariant
- `ai-platform/src/context/context-request.ts` ← `ai-platform/src/adapter.ts`: unchanged supporting dependency; read only as required by owned invariant
- `ai-platform/src/manifest` ← `ai-platform/src/adapter.ts`: unchanged supporting dependency; read only as required by owned invariant
- `ai-platform/src/reference.ts` ← `ai-platform/src/adapter.ts`: unchanged supporting dependency; read only as required by owned invariant
- `ai-platform/src/trace.ts` ← `ai-platform/src/adapter.ts`: unchanged supporting dependency; read only as required by owned invariant
- `ai-platform/src/config-cache` ← `ai-platform/src/admission/index.ts`: unchanged supporting dependency; read only as required by owned invariant
- `ai-platform/src/identity` ← `ai-platform/src/admission/index.ts`: unchanged supporting dependency; read only as required by owned invariant
- `ai-platform/src/logger.ts` ← `ai-platform/src/admission/index.ts`: unchanged supporting dependency; read only as required by owned invariant
- `ai-platform/src/logger.ts` ← `ai-platform/src/admission/index.ts`: unchanged supporting dependency; read only as required by owned invariant
- `ai-platform/src/capability` ← `ai-platform/src/admission/index.ts`: unchanged supporting dependency; read only as required by owned invariant
- `ai-platform/src/rate-limit` ← `ai-platform/src/admission/index.ts`: unchanged supporting dependency; read only as required by owned invariant
- `ai-platform/src/config-cache` ← `ai-platform/src/capability/index.ts`: unchanged supporting dependency; read only as required by owned invariant
- `ai-platform/src/identity` ← `ai-platform/src/capability/index.ts`: unchanged supporting dependency; read only as required by owned invariant
- `ai-platform/src/logger.ts` ← `ai-platform/src/capability/index.ts`: unchanged supporting dependency; read only as required by owned invariant
- `ai-platform/src/rate-limit` ← `ai-platform/src/capability/index.ts`: unchanged supporting dependency; read only as required by owned invariant
- `ai-platform/src/manifest` ← `ai-platform/src/capability/index.ts`: unchanged supporting dependency; read only as required by owned invariant
- `ai-platform/src/logger.ts` ← `ai-platform/src/config-cache/index.ts`: unchanged supporting dependency; read only as required by owned invariant
- `ai-platform/src/logger.ts` ← `ai-platform/src/credit/index.ts`: unchanged supporting dependency; read only as required by owned invariant
- `ai-platform/src/trace.ts` ← `ai-platform/src/credit/index.ts`: unchanged supporting dependency; read only as required by owned invariant
- `ai-platform/src/capability` ← `ai-platform/src/discovery/index.ts`: unchanged supporting dependency; read only as required by owned invariant
- `ai-platform/src/config-cache` ← `ai-platform/src/discovery/index.ts`: unchanged supporting dependency; read only as required by owned invariant
- `ai-platform/src/identity` ← `ai-platform/src/discovery/index.ts`: unchanged supporting dependency; read only as required by owned invariant
- `ai-platform/src/alert` ← `ai-platform/src/discovery/index.ts`: unchanged supporting dependency; read only as required by owned invariant
- `ai-platform/src/logger.ts` ← `ai-platform/src/discovery/index.ts`: unchanged supporting dependency; read only as required by owned invariant
- `ai-platform/src/reference.ts` ← `ai-platform/src/discovery/index.ts`: unchanged supporting dependency; read only as required by owned invariant
- `ai-platform/src/trace.ts` ← `ai-platform/src/discovery/index.ts`: unchanged supporting dependency; read only as required by owned invariant
- `ai-platform/src/capability` ← `ai-platform/src/entitlement/index.ts`: unchanged supporting dependency; read only as required by owned invariant
- `ai-platform/src/config-cache` ← `ai-platform/src/entitlement/index.ts`: unchanged supporting dependency; read only as required by owned invariant
- `ai-platform/src/identity` ← `ai-platform/src/entitlement/index.ts`: unchanged supporting dependency; read only as required by owned invariant
- `ai-platform/src/logger.ts` ← `ai-platform/src/entitlement/index.ts`: unchanged supporting dependency; read only as required by owned invariant
- `ai-platform/src/rate-limit` ← `ai-platform/src/entitlement/index.ts`: unchanged supporting dependency; read only as required by owned invariant
- `ai-platform/src/context/index.ts` ← `ai-platform/src/manifest/index.ts`: unchanged supporting dependency; read only as required by owned invariant
- `ai-platform/src/admission` ← `ai-platform/src/pipeline/index.ts`: unchanged supporting dependency; read only as required by owned invariant
- `ai-platform/src/capability` ← `ai-platform/src/pipeline/index.ts`: unchanged supporting dependency; read only as required by owned invariant
- `ai-platform/src/config-cache` ← `ai-platform/src/pipeline/index.ts`: unchanged supporting dependency; read only as required by owned invariant
- `ai-platform/src/contracts/canonical.ts` ← `ai-platform/src/pipeline/index.ts`: unchanged supporting dependency; read only as required by owned invariant
- `ai-platform/src/context/preflight.ts` ← `ai-platform/src/pipeline/index.ts`: unchanged supporting dependency; read only as required by owned invariant
- `ai-platform/src/context/validator.ts` ← `ai-platform/src/pipeline/index.ts`: unchanged supporting dependency; read only as required by owned invariant
- `ai-platform/src/credit` ← `ai-platform/src/pipeline/index.ts`: unchanged supporting dependency; read only as required by owned invariant
- `ai-platform/src/entitlement` ← `ai-platform/src/pipeline/index.ts`: unchanged supporting dependency; read only as required by owned invariant
- `ai-platform/src/identity` ← `ai-platform/src/pipeline/index.ts`: unchanged supporting dependency; read only as required by owned invariant
- `ai-platform/src/journal` ← `ai-platform/src/pipeline/index.ts`: unchanged supporting dependency; read only as required by owned invariant
- `ai-platform/src/manifest` ← `ai-platform/src/pipeline/index.ts`: unchanged supporting dependency; read only as required by owned invariant
- `ai-platform/src/pricing` ← `ai-platform/src/pipeline/index.ts`: unchanged supporting dependency; read only as required by owned invariant
- `ai-platform/src/provider/fake.ts` ← `ai-platform/src/pipeline/index.ts`: unchanged supporting dependency; read only as required by owned invariant
- `ai-platform/src/rate-limit` ← `ai-platform/src/pipeline/index.ts`: unchanged supporting dependency; read only as required by owned invariant
- `ai-platform/src/soft-threshold` ← `ai-platform/src/pipeline/index.ts`: unchanged supporting dependency; read only as required by owned invariant
- `ai-platform/src/logger.ts` ← `ai-platform/src/pipeline/index.ts`: unchanged supporting dependency; read only as required by owned invariant
- `ai-platform/src/logger.ts` ← `ai-platform/src/pipeline/index.ts`: unchanged supporting dependency; read only as required by owned invariant
- `ai-platform/src/logger.ts` ← `ai-platform/src/quota-do/coverage.ts`: unchanged supporting dependency; read only as required by owned invariant
- `ai-platform/src/logger.ts` ← `ai-platform/src/quota-do/coverage.ts`: unchanged supporting dependency; read only as required by owned invariant
- `ai-platform/src/trace.ts` ← `ai-platform/src/quota-do/coverage.ts`: unchanged supporting dependency; read only as required by owned invariant
- `ai-platform/src/logger.ts` ← `ai-platform/src/quota-do/index.ts`: unchanged supporting dependency; read only as required by owned invariant
- `ai-platform/src/logger.ts` ← `ai-platform/src/quota-do/index.ts`: unchanged supporting dependency; read only as required by owned invariant
- `ai-platform/src/config-cache` ← `ai-platform/src/router/index.ts`: unchanged supporting dependency; read only as required by owned invariant
- `ai-platform/src/logger.ts` ← `ai-platform/src/router/index.ts`: unchanged supporting dependency; read only as required by owned invariant
- `ai-platform/src/logger.ts` ← `ai-platform/src/router/index.ts`: unchanged supporting dependency; read only as required by owned invariant
- `ai-platform/src/config-cache` ← `ai-platform/src/usage-summary/index.ts`: unchanged supporting dependency; read only as required by owned invariant
- `ai-platform/src/identity` ← `ai-platform/src/usage-summary/index.ts`: unchanged supporting dependency; read only as required by owned invariant
- `ai-platform/src/logger.ts` ← `ai-platform/src/usage-summary/index.ts`: unchanged supporting dependency; read only as required by owned invariant
- `ai-platform/src/quota-do` ← `ai-platform/src/usage-summary/index.ts`: unchanged supporting dependency; read only as required by owned invariant
- `ai-platform/src/reference.ts` ← `ai-platform/src/usage-summary/index.ts`: unchanged supporting dependency; read only as required by owned invariant
- `ai-platform/src/trace.ts` ← `ai-platform/src/usage-summary/index.ts`: unchanged supporting dependency; read only as required by owned invariant
- `ai-platform/src/capability` ← `ai-platform/src/worker.ts`: unchanged supporting dependency; read only as required by owned invariant
- `ai-platform/src/config-cache` ← `ai-platform/src/worker.ts`: unchanged supporting dependency; read only as required by owned invariant
- `ai-platform/src/credit` ← `ai-platform/src/worker.ts`: unchanged supporting dependency; read only as required by owned invariant
- `ai-platform/src/contracts/canonical.ts` ← `ai-platform/src/worker.ts`: unchanged supporting dependency; read only as required by owned invariant
- `ai-platform/src/discovery` ← `ai-platform/src/worker.ts`: unchanged supporting dependency; read only as required by owned invariant
- `ai-platform/src/coverage-read` ← `ai-platform/src/worker.ts`: unchanged supporting dependency; read only as required by owned invariant
- `ai-platform/src/identity` ← `ai-platform/src/worker.ts`: unchanged supporting dependency; read only as required by owned invariant
- `ai-platform/src/journal` ← `ai-platform/src/worker.ts`: unchanged supporting dependency; read only as required by owned invariant
- `ai-platform/src/manifest` ← `ai-platform/src/worker.ts`: unchanged supporting dependency; read only as required by owned invariant
- `ai-platform/manifests/published/clinic.visit_summary@1.0.0.json` ← `ai-platform/src/worker.ts`: unchanged supporting dependency; read only as required by owned invariant
- `ai-platform/src/pipeline` ← `ai-platform/src/worker.ts`: unchanged supporting dependency; read only as required by owned invariant
- `ai-platform/src/provider/fake.ts` ← `ai-platform/src/worker.ts`: unchanged supporting dependency; read only as required by owned invariant
- `ai-platform/src/provider/port.ts` ← `ai-platform/src/worker.ts`: unchanged supporting dependency; read only as required by owned invariant
- `ai-platform/src/provider/wiring.ts` ← `ai-platform/src/worker.ts`: unchanged supporting dependency; read only as required by owned invariant
- `ai-platform/src/provider/fetch-transport.ts` ← `ai-platform/src/worker.ts`: unchanged supporting dependency; read only as required by owned invariant
- `ai-platform/src/rate-limit` ← `ai-platform/src/worker.ts`: unchanged supporting dependency; read only as required by owned invariant
- `ai-platform/src/retention` ← `ai-platform/src/worker.ts`: unchanged supporting dependency; read only as required by owned invariant
- `ai-platform/src/rollup` ← `ai-platform/src/worker.ts`: unchanged supporting dependency; read only as required by owned invariant
- `ai-platform/src/router` ← `ai-platform/src/worker.ts`: unchanged supporting dependency; read only as required by owned invariant
- `ai-platform/src/invocation` ← `ai-platform/src/worker.ts`: unchanged supporting dependency; read only as required by owned invariant
- `ai-platform/src/pricing` ← `ai-platform/src/worker.ts`: unchanged supporting dependency; read only as required by owned invariant
- `ai-platform/src/wall-clock-sleeper.ts` ← `ai-platform/src/worker.ts`: unchanged supporting dependency; read only as required by owned invariant
- `ai-platform/src/soft-threshold` ← `ai-platform/src/worker.ts`: unchanged supporting dependency; read only as required by owned invariant
- `ai-platform/src/stream` ← `ai-platform/src/worker.ts`: unchanged supporting dependency; read only as required by owned invariant
- `ai-platform/src/stream/prose-guards.ts` ← `ai-platform/src/worker.ts`: unchanged supporting dependency; read only as required by owned invariant
- `ai-platform/src/logger.ts` ← `ai-platform/src/worker.ts`: unchanged supporting dependency; read only as required by owned invariant
