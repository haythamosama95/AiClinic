# AiClinic Web Reference

Canonical React visual specification for the AiClinic design system. Flutter reproduces this faithfully.

## Stack

- React + TypeScript + Vite
- Tailwind CSS v4
- Radix UI primitives
- Lucide icons
- Motion (Framer Motion)

## Development

```bash
npm install
npm run dev
```

Open the Foundations demo at `http://localhost:5173`.

## Design tokens

`tokens.json` at the project root mirrors `docs/ui/design-system/02-tokens.md` (W3C DTCG shape: primitive → semantic → component). CSS custom properties in `src/index.css` wire semantic tokens into Tailwind.

## Milestone 1 — Foundations

- Token system (light/dark semantic themes)
- Theme + direction providers (LTR/RTL, en/ar)
- Typography scale (Inter, Geist, IBM Plex Sans Arabic)
- Motion presets with reduced-motion support
- The Signal signature primitive
- Foundations demo page (no components yet)
