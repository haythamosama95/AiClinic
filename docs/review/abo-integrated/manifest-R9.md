# R9 bounded source manifest

Target: `db9244fddfddc1905335fb8c7105328c15a0cc5e`. Deletions use baseline coordinates. Inventory only; no source reviewed by preparation.

| Path | Lines | Symbol / region | Revision |
| --- | --- | --- | --- |
| `.github/scripts/control-residue-guard.sh` | 1–103 | preamble / imports / shared declarations | T |
| `abo/migrations/0001_records.sql` | 1–6 | preamble / imports / shared declarations | T |
| `abo/migrations/0001_records.sql` | 7–26 | offer_version | T |
| `abo/migrations/0001_records.sql` | 27–36 | offer_event | T |
| `abo/migrations/0001_records.sql` | 37–46 | terms_version | T |
| `abo/migrations/0001_records.sql` | 47–62 | billing_contact | T |
| `abo/migrations/0001_records.sql` | 63–64 | billing_contact_org_version | T |
| `abo/migrations/0001_records.sql` | 65–72 | fact_log | T |
| `abo/migrations/0001_records.sql` | 73–77 | fact_export | T |
| `abo/migrations/0001_records.sql` | 78–83 | token_use | T |
| `abo/migrations/0001_records.sql` | 84–85 | token_use_org_id | T |
| `abo/migrations/0001_records.sql` | 86–95 | alert | T |
| `abo/migrations/0001_records.sql` | 96–101 | offer_abort_update | T |
| `abo/migrations/0001_records.sql` | 102–107 | offer_abort_delete | T |
| `abo/migrations/0001_records.sql` | 108–113 | offer_version_abort_update | T |
| `abo/migrations/0001_records.sql` | 114–119 | offer_version_abort_delete | T |
| `abo/migrations/0001_records.sql` | 120–125 | offer_event_abort_update | T |
| `abo/migrations/0001_records.sql` | 126–131 | offer_event_abort_delete | T |
| `abo/migrations/0001_records.sql` | 132–137 | terms_version_abort_update | T |
| `abo/migrations/0001_records.sql` | 138–142 | terms_version_abort_delete | T |
| `abo/migrations/0008_reconciliation.sql` | 1–7 | preamble / imports / shared declarations | T |
| `abo/migrations/0008_reconciliation.sql` | 8–16 | payout_import | T |
| `abo/migrations/0008_reconciliation.sql` | 17–18 | payout_import_period | T |
| `abo/migrations/0008_reconciliation.sql` | 19–30 | payout_line | T |
| `abo/migrations/0008_reconciliation.sql` | 31–32 | payout_line_payment_id | T |
| `abo/migrations/0008_reconciliation.sql` | 33–38 | finding_resolution_abort_update | T |
| `abo/migrations/0008_reconciliation.sql` | 39–44 | finding_resolution_abort_delete | T |
| `abo/migrations/0008_reconciliation.sql` | 45–50 | payout_import_abort_update | T |
| `abo/migrations/0008_reconciliation.sql` | 51–56 | payout_import_abort_delete | T |
| `abo/migrations/0008_reconciliation.sql` | 57–62 | payout_line_abort_update | T |
| `abo/migrations/0008_reconciliation.sql` | 63–67 | payout_line_abort_delete | T |
| `abo/migrations/0009_digest_watch.sql` | 1–5 | preamble / imports / shared declarations | T |
| `abo/migrations/0009_digest_watch.sql` | 6–12 | seen_operator_credential | T |
| `abo/migrations/0009_digest_watch.sql` | 13–21 | channel_version_seen | T |
| `abo/package-lock.json` | 1–4434 | preamble / imports / shared declarations | T |
| `abo/package.json` | 1–27 | preamble / imports / shared declarations | T |
| `abo/scripts/check-import-boundary.mjs` | 1–9 | preamble / imports / shared declarations | T |
| `abo/scripts/check-import-boundary.mjs` | 10–11 | aboRoot | T |
| `abo/scripts/check-import-boundary.mjs` | 12–12 | ADAPTER_SUFFIX | T |
| `abo/scripts/check-import-boundary.mjs` | 13–14 | CLIENT_SUFFIX | T |
| `abo/scripts/check-import-boundary.mjs` | 15–16 | SOURCE_EXTENSIONS | T |
| `abo/scripts/check-import-boundary.mjs` | 17–22 | usage | T |
| `abo/scripts/check-import-boundary.mjs` | 23–46 | walkSourceFiles | T |
| `abo/scripts/check-import-boundary.mjs` | 47–50 | normalizeSpecifier | T |
| `abo/scripts/check-import-boundary.mjs` | 51–63 | specifierCandidates | T |
| `abo/scripts/check-import-boundary.mjs` | 64–82 | classifyImport | T |
| `abo/scripts/check-import-boundary.mjs` | 83–97 | extractImportSpecifiers | T |
| `abo/scripts/check-import-boundary.mjs` | 98–102 | isAdapterFile | T |
| `abo/scripts/check-import-boundary.mjs` | 103–111 | isUnderProviderDir | T |
| `abo/scripts/check-import-boundary.mjs` | 112–122 | resolveScanRoot | T |
| `abo/scripts/check-import-boundary.mjs` | 123–160 | main | T |
| `abo/scripts/rebuild-abo.ts` | 1–12 | preamble / imports / shared declarations | T |
| `abo/scripts/rebuild-abo.ts` | 13–13 | scriptDir | T |
| `abo/scripts/rebuild-abo.ts` | 14–15 | aboRoot | T |
| `abo/scripts/rebuild-abo.ts` | 16–23 | printUsage | T |
| `abo/scripts/rebuild-abo.ts` | 24–54 | parseArgs | T |
| `abo/scripts/rebuild-abo.ts` | 55–80 | main | T |
| `abo/src/alert/index.ts` | 1–2 | preamble / imports / shared declarations | T |
| `abo/src/alert/index.ts` | 3–18 | AlertEnv | T |
| `abo/src/alert/index.ts` | 19–19 | ONE_HOUR_MS | T |
| `abo/src/alert/index.ts` | 20–21 | ONE_DAY_MS | T |
| `abo/src/alert/index.ts` | 22–22 | EXPORT_LAG_ALERT_KEY | T |
| `abo/src/alert/index.ts` | 23–23 | R2_LOCK_ALERT_KEY | T |
| `abo/src/alert/index.ts` | 24–25 | ALERT_CODE | T |
| `abo/src/alert/index.ts` | 26–42 | AlertCode | T |
| `abo/src/alert/index.ts` | 43–52 | AlertRow | T |
| `abo/src/alert/index.ts` | 53–56 | alertEmailText | T |
| `abo/src/alert/index.ts` | 57–77 | nextSendAtForCode | T |
| `abo/src/alert/index.ts` | 78–90 | readAlert | T |
| `abo/src/alert/index.ts` | 91–122 | activateExportLagAlert | T |
| `abo/src/alert/index.ts` | 123–134 | clearAlert | T |
| `abo/src/alert/index.ts` | 135–139 | OldestUnexported | T |
| `abo/src/alert/index.ts` | 140–154 | oldestUnexportedFact | T |
| `abo/src/alert/index.ts` | 155–165 | clearExportLagWhenResolved | T |
| `abo/src/alert/index.ts` | 166–181 | markExportLagIfDue | T |
| `abo/src/alert/index.ts` | 182–199 | markRepeatDueIfNeeded | T |
| `abo/src/alert/index.ts` | 200–233 | raiseAlert | T |
| `abo/src/alert/index.ts` | 234–261 | sendAlertRow | T |
| `abo/src/alert/index.ts` | 262–281 | sendDueAlerts | T |
| `abo/src/alert/lock.ts` | 1–2 | preamble / imports / shared declarations | T |
| `abo/src/alert/lock.ts` | 3–3 | R2_LOCK_ALERT_KEY | T |
| `abo/src/alert/lock.ts` | 4–5 | ALERT_CODE | T |
| `abo/src/alert/lock.ts` | 6–11 | LockRule | T |
| `abo/src/alert/lock.ts` | 12–16 | LockResponse | T |
| `abo/src/alert/lock.ts` | 17–29 | lockIsPresent | T |
| `abo/src/alert/lock.ts` | 30–37 | clearR2LockAlert | T |
| `abo/src/alert/lock.ts` | 38–62 | markR2LockAlertDue | T |
| `abo/src/alert/lock.ts` | 63–84 | checkR2BucketLock | T |
| `abo/src/clock.ts` | 1–2 | preamble / imports / shared declarations | T |
| `abo/src/clock.ts` | 3–7 | ClockEnv | T |
| `abo/src/clock.ts` | 8–32 | harnessClockMs | T |
| `abo/src/clock.ts` | 33–37 | clockNowMs | T |
| `abo/src/clock.ts` | 38–40 | clockNowIso | T |
| `abo/src/digest/run.ts` | 1–4 | preamble / imports / shared declarations | T |
| `abo/src/digest/run.ts` | 5–5 | ONE_DAY_MS | T |
| `abo/src/digest/run.ts` | 6–6 | THIRTY_DAYS_MS | T |
| `abo/src/digest/run.ts` | 7–7 | EXPORT_LAG_ALERT_KEY | T |
| `abo/src/digest/run.ts` | 8–9 | R2_LOCK_ALERT_KEY | T |
| `abo/src/digest/run.ts` | 10–17 | IssuerKeyRow | T |
| `abo/src/digest/run.ts` | 18–24 | ServiceKeyRow | T |
| `abo/src/digest/run.ts` | 25–30 | GrantRow | T |
| `abo/src/digest/run.ts` | 31–38 | FindingRow | T |
| `abo/src/digest/run.ts` | 39–46 | WorkRow | T |
| `abo/src/digest/run.ts` | 47–53 | AlertRow | T |
| `abo/src/digest/run.ts` | 54–58 | JobRunRow | T |
| `abo/src/digest/run.ts` | 59–65 | ChannelVersionRow | T |
| `abo/src/digest/run.ts` | 66–70 | CountRow | T |
| `abo/src/digest/run.ts` | 71–86 | DigestEnv | T |
| `abo/src/digest/run.ts` | 87–94 | keyExpiresWithin30Days | T |
| `abo/src/digest/run.ts` | 95–133 | raiseAl14ForExpiringKeys | T |
| `abo/src/digest/run.ts` | 134–142 | countSince | T |
| `abo/src/digest/run.ts` | 143–156 | oldestUnexportedFactSeq | T |
| `abo/src/digest/run.ts` | 157–175 | readFeedConsumerHealth | T |
| `abo/src/digest/run.ts` | 176–207 | grantEnvelopeDetails | T |
| `abo/src/digest/run.ts` | 208–406 | buildDigestBody | T |
| `abo/src/digest/run.ts` | 407–420 | sendDigestEmail | T |
| `abo/src/digest/run.ts` | 421–426 | runDailyDigest | T |
| `abo/src/housekeeping/run.ts` | 1–2 | preamble / imports / shared declarations | T |
| `abo/src/housekeeping/run.ts` | 3–3 | ONE_DAY_MS | T |
| `abo/src/housekeeping/run.ts` | 4–4 | RETENTION_DAYS_MS | T |
| `abo/src/housekeeping/run.ts` | 5–6 | HMAC_INVALID_RETENTION_DAYS | T |
| `abo/src/housekeeping/run.ts` | 7–11 | HousekeepingEnv | T |
| `abo/src/housekeeping/run.ts` | 12–43 | runHousekeeping | T |
| `abo/src/ops/index.ts` | 1631–1645 | handleGetFindings | T |
| `abo/src/ops/index.ts` | 1688–1697 | handleGetPayoutImports | T |
| `abo/src/ops/index.ts` | 1705–1712 | periodFromSettledAt | T |
| `abo/src/ops/index.ts` | 1713–1838 | handlePostPayoutImport | T |
| `abo/src/ops/index.ts` | 1839–1928 | handlePostResolveFinding | T |
| `abo/src/rebuild.ts` | 1–21 | preamble / imports / shared declarations | T |
| `abo/src/rebuild.ts` | 22–29 | LedgerLine | T |
| `abo/src/rebuild.ts` | 30–41 | CheckoutRow | T |
| `abo/src/rebuild.ts` | 42–47 | AboGrantKey | T |
| `abo/src/rebuild.ts` | 48–58 | GrantCheckoutRow | T |
| `abo/src/rebuild.ts` | 59–65 | GrantPaymentRow | T |
| `abo/src/rebuild.ts` | 66–79 | RebuildEnv | T |
| `abo/src/rebuild.ts` | 80–83 | RebuildOptions | T |
| `abo/src/rebuild.ts` | 84–90 | newId | T |
| `abo/src/rebuild.ts` | 91–107 | factCreatedAt | T |
| `abo/src/rebuild.ts` | 108–120 | ledgerInsertStatement | T |
| `abo/src/rebuild.ts` | 121–141 | listLedgerLines | T |
| `abo/src/rebuild.ts` | 142–166 | replayLedger | T |
| `abo/src/rebuild.ts` | 167–176 | checkoutStatusFromEventKind | T |
| `abo/src/rebuild.ts` | 177–230 | recomputeCheckoutStatus | T |
| `abo/src/rebuild.ts` | 231–244 | loadCheckout | T |
| `abo/src/rebuild.ts` | 245–256 | paymentExists | T |
| `abo/src/rebuild.ts` | 257–269 | base64UrlDecode | T |
| `abo/src/rebuild.ts` | 270–277 | envelopeB64 | T |
| `abo/src/rebuild.ts` | 278–297 | parseAboGrantKey | T |
| `abo/src/rebuild.ts` | 298–315 | importEd25519PrivateKey | T |
| `abo/src/rebuild.ts` | 316–327 | loadGrantPayment | T |
| `abo/src/rebuild.ts` | 328–340 | loadGrantCheckout | T |
| `abo/src/rebuild.ts` | 341–352 | paymentFactSha256 | T |
| `abo/src/rebuild.ts` | 353–364 | grantOutcomeExists | T |
| `abo/src/rebuild.ts` | 365–396 | buildEnvelopeWithoutApprovals | T |
| `abo/src/rebuild.ts` | 397–439 | buildGrantEnvelope | T |
| `abo/src/rebuild.ts` | 440–489 | preapplyPlatformGrant | T |
| `abo/src/rebuild.ts` | 490–498 | preapplyPlatformGrants | T |
| `abo/src/rebuild.ts` | 499–513 | awaitPlatformGrantInList | T |
| `abo/src/rebuild.ts` | 514–522 | awaitGapGrantsInList | T |
| `abo/src/rebuild.ts` | 523–551 | maybeRecordSucceededPayment | T |
| `abo/src/rebuild.ts` | 552–562 | paidGrantIdsFromPayments | T |
| `abo/src/rebuild.ts` | 563–566 | isRecord | T |
| `abo/src/rebuild.ts` | 567–579 | parsePlatformGrants | T |
| `abo/src/rebuild.ts` | 580–615 | ensurePaymobIntentions | T |
| `abo/src/rebuild.ts` | 616–703 | inquireGapPayments | T |
| `abo/src/rebuild.ts` | 704–723 | rebuildAbo | T |
| `abo/src/reconciliation/run.ts` | 1–16 | preamble / imports / shared declarations | T |
| `abo/src/reconciliation/run.ts` | 17–17 | FIFTEEN_MINUTES_MS | T |
| `abo/src/reconciliation/run.ts` | 18–18 | ONE_DAY_MS | T |
| `abo/src/reconciliation/run.ts` | 19–20 | SEVEN_DAYS_MS | T |
| `abo/src/reconciliation/run.ts` | 21–36 | ReconciliationEnv | T |
| `abo/src/reconciliation/run.ts` | 37–38 | PlatformGrant | T |
| `abo/src/reconciliation/run.ts` | 39–45 | newId | T |
| `abo/src/reconciliation/run.ts` | 46–58 | findingExists | T |
| `abo/src/reconciliation/run.ts` | 59–86 | insertFinding | T |
| `abo/src/reconciliation/run.ts` | 87–99 | parsePlatformGrants | T |
| `abo/src/reconciliation/run.ts` | 100–112 | paidGrantIdsFromPayments | T |
| `abo/src/reconciliation/run.ts` | 113–125 | complimentaryActionGrantIds | T |
| `abo/src/reconciliation/run.ts` | 126–172 | checkPaymentWithoutGrant | T |
| `abo/src/reconciliation/run.ts` | 173–190 | checkGrantWithoutPayment | T |
| `abo/src/reconciliation/run.ts` | 191–210 | checkGrantWithoutOperatorAction | T |
| `abo/src/reconciliation/run.ts` | 211–270 | checkTransferWithoutAuthorisation | T |
| `abo/src/reconciliation/run.ts` | 271–296 | checkReversalNotApplied | T |
| `abo/src/reconciliation/run.ts` | 297–328 | checkPayoutUnmatched | T |
| `abo/src/reconciliation/run.ts` | 329–335 | periodEndMs | T |
| `abo/src/reconciliation/run.ts` | 336–399 | checkPaymentNotInPayout | T |
| `abo/src/reconciliation/run.ts` | 400–430 | checkUnrecordedReversal | T |
| `abo/src/reconciliation/run.ts` | 431–491 | checkCallbackWithoutConfirmation | T |
| `abo/src/reconciliation/run.ts` | 492–534 | clinicsWithRecentCoverageEvents | T |
| `abo/src/reconciliation/run.ts` | 535–546 | canonicalEqual | T |
| `abo/src/reconciliation/run.ts` | 547–564 | receiptObject | T |
| `abo/src/reconciliation/run.ts` | 565–600 | checkFeedDivergence | T |
| `abo/src/reconciliation/run.ts` | 601–649 | checkReceiptMismatch | T |
| `abo/src/reconciliation/run.ts` | 650–662 | runReconciliation | T |
| `abo/src/records/append.ts` | 1–3 | preamble / imports / shared declarations | T |
| `abo/src/records/append.ts` | 4–7 | AppendEnv | T |
| `abo/src/records/append.ts` | 8–11 | FactLogEnv | T |
| `abo/src/records/append.ts` | 12–13 | textDecoder | T |
| `abo/src/records/append.ts` | 14–28 | insertFactLog | T |
| `abo/src/records/append.ts` | 29–34 | OfferRow | T |
| `abo/src/records/append.ts` | 35–44 | FixtureTermsVersion | T |
| `abo/src/records/append.ts` | 45–63 | FixtureOfferVersion | T |
| `abo/src/records/append.ts` | 64–72 | FixtureOfferEvent | T |
| `abo/src/records/append.ts` | 73–79 | OffersFixture | T |
| `abo/src/records/append.ts` | 80–83 | HarnessAppendEnv | T |
| `abo/src/records/append.ts` | 84–88 | dynamicImport | T |
| `abo/src/records/append.ts` | 89–93 | resolveHarnessEnv | T |
| `abo/src/records/append.ts` | 94–111 | appendOfferRow | T |
| `abo/src/records/append.ts` | 112–122 | appendOffer | T |
| `abo/src/records/append.ts` | 123–160 | appendTermsVersion | T |
| `abo/src/records/append.ts` | 161–221 | appendOfferVersion | T |
| `abo/src/records/append.ts` | 222–259 | appendOfferEvent | T |
| `abo/src/records/append.ts` | 260–280 | loadOffersFixture | T |
| `abo/src/records/export.ts` | 1–3 | preamble / imports / shared declarations | T |
| `abo/src/records/export.ts` | 4–8 | ExportEnv | T |
| `abo/src/records/export.ts` | 9–16 | PendingFact | T |
| `abo/src/records/export.ts` | 17–29 | listPendingFacts | T |
| `abo/src/records/export.ts` | 30–42 | ledgerLinePayload | T |
| `abo/src/records/export.ts` | 43–60 | exportFacts | T |
| `abo/src/watch/hourly.ts` | 1–5 | preamble / imports / shared declarations | T |
| `abo/src/watch/hourly.ts` | 6–7 | FIVE_MINUTES_MS | T |
| `abo/src/watch/hourly.ts` | 8–15 | IssuerKeyRow | T |
| `abo/src/watch/hourly.ts` | 16–21 | OperatorCredentialRow | T |
| `abo/src/watch/hourly.ts` | 22–38 | WatchEnv | T |
| `abo/src/watch/hourly.ts` | 39–64 | rememberOperatorCredential | T |
| `abo/src/watch/hourly.ts` | 65–92 | raiseAl15IfFeedStale | T |
| `abo/src/watch/hourly.ts` | 93–124 | raiseAl22ForIssuerPinMismatch | T |
| `abo/src/watch/hourly.ts` | 125–175 | raiseAl22ForUnannouncedCredentials | T |
| `abo/src/watch/hourly.ts` | 176–182 | runHourlyWatch | T |
| `abo/src/work/runner.ts` | 61–67 | newId | T |
| `abo/src/work/runner.ts` | 68–75 | backoffMs | T |
| `abo/src/work/runner.ts` | 971–984 | raiseStaleConfirmAlerts | T |
| `abo/src/worker.ts` | 1–44 | preamble / imports / shared declarations | T |
| `abo/src/worker.ts` | 45–130 | Env | T |
| `abo/src/worker.ts` | 133–146 | stampScheduledJobRun | T |
| `abo/src/worker.ts` | 147–154 | pingHeartbeat | T |
| `abo/src/worker.ts` | 159–167 | signingKeyGateMissing | T |
| `abo/src/worker.ts` | 168–178 | maybeRefreshSigningKeyCheck | T |
| `abo/src/worker.ts` | 360–446 | scheduled | T |
| `abo/tsconfig.json` | 1–16 | preamble / imports / shared declarations | T |
| `abo/wrangler.toml` | 1–130 | preamble / imports / shared declarations | T |
| `ai-platform/migrations/20260803120000_token_contract.sql` | 1–1 | preamble / imports / shared declarations | T |
| `ai-platform/migrations/20260803120000_token_contract.sql` | 2–10 | token_contract | T |
| `ai-platform/migrations/20261006130000_ceiling_policy.sql` | 1–25 | preamble / imports / shared declarations | T |
| `ai-platform/migrations/20261006170000_drop_invoicing.sql` | 1–2 | preamble / imports / shared declarations | T |
| `ai-platform/migrations/20261006170100_drop_plan_entitlement.sql` | 1–5 | preamble / imports / shared declarations | T |
| `ai-platform/package-lock.json` | 1–3785 | preamble / imports / shared declarations | T |
| `ai-platform/package.json` | 1–30 | preamble / imports / shared declarations | T |
| `ai-platform/src/alert/email.ts` | 1–7 | preamble / imports / shared declarations | T |
| `ai-platform/src/alert/email.ts` | 8–13 | SendEmailEnv | T |
| `ai-platform/src/alert/email.ts` | 14–19 | sendPlatformEmail | T |
| `ai-platform/src/alert/index.ts` | 1–4 | preamble / imports / shared declarations | T |
| `ai-platform/src/alert/index.ts` | 5–10 | AlertEnv | T |
| `ai-platform/src/alert/index.ts` | 11–15 | CoverageAlertEnv | T |
| `ai-platform/src/alert/index.ts` | 16–17 | ONE_HOUR_MS | T |
| `ai-platform/src/alert/index.ts` | 18–18 | FIVE_MINUTE_CRON | T |
| `ai-platform/src/alert/index.ts` | 19–19 | ONE_DAY_MS | T |
| `ai-platform/src/alert/index.ts` | 20–21 | AL20_ALERT_KEY | T |
| `ai-platform/src/alert/index.ts` | 22–23 | Al13Kind | T |
| `ai-platform/src/alert/index.ts` | 24–31 | Al13Body | T |
| `ai-platform/src/alert/index.ts` | 32–35 | al13AlertKey | T |
| `ai-platform/src/alert/index.ts` | 36–39 | al13EmailText | T |
| `ai-platform/src/alert/index.ts` | 40–41 | Al13IssuerKeyKind | T |
| `ai-platform/src/alert/index.ts` | 42–47 | Al13IssuerKeyBody | T |
| `ai-platform/src/alert/index.ts` | 48–51 | al13IssuerKeyAlertKey | T |
| `ai-platform/src/alert/index.ts` | 52–55 | al13IssuerKeyEmailText | T |
| `ai-platform/src/alert/index.ts` | 56–75 | parseAl13IssuerKeyAlertKey | T |
| `ai-platform/src/alert/index.ts` | 76–85 | issuerKeyHpMethod | T |
| `ai-platform/src/alert/index.ts` | 86–101 | readIssuerKeyForAlert | T |
| `ai-platform/src/alert/index.ts` | 102–156 | rebuildAl13IssuerKeyOperation | T |
| `ai-platform/src/alert/index.ts` | 157–170 | readPlatformAlertSendState | T |
| `ai-platform/src/alert/index.ts` | 171–190 | sendAl13IssuerKeyBody | T |
| `ai-platform/src/alert/index.ts` | 191–192 | Al13ServiceKeyKind | T |
| `ai-platform/src/alert/index.ts` | 193–198 | Al13ServiceKeyBody | T |
| `ai-platform/src/alert/index.ts` | 199–202 | al13ServiceKeyAlertKey | T |
| `ai-platform/src/alert/index.ts` | 203–206 | al13ServiceKeyEmailText | T |
| `ai-platform/src/alert/index.ts` | 207–226 | parseAl13ServiceKeyAlertKey | T |
| `ai-platform/src/alert/index.ts` | 227–230 | serviceKeyHpMethod | T |
| `ai-platform/src/alert/index.ts` | 231–246 | readServiceKeyForAlert | T |
| `ai-platform/src/alert/index.ts` | 247–301 | rebuildAl13ServiceKeyOperation | T |
| `ai-platform/src/alert/index.ts` | 302–321 | sendAl13ServiceKeyBody | T |
| `ai-platform/src/alert/index.ts` | 322–348 | raiseAl13ServiceKey | T |
| `ai-platform/src/alert/index.ts` | 349–375 | raiseAl13IssuerKey | T |
| `ai-platform/src/alert/index.ts` | 376–379 | Al20Body | T |
| `ai-platform/src/alert/index.ts` | 380–383 | al20EmailText | T |
| `ai-platform/src/alert/index.ts` | 384–397 | markAl20AlertSent | T |
| `ai-platform/src/alert/index.ts` | 398–415 | sendAl20Body | T |
| `ai-platform/src/alert/index.ts` | 416–421 | raiseAl20 | T |
| `ai-platform/src/alert/index.ts` | 422–438 | countEpochOneBindingsLast24Hours | T |
| `ai-platform/src/alert/index.ts` | 439–471 | retryDueAl20Alerts | T |
| `ai-platform/src/alert/index.ts` | 472–504 | upsertPlatformAlert | T |
| `ai-platform/src/alert/index.ts` | 505–513 | markAlertSent | T |
| `ai-platform/src/alert/index.ts` | 514–526 | markAlertUnsent | T |
| `ai-platform/src/alert/index.ts` | 527–561 | raiseAl13 | T |
| `ai-platform/src/alert/index.ts` | 562–576 | raiseAl13Bootstrap | T |
| `ai-platform/src/alert/index.ts` | 577–585 | insertDoRebuildMismatchAlert | T |
| `ai-platform/src/alert/index.ts` | 586–605 | parseAl13AlertKey | T |
| `ai-platform/src/alert/index.ts` | 606–618 | readOperatorCredentialForAlert | T |
| `ai-platform/src/alert/index.ts` | 619–680 | rebuildAl13Operation | T |
| `ai-platform/src/alert/index.ts` | 681–704 | sendScheduledJobFailedBody | T |
| `ai-platform/src/alert/index.ts` | 705–724 | sendAl13Body | T |
| `ai-platform/src/alert/index.ts` | 725–818 | retryUnsentPlatformAlerts | T |
| `ai-platform/src/alert/index.ts` | 819–825 | pingPlatformHeartbeat | T |
| `ai-platform/src/alert/index.ts` | 826–834 | insertScheduledJobFailedAlert | T |
| `ai-platform/src/alert/index.ts` | 835–850 | logScheduledJobFailure | T |
| `ai-platform/src/alert/index.ts` | 851–863 | runFiveMinuteJob | T |
| `ai-platform/src/alert/index.ts` | 864–883 | sendAl11GrantBody | T |
| `ai-platform/src/alert/index.ts` | 884–908 | sendAl17Body | T |
| `ai-platform/src/alert/index.ts` | 909–922 | raiseAl11GrantFromOutbox | T |
| `ai-platform/src/alert/index.ts` | 923–938 | raiseAl11Transfer | T |
| `ai-platform/src/alert/index.ts` | 939–954 | raiseAl18HeldBinding | T |
| `ai-platform/src/alert/index.ts` | 955–991 | sendDailyAl18ForHeldBindings | T |
| `ai-platform/src/alert/index.ts` | 992–1012 | sendCoverageAlertBody | T |
| `ai-platform/src/alert/index.ts` | 1013–1026 | raiseAl12GrantFromOutbox | T |
| `ai-platform/src/alert/index.ts` | 1027–1040 | raiseAl19FromOutbox | T |
| `ai-platform/src/alert/index.ts` | 1041–1057 | raiseAl17FromOutbox | T |
| `ai-platform/src/alert/index.ts` | 1058–1073 | countPaidGrantsForOrgLast24Hours | T |
| `ai-platform/src/alert/index.ts` | 1074–1088 | countGlobalPaidGrantsLastHour | T |
| `ai-platform/src/alert/index.ts` | 1089–1106 | al17ConditionStillHolds | T |
| `ai-platform/src/alert/index.ts` | 1107–1144 | retryDueAl17Alerts | T |
| `ai-platform/src/alert/index.ts` | 1145–1152 | runFiveMinuteCron | T |
| `ai-platform/src/dashboards/index.ts` | 1–5 | preamble / imports / shared declarations | T |
| `ai-platform/src/dashboards/index.ts` | 6–7 | AvgAttemptLatencyByProvider | T |
| `ai-platform/src/dashboards/index.ts` | 8–8 | TtftByProvider | T |
| `ai-platform/src/dashboards/index.ts` | 9–9 | RateByDimension | T |
| `ai-platform/src/dashboards/index.ts` | 10–20 | CostByCapabilityInstallation | T |
| `ai-platform/src/dashboards/index.ts` | 21–40 | dashboardAvgAttemptLatencyByProvider | T |
| `ai-platform/src/dashboards/index.ts` | 41–42 | dashboardTtftByProvider | T |
| `ai-platform/src/dashboards/index.ts` | 43–70 | dashboardValidationFailureByPromptVersion | T |
| `ai-platform/src/dashboards/index.ts` | 71–106 | dashboardRepairRateByCapability | T |
| `ai-platform/src/dashboards/index.ts` | 107–131 | dashboardFallbackRateByProvider | T |
| `ai-platform/src/dashboards/index.ts` | 132–156 | dashboardCostPerCapabilityPerInstallation | T |
| `ai-platform/src/dashboards/index.ts` | 157–174 | CLINIC_DENIAL_COUNTER_CODES | T |
| `ai-platform/src/dashboards/index.ts` | 175–209 | dashboardQuotaRejectionRate | T |
| `ai-platform/src/dashboards/index.ts` | 210–245 | runAllDashboardQueries | T |
| `ai-platform/src/journal/index.ts` | 1–22 | preamble / imports / shared declarations | T |
| `ai-platform/src/journal/index.ts` | 23–34 | TransitionState | T |
| `ai-platform/src/journal/index.ts` | 35–50 | RequestRowInput | T |
| `ai-platform/src/journal/index.ts` | 51–64 | AttemptInput | T |
| `ai-platform/src/journal/index.ts` | 65–78 | PostResponseInput | T |
| `ai-platform/src/journal/index.ts` | 79–85 | Envelope | T |
| `ai-platform/src/journal/index.ts` | 86–94 | GetRequestResult | T |
| `ai-platform/src/journal/index.ts` | 95–103 | CreateRequestRowResult | T |
| `ai-platform/src/journal/index.ts` | 104–109 | WritePostResponseBindings | T |
| `ai-platform/src/journal/index.ts` | 110–114 | GetRequestBindings | T |
| `ai-platform/src/journal/index.ts` | 115–118 | GetRequestOptions | T |
| `ai-platform/src/journal/index.ts` | 119–125 | TERMINAL_TRANSITION_STATES | T |
| `ai-platform/src/journal/index.ts` | 126–139 | KNOWN_TRANSITION_STATES | T |
| `ai-platform/src/journal/index.ts` | 140–142 | TERMINAL_IMMUTABLE_WHERE | T |
| `ai-platform/src/journal/index.ts` | 143–149 | JOURNAL_TERMINAL_IMMUTABLE_STATES | T |
| `ai-platform/src/journal/index.ts` | 150–153 | isJournalTerminalState | T |
| `ai-platform/src/journal/index.ts` | 154–167 | isJournalTransitionAllowed | T |
| `ai-platform/src/journal/index.ts` | 168–173 | canReachAwaitingContext | T |
| `ai-platform/src/journal/index.ts` | 174–182 | assertAwaitingContextReachable | T |
| `ai-platform/src/journal/index.ts` | 183–186 | envelopeKey | T |
| `ai-platform/src/journal/index.ts` | 187–196 | buildEnvelope | T |
| `ai-platform/src/journal/index.ts` | 197–200 | isTransitionState | T |
| `ai-platform/src/journal/index.ts` | 201–295 | createRequestRow | T |
| `ai-platform/src/journal/index.ts` | 296–311 | persistRoutingDecision | T |
| `ai-platform/src/journal/index.ts` | 312–348 | journalTransition | T |
| `ai-platform/src/journal/index.ts` | 349–383 | recordTerminalState | T |
| `ai-platform/src/journal/index.ts` | 384–443 | persistPostResponseDetail | T |
| `ai-platform/src/journal/index.ts` | 444–460 | writePostResponseDetail | T |
| `ai-platform/src/journal/index.ts` | 461–468 | AiRequestLookupRow | T |
| `ai-platform/src/journal/index.ts` | 469–542 | getRequest | T |
| `ai-platform/src/journal/index.ts` | 543–550 | AuthenticateGetRequestResult | T |
| `ai-platform/src/journal/index.ts` | 551–556 | AuthenticateGetRequestEnv | T |
| `ai-platform/src/journal/index.ts` | 557–598 | authenticateGetRequest | T |
| `ai-platform/src/journal/index.ts` | 599–608 | getRequestAuthErrorBody | T |
| `ai-platform/src/journal/index.ts` | 609–615 | ConversationLegRow | T |
| `ai-platform/src/journal/index.ts` | 616–632 | listConversationLegs | T |
| `ai-platform/src/quota-do/coverage.ts` | 14–19 | SqlStorage | T |
| `ai-platform/src/quota-do/coverage.ts` | 20–27 | sqlExec | T |
| `ai-platform/src/quota-do/coverage.ts` | 28–38 | sqlSelect | T |
| `ai-platform/src/quota-do/coverage.ts` | 39–42 | sqlString | T |
| `ai-platform/src/quota-do/coverage.ts` | 43–60 | HotRow | T |
| `ai-platform/src/quota-do/coverage.ts` | 181–205 | loadPlatformSigningKey | T |
| `ai-platform/src/quota-do/coverage.ts` | 206–222 | ensureHotRow | T |
| `ai-platform/src/quota-do/coverage.ts` | 693–703 | insertOutbox | T |
| `ai-platform/src/quota-do/coverage.ts` | 946–1004 | updateHot | T |
| `ai-platform/src/quota-do/coverage.ts` | 1023–1042 | scheduleOutboxAlarmIfPending | T |
| `ai-platform/src/quota-do/coverage.ts` | 2664–2827 | shipCoverageOutboxInLock | T |
| `ai-platform/src/quota-do/coverage.ts` | 2828–2850 | shipCoverageOutboxAlarm | T |
| `ai-platform/src/quota-do/coverage.ts` | 3307–3314 | snapshotTermPlanSnapshot | T |
| `ai-platform/src/quota-do/coverage.ts` | 3315–3325 | snapshotTermUsedFinal | T |
| `ai-platform/src/quota-do/coverage.ts` | 3326–3357 | hotActiveUsageFromSnapshot | T |
| `ai-platform/src/quota-do/coverage.ts` | 3358–3420 | insertOrUpdateTermFromSnapshotEntry | T |
| `ai-platform/src/quota-do/coverage.ts` | 3421–3453 | syncDoTermsAndHotFromCoverageSnapshot | T |
| `ai-platform/src/quota-do/coverage.ts` | 3454–3505 | hydrateDoFromCoverageSnapshot | T |
| `ai-platform/src/quota-do/coverage.ts` | 3528–3560 | snapshotUsedByTermId | T |
| `ai-platform/src/quota-do/coverage.ts` | 3561–3613 | reapplyUsageEventsAfterSnapshot | T |
| `ai-platform/src/quota-do/coverage.ts` | 3614–3625 | GrantLedgerRebuildRow | T |
| `ai-platform/src/quota-do/coverage.ts` | 3626–3642 | loadGrantLedgerR2Line | T |
| `ai-platform/src/quota-do/coverage.ts` | 3643–3675 | insertDoGrantRowFromLedger | T |
| `ai-platform/src/quota-do/coverage.ts` | 3676–3698 | restoreDoGrantRowsFromLedger | T |
| `ai-platform/src/quota-do/coverage.ts` | 3699–3718 | snapshotTermsIncludeGrant | T |
| `ai-platform/src/quota-do/coverage.ts` | 3746–3767 | applyGrantLedgerRowToDo | T |
| `ai-platform/src/quota-do/coverage.ts` | 3809–3817 | REBUILD_COVERAGE_EVENT_KINDS | T |
| `ai-platform/src/quota-do/coverage.ts` | 3818–3829 | RebuildClinicDoRequest | T |
| `ai-platform/src/quota-do/coverage.ts` | 3830–3835 | RebuildClinicDoResponse | T |
| `ai-platform/src/quota-do/coverage.ts` | 3836–3839 | RunRebuildClinicDoResult | T |
| `ai-platform/src/quota-do/coverage.ts` | 3840–3989 | rebuildClinicDoRPC | T |
| `ai-platform/src/quota-do/coverage.ts` | 3990–4053 | coverageMirrorMatchesSnapshot | T |
| `ai-platform/src/quota-do/coverage.ts` | 4054–4087 | normalizeCoverageSnapshotForMirrorCompare | T |
| `ai-platform/src/quota-do/coverage.ts` | 4088–4147 | runRebuildClinicDo | T |
| `ai-platform/src/quota-do/coverage.ts` | 4148–4210 | runRebuildGrantLedger | T |
| `ai-platform/src/quota-do/coverage.ts` | 4211–4221 | RefreshCoverageSnapshotRequest | T |
| `ai-platform/src/quota-do/coverage.ts` | 4222–4228 | RefreshCoverageSnapshotResponse | T |
| `ai-platform/src/quota-do/coverage.ts` | 4229–4270 | refreshCoverageSnapshotRPC | T |
| `ai-platform/src/quota-do/coverage.ts` | 4271–4315 | runRefreshCoverageSnapshot | T |
| `ai-platform/src/quota-do/index.ts` | 1980–2042 | ensureCoverageDoTables | T |
| `ai-platform/src/retention/index.ts` | 1–10 | preamble / imports / shared declarations | T |
| `ai-platform/src/retention/index.ts` | 11–12 | DIAGNOSTIC_BASELINE_DAYS | T |
| `ai-platform/src/retention/index.ts` | 13–13 | DIAGNOSTIC_HORIZON_MIN_DAYS | T |
| `ai-platform/src/retention/index.ts` | 14–14 | DIAGNOSTIC_HORIZON_MAX_DAYS | T |
| `ai-platform/src/retention/index.ts` | 15–15 | JOURNAL_HORIZON_DAYS | T |
| `ai-platform/src/retention/index.ts` | 16–17 | LEDGER_HORIZON_DAYS | T |
| `ai-platform/src/retention/index.ts` | 18–19 | COUNTER_HORIZON_DAYS | T |
| `ai-platform/src/retention/index.ts` | 20–21 | MS_PER_DAY | T |
| `ai-platform/src/retention/index.ts` | 22–27 | RetentionClassResolver | T |
| `ai-platform/src/retention/index.ts` | 28–31 | defaultRetentionClassResolver | T |
| `ai-platform/src/retention/index.ts` | 32–35 | PUBLISHED_MANIFEST_JSON | T |
| `ai-platform/src/retention/index.ts` | 36–43 | envelopeObjectKey | T |
| `ai-platform/src/retention/index.ts` | 44–61 | minPublishedDiagnosticHorizonDays | T |
| `ai-platform/src/retention/index.ts` | 62–73 | createManifestRetentionClassResolver | T |
| `ai-platform/src/retention/index.ts` | 74–81 | parseDiagnosticHorizonDays | T |
| `ai-platform/src/retention/index.ts` | 82–85 | diagnosticHorizonMs | T |
| `ai-platform/src/retention/index.ts` | 86–95 | isWithinDiagnosticRetention | T |
| `ai-platform/src/retention/index.ts` | 96–103 | RetentionBindings | T |
| `ai-platform/src/retention/index.ts` | 104–112 | RequestRetentionRow | T |
| `ai-platform/src/retention/index.ts` | 113–116 | referenceTimestamp | T |
| `ai-platform/src/retention/index.ts` | 117–132 | writePurgeAudit | T |
| `ai-platform/src/retention/index.ts` | 133–286 | runRetentionPurge | T |
| `ai-platform/src/retention/index.ts` | 287–382 | purgeByInstallationId | T |
| `ai-platform/src/rollup/index.ts` | 1–3 | preamble / imports / shared declarations | T |
| `ai-platform/src/rollup/index.ts` | 4–9 | ReconciliationReport | T |
| `ai-platform/src/rollup/index.ts` | 10–17 | RollupBindings | T |
| `ai-platform/src/rollup/index.ts` | 18–26 | UsageAggregate | T |
| `ai-platform/src/rollup/index.ts` | 27–32 | TerminalRequestRow | T |
| `ai-platform/src/rollup/index.ts` | 33–38 | defaultReconciliationWindow | T |
| `ai-platform/src/rollup/index.ts` | 39–48 | dimensionsKey | T |
| `ai-platform/src/rollup/index.ts` | 49–91 | aggregateUsageEvents | T |
| `ai-platform/src/rollup/index.ts` | 92–142 | runRollup | T |
| `ai-platform/src/rollup/index.ts` | 143–197 | runReconciliation | T |
| `ai-platform/src/rollup/index.ts` | 198–210 | logReconciliationReport | T |
| `ai-platform/src/rollup/index.ts` | 211–218 | runRollupAndReconciliation | T |
| `ai-platform/src/vendor/entrypoint.ts` | 1648–1675 | loadPlatformSigningKey | T |
| `ai-platform/src/vendor/entrypoint.ts` | 4962–4995 | rebuildClinicDo | T |
| `ai-platform/src/vendor/entrypoint.ts` | 4996–5004 | rebuildGrantLedger | T |
| `ai-platform/src/vendor/entrypoint.ts` | 5005–5039 | refreshCoverageSnapshot | T |
| `ai-platform/src/worker.ts` | 2515–2603 | scheduled | T |
| `ai-platform/wrangler.toml` | 1–174 | preamble / imports / shared declarations | T |
| `backend/supabase/config.toml` | 1–409 | preamble / imports / shared declarations | T |
| `packages/vendor-contracts/package-lock.json` | 1–4415 | preamble / imports / shared declarations | T |
| `packages/vendor-contracts/package.json` | 1–19 | preamble / imports / shared declarations | T |
| `packages/vendor-contracts/tsconfig.json` | 1–16 | preamble / imports / shared declarations | T |
| `packages/vendor-contracts/wrangler.toml` | 1–2 | preamble / imports / shared declarations | T |

## Unchanged supporting dependencies

- `ai-platform/src/retention` ← `ai-platform/src/dashboards/index.ts`: unchanged supporting dependency; read only as required by owned invariant
- `ai-platform/src/alert` ← `ai-platform/src/journal/index.ts`: unchanged supporting dependency; read only as required by owned invariant
- `ai-platform/src/logger.ts` ← `ai-platform/src/journal/index.ts`: unchanged supporting dependency; read only as required by owned invariant
- `ai-platform/src/identity` ← `ai-platform/src/journal/index.ts`: unchanged supporting dependency; read only as required by owned invariant
- `ai-platform/src/manifest` ← `ai-platform/src/journal/index.ts`: unchanged supporting dependency; read only as required by owned invariant
- `ai-platform/src/reference.ts` ← `ai-platform/src/journal/index.ts`: unchanged supporting dependency; read only as required by owned invariant
- `ai-platform/src/trace.ts` ← `ai-platform/src/journal/index.ts`: unchanged supporting dependency; read only as required by owned invariant
- `ai-platform/src/config-cache` ← `ai-platform/src/journal/index.ts`: unchanged supporting dependency; read only as required by owned invariant
- `ai-platform/src/contracts/canonical.ts` ← `ai-platform/src/journal/index.ts`: unchanged supporting dependency; read only as required by owned invariant
- `ai-platform/src/router` ← `ai-platform/src/journal/index.ts`: unchanged supporting dependency; read only as required by owned invariant
- `ai-platform/src/manifest` ← `ai-platform/src/retention/index.ts`: unchanged supporting dependency; read only as required by owned invariant
- `ai-platform/src/journal` ← `ai-platform/src/retention/index.ts`: unchanged supporting dependency; read only as required by owned invariant
- `ai-platform/src/logger.ts` ← `ai-platform/src/retention/index.ts`: unchanged supporting dependency; read only as required by owned invariant
- `ai-platform/manifests/published/clinic.visit_summary@1.0.0.json` ← `ai-platform/src/retention/index.ts`: unchanged supporting dependency; read only as required by owned invariant
- `ai-platform/src/logger.ts` ← `ai-platform/src/rollup/index.ts`: unchanged supporting dependency; read only as required by owned invariant
