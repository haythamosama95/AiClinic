# Implementation Plan — Auth → Login Page (Flutter Port)

Spec target: port the **Login page** of `web-reference/src/pages/auth/LoginPage.tsx` into the Flutter `frontend/` App abstraction layer, surfaced as the `/login` route (V1-1, US1 sign-in). Single phase.

> ⚠️ **Set-specific runtime regressions.** This page embeds `AppTextInput`, `AppPasswordInput`, `AppButton`, and a motion backdrop + focus trap. Before coding, confirm the group-specific regressions to avoid (consult `docs/ui/memory/ui-runtime-errors.md` only when explicitly instructed):
> - The login page renders **outside** `AuthenticatedShell` (no `Scaffold`/`Material` from the shell) → embed inputs inside a `Scaffold` so the Material primitive ancestors (TextField, InkWell) are valid (memory §1, §23). `AppTextInput`/`AppPasswordInput` already wrap their `TextField` in `appWrapMaterialInput`, but the **link buttons** (`AppButton variant: link` "Forgot your password?" and the carousel `IconButton`s) need a `Material` ancestor for ink.
> - The page hosts a carousel using `AnimationController` → initialize the controller with a static `AppMotion.resolveDuration(...)` in `initState` and only defer `forward()` to `didChangeDependencies` after applying reduced-motion (memory §2, §27). Never read `MediaQuery` (reduced motion) in `initState`.
> - A `FocusScope`/`FocusTraversalPolicy` around the form is the Flutter analog of the web `trapFocus`. Do **not** share one `FocusNode` between an ancestor `Focus` and a descendant `TextField` (memory §4); keep `FocusNode` only on the `TextField`.
> - The page builds a backdrop `BackdropFilter` + `ColoredBox`: gate blur on `AppMotion.prefersReducedMotion(context)` and on `widget.blur`, exactly like `_AppDialogTransition` (memory §27).
> - Loading state on submit reuses `AppButton(loading: true)`; the button locks its width during loading already (`AppButton` §`_lockedWidth`), so no custom ~600 ms simulated delay is needed when wiring to `authNotifierProvider`.

## 0. Ambiguities & Design Decisions (resolve before coding)

1. **forui vs native Material.** As with the Actions / Inputs groups, the shipping convention is **native Material**. `forui` is imported nowhere. **Decision: native Material only.**

2. **Where the login page lives in the router.** Today `AppRoutes.login` is registered *inside* the `ShellRoute` whose builder is `AuthenticatedShell` (`app/router.dart:54`), so the placeholder renders with sidebar + top bar. The web `LoginPage` is a full-screen chrome-less portal (`fixed inset-0 z-[2000]`, no shell).
   **Decision: hoist `/login` (and only `/login`) out of the `ShellRoute` into a top-level `GoRoute` parallel to the shell route.** The redirect logic in `app/router.dart` keys off `state.matchedLocation == AppRoutes.login` / `AppRoutes.forgotPassword`, not on the route's parent, so hoisting does not change redirect behavior. `forgotPassword` is a `redirect → '${login}?forgot=1'` alias; leave it where it is (it resolves into the login page's `forgot` query param). The post-auth redirect (login → home when already authenticated, `auth_route_guard.dart:510`) stays intact.

3. **Not a `showDialog` modal.** The web uses `createPortal(... , document.body)` only because the showcase app has no router; in Flutter this is a real route page. **Decision: render as a normal `MaterialApp` route page** (`Scaffold` with `resizeToAvoidBottomInset: true`), **not** via `AppDialog.show`. The backdrop fade + panel `modal` motion are reproduced with an `AnimationController` + `AppMotion.animatedPreset(AppMotionPreset.modal)` on mount, mirroring `_AppDialogShell` but without the `Navigator.pop`/barrier-dismiss machinery (the login route is not dismissible by tapping outside).

4. **Split layout + the testimonial carousel.** Web uses a two-column `lg:grid-cols-2` grid: left = scrollable form column, right = full-bleed testimonial image carousel (hidden below `lg`). **Decision:** use `LayoutBuilder`; at `width >= 960` (`lg`) render the two-column `Row`, otherwise render only the form column centered (the carousel is decorative, `aria-hidden`, and not needed on mobile). The carousel is a single-image `Stack` with prev/next `IconButton`s and an `AnimatePresence`-equivalent `AnimatedSwitcher` (fade + horizontal slide via `AppMotionPreset.slideInline`).

5. **Carousel images from Unsplash URLs.** The web loads 3 remote Unsplash images. Flutter can fetch them over HTTP, but relying on network images on the auth screen (before any session, possibly offline) is fragile. **Decision: bundle three local testimonial images under `assets/images/auth/`** and declare them in `pubspec.yaml`. Fall back to a `colors.surfaceMuted` placeholder `ColoredBox` while the asset decodes. Keep the same 3 quote/name/title/organization strings verbatim from the web file.

6. **AiClinicMark brand mark.** There is no brand/logo App widget today (search for `brand`/`mark`/`logo` in `lib/core/ui` returns nothing). The web `AiClinicMark` is reused (a stethoscope glyph in a primary square + "Ai" + green "Clinic" wordmark). **Decision: introduce a new `AppBrandMark`** under `core/ui/components/` and export it from `widgets.dart`, so the future app shell / sidebar can reuse it.

7. **i18n / RTL.** The login form is bidi-agnostic via `Directionality.of(context)`. The carousel prev/next buttons must mirror in RTL (left ↔ right) — use `Icons.arrow_back`/`arrow_forward` resolved through `Directionality` and `AppMotionPreset.slideInline` (`hidden()` already honors `direction`). The footer "© AiClinic Health Group" and the copy strings stay English (no AR translation is required for V1-1; the auth strings in `auth_notifier.dart` and `staff_username.dart` are already English-only).

8. **Submit wiring.** Do not reimplement the web's `setTimeout(600)` mock loading. **Decision: wire the form directly to `authNotifierProvider.signIn`** (`features/auth/presentation/providers/auth_notifier.dart`). It already sets `isSubmitting`/`errorMessage`, normalizes + validates the username (`validateStaffUsername`), and waits for post-login resolution. The submit button's `loading` bind to `authState.isSubmitting`; an inline error lives in an `AppFormField error` slot OR a centered `AppAlert` (variant error) above the form — see §3.

9. **Focus trap.** The web `trapFocus` constrains Tab cycling inside the dialog. In Flutter, a `FocusScope` with `FocusTraversalOrder` on each focusable child + `OnKey`/`FocusNode.onKeyEvent` to wrap Tab is the analog. **Decision:** wrap the whole page in a `FocusScope` with a `OrderedTraversalPolicy` and let Flutter's default traversal handle Tab order; do not manually reinvent tab wrapping unless QA finds broken cycling. Ancestors `Focus` widgets must **not** carry the `TextField`'s `FocusNode` (memory §4).

## 1. Existing App assets to reuse (do not recreate)

| Asset | Path | Used by |
|---|---|---|
| `AppButton` (`primary`/`link`, `lg`, `loading`) | `core/ui/components/app_button.dart` | submit + "Forgot your password?" |
| `AppFormField` (`label`, `requiredMark`, `error`, `helperText`) | `core/ui/components/app_form_field.dart` | username + password fields |
| `AppTextInput` (`size: lg`, `placeholder`, `onChanged`, `id`) | `core/ui/components/app_text_input.dart` | username control |
| `AppPasswordInput` (`size: lg`, `placeholder`, `onChanged`, `id`, reveal toggle + caps-lock hint) | `core/ui/components/app_password_input.dart` | password control (web's reveal + Caps Lock hint already match 1:1) |
| `AppAlert` (`variant: error`) | `core/ui/components/app_alert.dart` | sign-in failure banner (optional — see §3) |
| `AppIconButton` | `core/ui/components/app_icon_button.dart` | carousel prev/next |
| Theme: `context.appColors` (`AppSemanticColors`), `AppSpacing`, `AppRadius`, `AppTypography`, `AppElevation` | `core/ui/theme/*` | every region |
| `AppMotion` (`AppMotionPreset.modal`/`.fade`/`.slideInline`, `prefersReducedMotion`, `animatedPreset`, `resolveDuration`) | `core/ui/motion/app_motion.dart` | backdrop + panel + carousel transitions |
| `BackdropFilter` + `ColoredBox` backdrop pattern | reference: `app_dialog.dart` `_AppDialogTransition` | informs the login backdrop (`surfaceBackdrop/60`, blur-2px gated on reduced motion) |
| `authNotifierProvider` + `AuthUiState` (`isSubmitting`, `errorMessage`) | `features/auth/presentation/providers/auth_notifier.dart` | submit + error + loading |
| `validateStaffUsername`, `normalizeStaffUsername`, `staffUsernameRequirements` | `features/auth/domain/staff_username.dart` | username field validation helper text |
| `AppRoutes.login` / `AppRoutes.home` / `AppRoutes.forgotPassword` | `app/app_routes.dart` | navigation on submit + forgot link |
| `context.go` / `context.goNamed` (go_router) | `package:go_router` | post-login redirect (handled by router `refreshListenable` once `authSession` flips authenticated) |

## 2. New shared abstractions to introduce

| File (`lib/core/ui/components/`) | Export name | Web analog | Purpose |
|---|---|---|---|
| `app_brand_mark.dart` | `AppBrandMark({bool compact})` | `components/brand/AiClinicMark.tsx` | primary-filled `AppRadius.lg` square with `Icons.medical_services` (stethoscope analog) + "Ai" `textPrimary` + "Clinic" `textLink` wordmark. `compact: false` → 36px square, 18px icon, h3 wordmark; `compact: true` → 32px square, 16px icon, no wordmark. |

Feature-side files (not shared, but new):

| File (`lib/features/auth/presentation/`) | Export name | Purpose |
|---|---|---|
| `pages/login_page.dart` | `LoginPage` (`ConsumerStatefulWidget`) | the route widget; owns local `username`/`password` controllers, the carousel `AnimationController`/page index, and the enter animation; reads `authNotifierProvider`. |

**Barrel update:** append `app_brand_mark.dart` to `lib/core/ui/widgets/widgets.dart` under a new `// Brand` sub-comment (or the existing `// Components` block — match the existing grouping style).

## 3. Phase 1 — Login page (single phase)

> Rationale: the login page is one self-contained route. All underlying controls (`AppButton`, `AppFormField`, `AppTextInput`, `AppPasswordInput`) and the notifier already exist; the only new primitives are `AppBrandMark` (shared) and `LoginPage` (feature). No multi-phase split is needed.

| Region | Flutter widget(s) | File(s) | Reuse | Wrapper | Deps |
|---|---|---|---|---|---|
| Brand mark | `AppBrandMark` | CREATE `core/ui/components/app_brand_mark.dart`; MOD `widgets.dart` | `colors.actionPrimary`/`actionPrimaryFg`, `AppRadius.lg`, `AppTypography.h3`, `AppSpacing.space2` | NEW | none |
| Backdrop | `_Backdrop` (private) inside `LoginPage` | CREATE `features/auth/presentation/pages/login_page.dart` | `AppMotionPreset.fade`, `AppMotion.prefersReducedMotion`, `colors.surfaceBackdrop` (60% alpha), `BackdropFilter(blur 2px)` gated on reduced motion | NEW (private) | `AppMotion`, theme |
| Dialog panel | `_LoginPanel` (`Material` + `DecoratedBox`, `AppRadius.x2l`, `colors.borderDefault`, `colors.surfaceDefault`, `context.appElevation.decoration(level: 3, …)` for `shadow-elevation-3`) | same file | `AppMotionPreset.modal` enter animation, `AppMotion.animatedPreset` | NEW (private) | backdrop |
| Form column | `SingleChildScrollView` + `Column` (gap `AppSpacing.space6`): header → title/subtitle → `Form` → footer | same file | `AppBrandMark`, `AppTypography.h1`/`body`/`caption`, `AppSpacing.space8`/`space6`/`space5`, `colors.textPrimary`/`textSecondary`/`textTertiary` | NEW (private) | brand, controls |
| Username field | `AppFormField(id: 'login-username', label: 'Username', requiredMark: true, helperText: staffUsernameRequirements)` wrapping `AppTextInput(size: lg, placeholder: 'Enter your username', keyboardType: TextInputType.text, textInputAction: TextInputAction.next, onChanged: …)` | same file | `AppFormField`, `AppTextInput`, `validateStaffUsername` for live-ish guidance | extend (use) | `app_form_field`, `app_text_input` |
| Password field | `AppFormField(id: 'login-password', label: 'Password', requiredMark: true)` wrapping `AppPasswordInput(size: lg, placeholder: 'Enter your password', textInputAction: TextInputAction.done, onChanged: …)` | same file | `AppFormField`, `AppPasswordInput` | extend (use) | `app_form_field`, `app_password_input` |
| Forgot-password link | `Align(centerEnd)` → `AppButton(variant: link, size: md, onPressed: () => context.go(AppRoutes.forgotPassword), child: Text('Forgot your password?'))` | same file | `AppButton` link variant | extend (use) | `app_button` |
| Submit button | `SizedBox(width: double.infinity)` → `AppButton(variant: primary, size: lg, loading: authState.isSubmitting, onPressed: _submit, child: Text('Log in'))` | same file | `AppButton`, `authNotifierProvider` | extend (use) | `app_button`, notifier |
| Sign-in error | `AppAlert(variant: AppAlertVariant.error, title: authState.errorMessage)` above the form (or wire into a per-field `AppFormField error: <username message>` when the notifier returns a field-specific message) | same file | `AppAlert` | extend (use) | `app_alert`, notifier |
| Carousel column (lg only) | `_TestimonialCarousel` (`StatefulWidget`): `Stack` with `Image.asset` (cover) + gradient `Container` + glass card `ClipRRect(AppRadius.x2l)` containing `AnimatedSwitcher` (slideInline) for quote/name/meta + 5× `Icon(Icons.star)` + prev/next `AppIconButton` (`Icons.arrow_back`/`arrow_forward` resolved by `Directionality`) | same file | `AppIconButton`, `AppMotionPreset.slideInline`, `AppTypography.h2`/`bodyStrong`/`bodySm`, `colors.*` | NEW (private, page-local) | `AppMotion`, `AppIconButton` |
| Focus trap | `FocusScope` with `OrderedTraversalPolicy` wrapping the panel; `FocusNode.onKeyEvent` on the submit button to submit on Enter; wrap Tab wrap-around only if QA finds broken cycling | same file | `FocusScope`, `FocusTraversalPolicy` | extend (use) | none |

Showcase/Dev page: **not applicable** — the login page is a feature route, not a Dev components showcase entry, so there is no `component_registry.dart` / `component_section_builders.dart` work.

## 4. Page instantiation spec (mirrors web reference)

> **Binding source of truth:** `web-reference/src/pages/auth/LoginPage.tsx` is the binding source to reproduce, region-for-region. The web file is a single full-screen portal; the Flutter port renders the same regions in the same order, with the same copy, the same `lg` two-column breakpoint (960px), and the same 3 testimonials in the same order. Web motion presets map 1:1: `motionPresets.fade` → `AppMotionPreset.fade`, `motionPresets.modal` → `AppMotionPreset.modal`, the custom carousel `enter/center/exit` (x: ±500, opacity 0→1, tween 0.8s ease `[0.8,0,0.2,1]`) → `AppMotionPreset.slideInline` (closest match; tuned duration 800ms, curve `AppMotionEasing.emphasized`).

Region-by-region (copy EN strings verbatim from the web file):

- **Backdrop** — `position: full`, `colors.surfaceBackdrop` at alpha 0.6, optional `BackdropFilter(blur: ImageFilter.blur(sigmaX: 2, sigmaY: 2))` gated on `!AppMotion.prefersReducedMotion(context)`. Fade in on mount.
- **Panel** — max width 960, `AppRadius.x2l` (`rounded-2xl`), `colors.borderDefault`, `colors.surfaceDefault`, `context.appElevation.decoration(level: 3)` (matches `shadow-elevation-3`). At `lg`: two-column `Row` (`lg:grid-cols-2`), `maxHeight: min(90dvh, 680)`; below `lg`: single column, scrollable.
- **Header** — `AppBrandMark()` (web `<AiClinicMark />`).
- **Title** — `h1` `colors.textPrimary`: **"Welcome back"**.
- **Subtitle** — `AppTypography.body` `colors.textSecondary`: **"Sign in with your clinic credentials to continue."**.
- **Form** (gap `space6` between title block, fields block, forgot link, submit):
  - Fields block (gap `space5`):
    - `AppFormField(id: 'login-username', label: 'Username', requiredMark: true, helperText: staffUsernameRequirements)` → `AppTextInput(size: lg, placeholder: 'Enter your username', keyboardType: text, textInputAction: TextInputAction.next)`.
    - `AppFormField(id: 'login-password', label: 'Password', requiredMark: true)` → `AppPasswordInput(size: lg, placeholder: 'Enter your password', textInputAction: TextInputAction.done)`.
  - Forgot link: `Align(centerEnd)` → `AppButton(variant: link, size: md, onPressed: () => context.go(AppRoutes.forgotPassword))` → **"Forgot your password?"**.
  - Submit: full-width `AppButton(variant: primary, size: lg, loading: authState.isSubmitting, onPressed: _submit)` → **"Log in"**.
- **Footer** — `AppTypography.caption` `colors.textTertiary`: **"© AiClinic Health Group"**.
- **Carousel column** (lg only, `minHeight: 420`):
  - Image covers the column (`Image.asset` of the bundled testimonial asset, `BoxFit.cover`, `aria-hidden`).
  - Gradient overlay: bottom-up black 45% → transparent (`LinearGradient(begin: bottomCenter, end: topCenter, colors: [Colors.black45, Colors.transparent])`).
  - Glass card: `ClipRRect(AppRadius.x2l)` on `Container(color: Colors.black25, ring: Border.all(color: Colors.white30))` + `BackdropFilter(blur: moderate)`, padding 20/20, gap `AppSpacing.space6`:
    - `AnimatedSwitcher` quote: **quotes verbatim from `testimonials[*].quote`**, `h2` white, `text-balance`.
    - Row: `AnimatedSwitcher` name (white, `bodyStrong`) + 5× `Icon(Icons.star, size: 16, color: white)` (hidden below md → below `lg` it is always shown since the whole column is lg-only).
    - Row: `AnimatedSwitcher` (title `bodyStrong` white + organization `bodySm` white85) + prev/next `AppIconButton(ghost, Icons.arrow_back/forward, 44px circle, border white50, hover white70)`.
  - Prev/next cycle through the 3 testimonials with `wrapIndex(0, testimonials.length, page ± 1)`.
- **Enter animation** — `AppMotionPreset.modal` (opacity + scale 0.97 + y:8), `resolveDuration(AppMotionPreset.modal)`; `forward()` from `didChangeDependencies` after `AppMotion.prefersReducedMotion` adjustment (memory §2).
- **Reduced motion** — when `AppMotion.prefersReducedMotion(context)` is true, skip blur, skip carousel slide animation (cross-fade only or instant).

State & handlers (mirror web's `useState`/`handleSubmit`):
- Local controllers for `username` / `password` (use `TextEditingController` on the inputs OR pass `onChanged` and keep local `String` state — match how other feature pages drive `AppTextInput`; prefer controllers for autofill).
- `_submit()`: `ref.read(authNotifierProvider.notifier).signIn(username: _username.text, password: _password.text)`. Do **not** call `context.go(AppRoutes.home)` directly — the router's `refreshListenable` (rebuilt on `authSessionProvider` change) redirects to `/home` once `isAuthenticated` becomes true (`auth_route_guard.dart:510`).
- `clearSignInError()` on any field `onChanged` to dismiss the banner while typing (`auth_notifier.dart:144`).
- `resetSignInForm()` in `dispose` (`auth_notifier.dart:150`) to clear transient state on leave.

## 5. Wiring steps (do after the page + brand mark land)

1. **`app/router.dart`** — move the `AppRoutes.login` `GoRoute` out of the `ShellRoute.routes` list to a **sibling** top-level route:
   ```dart
   routes: [
     GoRoute(
       path: AppRoutes.login,
       builder: (context, state) => const LoginPage(),
     ),
     ShellRoute(
       builder: (context, state, child) => AuthenticatedShell(child: child),
       routes: [
         // remove the old login GoRoute here; keep everything else
         ...
       ],
     ),
   ],
   ```
   Leave `AppRoutes.forgotPassword` as a `redirect → '${AppRoutes.login}?forgot=1'` (it currently lives in the shell route; move it to the top-level too, alongside login, or keep its redirect target `AppRoutes.login` working — verify the redirect fires for unauthenticated users via `isPublicUnauthenticatedRoute`, which already lists both). Add `import 'package:ai_clinic/features/auth/presentation/pages/login_page.dart';`.
2. **`widgets.dart`** — append `export 'package:ai_clinic/core/ui/components/app_brand_mark.dart';` (under a `// Brand` comment or the `// Components` block).
3. **`pubspec.yaml`** — add the three bundled testimonial images under `assets:`:
   ```yaml
   - assets/images/auth/testimonial_1.jpg
   - assets/images/auth/testimonial_2.jpg
   - assets/images/auth/testimonial_3.jpg
   ```
   Drop the corresponding files under `frontend/assets/images/auth/`.
4. **No `component_registry.dart` / `component_section_builders.dart` changes** — not a Dev showcase entry.
5. **Run `flutter analyze`** (`flutter_lints`) on the new/changed files; fix lints. Do **not** commit unless asked.
6. **Smoke test:** launch unauthenticated → land on `/login`; enter creds → submit → loading spinner on button → on success router redirects `/home`; on failure banner appears and clears on typing; carousel prev/next cycle at `lg`; below `lg` only the form column shows; reduced-motion (toggled via platform or `MediaQuery.disableAnimationsOf`) disables blur + carousel slide.

## 6. Out-of-scope / defer

- **Forgot-password UI** — `/forgot-password` currently redirects to `/login?forgot=1`. The web `LoginPage` ignores the `forgot` query param (the forgot flow is a separate screen in the showcase nav). A real forgot-password page is a later milestone; the login page only needs the link + the redirect alias.
- **AR localization of the login copy** — V1-1 ships English-only copy (matches `auth_notifier.dart`/`staff_username.dart`); add AR strings when the l10n story for auth lands.
- **Remote Unsplash carousel images** — bundled assets only for V1-1; revisit network images when a CMS-backed testimonial feed exists.
- **Post-reset-password deep link from email** — not part of the login page surface.
- **`AppBrandMark` reuse in sidebar/top bar** — created here as a shared primitive, but wiring it into the shell is a separate task (do not touch `app_sidebar.dart`/`app_top_bar.dart` in this phase).
- **Idle-timeout / sign-out-from-elsewhere landing copy** — handled by `authSessionProvider` failure messages routed through the home placeholder; not surfaced on the login page beyond the generic error banner.

## 7. Source reference — web inventory

The login page is a single composite screen (not a registry group), so the inventory is per-region:

| Region | Web source | Underlying web component | Flutter port |
|---|---|---|---|
| Brand mark | `components/brand/AiClinicMark.tsx` (`Stethoscope` lucide, `compact?`) | — | `AppBrandMark` (new) |
| Backdrop | `LoginPage.tsx` lines 130–140 (`motion.div` fade, `bg-surface-backdrop/60`, `backdrop-blur-[2px]`) | `motionPresets.fade`, `cn` | `_Backdrop` (private) using `AppMotionPreset.fade` |
| Panel | `LoginPage.tsx` lines 142–154 (`motion.div` `motionPresets.modal`, `rounded-2xl`, `shadow-elevation-3`, `lg:grid-cols-2`) | `motionPresets.modal` | `_LoginPanel` using `AppMotionPreset.modal`, `AppRadius.x2l`, `AppElevation.level3` |
| Username field | `LoginPage.tsx` lines 172–183 (`FormField` + `TextInput size=lg`) | `components/ui/form-field/FormField.tsx`, `components/ui/text-input/TextInput.tsx` | `AppFormField` + `AppTextInput` |
| Password field | `LoginPage.tsx` lines 185–196 (`FormField` + `PasswordInput size=lg`) | `components/ui/form-field/FormField.tsx`, `components/ui/password-input/PasswordInput.tsx` (reveal toggle + Caps Lock hint) | `AppFormField` + `AppPasswordInput` (already 1:1 incl. Caps Lock hint) |
| Forgot link | lines 200–208 | `components/actions/Button.tsx` `variant=link` | `AppButton(variant: link)` |
| Submit button | lines 211–213 (`Button type=submit size=lg loading=…`) | `Button` + `Spinner` | `AppButton(variant: primary, size: lg, loading: …)` |
| Carousel | lines 220–310 (`<img>`, gradient + glass card, `AnimatePresence` + `motion.blockquote`/`motion.p`/`motion.div`, 5× `Star`, prev/next ArrowLeft/ArrowRight) | `lucide-react` (`ArrowLeft`/`ArrowRight`/`Star`), `lib/motion.ts` (`motionPresets`, custom `carouselVariants`/`carouselTransition`), `cn` | `_TestimonialCarousel` (`AnimatedSwitcher` + `AppMotionPreset.slideInline`, bundled assets) |
| Focus trap | lines 100–108 (`useEffect` → `document.addEventListener('keydown', …)` → `trapFocus`) | `lib/focus-trap.ts` | `FocusScope` + `OrderedTraversalPolicy` (no manual Tab rewrite unless QA fails) |
| Submit mock | lines 119–126 (`handleSubmit` → `setLoading(true)` → `setTimeout(600)` → `onLogin?.()`) | `useState` | `authNotifierProvider.signIn` (replaces the mock) |

Shared web building blocks and their Flutter equivalents:
- `cn` (className merge) → N/A (Flutter uses composition; theme tokens via `context.appColors`/`AppSpacing`/`AppRadius`/`AppTypography`).
- `motionPresets` + `resolveTransition` + `getReducedMotion` → `AppMotion` (`AppMotionPreset`, `resolveDuration`/`resolveCurve`, `prefersReducedMotion`, `animatedPreset`) — 1:1 token parity (`lib/motion.ts` ↔ `core/ui/motion/app_motion.dart`).
- `createPortal` (document.body) → N/A (Flutter route; hoisted out of `ShellRoute`).
- `useId`/`aria-labelledby`/`aria-describedby`/`role="dialog"`/`aria-modal` → `Semantics(scopesRoute: true, explicitChildNodes: true, labelledBy: …)` on `_LoginPanel` + `Semantics(header: true)` on the title.
- `lucide-react` icons → `Icons.medical_services` (stethoscope analog), `Icons.arrow_back`/`arrow_forward`, `Icons.star`.
- `trapFocus` → `FocusScope` + `OrderedTraversalPolicy`.
- `input-base/input-styles.ts` → `app_input_styles.dart` (already used by `AppTextInput`/`AppPasswordInput` — no direct use in `LoginPage`).