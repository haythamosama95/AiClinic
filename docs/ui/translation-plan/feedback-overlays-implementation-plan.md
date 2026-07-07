# Implementation Plan — Dev → Components → Feedback & Overlays (Flutter Port)

Spec target: port the **Feedback & overlays** group of `web-reference/` into the Flutter `frontend/` App abstraction layer, surfaced in the Dev components page. 8 widgets, divided into **2 phases**.

## 0. Ambiguities & Design Decisions (resolve before coding)

1. **forui vs native Material.** As with Actions/Inputs, `forui` is imported nowhere. **Decision: native Material** (`showDialog`, `showGeneralDialog`, `Overlay`/`OverlayEntry`, `Material`, `CircularProgressIndicator`). `forui-wrappers.md` is superseded.

2. **Core file layout.** Keep the flat `core/ui/components/app_<name>.dart` convention. Showcase sections live under `features/design_system/presentation/components/feedback/<name>_showcase_section.dart` (mirrors existing `actions/` and `inputs/` subfolders).

3. **Popover reuse.** The inputs group already shipped `AppPopover` (`app_popover.dart`, exported via `widgets.dart`) — an `Overlay`/`OverlayEntry` + `LayerLink` + `CompositedTransformFollower` wrapper with fade-scale motion, trigger-width matching, RTL-aware anchoring, and Esc-to-close. **Decision: the Popover showcase reuses `AppPopover` directly — no new wrapper.** The showcase only needs a `<Button variant="secondary" size="sm">`-equivalent trigger (`AppButton` secondary sm) and a `p-4 text-body-sm` content padding.

4. **Status color tokens gap.** `AppSemanticColors` currently exposes `statusSuccessFg`, `statusDangerFg`, `statusDangerBorder` only. The web `Alert` (info/success/warning/danger/ai) and `EmptyState`/`ErrorState` need **surface + border + fg** per status. `AppColorPrimitives` already has `statusInfoFg/Surface/Border`, `statusWarningFg/Surface/Border`, `statusSuccessFg/Surface/Border`, `statusDangerFg/Surface/Border` (light + dark). **Decision: extend `AppSemanticColors`** (in `app_semantic_colors.dart`) with the missing `statusInfoFg/statusInfoSurface/statusInfoBorder`, `statusWarningFg/statusWarningSurface/statusWarningBorder`, `statusSuccessSurface/statusSuccessBorder`, `statusDangerSurface` tokens, wired from `AppColorPrimitives`, with `copyWith`/`lerp` parity. This is the one theme-touch justified by the group; AI variant reuses `surfaceAi`/`textAi`/`borderAi`.

5. **Toast architecture.** Web uses React context + portal. Flutter has no provider-scoped overlay tree by default. **Decision: introduce an `AppToastHost` widget** (mounted once near the app root, hosts an `Overlay` + a `Listenable` of active toasts) plus a top-level `appToast(BuildContext, AppToastInput)` helper that finds the host via `InheritedWidget`/`Provider`. Built on `OverlayEntry` with `AppMotion.slideUp`, max 3 stacked, `danger`→8s / others→4s, dismiss `IconButton`. This is the one new architectural piece in Phase 2; justified because toasts are app-global and need a host outside the widget tree of the trigger.

6. **Dialog/Drawer technology.** Web uses Radix-less custom portals + motion + focus-trap. **Decision: native Material `showDialog` / `showGeneralDialog`** for Dialog (with `AppMotion.modal` fade-scale on the `Dialog` widget, barrier `surfaceBackdrop` + optional blur), and `showGeneralDialog` (not `showModalBottomSheet`, to control side anchoring + RTL + slide motion) for Drawer. `barrierDismissible`, Esc, and focus are handled by Material; we add `onOpenChange` semantics and a `title`/`description`/`footer` slot structure mirroring web.

7. **i18n / RTL.** Showcase copy is bilingual EN/AR via `devPreviewProvider` (existing `_copyEn`/`_copyAr` convention from `button_showcase_section.dart`). Drawer side `inline-end`/`inline-start` maps to `TextDirection` (RTL mirrors). Dialog/Drawer/Toast/Popover consume `Directionality.of(context)` for padding/mirror. Alert/EmptyState/ErrorState copy is locale-driven; the toast action label "Undo" and confirmation typed-string "ARCHIVE" stay Latin in both locales (web treats them as fixed affordances — keep parity).

8. **Controlled/uncontrolled.** Dialog/Drawer/Toast are imperative (`showDialog`/`appToast`) plus optional controlled `open`/`onOpenChange` for Dialog/Drawer parity — implement `AppDialog.show(context, ...)` returning a `Future` and a controlled `AppDialog` widget variant. ConfirmationDialog's typed-confirmation (`requireTypedConfirmation='ARCHIVE'`) is a local `TextEditingController`. LoadingOverlay is `loading`/`scoped` props (controlled by parent). Alert `dismissible`+`onDismiss` is uncontrolled-internal-state with optional controlled `onDismiss`.

## 1. Existing App assets to reuse (do not recreate)

| Asset | Path | Used by |
|---|---|---|
| `AppButton` (`variant`, `size`, `loading`, `error`, `disabled`, `leadingIcon`/`trailingIcon`) | `core/ui/components/app_button.dart` | Toast trigger, Dialog/Drawer open buttons, EmptyState/ErrorState action, Confirmation cancel/confirm |
| `AppIconButton` (ghost sm) | `core/ui/components/app_icon_button.dart` | Alert/Toast/Dialog/Drawer dismiss `X` |
| `AppPopover` | `core/ui/components/app_popover.dart` | Popover showcase (verbatim) |
| `AppKbd` | `core/ui/components/app_kbd.dart` | EmptyState shortcut hint `⌘ N` |
| Theme: `context.appColors`, `AppSpacing`, `AppRadius`, `AppTypography`, `AppMotion`, `AppElevation` | `core/ui/theme/*` | every widget |
| `AppMotion` presets (`modal`, `drawer`, `slideUp`, `fade`, `fadeScale`) | `core/ui/motion/app_motion.dart` | Dialog/Drawer/Toast motion |
| `devPreviewProvider` | `features/design_system/presentation/providers/dev_preview_provider.dart` | locale/direction in showcases |
| Showcase primitives: `ShowcaseSection`, `ShowcaseDemoGrid`, `ShowcaseDemo`, `ShowcaseVariantMatrix`, `PlaceholderSection` | `components/showcase_primitives.dart` | every showcase section |
| Section wiring: `component_registry.dart`, `component_section_builders.dart` | `components/` | one-line registration per widget |

## 2. New shared abstractions to introduce

| File (`lib/core/ui/components/`) | Export name | Analog | Purpose | Phase |
|---|---|---|---|---|
| `app_alert.dart` | `AppAlert` (+ `AppAlertVariant {info,success,warning,danger,ai}`) | web `Alert` | inline status banner: icon + title + body + optional actions + dismissible. `role=alert` for danger else `status`. | 1 |
| `app_loading_overlay.dart` | `AppLoadingOverlay` | web `LoadingOverlay` | `loading`/`scoped`/`label`; scoped = `Stack`-positioned over children with `bg-surface-default/80` + `CircularProgressIndicator` (md) + label; non-scoped = full-screen `OverlayEntry`. | 1 |
| `app_empty_state.dart` | `AppEmptyState` (+ `AppEmptyStateVariant {firstRun,noResults,noAccess,error}`) | web `EmptyState` | centered icon-in-circle + title + description + primary action + secondaryAction + `shortcutHint` kbd row. | 1 |
| `app_error_state.dart` | `AppErrorState` | web `ErrorState` | centered `AlertTriangle` in danger circle + title + message + secondary `Try again` button w/ `RefreshCw` icon. `role=alert`. | 1 |
| `app_toast.dart` | `AppToastHost`, `appToast(ctx, input)`, `AppToastVariant {success,danger,info,neutral}`, `AppToastInput` | web `Toast`/`useToast` | app-global toast host (mounted at root) + imperative `appToast`; max 3, slide-up motion, auto-dismiss 8s(danger)/4s, action link + dismiss. | 2 |
| `app_dialog.dart` | `AppDialog`, `AppDialog.show(...)`, `AppDialogSize {sm,md,lg,full}`, `AppConfirmationDialog` | web `Dialog`/`ConfirmationDialog` | `showDialog`-backed modal: backdrop+blur, `AppMotion.modal` panel, title/description/`X`/children/footer, 4 sizes; Confirmation variant with optional typed-confirmation + `destructive`/`financial`. | 2 |
| `app_drawer.dart` | `AppDrawer`, `AppDrawer.show(...)`, `AppDrawerSide {inlineEnd,inlineStart,bottom}`, `AppDrawerSize {sm,md,lg}` | web `Drawer` | `showGeneralDialog`-backed side/bottom panel: optional modal backdrop, `AppMotion.drawer` slide, title/description/`X`/children/footer, RTL mirror, 3 sizes + bottom sheet. | 2 |

**Theme touch:** extend `app_semantic_colors.dart` (Phase 1 kickoff) with the missing status surface/border/fg tokens listed in §0.4. **Barrel update:** append every new `app_*.dart` to `widgets.dart` under a `// Feedback & overlays` sub-comment.

## 3. Phasing

> Rationale (2 phases): **Phase 1** = the inline/static feedback surfaces + popover reuse — no portal/modal infra, ships the `AppSemanticColors` status-token extension that several of them need. **Phase 2** = the three portal/modal surfaces (Toast host, Dialog, Drawer) that introduce new imperative-show infrastructure; they cluster naturally and are independently shippable after Phase 1.

### Phase 1 — Inline feedback + popover reuse
Widgets: **Inline alert, Loading overlay, Empty states, Error state, Popover**

| Widget | Flutter widget(s) to create | File(s) | Reuse | Wrapper | Deps |
|---|---|---|---|---|---|
| Inline alert | `AppAlert` | CREATE `components/app_alert.dart`; MOD `widgets.dart` | `AppIconButton` (dismiss), `AppTypography`, status tokens (§0.4), lucide→`Icons` (info `Icons.info_outline`, success `Icons.check_circle_outlined`, warning `Icons.error_outline`, danger `Icons.cancel_outlined`, ai `Icons.auto_awesome_outlined`) | NEW | status tokens extension |
| Loading overlay | `AppLoadingOverlay` | CREATE `components/app_loading_overlay.dart`; MOD `widgets.dart` | `CircularProgressIndicator` (md=20px), `AppTypography`, `surfaceDefault` w/ 80% alpha, `OverlayEntry` for non-scoped | NEW | none |
| Empty states | `AppEmptyState` | CREATE `components/app_empty_state.dart`; MOD `widgets.dart` | `AppButton` (primary, action), `AppKbd` (shortcutHint `⌘ N`), `surfaceMuted`+`iconMuted` circle, variant icons (`Icons.folder_open`, `Icons.search_off`, `Icons.lock_outline`, `Icons.help_outline`) | NEW | `AppKbd` (existing) |
| Error state | `AppErrorState` | CREATE `components/app_error_state.dart`; MOD `widgets.dart` | `AppButton` (secondary + `RefreshCw`=`Icons.refresh`), `statusDangerSurface`+`statusDangerFg` circle, `Icons.warning_amber_outlined` | NEW | status tokens extension |
| Popover | (no new widget) | CREATE only the showcase section | `AppPopover` (existing), `AppButton` (secondary sm trigger) | REUSE `AppPopover` | none |

Showcase sections (Phase 1), under `features/design_system/presentation/components/feedback/`:
`alert_showcase_section.dart`, `loading_overlay_showcase_section.dart`, `empty_state_showcase_section.dart`, `error_state_showcase_section.dart`, `popover_showcase_section.dart`.

### Phase 2 — Modal/portal overlays + toast
Widgets: **Toast, Dialog, Drawer**

| Widget | Flutter widget(s) to create | File(s) | Reuse | Wrapper | Deps |
|---|---|---|---|---|---|
| Toast | `AppToastHost` (root host) + `appToast(ctx, input)` + `AppToastInput`/`AppToastVariant` | CREATE `components/app_toast.dart`; MOD `widgets.dart`; MOD app root to mount `AppToastHost` (only if not already present) | `Overlay`+`OverlayEntry`, `AppMotion.slideUp`, `AppButton` (link, action label e.g. "Undo"), `AppIconButton` (ghost sm dismiss), variant icons (success `check_circle`, danger `cancel`, info `info`, neutral `info`), `surfaceRaised`+variant border | NEW (host + service) | none (self-contained) |
| Dialog | `AppDialog` (controlled widget) + `AppDialog.show(context, ...)` + `AppConfirmationDialog` | CREATE `components/app_dialog.dart`; MOD `widgets.dart` | `showDialog`/`Navigator`, `AppMotion.modal`, `AppIconButton` (close `X`), `AppButton` (footer actions, danger for destructive), `surfaceBackdrop`+blur barrier, `surfaceRaised`+`borderDefault`+`elevation-3` panel | NEW | none |
| Drawer | `AppDrawer` + `AppDrawer.show(context, ...)` | CREATE `components/app_drawer.dart`; MOD `widgets.dart` | `showGeneralDialog`, `AppMotion.drawer`, `AppIconButton` (close), `AppButton` (footer), optional `surfaceBackdrop`+blur barrier, RTL `inline-end`/`inline-start`/`bottom` anchoring, `surfaceRaised`+`borderDefault`+`elevation-3` panel | NEW | none |

Showcase sections (Phase 2): `toast_showcase_section.dart`, `dialog_showcase_section.dart`, `drawer_showcase_section.dart`.

## 4. Instantiation in the Dev page (mirrors web reference)

> **Binding source of truth:** the per-demo arrangement, props, labels, copy, and variant matrices in each Flutter showcase section **must mirror exactly** how `web-reference/src/showcase/components/feedback/FeedbackShowcase.tsx` instantiates the web widget. Composer 2.5 should open the referenced `.tsx` for each widget and reproduce, demo-for-demo: the number/order/titles of `ShowcaseDemo` cells; the exact props (variants, sizes, `dismissible`, `scoped`, `loading`, `label`, `action`, `shortcutHint`, `requireTypedConfirmation`, `variant='destructive'|'financial'`, dialog `size` sm/md/lg/full, etc.); any `ShowcaseVariantMatrix` rows; the bilingual EN/AR copy following the existing `_copyEn`/`_copyAr` convention. The Flutter `ShowcaseSection`/`ShowcaseDemoGrid`/`ShowcaseDemo`/`ShowcaseVariantMatrix` primitives are 1:1 in shape with the web ones, so the demo structure ports verbatim — only the control widget name and prop syntax change.

Concretely per widget (reproduce from `FeedbackShowcase.tsx`):

- **Toast** — 4 `ShowcaseDemo` cells in a 2-col grid, one per variant `success`/`danger`/`info`/`neutral`; each demo is a single `AppButton` (secondary sm) labelled `Show <variant>` that calls `appToast` with the matching `message` (`Published` / `Could not save changes` / `Sync in progress` / `Draft saved`) and `action: {label:'Undo'}` only on success. `componentName: 'useToast / ToastProvider'`.
- **Inline alert** — single column (`space-y-4` → vertical `Column`), 5 alerts one per variant `info`/`success`/`warning`/`danger`/`ai`, all `dismissible`; titles = `Info notice`/`Success notice`/`Warning notice`/`Danger notice`/`AI suggestions require your approval`; body = `Contextual message for the <variant> variant.` `componentName: 'Alert'`.
- **Dialog** — 2-col `ShowcaseDemoGrid`: demo `Sizes` (4 `AppButton` sm: Small/Medium/Large/Full opening `AppDialog` size sm/md/lg/full with the web titles + one-line bodies + footer Close/Save/Done/Close); demo `Confirmation` (danger `AppButton` "Destructive" → `AppConfirmationDialog` title "Archive patient?" description "This removes the patient from active lists. Visit history is retained." `confirmLabel:'Archive'` `variant:destructive` `requireTypedConfirmation:'ARCHIVE'`; and a sm `AppButton` "Financial" → `AppConfirmationDialog` title "Void invoice INV-2026-0842?" description "This voids EGP 1,850.00 and cannot be undone." `confirmLabel:'Void invoice'` `variant:financial`). `componentName: 'Dialog / ConfirmationDialog'`.
- **Drawer / sheet** — single `AppButton` "Open drawer" opening `AppDrawer` title "Patient detail" description "Side panel without leaving context" footer Close-button, body "Detail content for patient Layla Hassan." (use EN/AR copy). `componentName: 'Drawer'`.
- **Popover** — `AppPopover` with `AppButton` (secondary sm) trigger "Open popover" and content `Padding(p-4, Text('Quick edit or filter content.', bodySm/textSecondary))`. `componentName: 'Popover'`. No `ShowcaseDemoGrid` (single inline trigger, matches web).
- **Loading overlay** — single `ShowcaseDemo` "Scoped": `AppLoadingOverlay(loading: scoped, scoped: true, label: 'Loading patients…')` wrapping a `Card`-equivalent (h-32 w-full) containing "Content beneath overlay", plus an `AppButton` (ghost sm) "Toggle loading" that flips `scoped`. `componentName: 'LoadingOverlay'`.
- **Empty states** — 2-col `ShowcaseDemoGrid`, 4 `AppEmptyState` one per variant `first-run`/`no-results`/`no-access`/`error`; only `first-run` gets `action: {label:'Add patient'}` and `shortcutHint: ['⌘','N']`; others use default title/description per variant config. `componentName: 'EmptyState'`.
- **Error state** — single `AppErrorState` with `message: 'We could not load appointments. Check your connection and try again.'` and `onRetry: () => {}`. `componentName: 'ErrorState'`.

## 5. Wiring steps (do after each phase's widgets land)

1. `component_registry.dart` — for each finished `id` (`toast`, `alert`, `dialog`, `drawer`, `popover`, `loading-overlay`, `empty-state`, `error-state`; ids already present at lines 393–440 as placeholders), change `status: ShowcaseSectionStatus.placeholder` → `ShowcaseSectionStatus.ready` (keep order).
2. `component_section_builders.dart` — add an entry per ready id in `componentSectionBuilders`, grouped under a `// Feedback & overlays` comment (mirroring the existing Actions/Inputs blocks), e.g. `'toast': () => const ToastShowcaseSection(),` … `'error-state': () => const ErrorStateShowcaseSection(),`. Reuse the exact `'id'` strings from `component_registry.dart`.
3. Import the new section files at the top of `component_section_builders.dart` under the `// Feedback & overlays` comment.
4. Append new `app_*.dart` core files to `widgets.dart` under a `// Feedback & overlays` sub-comment (after the existing Inputs block, before Motion).
5. Phase 2 only: mount `AppToastHost` at the app root (e.g. wrap `MaterialApp`'s `builder` or the top-level `Material`) if no host is already present — the toast showcase and feature code depend on it.
6. Run `flutter analyze` (project uses `flutter_lints`) on changed files; fix lints. Do **not** commit unless asked.

## 6. Out-of-scope / defer

- The `forui`-based wrappers described in `docs/ui/forui-wrappers.md` are not built or reconciled here.
- Toast queue micro-interactions beyond `slideUp` + max-3 + auto-dismiss (e.g. hover-to-pause, swipe-to-dismiss, reordering via `AnimatePresence popLayout`) are deferred — keep `slideUp` enter/exit + auto-dismiss only, matching the minimal motion set already in `AppMotion`.
- Drawer non-modal (`modal:false`) inline-anchored variant: implement the API surface but the showcase only exercises the default `inline-end` modal mode; non-modal placement in real feature shells is deferred.
- Display-group `tooltip`/`kbd`/`chip` own showcase sections belong to the Display milestone; only their primitives (already shipped) are reused here.
- Full focus-trap parity with web (`trapFocus` tab cycling) — Material `showDialog`/`showGeneralDialog` provide focus management; explicit first-focus + Esc are wired, but a custom roving tab-trap is deferred unless accessibility audit requires it.
- No new architectural patterns beyond the justified `AppToastHost` toast service and the `AppSemanticColors` status-token extension.

## 7. Source reference — web widget inventory

The 8 widgets in `web-reference/src/showcase/components/feedback/index.ts`:

| id | Title | Showcase file | Underlying UI component |
|---|---|---|---|
| `toast` | Toast | `FeedbackShowcase.tsx` (`ToastShowcase`) | `components/toast/Toast.tsx` (`ToastProvider` + `useToast` + `ToastView`) |
| `alert` | Inline alert | `FeedbackShowcase.tsx` (`AlertShowcase`) | `components/alert/Alert.tsx` (`Alert`) |
| `dialog` | Dialog | `FeedbackShowcase.tsx` (`DialogShowcase`) | `components/dialog/Dialog.tsx` (`Dialog` + `ConfirmationDialog`) |
| `drawer` | Drawer / sheet | `FeedbackShowcase.tsx` (`DrawerShowcase`) | `components/drawer/Drawer.tsx` (`Drawer`) |
| `popover` | Popover | `FeedbackShowcase.tsx` (`PopoverShowcase`) | `components/ui/popover/Popover.tsx` (Radix `@radix-ui/react-popover` + motion) |
| `loading-overlay` | Loading overlay | `FeedbackShowcase.tsx` (`LoadingOverlayShowcase`) | `components/loading-overlay/LoadingOverlay.tsx` (`LoadingOverlay`) |
| `empty-state` | Empty states | `FeedbackShowcase.tsx` (`EmptyStateShowcase`) | `components/empty-state/EmptyState.tsx` (`EmptyState`) |
| `error-state` | Error state | `FeedbackShowcase.tsx` (`ErrorStateShowcase`) | `components/error-state/ErrorState.tsx` (`ErrorState`) |

Shared web building blocks (Flutter equivalents proposed in §2):
- `components/ui/spinner/Spinner.tsx` — lucide `Loader2` spinner (Flutter: `CircularProgressIndicator`, already used across inputs).
- `components/ui/popover/Popover.tsx` — Radix+motion fade-scale popover (Flutter: `AppPopover`, already shipped — reused verbatim by the Popover showcase).
- `components/kbd/Kbd.tsx` — keyboard glyph (Flutter: `AppKbd`, already shipped — reused by EmptyState `shortcutHint`).
- `lib/motion` (`motionPresets`, `resolveTransition`, `getReducedMotion`) — `modal`/`drawer`/`slide-up`/`fade`/`fade-scale` (Flutter: `AppMotion` presets in `core/ui/motion/app_motion.dart`).
- `lib/focus-trap` `trapFocus` — Dialog/Drawer focus cycling (Flutter: deferred to Material focus management, see §6).
- `lib/cn` — class merge (Flutter: N/A, conditional `Color`/`BoxDecoration`).
- Radix primitives (`Popover.Root/Trigger/Content`) — overlay primitives (Flutter: `Overlay`/`OverlayEntry` + `CompositedTransformFollower`).
- `lucide-react` icons → Flutter `Icons` equivalents noted per widget in §2/§3.

Cross-cutting web notes (inform the Flutter port):
- `Alert`/`Toast` use a `variant → {container, icon}` record; AI variant reuses `surface-ai`/`text-ai`/`border-ai` tokens (already present as `surfaceAi`/`textAi`/`borderAi`).
- `EmptyState` has 4 variants each with a default `icon`/`title`/`description` (overridable); only `first-run` exercises `action` + `shortcutHint` in the showcase.
- `ErrorState` is the single-variant danger sibling of `EmptyState` with `onRetry` + `retryLabel='Try again'` + `RefreshCw` leading icon.
- `LoadingOverlay` distinguishes `scoped` (absolute over children, `rounded-[inherit]`) vs non-scoped (fixed full-screen at `z-modal`).
- `Dialog` sizes: sm=`max-w-sm`, md=`max-w-lg`, lg=`max-w-2xl`, full=`calc(100vw-2rem)×calc(100dvh-2rem)`; `ConfirmationDialog` is always size `sm`.
- `Drawer` sides: `inline-end` (default, RTL-aware), `inline-start`, `bottom` (sheet, `max-h-85dvh`, rounded top); `modal` toggle controls backdrop.
- `Toast` stacks bottom-`end` fixed, `aria-live=polite`, max 3, danger→8s others→4s, optional `action` link + dismiss `IconButton`.
- i18n/RTL: Drawer side + toast `end-4` anchor mirror under `ar`; `requireTypedConfirmation='ARCHIVE'` stays Latin in both locales (web parity).
