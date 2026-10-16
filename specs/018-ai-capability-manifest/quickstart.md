# Quickstart: Capability manifest schema and loader (A4)

Slice **A4** freezes the §5.1 capability manifest: ten field groups as a typed schema, a
`load()` validator with interaction-mode and routing rules, and a published-version content-hash
registry so in-place edits to published versions fail CI.

Full requirements: [`spec.md`](spec.md). File-level traceability: [`plan.md`](plan.md).

## 1. Architecture context

This slice implements delivery-plan row **A4** (*Capability manifest schema and loader*), which maps to
[§5.1 and §5.7](../../docs/architecture/ai-platform/01-ai-platform.md) of
[`../../docs/architecture/ai-platform/01-ai-platform.md`](../../docs/architecture/ai-platform/01-ai-platform.md) and row A4 of
[`../../docs/architecture/ai-platform/03-ai-platform-delivery-plan.md`](../../docs/architecture/ai-platform/03-ai-platform-delivery-plan.md).
The **spec** freezes the ten §5.1 manifest field groups, a `load()` validator (including
`single_shot` default and conversational-field rules), and build-time immutability for published
versions. The **plan** scopes `manifest/index.ts`, seventeen contract tests (T-A4-01..17), and a
`contracts/manifest-schema.md` artifact — schema and loader only, no request-path resolver.

## 2. What was implemented

- **`ai-platform/src/manifest/index.ts`** — ten-group schema as data (`MANIFEST_FIELD_MANIFEST`);
  `Manifest` type with read-only `interactionMode`; `load()` applying the `single_shot` default,
  conversational-only-field rejection, exact key-set equality, content-enum checks, deep freeze,
  and a recursive never-names-provider/model denylist; WebCrypto SHA-256 `hashManifest()`,
  `verifyPublishedRegistry()`, and `verifyManifestTree()` for the published-version build gate.
- **`ai-platform/manifests/published/`** + **`published-registry.json`** — checked-in append-only
  registry tree walked by `npm run verify-manifests`.
- **`ai-platform/test/manifest.test.ts`** — contract cases T-A4-01..23 (groups, immutability, enums,
  denylist, SHA-256, registry gate).
- **`ai-platform/test/manifest-registry-gate.test.ts`** — build-gate entrypoint for `verify-manifests`.
- **`specs/018-ai-capability-manifest/contracts/manifest-schema.md`** — frozen manifest wire-shape
  reference for later slices' Consumes review.

## 3. Files to review

| Path | Role |
| --- | --- |
| `ai-platform/src/manifest/index.ts` | Schema manifest, `load`, hash registry helpers |
| `ai-platform/manifests/published-registry.json` | Append-only `(id, version)` → SHA-256 map |
| `ai-platform/test/manifest.test.ts` | T-A4-01..23 contract suite |
| `ai-platform/test/manifest-registry-gate.test.ts` | Build gate |
| `specs/018-ai-capability-manifest/contracts/manifest-schema.md` | Frozen §5.1 manifest wire shape |

## 4. Run the automated suite

From the repository root:

```bash
cd ai-platform
npm install   # first time only
npm run verify-manifests
npx vitest run test/manifest.test.ts
```

Expect the registry gate green and **46 passing tests** in `manifest.test.ts` (T-A4-01..23).

## 5. Inspect the changes

Read the frozen manifest wire shape:

```bash
cat specs/018-ai-capability-manifest/contracts/manifest-schema.md
```

Inspect the field-group manifest and validation rules in code:

```bash
grep -n 'MANIFEST_FIELD_MANIFEST\|CONVERSATIONAL_ONLY\|PROVIDER_SHAPED' \
  ai-platform/src/manifest/index.ts
```

View the manifest module:

```bash
cat ai-platform/src/manifest/index.ts
```
