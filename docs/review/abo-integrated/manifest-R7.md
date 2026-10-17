# R7 bounded source manifest

Target: `db9244fddfddc1905335fb8c7105328c15a0cc5e`. Deletions use baseline coordinates. Inventory only; no source reviewed by preparation.

| Path | Lines | Symbol / region | Revision |
| --- | --- | --- | --- |
| `abo/src/clinic-api/billing-reads.ts` | 1–4 | preamble / imports / shared declarations | T |
| `abo/src/clinic-api/billing-reads.ts` | 5–6 | PAYMENTS_PAGE_SIZE | T |
| `abo/src/clinic-api/billing-reads.ts` | 7–13 | BillingReadsEnv | T |
| `abo/src/clinic-api/billing-reads.ts` | 14–15 | CoverageSnapshot | T |
| `abo/src/clinic-api/billing-reads.ts` | 16–28 | PaymentRow | T |
| `abo/src/clinic-api/billing-reads.ts` | 29–35 | ReversalRow | T |
| `abo/src/clinic-api/billing-reads.ts` | 36–42 | parseSnapshot | T |
| `abo/src/clinic-api/billing-reads.ts` | 43–61 | loadCoverageViewSnapshot | T |
| `abo/src/clinic-api/billing-reads.ts` | 62–80 | resolveSnapshot | T |
| `abo/src/clinic-api/billing-reads.ts` | 81–143 | buildNotices | T |
| `abo/src/clinic-api/billing-reads.ts` | 144–154 | planDisplayNames | T |
| `abo/src/clinic-api/billing-reads.ts` | 155–181 | loadReversals | T |
| `abo/src/clinic-api/billing-reads.ts` | 182–200 | handleGetSubscription | T |
| `abo/src/clinic-api/billing-reads.ts` | 201–216 | validateCursor | T |
| `abo/src/clinic-api/billing-reads.ts` | 217–258 | loadPaymentPage | T |
| `abo/src/clinic-api/billing-reads.ts` | 259–312 | handleGetPayments | T |
| `abo/src/coverage/view.ts` | 1–6 | preamble / imports / shared declarations | T |
| `abo/src/coverage/view.ts` | 7–15 | CoverageViewEnv | T |
| `abo/src/coverage/view.ts` | 16–20 | CoveragePair | T |
| `abo/src/coverage/view.ts` | 21–27 | FeedPage | T |
| `abo/src/coverage/view.ts` | 28–37 | isNewerPair | T |
| `abo/src/coverage/view.ts` | 38–67 | parseFeedPage | T |
| `abo/src/coverage/view.ts` | 68–74 | readFeedCursor | T |
| `abo/src/coverage/view.ts` | 75–83 | writeFeedCursor | T |
| `abo/src/coverage/view.ts` | 84–95 | loadStoredPair | T |
| `abo/src/coverage/view.ts` | 96–112 | feedEventAccepted | T |
| `abo/src/coverage/view.ts` | 113–152 | applyFeedEvent | T |
| `abo/src/coverage/view.ts` | 153–187 | refreshCoverageView | T |
| `abo/src/worker.ts` | 231–238 | handleBillingV1: subscription/payments read routes | T |
| `ai-platform/src/coverage-read/index.ts` | 1–19 | preamble / imports / shared declarations | T |
| `ai-platform/src/coverage-read/index.ts` | 20–21 | QUOTA_DO_RPC_URL | T |
| `ai-platform/src/coverage-read/index.ts` | 22–29 | CoverageReadEnv | T |
| `ai-platform/src/coverage-read/index.ts` | 30–41 | unauthenticatedResponse | T |
| `ai-platform/src/coverage-read/index.ts` | 42–68 | callReadCoverage | T |
| `ai-platform/src/coverage-read/index.ts` | 69–145 | handleCoverageReadRequest | T |
| `ai-platform/src/quota-do/coverage.ts` | 88–96 | PlanSnapshot | T |
| `ai-platform/src/quota-do/coverage.ts` | 146–152 | ReadCoverageRequest | T |
| `ai-platform/src/quota-do/coverage.ts` | 153–159 | ReadCoverageResponse | T |
| `ai-platform/src/quota-do/coverage.ts` | 288–314 | snapshotTermObject | T |
| `ai-platform/src/quota-do/coverage.ts` | 315–324 | lastEndedTermForSnapshot | T |
| `ai-platform/src/quota-do/coverage.ts` | 325–335 | lapsedSnapshotReason | T |
| `ai-platform/src/quota-do/coverage.ts` | 336–351 | coverageSnapshotHotFields | T |
| `ai-platform/src/quota-do/coverage.ts` | 352–380 | buildSnapshotTermsArray | T |
| `ai-platform/src/quota-do/coverage.ts` | 381–461 | buildCoverageSnapshot | T |
| `ai-platform/src/quota-do/coverage.ts` | 2035–2087 | readCoverageRPC | T |
| `ai-platform/src/quota-do/coverage.ts` | 2552–2557 | MirrorTermView | T |
| `ai-platform/src/quota-do/coverage.ts` | 2558–2588 | mirrorTermViewFromSnapshot | T |
| `ai-platform/src/quota-do/coverage.ts` | 2589–2657 | mirrorFromSnapshot | T |
| `ai-platform/src/quota-do/coverage.ts` | 3076–3082 | sqlNullableString | T |
| `ai-platform/src/quota-do/coverage.ts` | 3083–3089 | sqlNullableNumber | T |
| `ai-platform/src/quota-do/coverage.ts` | 3305–3306 | SnapshotTermEntry | T |
| `ai-platform/src/quota-do/coverage.ts` | 3719–3745 | findGrantAppliedSnapshotForGrant | T |
| `ai-platform/src/vendor/entrypoint.ts` | 4516–4557 | inspectCoverage | T |
| `ai-platform/src/vendor/entrypoint.ts` | 4558–4596 | getCoverage | T |
| `ai-platform/src/vendor/entrypoint.ts` | 4597–4666 | listGrants | T |
| `ai-platform/src/vendor/entrypoint.ts` | 4667–4745 | readCoverageEvents | T |
| `ai-platform/src/vendor/entrypoint.ts` | 5126–5146 | feedConsumerHealth | T |
| `backend/supabase/migrations/20261007230000_coverage_feed_puller_status.sql` | 1–11 | preamble / imports / shared declarations | T |
| `backend/supabase/migrations/20261007230000_coverage_feed_puller_status.sql` | 12–35 | ai_internal.clinic_ai_coverage | T |
| `backend/supabase/migrations/20261007230000_coverage_feed_puller_status.sql` | 36–41 | clinic_ai_coverage_deny_all | T |
| `backend/supabase/migrations/20261007230000_coverage_feed_puller_status.sql` | 42–52 | ai_internal.feed_state | T |
| `backend/supabase/migrations/20261007230000_coverage_feed_puller_status.sql` | 53–75 | feed_state_deny_all | T |
| `backend/supabase/migrations/20261007230000_coverage_feed_puller_status.sql` | 76–82 | ai_internal.status_refresh | T |
| `backend/supabase/migrations/20261007230000_coverage_feed_puller_status.sql` | 83–104 | status_refresh_deny_all | T |
| `backend/supabase/migrations/20261007230000_coverage_feed_puller_status.sql` | 105–378 | auth_internal.pull_coverage_feed | T |
| `backend/supabase/migrations/20261007230000_coverage_feed_puller_status.sql` | 379–441 | auth_internal.get_ai_status | T |
| `backend/supabase/migrations/20261007230000_coverage_feed_puller_status.sql` | 442–470 | public.get_ai_status | T |
| `backend/supabase/migrations/20261007230000_coverage_feed_puller_status.sql` | 471–533 | auth_internal.request_ai_status_refresh | T |
| `backend/supabase/migrations/20261007230000_coverage_feed_puller_status.sql` | 534–557 | public.request_ai_status_refresh | T |
| `backend/supabase/migrations/20261008010000_read_time_status_notices.sql` | 1–8 | preamble / imports / shared declarations | T |
| `backend/supabase/migrations/20261008010000_read_time_status_notices.sql` | 9–320 | auth_internal.get_ai_status | T |
| `backend/supabase/migrations/20261008010000_read_time_status_notices.sql` | 321–349 | public.get_ai_status | T |
| `backend/supabase/migrations/20261008010000_read_time_status_notices.sql` | 350–463 | public.get_ai_billing_status | T |
| `frontend/lib/app/app.dart` | 1–19 | preamble / imports / shared declarations | T |
| `frontend/lib/app/app.dart` | 20–26 | AiClinicApp | T |
| `frontend/lib/app/app.dart` | 27–115 | _AiClinicAppState | T |
| `frontend/lib/app/app_routes.dart` | 1–168 | preamble / imports / shared declarations | T |
| `frontend/lib/app/providers/ai_shell_status_provider.dart` | 1–27 | preamble / imports / shared declarations | T |
| `frontend/lib/app/providers/ai_shell_status_provider.dart` | 28–85 | AiShellStatusNotifier | T |
| `frontend/lib/app/router.dart` | 1–384 | preamble / imports / shared declarations | T |
| `frontend/lib/core/ai/ai_client_sdk.dart` | 1–15 | preamble / imports / shared declarations | T |
| `frontend/lib/core/ai/ai_client_sdk.dart` | 16–18 | int | T |
| `frontend/lib/core/ai/ai_client_sdk.dart` | 19–189 | AiClientSdk | T |
| `frontend/lib/core/ai/ai_client_sdk.dart` | 190–299 | AiInvokeSession | T |
| `frontend/lib/core/ai/discovery_client.dart` | 1–9 | preamble / imports / shared declarations | T |
| `frontend/lib/core/ai/discovery_client.dart` | 10–23 | DiscoveryAuthFailure | T |
| `frontend/lib/core/ai/discovery_client.dart` | 24–36 | DiscoveryFetchResult | T |
| `frontend/lib/core/ai/discovery_client.dart` | 37–144 | DiscoveryClient | T |
| `frontend/lib/core/ai/https_submit_port.dart` | 1–12 | preamble / imports / shared declarations | T |
| `frontend/lib/core/ai/https_submit_port.dart` | 13–113 | PlatformHttpsSubmitPort | T |
| `frontend/lib/core/ai/https_submit_port.dart` | 114–166 | _HttpSseConnection | T |
| `frontend/lib/core/ai/https_submit_port.dart` | 167–262 | _SseLineParser | T |
| `frontend/lib/core/ai/ports.dart` | 1–4 | preamble / imports / shared declarations | T |
| `frontend/lib/core/ai/ports.dart` | 5–9 | AatMintPort | T |
| `frontend/lib/core/ai/ports.dart` | 10–42 | CapabilityInvokeInput | T |
| `frontend/lib/core/ai/ports.dart` | 43–61 | SubmitRequestHeaders | T |
| `frontend/lib/core/ai/ports.dart` | 62–69 | SseConnection | T |
| `frontend/lib/core/ai/ports.dart` | 70–104 | PlatformHttpException | T |
| `frontend/lib/core/ai/ports.dart` | 105–109 | TransportFailure | T |
| `frontend/lib/core/ai/ports.dart` | 110–124 | TransportRetryExhausted | T |
| `frontend/lib/core/ai/ports.dart` | 125–132 | InvokeCancelledException | T |
| `frontend/lib/core/ai/ports.dart` | 133–138 | HttpsSubmitPort | T |
| `frontend/lib/core/ai/sse_events.dart` | 1–141 | preamble / imports / shared declarations | T |
| `frontend/lib/core/ai/taxonomy.dart` | 1–1 | preamble / imports / shared declarations | T |
| `frontend/lib/core/ai/taxonomy.dart` | 2–30 | TaxonomyCode | T |
| `frontend/lib/core/ai/taxonomy.dart` | 31–58 | _wireToCode | T |
| `frontend/lib/core/ai/taxonomy.dart` | 59–87 | _codeToWire | T |
| `frontend/lib/core/ai/taxonomy.dart` | 88–122 | terminalNoRetryCodes | T |
| `frontend/lib/core/ai/taxonomy.dart` | 123–212 | PreStreamDenial | T |
| `frontend/lib/core/ai/usage_summary_client.dart` | 1–8 | preamble / imports / shared declarations | T |
| `frontend/lib/core/ai/usage_summary_client.dart` | 9–22 | UsageSummaryAuthFailure | T |
| `frontend/lib/core/ai/usage_summary_client.dart` | 23–37 | UsageSummaryFetchResult | T |
| `frontend/lib/core/ai/usage_summary_client.dart` | 38–102 | UsageSummaryClient | T |
| `frontend/lib/features/ai/availability/ai_availability.dart` | 1–3 | preamble / imports / shared declarations | T |
| `frontend/lib/features/ai/availability/ai_availability.dart` | 4–34 | AiStatusNotice | T |
| `frontend/lib/features/ai/availability/ai_availability.dart` | 35–44 | kCoverageDenialWireCodes | T |
| `frontend/lib/features/ai/availability/ai_availability.dart` | 45–51 | ContractVersionUnsupportedException | T |
| `frontend/lib/features/ai/availability/ai_availability.dart` | 52–134 | AiAvailability | T |
| `frontend/lib/features/ai/availability/ai_availability.dart` | 135–139 | AiAvailabilityReader | T |
| `frontend/lib/features/ai/availability/ai_availability.dart` | 140–142 | PlatformReachabilityPort | T |
| `frontend/lib/features/ai/availability/ai_availability_reader.dart` | 1–15 | preamble / imports / shared declarations | T |
| `frontend/lib/features/ai/availability/ai_availability_reader.dart` | 16–51 | SupabaseAiAvailabilityReader | T |
| `frontend/lib/features/ai/availability/ai_availability_reader.dart` | 52–71 | HttpPlatformReachabilityPort | T |
| `frontend/lib/features/ai/billing/abo_client.dart` | 1–8 | preamble / imports / shared declarations | T |
| `frontend/lib/features/ai/billing/abo_client.dart` | 9–9 | _contractVersionOverrideKey | T |
| `frontend/lib/features/ai/billing/abo_client.dart` | 10–10 | _billingHostOverrideKey | T |
| `frontend/lib/features/ai/billing/abo_client.dart` | 11–17 | _localBillingHost | T |
| `frontend/lib/features/ai/billing/abo_client.dart` | 339–360 | PaymentClassification | T |
| `frontend/lib/features/ai/billing/abo_client.dart` | 361–385 | ReversalKind | T |
| `frontend/lib/features/ai/billing/abo_client.dart` | 386–409 | PaymentReversal | T |
| `frontend/lib/features/ai/billing/abo_client.dart` | 410–457 | PaymentRecord | T |
| `frontend/lib/features/ai/billing/abo_client.dart` | 458–487 | PaymentsResponse | T |
| `frontend/lib/features/ai/billing/abo_client.dart` | 488–516 | SubscriptionResponse | T |
| `frontend/lib/features/ai/billing/abo_client.dart` | 517–577 | AboApiException | T |
| `frontend/lib/features/ai/billing/abo_client.dart` | 578–827 | AboClient | T |
| `frontend/lib/features/ai/billing/administrator_billing_page.dart` | 1–17 | preamble / imports / shared declarations | T |
| `frontend/lib/features/ai/billing/administrator_billing_page.dart` | 18–20 | _BillingStep | T |
| `frontend/lib/features/ai/billing/administrator_billing_page.dart` | 21–29 | AdministratorBillingPage | T |
| `frontend/lib/features/ai/billing/administrator_billing_page.dart` | 30–173 | _AdministratorBillingPageState | T |
| `frontend/lib/features/ai/billing/commercial_notices.dart` | 1–5 | preamble / imports / shared declarations | T |
| `frontend/lib/features/ai/billing/commercial_notices.dart` | 6–17 | CommercialNotices | T |
| `frontend/lib/features/ai/billing/commercial_notices.dart` | 18–87 | _CommercialNoticesState | T |
| `frontend/lib/features/ai/billing/payment_history.dart` | 1–4 | preamble / imports / shared declarations | T |
| `frontend/lib/features/ai/billing/payment_history.dart` | 5–16 | PaymentHistory | T |
| `frontend/lib/features/ai/billing/payment_history.dart` | 17–150 | _PaymentHistoryState | T |
| `frontend/lib/features/ai/billing/subscription_summary.dart` | 1–14 | preamble / imports / shared declarations | T |
| `frontend/lib/features/ai/billing/subscription_summary.dart` | 15–41 | SubscriptionSummaryData | T |
| `frontend/lib/features/ai/billing/subscription_summary.dart` | 42–57 | SubscriptionSummary | T |
| `frontend/lib/features/ai/billing/subscription_summary.dart` | 58–242 | _SubscriptionSummaryState | T |
| `frontend/lib/features/ai/degraded/ai_degraded_mode.dart` | 1–5 | preamble / imports / shared declarations | T |
| `frontend/lib/features/ai/degraded/ai_degraded_mode.dart` | 6–72 | AiDegradedMode | T |
| `frontend/lib/features/ai/degraded/ai_degraded_view.dart` | 1–10 | preamble / imports / shared declarations | T |
| `frontend/lib/features/ai/degraded/ai_degraded_view.dart` | 11–11 | kAiDegradedUnreachableKey | T |
| `frontend/lib/features/ai/degraded/ai_degraded_view.dart` | 12–12 | kAiDegradedQuotaKey | T |
| `frontend/lib/features/ai/degraded/ai_degraded_view.dart` | 13–13 | kAiDegradedAiUnavailableKey | T |
| `frontend/lib/features/ai/degraded/ai_degraded_view.dart` | 14–14 | kAiDegradedAppUpdateKey | T |
| `frontend/lib/features/ai/degraded/ai_degraded_view.dart` | 15–15 | kAiDegradedProviderUnavailableKey | T |
| `frontend/lib/features/ai/degraded/ai_degraded_view.dart` | 16–16 | kAiDegradedRetryKey | T |
| `frontend/lib/features/ai/degraded/ai_degraded_view.dart` | 17–17 | kAiDegradedNonEnrolledKey | T |
| `frontend/lib/features/ai/degraded/ai_degraded_view.dart` | 18–18 | kAiDegradedInstallationSuspendedKey | T |
| `frontend/lib/features/ai/degraded/ai_degraded_view.dart` | 19–19 | kAiDegradedForbiddenCapabilityKey | T |
| `frontend/lib/features/ai/degraded/ai_degraded_view.dart` | 20–20 | kAiDegradedSafetyLimitedKey | T |
| `frontend/lib/features/ai/degraded/ai_degraded_view.dart` | 21–21 | kAiDegradedRenewOrBuyKey | T |
| `frontend/lib/features/ai/degraded/ai_degraded_view.dart` | 22–24 | kAiAffordanceKey | T |
| `frontend/lib/features/ai/degraded/ai_degraded_view.dart` | 25–186 | AiDegradedView | T |
| `frontend/lib/features/ai/host/ai_feature_host_page.dart` | 1–25 | preamble / imports / shared declarations | T |
| `frontend/lib/features/ai/host/ai_feature_host_page.dart` | 26–31 | PlatformNetworkSpy | T |
| `frontend/lib/features/ai/host/ai_feature_host_page.dart` | 32–55 | InMemoryPlatformNetworkSpy | T |
| `frontend/lib/features/ai/host/ai_feature_host_page.dart` | 56–100 | AiFeatureHostDependencies | T |
| `frontend/lib/features/ai/host/ai_feature_host_page.dart` | 101–112 | AiFeatureHostPage | T |
| `frontend/lib/features/ai/host/ai_feature_host_page.dart` | 113–498 | _AiFeatureHostPageState | T |
| `frontend/lib/features/ai/host/ai_feature_host_page.dart` | 499–518 | _AiStatusNotices | T |
| `frontend/lib/features/ai/host/ai_feature_host_page.dart` | 519–559 | _AiStatusNoticeBanner | T |
| `frontend/lib/features/ai/presentation/pages/ai_page.dart` | 1–32 | preamble / imports / shared declarations | T |
| `frontend/lib/features/ai/presentation/pages/ai_page.dart` | 33–277 | LiveVisitSummaryComposition | T |
| `frontend/lib/features/ai/presentation/pages/ai_page.dart` | 278–287 | LiveVisitSummaryHostWidget | T |
| `frontend/lib/features/ai/presentation/pages/ai_page.dart` | 288–355 | _LiveVisitSummaryHostWidgetState | T |
| `frontend/lib/features/ai/presentation/pages/ai_page.dart` | 356–362 | AiPage | T |
| `frontend/lib/features/ai/presentation/pages/ai_page.dart` | 363–619 | _AiPageState | T |
| `frontend/lib/features/ai/presentation/pages/ai_page.dart` | 620–652 | _AiFeatureSection | T |
| `frontend/lib/features/ai/presentation/pages/ai_page.dart` | 653–661 | _LiveVisitSummaryHost | T |
| `frontend/lib/features/ai/presentation/pages/ai_page.dart` | 662–716 | _LiveVisitSummaryHostState | T |
| `frontend/lib/features/ai/surface/first_ai_feature_surface.dart` | 1–16 | preamble / imports / shared declarations | T |
| `frontend/lib/features/ai/surface/first_ai_feature_surface.dart` | 17–17 | kFirstAiCapabilityId | T |
| `frontend/lib/features/ai/surface/first_ai_feature_surface.dart` | 18–18 | kFirstAiCapabilityVersion | T |
| `frontend/lib/features/ai/surface/first_ai_feature_surface.dart` | 19–24 | kFirstAiIntent | T |
| `frontend/lib/features/ai/surface/first_ai_feature_surface.dart` | 25–26 | kFirstAiRequiredContextKeys | T |
| `frontend/lib/features/ai/surface/first_ai_feature_surface.dart` | 27–27 | kAiAcceptKey | T |
| `frontend/lib/features/ai/surface/first_ai_feature_surface.dart` | 28–28 | kAiDiscardKey | T |
| `frontend/lib/features/ai/surface/first_ai_feature_surface.dart` | 29–29 | kAiTerminalProseKey | T |
| `frontend/lib/features/ai/surface/first_ai_feature_surface.dart` | 30–30 | kAiAcknowledgedKey | T |
| `frontend/lib/features/ai/surface/first_ai_feature_surface.dart` | 31–31 | kAiLocalFailureKey | T |
| `frontend/lib/features/ai/surface/first_ai_feature_surface.dart` | 32–32 | kAiIdleKey | T |
| `frontend/lib/features/ai/surface/first_ai_feature_surface.dart` | 33–33 | kAiSurfaceSessionActiveKey | T |
| `frontend/lib/features/ai/surface/first_ai_feature_surface.dart` | 34–40 | kAiSurfaceLoadingKey | T |
| `frontend/lib/features/ai/surface/first_ai_feature_surface.dart` | 41–50 | AiPersistenceProbe | T |
| `frontend/lib/features/ai/surface/first_ai_feature_surface.dart` | 51–59 | AiExportProbe | T |
| `frontend/lib/features/ai/surface/first_ai_feature_surface.dart` | 60–77 | InMemoryAiPersistenceProbe | T |
| `frontend/lib/features/ai/surface/first_ai_feature_surface.dart` | 78–95 | InMemoryAiExportProbe | T |
| `frontend/lib/features/ai/surface/first_ai_feature_surface.dart` | 96–97 | _SurfacePhase | T |
| `frontend/lib/features/ai/surface/first_ai_feature_surface.dart` | 98–140 | FirstAiFeatureSurface | T |
| `frontend/lib/features/ai/surface/first_ai_feature_surface.dart` | 141–415 | _FirstAiFeatureSurfaceState | T |
| `frontend/lib/l10n/app_ar.arb` | 1–139 | preamble / imports / shared declarations | T |
| `frontend/lib/l10n/app_en.arb` | 1–139 | preamble / imports / shared declarations | T |

## Unchanged supporting dependencies

- `ai-platform/src/config-cache` ← `ai-platform/src/coverage-read/index.ts`: unchanged supporting dependency; read only as required by owned invariant
- `ai-platform/src/alert` ← `ai-platform/src/coverage-read/index.ts`: unchanged supporting dependency; read only as required by owned invariant
- `ai-platform/src/identity` ← `ai-platform/src/coverage-read/index.ts`: unchanged supporting dependency; read only as required by owned invariant
- `ai-platform/src/logger.ts` ← `ai-platform/src/coverage-read/index.ts`: unchanged supporting dependency; read only as required by owned invariant
- `ai-platform/src/quota-do` ← `ai-platform/src/coverage-read/index.ts`: unchanged supporting dependency; read only as required by owned invariant
- `ai-platform/src/reference.ts` ← `ai-platform/src/coverage-read/index.ts`: unchanged supporting dependency; read only as required by owned invariant
- `ai-platform/src/trace.ts` ← `ai-platform/src/coverage-read/index.ts`: unchanged supporting dependency; read only as required by owned invariant
- `frontend/lib/features/ai/surface/usage_gauge.dart` ← `frontend/lib/features/ai/host/ai_feature_host_page.dart`: unchanged supporting dependency; read only as required by owned invariant
