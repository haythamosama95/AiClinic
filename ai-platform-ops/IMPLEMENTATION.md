# AI Platform Ops — Implementation Brief (LOCKED)

Decisions are final. Implementers copy this; do not redesign.

## 1. Subject / job

- **Product:** AiClinic AI Platform ops console
- **Audience:** operators and developers invoking gateway surfaces
- **Job:** enter parameters → run → read raw response (no verdicts, no expected results, no pass/fail chrome)

## 2. Package

`ai-platform-ops/` sibling of `ai-platform/`. **Never modify** `ai-platform/src/**`.

Stack: Vite 8 + React 19 + TypeScript + Tailwind 4. Fonts via `@fontsource/ibm-plex-sans` + `@fontsource/ibm-plex-mono`.

## 3. Design system (locked)

**Direction:** daylight lab requisition — cool paper workspace, not dark mode, not cream+serif, not purple.

| Token | Hex | Role |
|-------|-----|------|
| `--paper` | `#EEF2F6` | page background |
| `--chalk` | `#F7FAFC` | form / response panels |
| `--ink` | `#1C2A3A` | primary text |
| `--steel` | `#5A6F85` | secondary labels |
| `--rule` | `#C5D0DC` | hairlines |
| `--teal` | `#0E6B6D` | brand + primary actions |
| `--teal-deep` | `#0A4F51` | active tab / focus |
| `--warn` | `#C45C26` | dangerous ops only (purge, delete, retire, rollback) |
| `--ok-line` | `#1F6B4A` | focus ring success optional |

**Type:** IBM Plex Sans (UI) + IBM Plex Mono (fields, response, ids). Brand wordmark “Platform Ops” in Plex Sans semibold — no display serif.

**Signature:** top **connection strip** (platform URL + credentials) + **solid block category tabs** (Clinic | Control | Debug | E2E). Entity list is a left column of plain text links; main pane is a single requisition form (label / control rows) + raw response dump. No cards, no stats, no expected-verdict UI.

**Motion:** tab underline slide 180ms; form mount fade 120ms; respect `prefers-reduced-motion`.

## 4. Navigation

Four top-level tabs = categories. Selecting a tab shows that category’s entity list + form.

## 5. Connection strip (global)

Persisted in `sessionStorage` key `ai-platform-ops.connection`:

- `platformBaseUrl` (string) — Worker origin, e.g. `http://127.0.0.1:8787`
- `operatorBearer` (string) — for Control / support
- `aat` (string) — for Clinic authenticated calls

Never log full tokens to console.

## 6. API architecture

- Browser → `POST/GET /ops/*` (Vite middleware / Node server)
- Server proxies to `platformBaseUrl` OR runs local pure helpers / subprocess
- Response always returned as `{ status, headers, bodyText, contentType }` for the UI dump

Do not add “expected” or scoring fields in the response UI — only status + body.

## 7. Entity catalog

See `src/catalog/*.ts`. Every entity has: `id`, `category`, `title`, `description`, `mode` (`proxy` | `local` | `subprocess`), `dangerous?`, `fields[]`, `buildRequest(values)`.

Field kinds: `text` | `password` | `textarea` | `json` | `number` | `select` | `checkbox`.

## 8. UI rules for forms

- Render **every** field declared for the entity
- Primary button label: **Run** (or **Run (dangerous)** when `dangerous`)
- Optional confirm text input when `dangerous`: must type entity id to enable Run
- Below: monospace response panel showing HTTP status + raw body
- No expected verdict, golden compare, or pass/fail badges
