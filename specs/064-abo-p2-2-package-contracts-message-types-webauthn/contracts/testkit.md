# Contract: testkit subpath

**Unit**: P2.2 · **Requirements**: FR-012

Later units bind to this file. The package export is `vendor-contracts/testkit`, mapped in `package.json` to `./src/testkit/index.ts`. `src/index.ts` does not export it. Production code does not import it.

## 1. Marker

`src/testkit/index.ts` exports `TESTKIT_MARKER` with the value `vendor-contracts-testkit`. Each exported function reads that constant, so a bundle that pulls in any of them contains the string. E2E-P2.2-08 scans the production `ai-platform` bundle for that string.

## 2. Software authenticator

`src/testkit/authenticator.ts`.

```ts
export function createSoftwareAuthenticator(
  alg: "ES256" | "EdDSA",
): Promise<{
  attest(): Promise<{ alg: "ES256" | "EdDSA"; publicKey: Uint8Array }>
  assert(input: {
    operation: unknown
    rpId: string
    origin: string
    up: boolean
    uv: boolean
  }): Promise<Assertion>
}>
```

`attest` returns the attestation `contracts/webauthn.md` parses. `assert` sets the challenge to `operationChallenge(operation)`, puts `origin` and `type: "webauthn.get"` in `clientDataJSON`, and sets the authenticator-data flags from `up` and `uv`. ES256 signatures are DER. EdDSA signatures are raw. The public key matches `attest().publicKey`.

## 3. Access team

`src/testkit/access-team.ts`.

```ts
export function createAccessTeam(input: {
  issuer: string
}): Promise<{
  certs: AccessCertsDocument
  mint(input: {
    email: string
    aud: string
    exp: number
    iat: number
    kid?: string
  }): Promise<string>
}>
```

`certs` is one RS256 public JWK and `issuer`. `mint` signs with that key (`RSASSA-PKCS1-v1_5`, SHA-256) and sets `iss` from `issuer`. `kid` defaults to the document's key. A passed `kid` is written into the header while the signature still uses the real key, so an unknown kid fails lookup.

## 4. Issuer minters

`src/testkit/issuer.ts`.

```ts
export function createIssuer(input: {
  issuerId: string
}): Promise<{
  kid: string
  publicKey: CryptoKey
  mintAi(claims: {
    sub: string
    org: string
    role: string
    branch: string
    scopes: string[]
    iat: number
    exp: number
    jti: string
  }): Promise<string>
  mintBilling(claims: {
    sub: string
    org: string
    role: string
    branch: string
    iat: number
    exp: number
    jti: string
  }): Promise<string>
  mintFeed(claims: {
    iat: number
    exp: number
    jti: string
    org?: string
  }): Promise<string>
}>
```

Each minter signs the 04 §2.1 header from `contracts/token-claims.md` and sets `iss` to `issuerId` and `ver` to `"2"`. It signs the claim object it is given, including a billing lifetime above 300 seconds or a feed payload that includes `org`. `validateTokenClaims` is what rejects those.

## 5. ABO grant signer and platform receipt signer

`src/testkit/signers.ts`.

```ts
export function createAboGrantSigner(): Promise<{
  kid: string
  publicKey: CryptoKey
  sign(envelope: unknown): Promise<string>
}>

export function createPlatformReceiptSigner(): Promise<{
  kid: string
  publicKey: CryptoKey
  sign(receiptWithoutSignature: unknown): Promise<string>
}>
```

Both use Ed25519 keys and `signCompactJws`. The ABO signer signs `canonicalize(envelope)`. The platform signer signs `canonicalize(receiptWithoutSignature)`, and the returned compact JWS is the receipt's `signature`. The receipt's `kid` is this signer's `kid`.

## 6. Bundle scan

E2E-P2.2-08 runs under the Node Vitest config only. `vitest.workers.config.ts` excludes `test/bundle-scan.test.ts`. The test reads `package.json` and requires the `./testkit` export, then runs, with working directory `ai-platform/`:

```bash
npx wrangler deploy --dry-run --outdir <tmpdir> --env production
```

`ai-platform/wrangler.toml` has `main = "src/worker.ts"`. The production env name is `ai-platform-gateway-production`. The test reads the emitted bundle and requires the text to omit `vendor-contracts-testkit`.
