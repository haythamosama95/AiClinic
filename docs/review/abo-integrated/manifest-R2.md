# R2 bounded source manifest

Target: `db9244fddfddc1905335fb8c7105328c15a0cc5e`. Deletions use baseline coordinates. Inventory only; no source reviewed by preparation.

| Path | Lines | Symbol / region | Revision |
| --- | --- | --- | --- |
| `abo/src/clinic-api/version.ts` | 1–6 | preamble / imports / shared declarations | T |
| `abo/src/clinic-api/version.ts` | 7–8 | ContractChannel | T |
| `abo/src/clinic-api/version.ts` | 9–12 | VersionEnv | T |
| `abo/src/clinic-api/version.ts` | 13–26 | parseContractVersionHeader | T |
| `abo/src/clinic-api/version.ts` | 27–30 | currentChannelVersion | T |
| `abo/src/clinic-api/version.ts` | 31–36 | VersionGateSuccess | T |
| `abo/src/clinic-api/version.ts` | 37–41 | VersionGateFailure | T |
| `abo/src/clinic-api/version.ts` | 42–70 | recordChannelVersionSeen | T |
| `abo/src/clinic-api/version.ts` | 71–111 | checkContractVersion | T |
| `abo/src/clinic-api/version.ts` | 112–125 | clinicJsonResponse | T |
| `abo/src/clinic-api/version.ts` | 126–142 | clinicErrorResponse | T |
| `abo/src/ops/index.ts` | 35–36 | ASSERTION_MAX_AGE_MS | T |
| `abo/src/ops/index.ts` | 185–190 | HpCredential | T |
| `abo/src/ops/index.ts` | 208–213 | VerifiedAccess | T |
| `abo/src/ops/index.ts` | 214–234 | parseJwtPayload | T |
| `abo/src/ops/index.ts` | 235–261 | loadAccessCerts | T |
| `abo/src/ops/index.ts` | 262–296 | verifyOpsAccess | T |
| `abo/src/ops/index.ts` | 399–411 | base64UrlDecode | T |
| `abo/src/ops/index.ts` | 412–445 | decodeAssertion | T |
| `abo/src/ops/index.ts` | 446–467 | listActiveHpCredentials | T |
| `abo/src/ops/index.ts` | 468–511 | verifyMatchingCredential | T |
| `abo/src/ops/index.ts` | 512–523 | assertionChallengeUsed | T |
| `abo/src/ops/index.ts` | 524–534 | insertAssertionUsed | T |
| `abo/src/ops/index.ts` | 595–623 | refuseHpAction | T |
| `abo/src/ops/index.ts` | 624–749 | verifyHpRequest | T |
| `abo/src/ops/index.ts` | 750–773 | commitAcceptedHp | T |
| `abo/src/ops/index.ts` | 778–788 | parseHpRequestBody | T |
| `abo/src/ops/index.ts` | 1372–1403 | handleHpPost | T |
| `abo/src/ops/index.ts` | 2358–2443 | handlePostRegisterOperatorCredential | T |
| `abo/src/ops/index.ts` | 2444–2478 | handlePostRevokeOperatorCredential | T |
| `abo/src/worker.ts` | 131–132 | SIGNING_KEY_GATE_ROW_ID | T |
| `abo/src/worker.ts` | 155–158 | emptyNotFound | T |
| `abo/src/worker.ts` | 179–188 | isCrossHostRejection | T |
| `abo/src/worker.ts` | 189–192 | isKnownHost | T |
| `abo/src/worker.ts` | 193–206 | isAcceptedPath | T |
| `abo/src/worker.ts` | 207–226 | handleBillingV1: version/auth/rate gate | T |
| `abo/src/worker.ts` | 294–314 | handleOps | T |
| `abo/src/worker.ts` | 315–359 | fetch | T |
| `ai-platform/src/quota-do/index.ts` | 92–93 | JtiReplayEntry | T |
| `ai-platform/src/quota-do/index.ts` | 226–230 | AdmissionReplay | T |
| `ai-platform/src/quota-do/index.ts` | 809–814 | StoredReplayEntry | T |
| `ai-platform/src/vendor/contract-version.ts` | 1–2 | preamble / imports / shared declarations | T |
| `ai-platform/src/vendor/contract-version.ts` | 3–4 | AIP_CONTRACT_VERSION_HEADER | T |
| `ai-platform/src/vendor/contract-version.ts` | 5–15 | parseRequestedVersion | T |
| `ai-platform/src/vendor/contract-version.ts` | 16–37 | requireAipContractVersion | T |
| `ai-platform/src/vendor/contract-version.ts` | 38–49 | withAipContractVersion | T |
| `ai-platform/src/vendor/entrypoint.ts` | 1–78 | preamble / imports / shared declarations | T |
| `ai-platform/src/vendor/entrypoint.ts` | 81–82 | ASSERTION_FRESHNESS_MS | T |
| `ai-platform/src/vendor/entrypoint.ts` | 83–128 | METHOD_CLASS | T |
| `ai-platform/src/vendor/entrypoint.ts` | 135–136 | HpAssertionMethod | T |
| `ai-platform/src/vendor/entrypoint.ts` | 231–234 | isRecord | T |
| `ai-platform/src/vendor/entrypoint.ts` | 235–247 | parseRequestedVersion | T |
| `ai-platform/src/vendor/entrypoint.ts` | 248–260 | rejected | T |
| `ai-platform/src/vendor/entrypoint.ts` | 261–269 | ok | T |
| `ai-platform/src/vendor/entrypoint.ts` | 270–278 | conflict | T |
| `ai-platform/src/vendor/entrypoint.ts` | 279–294 | envelopeFromControlResult | T |
| `ai-platform/src/vendor/entrypoint.ts` | 295–308 | rowToDetail | T |
| `ai-platform/src/vendor/entrypoint.ts` | 451–458 | jwsPayloadBytes | T |
| `ai-platform/src/vendor/entrypoint.ts` | 459–503 | verifyJwsAgainstWirePayload | T |
| `ai-platform/src/vendor/entrypoint.ts` | 504–515 | bytesEqual | T |
| `ai-platform/src/vendor/entrypoint.ts` | 516–531 | importEd25519VerifyKey | T |
| `ai-platform/src/vendor/entrypoint.ts` | 689–694 | isStringArray | T |
| `ai-platform/src/vendor/entrypoint.ts` | 695–712 | base64UrlDecode | T |
| `ai-platform/src/vendor/entrypoint.ts` | 713–747 | decodeAssertion | T |
| `ai-platform/src/vendor/entrypoint.ts` | 765–792 | loadAccessCerts | T |
| `ai-platform/src/vendor/entrypoint.ts` | 793–812 | verifyHpAccess | T |
| `ai-platform/src/vendor/entrypoint.ts` | 813–819 | operatorCredentialCount | T |
| `ai-platform/src/vendor/entrypoint.ts` | 820–833 | readOperatorCredential | T |
| `ai-platform/src/vendor/entrypoint.ts` | 834–854 | promoteCredentialIfDue | T |
| `ai-platform/src/vendor/entrypoint.ts` | 855–864 | promoteAllDueCredentials | T |
| `ai-platform/src/vendor/entrypoint.ts` | 865–870 | operationAssertionSha256 | T |
| `ai-platform/src/vendor/entrypoint.ts` | 871–881 | assertionChallengeUsed | T |
| `ai-platform/src/vendor/entrypoint.ts` | 882–895 | insertAssertionUsed | T |
| `ai-platform/src/vendor/entrypoint.ts` | 896–913 | importSignerPublicKey | T |
| `ai-platform/src/vendor/entrypoint.ts` | 914–917 | stableJson | T |
| `ai-platform/src/vendor/entrypoint.ts` | 918–1001 | operationParamsMatch | T |
| `ai-platform/src/vendor/entrypoint.ts` | 1002–1047 | hpAuditTarget | T |
| `ai-platform/src/vendor/entrypoint.ts` | 1077–1094 | readCeilingPolicyByAssertionSha256 | T |
| `ai-platform/src/vendor/entrypoint.ts` | 1095–1106 | assertionIssuedAtFresh | T |
| `ai-platform/src/vendor/entrypoint.ts` | 1107–1113 | HpAssertionReject | T |
| `ai-platform/src/vendor/entrypoint.ts` | 1114–1121 | HpAssertionOk | T |
| `ai-platform/src/vendor/entrypoint.ts` | 1122–1123 | HpAssertionResult | T |
| `ai-platform/src/vendor/entrypoint.ts` | 1124–1289 | runHpAssertionChecks | T |
| `ai-platform/src/vendor/entrypoint.ts` | 1290–1305 | finishHpAssertion | T |
| `ai-platform/src/vendor/entrypoint.ts` | 1334–1451 | verifyCeilingOverrideAssertion | T |
| `ai-platform/src/vendor/entrypoint.ts` | 1858–1873 | rejectHpAssertion | T |
| `ai-platform/src/vendor/entrypoint.ts` | 1874–1928 | bootstrapRegister | T |
| `frontend/lib/core/contract_versions.dart` | 1–4 | preamble / imports / shared declarations | T |
| `frontend/lib/core/contract_versions.dart` | 5–5 | int | T |
| `frontend/lib/core/contract_versions.dart` | 6–6 | int | T |
| `frontend/lib/core/contract_versions.dart` | 7–7 | int | T |
| `frontend/lib/core/contract_versions.dart` | 8–8 | int | T |
| `frontend/lib/core/contract_versions.dart` | 9–9 | int | T |
| `frontend/lib/core/contract_versions.dart` | 10–10 | int | T |
| `frontend/lib/core/contract_versions.dart` | 11–11 | int | T |
| `frontend/lib/core/contract_versions.dart` | 12–12 | int | T |
| `frontend/lib/core/contract_versions.dart` | 13–13 | int | T |
| `packages/vendor-contracts/src/access-jwt.ts` | 1–2 | preamble / imports / shared declarations | T |
| `packages/vendor-contracts/src/access-jwt.ts` | 3–4 | textEncoder | T |
| `packages/vendor-contracts/src/access-jwt.ts` | 5–15 | AccessCertsDocument | T |
| `packages/vendor-contracts/src/access-jwt.ts` | 16–19 | fail | T |
| `packages/vendor-contracts/src/access-jwt.ts` | 20–38 | base64UrlDecode | T |
| `packages/vendor-contracts/src/access-jwt.ts` | 39–47 | parseJsonUtf8 | T |
| `packages/vendor-contracts/src/access-jwt.ts` | 48–57 | audMatches | T |
| `packages/vendor-contracts/src/access-jwt.ts` | 58–146 | verifyAccessJwt | T |
| `packages/vendor-contracts/src/base64url.ts` | 1–1 | preamble / imports / shared declarations | T |
| `packages/vendor-contracts/src/base64url.ts` | 2–12 | base64UrlEncode | T |
| `packages/vendor-contracts/src/base64url.ts` | 13–19 | hexToBytes | T |
| `packages/vendor-contracts/src/canonical.ts` | 1–2 | preamble / imports / shared declarations | T |
| `packages/vendor-contracts/src/canonical.ts` | 3–8 | comparePropertyNames | T |
| `packages/vendor-contracts/src/canonical.ts` | 9–18 | serializeNumber | T |
| `packages/vendor-contracts/src/canonical.ts` | 19–22 | serializeString | T |
| `packages/vendor-contracts/src/canonical.ts` | 23–51 | serializeJsonValue | T |
| `packages/vendor-contracts/src/canonical.ts` | 52–56 | canonicalize | T |
| `packages/vendor-contracts/src/canonical.ts` | 57–65 | sha256Hex | T |
| `packages/vendor-contracts/src/coverage-snapshot.ts` | 1–3 | preamble / imports / shared declarations | T |
| `packages/vendor-contracts/src/coverage-snapshot.ts` | 4–4 | TERM_BANDS | T |
| `packages/vendor-contracts/src/coverage-snapshot.ts` | 5–14 | REASONS | T |
| `packages/vendor-contracts/src/coverage-snapshot.ts` | 15–26 | SNAPSHOT_KEYS | T |
| `packages/vendor-contracts/src/coverage-snapshot.ts` | 27–37 | TERM_KEYS | T |
| `packages/vendor-contracts/src/coverage-snapshot.ts` | 38–41 | isRecord | T |
| `packages/vendor-contracts/src/coverage-snapshot.ts` | 42–45 | fail | T |
| `packages/vendor-contracts/src/coverage-snapshot.ts` | 46–49 | isUuid | T |
| `packages/vendor-contracts/src/coverage-snapshot.ts` | 50–62 | hasOnlyKeys | T |
| `packages/vendor-contracts/src/coverage-snapshot.ts` | 63–77 | validateTerm | T |
| `packages/vendor-contracts/src/coverage-snapshot.ts` | 78–123 | validateCoverageSnapshot | T |
| `packages/vendor-contracts/src/feed-event.ts` | 1–2 | preamble / imports / shared declarations | T |
| `packages/vendor-contracts/src/feed-event.ts` | 3–5 | UUID_RE | T |
| `packages/vendor-contracts/src/feed-event.ts` | 6–17 | FEED_EVENT_KEYS | T |
| `packages/vendor-contracts/src/feed-event.ts` | 18–21 | isRecord | T |
| `packages/vendor-contracts/src/feed-event.ts` | 22–25 | fail | T |
| `packages/vendor-contracts/src/feed-event.ts` | 26–29 | isUuid | T |
| `packages/vendor-contracts/src/feed-event.ts` | 30–42 | hasOnlyKeys | T |
| `packages/vendor-contracts/src/feed-event.ts` | 43–71 | validateFeedEvent | T |
| `packages/vendor-contracts/src/grant-envelope.ts` | 1–4 | preamble / imports / shared declarations | T |
| `packages/vendor-contracts/src/grant-envelope.ts` | 5–6 | UUID_RE | T |
| `packages/vendor-contracts/src/grant-envelope.ts` | 7–8 | HEX64_RE | T |
| `packages/vendor-contracts/src/grant-envelope.ts` | 9–9 | PAID_MONTH_COUNTS | T |
| `packages/vendor-contracts/src/grant-envelope.ts` | 10–11 | ADJUSTMENT_KEYS | T |
| `packages/vendor-contracts/src/grant-envelope.ts` | 12–15 | isRecord | T |
| `packages/vendor-contracts/src/grant-envelope.ts` | 16–19 | fail | T |
| `packages/vendor-contracts/src/grant-envelope.ts` | 20–23 | placementNotSupported | T |
| `packages/vendor-contracts/src/grant-envelope.ts` | 24–27 | isUuid | T |
| `packages/vendor-contracts/src/grant-envelope.ts` | 28–31 | isHex64 | T |
| `packages/vendor-contracts/src/grant-envelope.ts` | 32–44 | hasOnlyKeys | T |
| `packages/vendor-contracts/src/grant-envelope.ts` | 45–55 | validatePlan | T |
| `packages/vendor-contracts/src/grant-envelope.ts` | 56–75 | validateGrace | T |
| `packages/vendor-contracts/src/grant-envelope.ts` | 76–79 | isPaidOperationApproval | T |
| `packages/vendor-contracts/src/grant-envelope.ts` | 80–92 | validateApproval | T |
| `packages/vendor-contracts/src/grant-envelope.ts` | 93–108 | validateEvidence | T |
| `packages/vendor-contracts/src/grant-envelope.ts` | 109–139 | validateSource | T |
| `packages/vendor-contracts/src/grant-envelope.ts` | 140–161 | validateDuration | T |
| `packages/vendor-contracts/src/grant-envelope.ts` | 162–203 | validateAdjustment | T |
| `packages/vendor-contracts/src/grant-envelope.ts` | 204–314 | validateGrantEnvelope | T |
| `packages/vendor-contracts/src/grant-envelope.ts` | 315–318 | grantEnvelopeHash | T |
| `packages/vendor-contracts/src/grant-envelope.ts` | 319–340 | payloadBytesFromJws | T |
| `packages/vendor-contracts/src/grant-envelope.ts` | 341–352 | bytesEqual | T |
| `packages/vendor-contracts/src/grant-envelope.ts` | 353–372 | verifyGrantSignature | T |
| `packages/vendor-contracts/src/identifiers.ts` | 1–2 | preamble / imports / shared declarations | T |
| `packages/vendor-contracts/src/identifiers.ts` | 3–4 | CROCKFORD_ALPHABET | T |
| `packages/vendor-contracts/src/identifiers.ts` | 5–6 | textEncoder | T |
| `packages/vendor-contracts/src/identifiers.ts` | 7–29 | crockfordEncode | T |
| `packages/vendor-contracts/src/identifiers.ts` | 30–33 | crockfordPrefix8 | T |
| `packages/vendor-contracts/src/identifiers.ts` | 34–37 | sha256Utf8Hex | T |
| `packages/vendor-contracts/src/identifiers.ts` | 38–59 | ulid | T |
| `packages/vendor-contracts/src/identifiers.ts` | 60–67 | subscriptionRef | T |
| `packages/vendor-contracts/src/identifiers.ts` | 68–74 | paymentId | T |
| `packages/vendor-contracts/src/identifiers.ts` | 75–78 | grantIdPaid | T |
| `packages/vendor-contracts/src/identifiers.ts` | 79–82 | grantIdComp | T |
| `packages/vendor-contracts/src/identifiers.ts` | 83–89 | grantIdTransfer | T |
| `packages/vendor-contracts/src/identifiers.ts` | 90–96 | coverageEventId | T |
| `packages/vendor-contracts/src/identifiers.ts` | 97–102 | humanRef | T |
| `packages/vendor-contracts/src/index.ts` | 1–41 | preamble / imports / shared declarations | T |
| `packages/vendor-contracts/src/jws.ts` | 1–2 | preamble / imports / shared declarations | T |
| `packages/vendor-contracts/src/jws.ts` | 3–4 | textEncoder | T |
| `packages/vendor-contracts/src/jws.ts` | 5–15 | base64UrlEncode | T |
| `packages/vendor-contracts/src/jws.ts` | 16–29 | base64UrlDecode | T |
| `packages/vendor-contracts/src/jws.ts` | 30–38 | parseJsonUtf8 | T |
| `packages/vendor-contracts/src/jws.ts` | 39–50 | bytesEqual | T |
| `packages/vendor-contracts/src/jws.ts` | 51–65 | parseHeader | T |
| `packages/vendor-contracts/src/jws.ts` | 66–83 | signCompactJws | T |
| `packages/vendor-contracts/src/jws.ts` | 84–124 | verifyCompactJws | T |
| `packages/vendor-contracts/src/operation.ts` | 1–3 | preamble / imports / shared declarations | T |
| `packages/vendor-contracts/src/operation.ts` | 4–12 | OPERATION_KEYS | T |
| `packages/vendor-contracts/src/operation.ts` | 13–16 | isRecord | T |
| `packages/vendor-contracts/src/operation.ts` | 17–20 | fail | T |
| `packages/vendor-contracts/src/operation.ts` | 21–33 | hasOnlyKeys | T |
| `packages/vendor-contracts/src/operation.ts` | 34–58 | validateOperation | T |
| `packages/vendor-contracts/src/operation.ts` | 59–65 | operationChallenge | T |
| `packages/vendor-contracts/src/receipt.ts` | 1–3 | preamble / imports / shared declarations | T |
| `packages/vendor-contracts/src/receipt.ts` | 4–5 | UUID_RE | T |
| `packages/vendor-contracts/src/receipt.ts` | 6–7 | HEX64_RE | T |
| `packages/vendor-contracts/src/receipt.ts` | 8–20 | RECEIPT_BASE_KEYS | T |
| `packages/vendor-contracts/src/receipt.ts` | 21–24 | isRecord | T |
| `packages/vendor-contracts/src/receipt.ts` | 25–28 | fail | T |
| `packages/vendor-contracts/src/receipt.ts` | 29–32 | isUuid | T |
| `packages/vendor-contracts/src/receipt.ts` | 33–36 | isHex64 | T |
| `packages/vendor-contracts/src/receipt.ts` | 37–49 | hasOnlyKeys | T |
| `packages/vendor-contracts/src/receipt.ts` | 50–56 | validateTermIds | T |
| `packages/vendor-contracts/src/receipt.ts` | 57–109 | validateReceipt | T |
| `packages/vendor-contracts/src/receipt.ts` | 110–118 | receiptSigningBytes | T |
| `packages/vendor-contracts/src/receipt.ts` | 119–145 | payloadBytesFromJws | T |
| `packages/vendor-contracts/src/receipt.ts` | 146–157 | bytesEqual | T |
| `packages/vendor-contracts/src/receipt.ts` | 158–182 | verifyReceiptSignature | T |
| `packages/vendor-contracts/src/result-envelope.ts` | 1–2 | preamble / imports / shared declarations | T |
| `packages/vendor-contracts/src/result-envelope.ts` | 3–11 | RESULT_NAMES | T |
| `packages/vendor-contracts/src/result-envelope.ts` | 12–18 | TRANSIENT_DETAILS | T |
| `packages/vendor-contracts/src/result-envelope.ts` | 19–22 | isRecord | T |
| `packages/vendor-contracts/src/result-envelope.ts` | 23–26 | fail | T |
| `packages/vendor-contracts/src/result-envelope.ts` | 27–39 | hasOnlyKeys | T |
| `packages/vendor-contracts/src/result-envelope.ts` | 40–80 | validateResultEnvelope | T |
| `packages/vendor-contracts/src/token-claims.ts` | 1–2 | preamble / imports / shared declarations | T |
| `packages/vendor-contracts/src/token-claims.ts` | 3–4 | textEncoder | T |
| `packages/vendor-contracts/src/token-claims.ts` | 5–7 | UUID_RE | T |
| `packages/vendor-contracts/src/token-claims.ts` | 8–13 | LIFETIME_MAX | T |
| `packages/vendor-contracts/src/token-claims.ts` | 14–15 | TokenAudience | T |
| `packages/vendor-contracts/src/token-claims.ts` | 16–34 | base64UrlDecode | T |
| `packages/vendor-contracts/src/token-claims.ts` | 35–43 | parseJsonUtf8 | T |
| `packages/vendor-contracts/src/token-claims.ts` | 44–55 | bytesEqual | T |
| `packages/vendor-contracts/src/token-claims.ts` | 56–59 | isRecord | T |
| `packages/vendor-contracts/src/token-claims.ts` | 60–63 | fail | T |
| `packages/vendor-contracts/src/token-claims.ts` | 64–76 | hasOnlyKeys | T |
| `packages/vendor-contracts/src/token-claims.ts` | 77–102 | parseJwtHeader | T |
| `packages/vendor-contracts/src/token-claims.ts` | 103–128 | validateCommonClaims | T |
| `packages/vendor-contracts/src/token-claims.ts` | 129–149 | validateAiClaims | T |
| `packages/vendor-contracts/src/token-claims.ts` | 150–162 | validateBillingClaims | T |
| `packages/vendor-contracts/src/token-claims.ts` | 163–173 | validateFeedClaims | T |
| `packages/vendor-contracts/src/token-claims.ts` | 174–189 | validateAudienceClaims | T |
| `packages/vendor-contracts/src/token-claims.ts` | 190–244 | validateTokenClaims | T |
| `packages/vendor-contracts/src/version.ts` | 1–12 | preamble / imports / shared declarations | T |
| `packages/vendor-contracts/src/version.ts` | 13–16 | acceptedVersions | T |
| `packages/vendor-contracts/src/version.ts` | 17–43 | negotiate | T |
| `packages/vendor-contracts/src/webauthn.ts` | 1–4 | preamble / imports / shared declarations | T |
| `packages/vendor-contracts/src/webauthn.ts` | 5–11 | Assertion | T |
| `packages/vendor-contracts/src/webauthn.ts` | 12–13 | textEncoder | T |
| `packages/vendor-contracts/src/webauthn.ts` | 14–17 | fail | T |
| `packages/vendor-contracts/src/webauthn.ts` | 18–29 | bytesEqual | T |
| `packages/vendor-contracts/src/webauthn.ts` | 30–58 | parseClientDataJson | T |
| `packages/vendor-contracts/src/webauthn.ts` | 59–99 | derEcdsaDerToRaw | T |
| `packages/vendor-contracts/src/webauthn.ts` | 100–115 | leftPadInteger | T |
| `packages/vendor-contracts/src/webauthn.ts` | 116–135 | derEcdsaRawToDer | T |
| `packages/vendor-contracts/src/webauthn.ts` | 136–209 | verifyAssertion | T |
| `packages/vendor-contracts/src/webauthn.ts` | 210–248 | parseRegistrationAttestation | T |

## Unchanged supporting dependencies

