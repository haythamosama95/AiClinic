import { describe, expect, it } from "vitest";
import {
  hashManifest,
  load,
  verifyPublishedRegistry,
  type Manifest,
} from "../src/manifest";

type ManifestWire = Record<string, unknown>;

function baseManifestWire(): ManifestWire {
  return {
    Identity: {
      capabilityId: "clinic.chat_assistant",
      version: "1.0.0",
      title: "Chat assistant",
      lifecycleState: "active",
      successorId: null,
    },
    Access: {
      requiredCapabilityScope: "ai.chat_assistant",
      minimumPlanTier: "standard",
      allowedStaffRoles: ["clinician", "nurse"],
      killSwitchFlag: false,
    },
    Interaction: {
      interactionMode: "conversational",
      maxHistoryTurns: 10,
      maxContextRoundsPerTurn: 3,
      transcriptSizeLimit: 50_000,
    },
    Input: {
      userIntentShape: "plain_text",
      priorTurnShape: "transcript",
      sizeLimits: { maxChars: 8_000 },
      allowedLanguages: ["en"],
    },
    "Context requirements": {
      permittedKeySet: [
        "visit.chief_complaint@v1",
        "patient.demographics@v1",
      ],
    },
    "Prompt binding": {
      systemInstructionArtifactRef: "prompt/chat-system@v1",
      businessRuleFragmentRefs: ["rules/chat@v1"],
      contextRenderingTemplateRef: "templates/chat@v1",
      outputFormatInstructionDerivationRule: "derive_from_output_mode",
    },
    Output: {
      mode: "prose",
      outputSchemaRef: null,
      businessValidationRuleRefs: [],
      repairPolicy: { allowed: false, maxAttempts: 0 },
    },
    Routing: {
      routingPolicyRef: "routing/standard@v1",
      requiredProviderFeatures: {
        structuredOutput: false,
        contextWindow: 32_000,
        language: "en",
      },
      latencyClass: "standard",
      degradedTierPolicy: "fallback_chain",
    },
    Economics: {
      maxInputTokens: 8_000,
      maxOutputTokens: 1_024,
      perRequestTokenCeiling: 9_024,
      quotaWeight: 1,
    },
    Governance: {
      acceptanceMode: "advisory_display",
      retentionClass: "diagnostic_30d",
      evalSuiteRef: "evals/chat@v1",
    },
  };
}

function validConversationalManifest(): ManifestWire {
  return baseManifestWire();
}

function omitConversationalInteractionField(
  field: "maxHistoryTurns" | "maxContextRoundsPerTurn" | "transcriptSizeLimit",
): ManifestWire {
  const manifest = baseManifestWire();
  const interaction = {
    ...(manifest.Interaction as Record<string, unknown>),
  };
  delete interaction[field];
  return { ...manifest, Interaction: interaction };
}

function omitPermittedKeySet(): ManifestWire {
  const manifest = baseManifestWire();
  return { ...manifest, "Context requirements": {} };
}

function singleShotManifestWire(): ManifestWire {
  const manifest = baseManifestWire();
  return {
    ...manifest,
    Interaction: { interactionMode: "single_shot" },
    "Context requirements": [
      {
        key: "visit.chief_complaint@v1",
        required: true,
        shapeRef: "visit.chief_complaint@v1",
        maxSize: 4_096,
      },
    ],
  };
}

function singleShotWithConversationalField(
  field:
    | "maxHistoryTurns"
    | "maxContextRoundsPerTurn"
    | "transcriptSizeLimit"
    | "permittedKeySet",
): ManifestWire {
  if (field === "permittedKeySet") {
    const manifest = singleShotManifestWire();
    return {
      ...manifest,
      "Context requirements": {
        permittedKeySet: ["visit.chief_complaint@v1"],
      },
    };
  }

  const manifest = singleShotManifestWire();
  return {
    ...manifest,
    Interaction: {
      interactionMode: "single_shot",
      [field]: field === "transcriptSizeLimit" ? 50_000 : 10,
    },
  };
}

describe("conversational_manifest_loads_all_four_extra_fields", () => {
  it("returns a typed Manifest with all four conversational extras present", () => {
    const fixture = validConversationalManifest();
    const loaded = load(fixture);

    expect(loaded.interactionMode).toBe("conversational");
    expect(loaded.Interaction.maxHistoryTurns).toBe(10);
    expect(loaded.Interaction.maxContextRoundsPerTurn).toBe(3);
    expect(loaded.Interaction.transcriptSizeLimit).toBe(50_000);
    expect(loaded["Context requirements"]).toEqual({
      permittedKeySet: [
        "visit.chief_complaint@v1",
        "patient.demographics@v1",
      ],
    });
  });
});

describe("conversational_manifest_omits_max_history_turns_fails", () => {
  it("fails load() naming maxHistoryTurns omission", () => {
    expect(() =>
      load(omitConversationalInteractionField("maxHistoryTurns")),
    ).toThrow(/maxHistoryTurns/i);
  });
});

describe("conversational_manifest_omits_max_context_rounds_fails", () => {
  it("fails load() naming maxContextRoundsPerTurn omission", () => {
    expect(() =>
      load(omitConversationalInteractionField("maxContextRoundsPerTurn")),
    ).toThrow(/maxContextRoundsPerTurn/i);
  });
});

describe("conversational_manifest_omits_transcript_size_limit_fails", () => {
  it("fails load() naming transcriptSizeLimit omission", () => {
    expect(() =>
      load(omitConversationalInteractionField("transcriptSizeLimit")),
    ).toThrow(/transcriptSizeLimit/i);
  });
});

describe("conversational_manifest_omits_permitted_key_set_fails", () => {
  it("fails load() naming permittedKeySet omission", () => {
    expect(() => load(omitPermittedKeySet())).toThrow(/permittedKeySet/i);
  });
});

describe("conversational_fields_rejected_on_single_shot", () => {
  const conversationalFields = [
    "maxHistoryTurns",
    "maxContextRoundsPerTurn",
    "transcriptSizeLimit",
    "permittedKeySet",
  ] as const;

  for (const field of conversationalFields) {
    it(`rejects single_shot manifest carrying ${field}`, () => {
      expect(() => load(singleShotWithConversationalField(field))).toThrow();
    });
  }
});

describe("conversational_fields_rejected_when_interaction_mode_omitted", () => {
  it("defaults omitted interactionMode to single_shot and rejects conversational fields", () => {
    const manifest = baseManifestWire();
    const interaction = {
      ...(manifest.Interaction as Record<string, unknown>),
    };
    delete interaction.interactionMode;
    manifest.Interaction = interaction;

    expect(() => load(manifest)).toThrow(
      /Conversational-only field rejected on single_shot/i,
    );
  });
});

describe("conversational_numeric_fields_reject_malformed_values", () => {
  const fields = [
    "maxHistoryTurns",
    "maxContextRoundsPerTurn",
    "transcriptSizeLimit",
  ] as const;

  for (const field of fields) {
    it.each([
      { label: "wrong_type_string", value: "ten" },
      { label: "negative", value: -3 },
      { label: "zero", value: 0 },
      { label: "non_integer", value: 1.5 },
    ] as const)(
      `rejects $label for ${field}`,
      ({ value }) => {
        const manifest = validConversationalManifest();
        const interaction = {
          ...(manifest.Interaction as Record<string, unknown>),
          [field]: value,
        };
        manifest.Interaction = interaction;
        expect(() => load(manifest)).toThrow(
          new RegExp(`Malformed conversational Interaction field: ${field}`),
        );
      },
    );
  }
});

describe("permitted_key_set_edge_policies", () => {
  it("accepts an empty permittedKeySet (allowlist of zero)", () => {
    const manifest = validConversationalManifest();
    manifest["Context requirements"] = { permittedKeySet: [] };
    const loaded = load(manifest);
    expect(loaded["Context requirements"]).toEqual({ permittedKeySet: [] });
  });

  it("rejects duplicate keys in permittedKeySet", () => {
    const manifest = validConversationalManifest();
    manifest["Context requirements"] = {
      permittedKeySet: [
        "visit.chief_complaint@v1",
        "visit.chief_complaint@v1",
      ],
    };
    expect(() => load(manifest)).toThrow(/duplicate/i);
  });
});

describe("interaction_mode_in_place_change_fails_build", () => {
  it("fails verifyPublishedRegistry when interactionMode changes in place", async () => {
    const singleShot = singleShotManifestWire();
    const conversational = validConversationalManifest();
    const capabilityId = (singleShot.Identity as { capabilityId: string })
      .capabilityId;
    const version = (singleShot.Identity as { version: string }).version;
    const registryKey = `${capabilityId}@${version}`;
    const conversationalHash = await hashManifest(conversational);
    const singleShotHash = await hashManifest(singleShot);

    expect(() =>
      verifyPublishedRegistry(
        [{ capabilityId, version, hash: conversationalHash }],
        { [registryKey]: singleShotHash },
      ),
    ).toThrow();
  });

  it("hashManifest changes when only interactionMode flips", async () => {
    // Prove interactionMode itself participates in the content hash (not only
    // sibling conversational fields). Use otherwise-identical Interaction wires.
    const base = singleShotManifestWire();
    const flipped = structuredClone(base) as ManifestWire;
    (flipped.Interaction as Record<string, unknown>).interactionMode =
      "conversational";

    const hashA = await hashManifest(base);
    const hashB = await hashManifest(flipped);
    expect(hashA).not.toBe(hashB);
  });
});

describe("permitted_key_set_unknown_key_fails", () => {
  it("fails load() when permitted key set names an unknown vocabulary key", () => {
    const manifest = validConversationalManifest();
    manifest["Context requirements"] = {
      permittedKeySet: ["unknown.not_in_vocabulary@v1"],
    };

    expect(() => load(manifest)).toThrow();
  });
});

describe("interaction_mode_fixed_for_life_of_version", () => {
  it("rejects runtime mutation of interactionMode on a loaded conversational manifest", () => {
    const loaded = load(validConversationalManifest());

    expect(() => {
      // @ts-expect-error interactionMode is read-only for the life of a version
      loaded.interactionMode = "single_shot";
    }).toThrow();

    expect(loaded.interactionMode).toBe("conversational");
  });

  it("does not mutate interactionMode during load", () => {
    const fixture = validConversationalManifest();
    const interaction = fixture.Interaction as Record<string, unknown>;
    const loaded = load(fixture);

    expect(loaded.interactionMode).toBe("conversational");
    expect(interaction.interactionMode).toBe("conversational");
  });
});
