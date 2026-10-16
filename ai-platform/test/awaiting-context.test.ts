import { describe, expect, it } from "vitest";
import {
  canReachAwaitingContext,
  isJournalTerminalState,
  isJournalTransitionAllowed,
  type TransitionState,
} from "../src/journal";

const TERMINAL_STATES: TransitionState[] = [
  "Completed",
  "Failed",
  "Cancelled",
  "AwaitingContext",
];

const NON_TERMINAL_STATES: TransitionState[] = [
  "Accepted",
  "Composing",
  "Invoking",
  "Streaming",
  "Validating",
  "Repairing",
];

describe("awaiting_context_is_terminal_and_immutable", () => {
  it("treats AwaitingContext as terminal with no further transitions", () => {
    expect(isJournalTerminalState("AwaitingContext")).toBe(true);

    for (const target of TERMINAL_STATES) {
      expect(isJournalTransitionAllowed("AwaitingContext", target)).toBe(false);
    }

    for (const target of NON_TERMINAL_STATES) {
      expect(isJournalTransitionAllowed("AwaitingContext", target)).toBe(false);
    }
  });

  it("allows AwaitingContext reachability only for conversational manifests", () => {
    expect(canReachAwaitingContext("conversational")).toBe(true);
    expect(canReachAwaitingContext("single_shot")).toBe(false);
  });

  it("allows Validating → AwaitingContext only when interactionMode is conversational", () => {
    expect(
      isJournalTransitionAllowed(
        "Validating",
        "AwaitingContext",
        "conversational",
      ),
    ).toBe(true);
    expect(
      isJournalTransitionAllowed("Validating", "AwaitingContext", "single_shot"),
    ).toBe(false);
    // Default mode is single_shot — mode-blind AwaitingContext is refused.
    expect(isJournalTransitionAllowed("Validating", "AwaitingContext")).toBe(
      false,
    );
    expect(isJournalTransitionAllowed("Validating", "Completed")).toBe(true);
  });
});
