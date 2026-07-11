# Implementation Plan — Dev → Components → AI (Flutter Port)

Spec target: port the **AI** group of `web-reference/` into the Flutter `frontend/` App abstraction layer, surfaced in the Dev components page. The web group has 6 sections: `ai-mode-toggle`, `ai-panel`, `ai-message-bubble`, `proposed-action-card`, `ai-suggestion`, `thinking-indicator`.

> Phase count: user requested **two phases** (`divide it into two phases only`). The skill's default 3-phase split is overridden here: phase 1 lands the atomic AI atoms + the standalone toggle; phase 2 lands the two composite workflow surfaces that build on phase 1.

## 0. Ambiguities & Design Decisions (resolve before coding)

> ⚠️ **Read `docs/ui/memory/ui-runtime-errors.md` end-to-end before writing a single AI file.** Surface the items below as the regression hot-spots for THIS group.

1. **forui vs native Material.** Same as the prior groups: `forui` is declared in `pubspec.yaml` but imported nowhere; the shipped App widgets are native Material under `core/ui/components/app_*.dart`. `docs/ui/forui-wrappers.md` is superseded.
   **Decision: follow the shipping Actions/Inputs/Display convention (native Material). Do not introduce forui.**

2. **Core file layout.** Existing App widgets are flat (`core/ui/components/app_<name>.dart`). Showcase sections use a `<group>/` subfolder (see `components/actions/`, `components/inputs/`, `components/display/`).
   **Decision: keep both conventions.** New core files: `app_ai_mode_toggle.dart`, `app_thinking_indicator.dart`, `app_ai_suggestion.dart`, `app_ai_message_bubble.dart`, `app_ai_panel.dart`, `app_proposed_action_card.dart`. New showcase subfolder: `features/design_system/presentation/components/ai/`.

3. **No new shared abstraction is required.** AI components are compositions of already-shipped primitives (`AppButton` (incl. `AppButtonVariant.ai`), `AppIconButton` (incl. `AppIconButtonVariant.ai`), `AppCard` (incl. `CardVariant.ai`), `AppBadge` (incl. `BadgeColor.ai`), `AppSignal` (incl. `AppSignalVariant.ai`), `AppFormField`, `AppTextInput`, `CircularProgressIndicator` for the web `Spinner`). The semantic AI tokens already exist on `AppSemanticColors` (`surfaceAi`, `borderAi`, `textAi`, `actionAi`, `actionAiHover`, `actionAiFg`, `signalColorAi`). **No new `app_*` shared widget is introduced for cross-group reuse** — each AI widget is a self-contained composition file.

4. **`AiModeToggle` provenance.** On the web this component lives under `navigation/AiModeToggle.tsx` and reads `useAiMode()` from `AiModeProvider`. In `registry.ts` it is filed under group `ai`. The Flutter port keeps it under the AI group (mirrors `component_registry.dart` group assignment) and lifts the mode value into the widget itself instead of a Riverpod provider: `AppAiModeToggle` is `StatefulWidget` with internal `aiMode` state plus optional `value`/`onChanged` for controlled use, exactly like the other controlled/uncontrolled App widgets. The showcase demo renders two toggles (default + `showLabel: false`) — both can manage their own internal state for the demo, matching how the actions showcases drive `AppButton` hover/press internally.

5. **`AppAiPanel` internal input.** Web uses a raw `<input>` with `focus-ring-ai` styling (violet border + ai focus ring). Flutter has no `AppTextInput` variant for an "ai focus ring"; introducing one would be over-engineering for one demo cell. **Decision:** use the existing `AppTextInput` (which already wraps its `TextField` in `Material` per memory entry #1) and override the border via `inputDecoration` to read `colors.borderAi`/`colors.actionAi` for the focused border. This keeps the Material-ancestor guarantee, mirrors the violet ring, and avoids a new variant. The header `Signal` and inner `ThinkingIndicator`/`AiMessageBubble` reuse phase 1 widgets directly.

6. **i18n / RTL.** Showcase copy is bilingual EN/AR via `ref.watch(devPreviewProvider).locale`, mirroring the `_copyEn`/`_copyAr` convention established in `button_showcase_section.dart` and used in `card_showcase_section.dart`. All AI widgets must stay direction-agnostic via `Directionality.of(context)` and `EdgeInsetsDirectional`/`AlignmentDirectional`. The `AiMessageBubble` aligns user messages to the **end** and assistant messages to the **start** (web `justify-end`/`justify-start`) — use `MainAxisAlignment.end`/`.start` inside a `Row` so it flips with RTL automatically. The `AiPanel` input's `Send` icon button sits at the **end** of the composer row (no manual mirroring).

7. **Controlled/uncontrolled.** `AppAiModeToggle` (value/onChanged or internal state), `AppProposedActionCard` (state/onApprove/onEdit/onDismiss or internal state machine — see phase 2 table for the controlled fallback mirrors-web pattern). `AppAiMessageBubble`, `AppThinkingIndicator`, `AppAiSuggestion`, `AppAiPanel` (messages list) follow the same `value`/`onChanged`/internal fallback rule.

8. **Error/invalid placement.** Only `AppProposedActionCard` has a failure surface; match the web — `state: 'failed'` + `errorMessage` renders a danger-bordered callout **inside the card body**, not on a control border. No `AppFormField` error slot is reused here.

### Group-specific regressions to avoid (cross-reference `ui-runtime-errors.md`)

- **Memory #1 (`No Material widget found`):** `AppAiPanel`'s composer embeds a `TextField`. Do **not** drop a bare `TextField` into the panel's `DecoratedBox` shell. Use `AppTextInput` (already wrapped) **or** call `appWrapMaterialInput(TextField(...))` from `app_input_styles.dart`. Same applies if `AppProposedActionCard` were ever to host a Material primitive — but it only embeds `AppFormField`/`AppTextInput`, both already safe.
- **Memory #2 / #10 / #12 / #13 (popover/MediaQuery/initState):** No AI widget uses `AppPopover`, `OverlayEntry`, or reads `MediaQuery` in `initState`. No risk. (`AppSignal`'s animation controller is already context-free in `app_signal.dart`; reuse as-is.)
- **Memory #3 (intl `DateFormat`):** None of the AI widgets format dates. No risk.
- **Memory #4 (duplicate `FocusNode`):** `AppAiPanel`'s input — if Composer needs arrow/enter handling, assign `FocusNode.onKeyEvent` on the field's own node, **do not** wrap the field in an ancestor `Focus` that shares the node.
- **Memory #5 (vertical centering of single-line field in shell):** Already handled by `AppTextInput` via `appCenterInputField`. No action when reusing `AppTextInput`.
- **Memory #15 (RenderFlex unbounded width + Expanded):** The `AppAiPanel` message list is `Expanded(child: SingleChildScrollView(...))` inside the page's scroll context — the panel itself lives in `SizedBox(height: 420, child: ...)`, so the inner `Column`/`Expanded` gets bounded height from that `SizedBox`, not from `SingleChildScrollView`. Pass `height: 420` to the panel demo wrapper. The composer `Row` must give `AppTextInput` a bounded width (use `Expanded` inside the composer `Row`, where the row's max width is finite because the panel has fixed height) — per memory #15 (5), parent must have bounded width; inside the fixed-height panel it is.
- **Memory #18 (hover without `onTap`):** The phase buttons inside `AppProposedActionCard` use real `onPressed` callbacks, so `Material`/`MouseRegion` hover works. No special handling. (Avoid `InkWell` for any custom AI hover surface — `AppCard` interactive already switched to `MouseRegion` per #18; the AI variant of `AppCard` is the non-interactive variant so it's fine.)
- **Memory #21 (badge stretching full width):** When `AppBadge` is placed inside the `AppProposedActionCard` header row, wrap inline (no `Expanded`) so it hugs content; `AppBadge` already self-queues via `UnconstrainedBox` per #21.
- **Checklist for new input components**: items 1 (Material ancestor — applies to `AppAiPanel` composer), 4 (Focus sharing — see note), 5 (vertical centering via `AppTextInput` reuse). Items 2/3/6/7/8/9 do not apply to the AI group.

## 1. Existing App assets to reuse (do not recreate)

| Asset | Path | Used by |
|---|---|---|
| `AppButton` (incl. `AppButtonVariant.ai`, `AppButtonSize.sm`) | `core/ui/components/app_button.dart` | AiMessageBubble (copy), AiSuggestion (Use suggestion / Dismiss), AiPanel (suggested-prompt chips), ProposedActionCard (Approve/Edit/Dismiss) |
| `AppIconButton` (incl. `AppIconButtonVariant.ai`, `AppIconButtonSize.sm`) | `core/ui/components/app_icon_button.dart` | AiSuggestion (close X), AiPanel (Send/Stop) |
| `AppCard` (`CardVariant.ai`) | `core/ui/components/app_card.dart` | ProposedActionCard (`variant="ai"` shell) |
| `AppBadge` (`BadgeColor.success`/`neutral`/`danger`, `BadgeVariant.soft`) | `core/ui/components/app_badge.dart` | ProposedActionCard header status (`Approved`/`Dismissed`/`Failed`) |
| `AppSignal` (`AppSignalVariant.ai`, `thinking: true`) | `core/ui/components/app_signal.dart` | ThinkingIndicator, AiPanel header |
| `AppFormField`, `AppTextInput` | `core/ui/components/app_form_field.dart`, `app_text_input.dart` | ProposedActionCard fields, AiPanel composer |
| `app_input_styles.dart` (`appWrapMaterialInput`, `appCenterInputField`, `AppInputSize`) | `core/ui/components/app_input_styles.dart` | AiPanel composer (Material wrap) |
| `CircularProgressIndicator` (Material; the web `Spinner` equivalent) | flutter/material | ProposedActionCard `submitting` body |
| Theme: `context.appColors` (`surfaceAi`, `borderAi`, `textAi`, `actionAi*`, `signalColorAi`, status colors), `AppSpacing`, `AppRadius`, `AppTypography`, `AppMotion` | `core/ui/theme/*` | every AI widget |
| `devPreviewProvider` | `features/design_system/presentation/providers/dev_preview_provider.dart` | locale/direction in AI showcases (EN/AR) |
| Showcase primitives: `ShowcaseSection`, `ShowcaseDemoGrid`, `ShowcaseDemo`, `ShowcaseVariantMatrix`, `PlaceholderSection` | `components/showcase_primitives.dart` | every AI section |

## 2. New shared abstractions to introduce

None. The AI group introduces no new shared `app_*.dart` primitive; every widget is a self-contained composition file under `core/ui/components/` that consumes the existing assets in §1. (See the per-phase tables for the files to create.)

**Barrel update:** append every new `app_ai_*.dart`/`app_proposed_action_card.dart`/`app_thinking_indicator.dart` to `lib/core/ui/widgets/widgets.dart` under a new `// AI` sub-comment, mirroring the existing `// Data display` block.

## 3. Phasing

> Rationale: **Phase 1** = the atomic AI atoms that have no AI-internal dependencies — the toggle, the thinking pulse, the inline suggestion, the message bubble. Each is a single small file consuming only already-shipped primitives. **Phase 2** = the two composite workflow surfaces whose internals reference phase-1 atoms (`AppAiPanel` embeds `AppAiMessageBubble` + `AppThinkingIndicator`; `AppProposedActionCard` embeds `AppCard`/`AppButton`/`AppBadge`/`AppFormField`/`AppTextInput`). Each phase is independently shippable.

### Phase 1 — Atomic AI atoms + mode toggle

Widgets: **AiModeToggle, ThinkingIndicator, AiSuggestion, AiMessageBubble**

| Widget | Flutter widget(s) to create | File(s) | Reuse | Wrapper | Deps |
|---|---|---|---|---|---|
| AI mode toggle | `AppAiModeToggle` (`StatefulWidget`, internal `aiMode` + `value`/`onChanged` optional; `showLabel: bool` default true; sparkles icon (Material `Icons.auto_awesome` or `Icons.star` — pick the closest semantic match) + label `"AI mode"`/`"Standard"`) | CREATE `components/app_ai_mode_toggle.dart`; MOD `widgets.dart` | `AppPressable`/`MouseRegion` (hover bg swap), theme AI tokens (`surfaceAi`/`borderAi`/`textAi` when ON; `surfaceDefault`/`borderDefault`/`textPrimary` + `surfaceHover` when OFF), `AppRadius.md`, `AppTypography.bodyStrong`, `AppMotion.instant` (transition-colors) | NEW wrapper | none (self-contained) |
| Thinking indicator | `AppThinkingIndicator` (composes `AppSignal(variant: ai, orientation: horizontal, thinking: true)` in a `SizedBox(width: 64)` + label `Text`; default `label: 'Thinking…'`, custom `label:` prop) | CREATE `components/app_thinking_indicator.dart`; MOD `widgets.dart` | `AppSignal`, `AppTypography.bodySm`, `colors.textAi`, `AppSpacing.space3` | NEW wrapper | **`AppSignal`** (already shipped) |
| Inline AI suggestion | `AppAiSuggestion` (`message`, `onAccept?`, `onDismiss?`); `role="note"`, `aria-label="AI suggestion"` → `Semantics(label: …)` | CREATE `components/app_ai_suggestion.dart`; MOD `widgets.dart` | outer `DecoratedBox(border: borderAi, color: surfaceAi, radius: lg)`, sparkles icon (text-ai), `AppButton(variant: ai, size: sm, "Use suggestion")`, `AppButton(variant: ghost, size: sm, "Dismiss")`, `AppIconButton(variant: ghost, size: sm, icon: X, label: "Dismiss suggestion")` | NEW wrapper | `AppButton`, `AppIconButton` |
| AI message bubble | `AppAiMessageBubble` (`role: AiMessageRole = user\|assistant`, `child: Widget`, `timestamp?`, `onCopy?`); user → end-aligned muted bubble; assistant → start-aligned surface-ai bubble with header row (`Sparkles` 12px + `"AI assistant"` caption) + copy button (hover-reveal) top-end | CREATE `components/app_ai_message_bubble.dart`; MOD `widgets.dart` | `AppButton(variant: ghost, size: sm, leadingIcon: Copy icon, "Copy")`, `AppTypography.body`/`caption`/`overline`, `colors.textAi`/`surfaceAi`/`borderAi`/`surfaceMuted`/`textTertiary`; `Directionality.of` already drives `MainAxisAlignment.end`/`.start` alignment | NEW wrapper | `AppButton` |

Showcase sections (Phase 1), under `features/design_system/presentation/components/ai/`:
`ai_mode_toggle_showcase_section.dart`, `thinking_indicator_showcase_section.dart`, `ai_suggestion_showcase_section.dart`, `ai_message_bubble_showcase_section.dart`.

### Phase 2 — Composite AI surfaces

Widgets: **AiPanel, ProposedActionCard**

| Widget | Flutter widget(s) | File(s) | Reuse | Wrapper | Deps |
|---|---|---|---|---|---|
| AI panel / chat | `AppAiPanel` (`scope: String = 'Main branch'`, internal message list + composer); `StatefulWidget` mirroring the web `send`/mock-1500ms-thinking/state machine (user msg → thinking `ThinkingIndicator` → delayed assistant response). Header: `Sparkles` + `"AI assistant"` + `"Scope: {scope} · Human approval required for all actions"` + `AppSignal(variant: ai, thinking: thinking\|\|streaming)`. Empty state: caption + suggested-prompt `AppButton(variant: secondary, size: sm)` chips. Body: `Expanded(SingleChildScrollView)` rendering `AppAiMessageBubble` per message + `AppThinkingIndicator` while thinking. Composer: `Row([Expanded(AppTextInput ai-bordered), AppIconButton(Send/Stop, variant: ai)])`. | CREATE `components/app_ai_panel.dart`; MOD `widgets.dart` | `AppAiMessageBubble` (P1), `AppThinkingIndicator` (P1), `AppSignal`, `AppButton`, `AppIconButton`, `AppTextInput` (with `inputDecoration` override reading `colors.borderAi` + `actionAi` focus; reuse `app_input_styles` Material-wrap so memory #1 holds), `AppMotion`, theme AI tokens; `Timer` for the 1500ms mock | NEW wrapper | **AppAiMessageBubble** (P1), **AppThinkingIndicator** (P1), `AppTextInput`, `AppSignal` |
| Proposed action card | `AppProposedActionCard` + `enum ProposedActionState { proposed, editing, submitting, approved, rejected, failed }`; props: `title`, `summary`, `fields: Widget?`, `state: ProposedActionState?` (controlled), `errorMessage: String?`, `onApprove?`, `onEdit?`, `onDismiss?`. Internal fallback state machine when `state` is null (web: approve → submitting → 1200ms → approved; reject → rejected; edit → editing). Body order mirrors web exactly: header (Sparkles + `"Proposed by AI"` overline + state badge for approved/rejected/failed), title (`bodyStrong`), summary (`bodySm` secondary), fields container (proposed/editing/failed only — `borderSubtle`/`surfaceDefault`, `borderFocus` ring when editing), failed callout (`statusDangerBorder`/`statusDangerSurface` + X icon), submitting spinner row (`AppSignal`? no, web uses `Spinner` → use `SizedBox(16, CircularProgressIndicator)` + `"Submitting for approval…"` `textAi`), approved success caption, footer `ActionRow`(Approve `variant: ai` + `leadingIcon: Check`, Edit `variant: secondary` + `leadingIcon: Pencil`, Dismiss `variant: ghost` + `leadingIcon: X`), trailing caption `"AI never executes actions directly. Approve to run the validated backend path."`. | CREATE `components/app_proposed_action_card.dart`; MOD `widgets.dart` | `AppCard(variant: CardVariant.ai)` shell (with `padding: CardPadding.md`), `AppButton` (3 variants + `size: sm`), `AppBadge` (soft, success/neutral/danger), `AppFormField`/`AppTextInput` (used inside the showcase `fields` slot only — the card itself accepts arbitrary `Widget`), `CircularProgressIndicator`, `AppTypography.overline`/`bodyStrong`/`bodySm`/`caption`, `AppSpacing`, `AppRadius.md`, semantic status colors, `Timer` for the submitting→approved mock | NEW wrapper | `AppCard`, `AppButton`, `AppBadge`, `AppFormField`, `AppTextInput` (showcase only) |

Showcase sections (Phase 2): `ai_panel_showcase_section.dart`, `proposed_action_card_showcase_section.dart`.

## 4. Instantiation in the Dev page (mirrors web reference)

> **Binding source of truth:** the per-demo arrangement, props, labels, copy, and variant matrices in each Flutter showcase section **must mirror exactly** how the corresponding showcase in `web-reference/src/showcase/components/ai/AiShowcase.tsx` instantiates the web widget. Composer 2.5 should open that file and reproduce, demo-for-demo:
> - the number, order, and titles of `ShowcaseDemo` cells;
> - the exact props passed to the control (sizes, variants, defaultValues, placeholders, icons, affixes, disabled/readOnly/invalid flags, etc.);
> - any `ShowcaseVariantMatrix` rows below the `ShowcaseDemoGrid`;
> - the bilingual EN/AR copy where the web demo uses labels/placeholders/helpers (AR translations follow the existing showcase convention from `button_showcase_section.dart`'s `_copyEn`/`_copyAr` pattern, also used in `card_showcase_section.dart`).
>
> The Flutter `ShowcaseSection`/`ShowcaseDemoGrid`/`ShowcaseDemo`/`ShowcaseVariantMatrix` primitives are 1:1 in shape with the web ones, so the demo structure ports verbatim — only the control widget name and prop syntax change (e.g. `showLabel={false}` → `showLabel: false`, `state="failed"` → `state: ProposedActionState.failed`).

For every widget, the showcase section wraps demos in the existing primitives so the Dev page renders them identically to `web-reference`.

Concretely per widget (copy EN/AR strings matching `AiShowcase.tsx`):

- **Ai mode toggle** — `ShowcaseSection` with a single `ShowcaseDemo(label: "Standard ↔ AI")` containing two `AppAiModeToggle`s: default (`showLabel: true`, internal state, starts in AI mode) and `showLabel: false`. (Web places both inside one demo; reproduce the same.) EN copy: "AI mode" / "Standard". AR: "وضع الذكاء" / "القياسي".
- **Thinking indicator** — `ShowcaseSection` with one `ShowcaseDemo(label: "Signal pulse")` containing `AppThinkingIndicator()` (default `label: 'Thinking…'`). AR demo label `نبض الإشارة`, label "يفكّر…". When the dev preview locale flips to `ar`, the same widget rebuilds with the AR label (driven via `_copyFor(locale)`).
- **Inline AI suggestion** — `ShowcaseSection` (no `ShowcaseDemoGrid` — single full-width demo to match web) containing `AppAiSuggestion(message: <locale copy>, onAccept: () {}, onDismiss: () {})`. EN message: "AI can draft a SOAP note from today's visit summary." AR: "يمكن للذكاء الاصطناعي صياغة ملاحظة SOAP من ملخص زيارة اليوم." Buttons: EN "Use suggestion" / "Dismiss"; AR "استخدم الاقتراح" / "رفض".
- **AI message bubbles** — `ShowcaseSection` with a `max-w-lg space-y-4` analog (a constrained-width `Column` with `SizedBox(width: 480, child: Column(...))`) rendering two bubbles: `AppAiMessageBubble(role: user, timestamp: "2:14 PM", child: Text(userMsg))` followed by `AppAiMessageBubble(role: assistant, timestamp: "2:14 PM", onCopy: () {}, child: Text(assistantMsg))`. EN user: "Which patients need follow-up this week?"; EN assistant: "Three patients have follow-ups due: Layla Hassan, Omar Farouk, and Nadia El-Sayed." AR mirrors verbatim (translate copy). The `"AI assistant"` overline + sparkles header render inside the assistant bubble; the copy button reveals on hover (use `MouseRegion` glaringly — match `AppCard` interactive pattern, memory #18).
- **Proposed action card** — `ShowcaseSection` (with `description`) containing a `ShowcaseVariantMatrix(title: "States")` of six state-switch buttons (`proposed`, `editing`, `submitting`, `approved`, `rejected`, `failed` — same set as web `PROPOSED_STATES`) driving a `StatefulWidget`'s `activeState`, then a `max-w-md` `AppProposedActionCard(title: "Book appointment", summary: <localized>, state: activeState, errorMessage: activeState == failed ? <localized> : null, fields: <Column of 3 AppFormField wrapping AppTextInput as web does>)`. EN title "Book appointment"; EN summary "Schedule a follow-up for Layla Hassan with Dr. Ahmed on Jul 8 at 10:00 AM."; EN failure message "Doctor is not available at the selected time." The 3 fields are `Patient` (readOnly, `defaultValue: "Layla Hassan"`), `Date` (`defaultValue: "Jul 8, 2026"`), `Time` (`defaultValue: "10:00 AM"`) — matching `AiShowcase.tsx` lines 92-103. AR copy: title "حجز موعد"; summary "جدولة متابعة ليلى حسن مع د. أحمد في 8 يوليو الساعة 10:00 ص."; error "الطبيب غير متاح في الوقت المحدد."; fields "المريض"/"التاريخ"/"الوقت".
- **AI panel / chat** — `ShowcaseSection` with a `SizedBox(height: 420, child: SizedBox(width: 480, child: AppAiPanel(scope: <localized>)))`. EN scope "Downtown branch"; AR "فرع وسط البلد". (Web uses `h-[420px] max-w-lg`; reproduce the fixed height so `Expanded`/scroll in the panel body has bounded height — see memory #15.) The `AppAiPanel` itself drives the suggested-prompt + send + mock-thinking flow internally; the showcase does not need to inject state.

## 5. Wiring steps (do after each phase's widgets land)

1. `component_registry.dart` — for each finished `id`, change `status: ShowcaseSectionStatus.placeholder` → `ShowcaseSectionStatus.ready` (keep order; ids already present at lines 429–463: `ai-mode-toggle`, `ai-panel`, `ai-message-bubble`, `proposed-action-card`, `ai-suggestion`, `thinking-indicator`).
2. `component_section_builders.dart` — add an entry per ready id in `componentSectionBuilders` (reuse exact `'id'` strings from `component_registry.dart`):
   - Phase 1: `'ai-mode-toggle': () => const AiModeToggleShowcaseSection(),`, `'thinking-indicator': () => const ThinkingIndicatorShowcaseSection(),`, `'ai-suggestion': () => const AiSuggestionShowcaseSection(),`, `'ai-message-bubble': () => const AiMessageBubbleShowcaseSection(),`.
   - Phase 2: `'ai-panel': () => const AiPanelShowcaseSection(),`, `'proposed-action-card': () => const ProposedActionCardShowcaseSection(),`.
3. Import the new section files at the top of `component_section_builders.dart` (group imports under a `// AI` comment, mirroring the existing `// Inputs & forms` and `// Data display` blocks).
4. Append new `app_ai_mode_toggle.dart`, `app_thinking_indicator.dart`, `app_ai_suggestion.dart`, `app_ai_message_bubble.dart`, `app_ai_panel.dart`, `app_proposed_action_card.dart` to the `widgets.dart` barrel export list under a `// AI` sub-comment (mirrors `// Data display`).
5. Run `flutter analyze` (project uses `flutter_lints`) on changed files; fix lints. Do **not** commit unless asked.

## 6. Out-of-scope / defer

- The hypothetical `AppAiInput` variant of `AppTextInput` (violet focus ring) is **not** introduced; `AppAiPanel` composes `AppTextInput` with a localized `inputDecoration` override. If a future milestone needs an ai-input elsewhere, promote it then.
- A real `AiModeProvider` (Riverpod) is **not** introduced; `AppAiModeToggle manages its own state (or accepts `value`/`onChanged`). If product flows later need global AI mode, replace the internal state with a Riverpod consumer at the call sites — no plan change here.
- Streaming token-by-token rendering of the assistant message (web sets `streaming`/`streamState` toggles; the showcase only sets `thinking` then drops the full message at 1500ms). The Flutter port reproduces the web showcase behavior exactly (mock 1500ms then full message); true streaming UX is a product feature, out of scope.
- `Sparkles` icon mapping: the web uses `lucide-react`'s `Sparkles`. The Flutter port uses the closest Material `Icons` glyph (`Icons.auto_awesome` is the conventional Flutter analog). Other lucide icons (`Copy`, `Check`, `Pencil`, `X`, `XCircle`, `Send`, `Square`) map to their Flutter Material equivalents; an icon mapping table belongs in the per-folder implementation, not this plan.
- No new shared abstraction beyond §1 (no popover, chip, calendar, overlay, dialog, etc. for the AI group).

## 7. Source reference — web widget inventory

The 6 sections in `web-reference/src/showcase/components/ai/index.ts`:

| id | Title | Showcase file | Underlying UI component |
|---|---|---|---|
| `ai-mode-toggle` | AI mode toggle | `AiShowcase.tsx` → `AiModeToggleShowcase` | `components/navigation/AiModeToggle.tsx` (`AiModeToggle`) |
| `ai-panel` | AI panel / chat | `AiShowcase.tsx` → `AiPanelShowcase` | `components/ai/AiPanel.tsx` (`AiPanel`) |
| `ai-message-bubble` | AI message bubbles | `AiShowcase.tsx` → `AiMessageBubbleShowcase` | `components/ai/AiMessageBubble.tsx` (`AiMessageBubble`) |
| `proposed-action-card` | Proposed action card | `AiShowcase.tsx` → `ProposedActionCardShowcase` | `components/ai/ProposedActionCard.tsx` (`ProposedActionCard`) |
| `ai-suggestion` | Inline AI suggestion | `AiShowcase.tsx` → `AiSuggestionShowcase` | `components/ai/AiSuggestion.tsx` (`AiSuggestion`) |
| `thinking-indicator` | Thinking indicator | `AiShowcase.tsx` → `ThinkingIndicatorShowcase` | `components/ai/ThinkingIndicator.tsx` (`ThinkingIndicator`) |

Shared web building blocks consumed by these components, with Flutter equivalents proposed in §1 (no new port abstraction needed):
- `components/actions/Button` (`Button`, variants incl. `secondary`/`ghost`/`ai`) → `AppButton` (`AppButtonVariant.secondary`/`ghost`/`ai`).
- `components/actions/IconButton` → `AppIconButton` (`AppIconButtonVariant.ghost`/`ai`).
- `components/card/Card` (`variant="ai"`) → `AppCard` (`CardVariant.ai`).
- `components/badge` (`Badge`, `color="success"/"neutral"/"danger"`, `variant="soft"`) → `AppBadge` (`BadgeColor.success`/`neutral`/`danger`, `BadgeVariant.soft`).
- `primitives/Signal` (`variant="ai"`, `orientation="horizontal"`, `thinking`) → `AppSignal` (`AppSignalVariant.ai`, `Axis.horizontal`, `thinking: true`).
- `components/ui/spinner/Spinner` (`size="sm"`) → `SizedBox(16, CircularProgressIndicator(strokeWidth: 2))` (matches the existing `AppButton` loading spinner pattern at `app_button.dart:198`).
- `components/ui/form-field/FormField` + `components/ui/text-input/TextInput` → `AppFormField` + `AppTextInput` (already shipped from the Inputs & forms group).
- `lucide-react` icons (`Sparkles`, `Copy`, `Check`, `Pencil`, `X`, `XCircle`, `Send`, `Square`) → Material `Icons` equivalents.
- `lib/cn`, `motionPresets`, web `focus-ring-ai` token → not ported directly; the violet focus ring is reproduced by overriding `AppInputDecoration`'s focused border with `colors.borderAi`/`colors.actionAi` in `AppAiPanel`.

Cross-cutting web notes (inform the Flutter port):
- Single AI color theme (`surfaceAi`, `borderAi`, `textAi`, `actionAi*`, `signalColorAi`) — all already defined on `AppSemanticColors`; no new tokens needed.
- All AI surfaces are blocked behind "Human approval required for all actions" / "AI never executes actions directly." copy — preserved verbatim in the showcase copy.
- The `ProposedActionCard` state machine (`proposed → submitting → approved` with 1200ms submit delay, and `→ rejected` / `→ editing` / `→ failed`) is reproduced in `AppProposedActionCard`'s internal fallback when no controlled `state` is supplied.
- The `AiPanel` mock flow (user msg → `thinking=true` for 1500ms → `streaming=true` → assistant msg) is reproduced verbatim with a `Timer` in `AppAiPanel`.