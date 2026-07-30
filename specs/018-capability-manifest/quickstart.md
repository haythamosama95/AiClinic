# Quickstart: Capability manifest schema and loader (A4)

Slice **A4** freezes the §5.1 capability manifest: ten field groups as a typed schema, a
`load()` validator with interaction-mode and routing rules, and a published-version content-hash
registry so in-place edits to published versions fail CI.

Full requirements: [`spec.md`](spec.md). File-level traceability: [`plan.md`](plan.md).

## 1. Architecture context

This slice implements delivery-plan row **A4** (*Capability manifest schema and loader*), which maps to
[§5.1 and §5.7](../../docs/architecture/17-ai-platform.md) of
[`../../docs/architecture/17-ai-platform.md`](../../docs/architecture/17-ai-platform.md) and row A4 of
[`../../docs/architecture/17b-ai-platform-delivery-plan.md`](../../docs/architecture/17b-ai-platform-delivery-plan.md).
The **spec** freezes the ten §5.1 manifest field groups, a `load()` validator (including
`single_shot` default and conversational-field rules), and build-time immutability for published
versions. The **plan** scopes `manifest/index.ts`, seventeen contract tests (T-A4-01..17), and a
`contracts/manifest-schema.md` artifact — schema and loader only, no request-path resolver.

## 2. What was implemented

- **`ai-platform/src/manifest/index.ts`** — ten-group schema as data (`MANIFEST_FIELD_MANIFEST`);
  `Manifest` type with read-only `interactionMode`; `load()` applying the `single_shot` default,
  conversational-only-field rejection, and never-names-provider/model check; stable
  `hashManifest()` and `verifyPublishedRegistry()` for published-version immutability.
- **`ai-platform/test/manifest.test.ts`** — seventeen named contract cases (T-A4-01..17): all-ten-groups
  load, per-group omit/malform rejection, published-version hash mismatch, interaction-mode default
  and immutability, conversational-field rejection, data-not-code export surface, and routing
  provider/model rejection.
- **`specs/018-capability-manifest/contracts/manifest-schema.md`** — frozen manifest wire-shape
  reference for later slices' Consumes review.

## 3. Files to review

| Path | Role |
| --- | --- |
| `ai-platform/src/manifest/index.ts` | Schema manifest, `load`, hash registry helpers |
| `ai-platform/test/manifest.test.ts` | T-A4-01..17 contract suite |
| `specs/018-capability-manifest/contracts/manifest-schema.md` | Frozen §5.1 manifest wire shape |

## 4. Run the automated suite

From the repository root:

```bash
cd ai-platform
npm install   # first time only
npx vitest run test/manifest.test.ts
```

Expect **31 passing tests** in `manifest.test.ts` — the seventeen named A4 contract cases
(T-A4-01..17) plus supporting assertions for per-group omit/malform pairs and conversational-field
variants.

## 5. Inspect the changes

Read the frozen manifest wire shape:

```bash
cat specs/018-capability-manifest/contracts/manifest-schema.md
```

Inspect the field-group manifest and validation rules in code:

```bash
grep -n 'MANIFEST_FIELD_MANIFEST\|CONVERSATIONAL_ONLY\|ROUTING_FORBIDDEN' \
  ai-platform/src/manifest/index.ts
```

View the manifest module:

```bash
cat ai-platform/src/manifest/index.ts
```
