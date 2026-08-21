import { describe, expect, it } from "vitest";
import {
  ECONOMICS_TOKEN_CEILING_FIELD,
  ECONOMICS_TOKEN_CEILING_LEGACY_ALIAS,
  ECONOMICS_TOKEN_CEILING_SCHEMA_NOTE,
  hashManifest,
  load,
  MANIFEST_FIELD_MANIFEST,
  verifyPublishedRegistry,
  type Manifest,
} from "../src/manifest";

const MANIFEST_GROUPS = [
  "Identity",
  "Access",
  "Interaction",
  "Input",
  "Context requirements",
  "Prompt binding",
  "Output",
  "Routing",
  "Economics",
  "Governance",
] as const;

type ManifestGroup = (typeof MANIFEST_GROUPS)[number];

type ManifestWire = Record<string, unknown>;

function validManifest(): ManifestWire {
  return {
    Identity: {
      capabilityId: "clinic.visit_summary",
      version: "1.0.0",
      title: "Visit summary",
      lifecycleState: "active",
      successorId: null,
    },
    Access: {
      requiredCapabilityScope: "ai.visit_summary",
      minimumPlanTier: "standard",
      allowedStaffRoles: ["clinician", "nurse"],
      killSwitchFlag: false,
    },
    Interaction: {
      interactionMode: "single_shot",
    },
    Input: {
      userIntentShape: "plain_text",
      priorTurnShape: null,
      sizeLimits: { maxChars: 8_000 },
      allowedLanguages: ["en"],
    },
    "Context requirements": [
      {
        key: "visit.chief_complaint@v1",
        required: true,
        shapeRef: "visit.chief_complaint@v1",
        maxSize: 4_096,
      },
    ],
    "Prompt binding": {
      systemInstructionArtifactRef: "prompt/visit-summary-system@v1",
      businessRuleFragmentRefs: ["rules/visit-summary@v1"],
      contextRenderingTemplateRef: "templates/visit-summary@v1",
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
      evalSuiteRef: "evals/visit-summary@v1",
    },
  };
}

function omitGroup(manifest: ManifestWire, group: ManifestGroup): ManifestWire {
  const copy = { ...manifest };
  delete copy[group];
  return copy;
}

function malformGroup(manifest: ManifestWire, group: ManifestGroup): ManifestWire {
  const copy = { ...manifest };
  copy[group] = "malformed";
  return copy;
}

function manifestWithoutInteractionMode(): ManifestWire {
  const manifest = validManifest();
  const interaction = {
    ...(manifest.Interaction as Record<string, unknown>),
  };
  delete interaction.interactionMode;
  return { ...manifest, Interaction: interaction };
}

function singleShotWithConversationalField(
  field: "maxHistoryTurns" | "maxContextRoundsPerTurn" | "transcriptSizeLimit",
): ManifestWire {
  const manifest = validManifest();
  return {
    ...manifest,
    Interaction: {
      interactionMode: "single_shot",
      [field]: field === "transcriptSizeLimit" ? 50_000 : 10,
    },
  };
}

function routingWithProviderOrModel(
  poison: "provider" | "model",
): ManifestWire {
  const manifest = validManifest();
  const routing = {
    ...(manifest.Routing as Record<string, unknown>),
  };
  if (poison === "provider") {
    routing.provider = "openai";
  } else {
    routing.model = "gpt-4";
  }
  return { ...manifest, Routing: routing };
}

function groupEntries(manifest: Manifest): Record<ManifestGroup, unknown> {
  return {
    Identity: manifest.Identity,
    Access: manifest.Access,
    Interaction: manifest.Interaction,
    Input: manifest.Input,
    "Context requirements": manifest["Context requirements"],
    "Prompt binding": manifest["Prompt binding"],
    Output: manifest.Output,
    Routing: manifest.Routing,
    Economics: manifest.Economics,
    Governance: manifest.Governance,
  };
}

describe("T-A4-01 manifest_loads_all_ten_groups", () => {
  it("load(validManifest()) returns a typed Manifest whose ten field groups equal the fixture", () => {
    const fixture = validManifest();
    const loaded = load(fixture);

    expect(groupEntries(loaded)).toEqual({
      Identity: fixture.Identity,
      Access: fixture.Access,
      Interaction: fixture.Interaction,
      Input: fixture.Input,
      "Context requirements": fixture["Context requirements"],
      "Prompt binding": fixture["Prompt binding"],
      Output: fixture.Output,
      Routing: fixture.Routing,
      Economics: fixture.Economics,
      Governance: fixture.Governance,
    });
  });
});

describe("T-A4-02..11 manifest_missing_or_malformed_group", () => {
  for (const group of MANIFEST_GROUPS) {
    describe(`manifest_missing_or_malformed_group_${group.replace(/\s+/g, "_")}`, () => {
      it(`load(omitGroup(...)) throws naming ${group}`, () => {
        expect(() => load(omitGroup(validManifest(), group))).toThrow(group);
      });

      it(`load(malformGroup(...)) throws naming ${group}`, () => {
        expect(() => load(malformGroup(validManifest(), group))).toThrow(group);
      });
    });
  }
});

describe("T-A4-12 in_place_edit_of_published_version_fails_build", () => {
  it("rejects an on-disk manifest whose hash differs from the registry entry", async () => {
    const valid = validManifest();
    const edited = {
      ...valid,
      Identity: {
        ...(valid.Identity as Record<string, unknown>),
        title: "Visit summary (edited)",
      },
    };
    const capabilityId = (valid.Identity as { capabilityId: string }).capabilityId;
    const version = (valid.Identity as { version: string }).version;
    const registryKey = `${capabilityId}@${version}`;
    const validHash = await hashManifest(valid);
    const editedHash = await hashManifest(edited);

    expect(() =>
      verifyPublishedRegistry(
        [{ capabilityId, version, hash: editedHash }],
        { [registryKey]: validHash },
      ),
    ).toThrow();

    expect(() =>
      verifyPublishedRegistry(
        [{ capabilityId, version, hash: validHash }],
        { [registryKey]: validHash },
      ),
    ).not.toThrow();
  });
});
describe("T-A4-13 omitted_interaction_mode_defaults_to_single_shot", () => {
  it("loads with interactionMode === single_shot when interactionMode is absent", () => {
    const loaded = load(manifestWithoutInteractionMode());
    expect(loaded.interactionMode).toBe("single_shot");
  });
});

describe("T-A4-14 conversational_fields_rejected_on_single_shot", () => {
  const conversationalFields = [
    "maxHistoryTurns",
    "maxContextRoundsPerTurn",
    "transcriptSizeLimit",
  ] as const;

  for (const field of conversationalFields) {
    it(`rejects single_shot manifest carrying ${field}`, () => {
      expect(() => load(singleShotWithConversationalField(field))).toThrow();
    });
  }
});

describe("T-A4-15 manifest_is_data_not_code", () => {
  it("export surface contains only data declarations and load/hashManifest/verifyPublishedRegistry", async () => {
    const manifestModule = await import("../src/manifest");
    const exportNames = Object.keys(manifestModule).sort();

    const allowedRuntimeExports = [
      "hashManifest",
      "load",
      "verifyManifestTree",
      "verifyPublishedRegistry",
    ].sort();

    const dataExports = exportNames.filter(
      (name) => !allowedRuntimeExports.includes(name),
    );

    for (const name of dataExports) {
      const value = manifestModule[name as keyof typeof manifestModule];
      const isData =
        typeof value !== "function" &&
        (typeof value === "object" || typeof value === "string" || typeof value === "number" || typeof value === "boolean");
      expect(isData, `export ${name} must be data, not executable wiring`).toBe(true);
    }

    expect(exportNames.filter((name) => typeof manifestModule[name as keyof typeof manifestModule] === "function").sort()).toEqual(
      allowedRuntimeExports,
    );

    expect(exportNames).not.toContain("createPipeline");
    expect(exportNames).not.toContain("handleRequest");
    expect(exportNames).not.toContain("clientEntryPoint");
  });
});

describe("T-A4-16 manifest_never_names_provider_or_model", () => {
  it("rejects a manifest whose Routing group names a provider", () => {
    expect(() => load(routingWithProviderOrModel("provider"))).toThrow();
  });

  it("rejects a manifest whose Routing group names a model identifier", () => {
    expect(() => load(routingWithProviderOrModel("model"))).toThrow();
  });
});

describe("T-A4-17 interaction_mode_fixed_for_life_of_version", () => {
  it("rejects runtime mutation of interactionMode", () => {
    const loaded = load(validManifest());

    expect(() => {
      // Compile-time: assignment to interactionMode must fail.
      // @ts-expect-error interactionMode is read-only for the life of a version
      loaded.interactionMode = "conversational";
    }).toThrow();

    expect(loaded.interactionMode).toBe("single_shot");
  });

  it("does not mutate interactionMode during load", () => {
    const fixture = manifestWithoutInteractionMode();
    const loaded = load(fixture);

    expect(loaded.interactionMode).toBe("single_shot");
    expect((fixture.Interaction as Record<string, unknown>).interactionMode).toBeUndefined();
  });
});

describe("T-A4-18 unknown_extra_keys_rejected", () => {
  it("rejects an unknown key in Output", () => {
    const manifest = validManifest();
    (manifest.Output as Record<string, unknown>).extraField = "nope";
    expect(() => load(manifest)).toThrow(/Output/);
  });

  it("rejects an unknown key in Routing", () => {
    const manifest = validManifest();
    (manifest.Routing as Record<string, unknown>).preferredProvider = "gemini";
    expect(() => load(manifest)).toThrow(/Routing/);
  });

  it("rejects an unknown key in Prompt binding", () => {
    const manifest = validManifest();
    (manifest["Prompt binding"] as Record<string, unknown>).modelHint = "gpt-4";
    expect(() => load(manifest)).toThrow(/Prompt binding/);
  });
});

describe("T-A4-19 provider_model_denylist_across_groups", () => {
  it("rejects provider-shaped key outside Routing literals", () => {
    const manifest = validManifest();
    (manifest.Routing as Record<string, unknown>).preferredProvider = "gemini";
    expect(() => load(manifest)).toThrow(/provider|model|Routing/i);
  });

  it("rejects model-shaped key nested under requiredProviderFeatures", () => {
    const manifest = validManifest();
    const routing = manifest.Routing as Record<string, unknown>;
    routing.requiredProviderFeatures = {
      ...(routing.requiredProviderFeatures as Record<string, unknown>),
      model: "gpt-4",
    };
    expect(() => load(manifest)).toThrow(/provider|model/i);
  });

  it("rejects modelHint on Prompt binding", () => {
    const manifest = validManifest();
    (manifest["Prompt binding"] as Record<string, unknown>).modelHint = "gpt-4";
    expect(() => load(manifest)).toThrow(/provider|model|Prompt binding/i);
  });
});

describe("T-A4-20 content_enum_validation", () => {
  it("rejects invalid Output.mode", () => {
    const manifest = validManifest();
    (manifest.Output as Record<string, unknown>).mode = "yolo";
    expect(() => load(manifest)).toThrow(/mode|Output/i);
  });

  it("rejects invalid Governance.acceptanceMode", () => {
    const manifest = validManifest();
    (manifest.Governance as Record<string, unknown>).acceptanceMode = "yolo";
    expect(() => load(manifest)).toThrow(/acceptanceMode|Governance/i);
  });

  it("rejects invalid Identity.lifecycleState", () => {
    const manifest = validManifest();
    (manifest.Identity as Record<string, unknown>).lifecycleState = "zombie";
    expect(() => load(manifest)).toThrow(/lifecycleState|Identity/i);
  });

  it("rejects diagnostic retentionClass outside the 1–90 day band", () => {
    const tooLong = validManifest();
    (tooLong.Governance as Record<string, unknown>).retentionClass =
      "diagnostic_365d";
    expect(() => load(tooLong)).toThrow(/retentionClass/i);

    const tooShort = validManifest();
    (tooShort.Governance as Record<string, unknown>).retentionClass =
      "diagnostic_0d";
    expect(() => load(tooShort)).toThrow(/retentionClass/i);

    const malformed = validManifest();
    (malformed.Governance as Record<string, unknown>).retentionClass =
      "forever";
    expect(() => load(malformed)).toThrow(/retentionClass/i);
  });

  it("accepts diagnostic retentionClass at band edges", () => {
    const min = validManifest();
    (min.Governance as Record<string, unknown>).retentionClass =
      "diagnostic_1d";
    expect(() => load(min)).not.toThrow();

    const max = validManifest();
    (max.Governance as Record<string, unknown>).retentionClass =
      "diagnostic_90d";
    expect(() => load(max)).not.toThrow();
  });
});

describe("T-A4-21 deep_freeze_rejects_group_mutation", () => {
  it("throws when mutating a non-interactionMode field on a loaded manifest", () => {
    const loaded = load(validManifest());
    expect(() => {
      (loaded.Output as { mode: string }).mode = "structured";
    }).toThrow();
    expect(loaded.Output.mode).toBe("prose");
  });

  it("throws when mutating a nested Identity field", () => {
    const loaded = load(validManifest());
    expect(() => {
      (loaded.Identity as { title: string }).title = "mutated";
    }).toThrow();
    expect(loaded.Identity.title).toBe("Visit summary");
  });
});

describe("T-A4-22 content_hash_is_sha256", () => {
  it("hashManifest returns a 64-char lowercase hex SHA-256 digest", async () => {
    const hash = await hashManifest(validManifest());
    expect(hash).toMatch(/^[0-9a-f]{64}$/);
  });
});

describe("T-A4-23 registry_gate_runs_in_build", () => {
  it("package.json declares a verify-manifests script", async () => {
    const pkg = JSON.parse(
      await import("node:fs/promises").then((fs) =>
        fs.readFile(new URL("../package.json", import.meta.url), "utf8"),
      ),
    ) as { scripts?: Record<string, string> };
    expect(pkg.scripts?.["verify-manifests"]).toMatch(/manifest-registry-gate/);
  });

  it("checked-in published registry passes verifyManifestTree", async () => {
    const fs = await import("node:fs/promises");
    const path = await import("node:path");
    const { verifyManifestTree } = await import("../src/manifest");
    const root = path.join(path.dirname(new URL(import.meta.url).pathname), "..");
    await expect(
      verifyManifestTree({
        manifestsDir: path.join(root, "manifests", "published"),
        registryPath: path.join(root, "manifests", "published-registry.json"),
        readFile: (p) => fs.readFile(p, "utf8"),
        readdir: (p) => fs.readdir(p),
        join: path.join,
      }),
    ).resolves.toBeUndefined();
  });

  it("in-place edit of a checked-in published manifest fails the registry gate", async () => {
    const fs = await import("node:fs/promises");
    const path = await import("node:path");
    const { verifyManifestTree } = await import("../src/manifest");
    const root = path.join(path.dirname(new URL(import.meta.url).pathname), "..");
    const registryPath = path.join(root, "manifests", "published-registry.json");
    const manifestsDir = path.join(root, "manifests", "published");
    const files = await fs.readdir(manifestsDir);
    const first = files.find((name) => name.endsWith(".json"));
    expect(first).toBeDefined();
    const original = JSON.parse(
      await fs.readFile(path.join(manifestsDir, first!), "utf8"),
    ) as Record<string, unknown>;
    const edited = {
      ...original,
      Identity: {
        ...(original.Identity as Record<string, unknown>),
        title: "Edited in place",
      },
    };
    await expect(
      verifyManifestTree({
        manifestsDir,
        registryPath,
        readFile: async (p) => {
          if (p.endsWith(first!)) {
            return JSON.stringify(edited);
          }
          return fs.readFile(p, "utf8");
        },
        readdir: (p) => fs.readdir(p),
        join: path.join,
      }),
    ).rejects.toThrow(/hash mismatch|Published manifest/i);
  });
});

describe("4.7 perRequestTokenCeiling is tokens, not currency", () => {
  it("names the Economics ceiling in tokens, not cost", () => {
    expect(MANIFEST_FIELD_MANIFEST.Economics).toEqual([
      "maxInputTokens",
      "maxOutputTokens",
      "perRequestTokenCeiling",
      "quotaWeight",
    ]);
    expect(MANIFEST_FIELD_MANIFEST.Economics).not.toContain(
      "perRequestCostCeiling",
    );
    expect(ECONOMICS_TOKEN_CEILING_FIELD).toBe("perRequestTokenCeiling");
    expect(ECONOMICS_TOKEN_CEILING_LEGACY_ALIAS).toBe("perRequestCostCeiling");
  });

  it("documents the field rename as a schema-version note with token units", () => {
    expect(ECONOMICS_TOKEN_CEILING_SCHEMA_NOTE).toMatch(/perRequestTokenCeiling/);
    expect(ECONOMICS_TOKEN_CEILING_SCHEMA_NOTE).toMatch(/token/i);
    expect(ECONOMICS_TOKEN_CEILING_SCHEMA_NOTE).toMatch(
      /perRequestCostCeiling/,
    );
    expect(ECONOMICS_TOKEN_CEILING_SCHEMA_NOTE).toMatch(/alias/i);
    expect(ECONOMICS_TOKEN_CEILING_SCHEMA_NOTE).toMatch(
      /token-denominated|never converts to currency|no currency/i,
    );
  });

  it("load normalizes a canonical perRequestTokenCeiling wire document", () => {
    const wire = validManifest();
    const economics = {
      ...(wire.Economics as Record<string, unknown>),
    };
    delete economics.perRequestCostCeiling;
    economics.perRequestTokenCeiling = 9_024;
    wire.Economics = economics;

    const loaded = load(wire);
    expect(loaded.Economics.perRequestTokenCeiling).toBe(9_024);
    expect(loaded.Economics).not.toHaveProperty("perRequestCostCeiling");
  });

  it("load accepts legacy perRequestCostCeiling as a compatibility alias", () => {
    const wire = validManifest();
    const economics = {
      ...(wire.Economics as Record<string, unknown>),
    };
    delete economics.perRequestTokenCeiling;
    economics.perRequestCostCeiling = 9_024;
    wire.Economics = economics;

    const loaded = load(wire);
    expect(loaded.Economics.perRequestTokenCeiling).toBe(9_024);
    expect(loaded.Economics).not.toHaveProperty("perRequestCostCeiling");
  });

  it("load prefers perRequestTokenCeiling when both keys are present", () => {
    const wire = validManifest();
    wire.Economics = {
      maxInputTokens: 8_000,
      maxOutputTokens: 1_024,
      perRequestTokenCeiling: 12_000,
      perRequestCostCeiling: 9_024,
      quotaWeight: 1,
    };

    const loaded = load(wire);
    expect(loaded.Economics.perRequestTokenCeiling).toBe(12_000);
    expect(loaded.Economics).not.toHaveProperty("perRequestCostCeiling");
  });

  it("load rejects Economics that omit both the canonical field and the alias", () => {
    const wire = validManifest();
    wire.Economics = {
      maxInputTokens: 8_000,
      maxOutputTokens: 1_024,
      quotaWeight: 1,
    };
    expect(() => load(wire)).toThrow(/Economics/);
  });

  it("published visit-summary manifest uses the token ceiling name", async () => {
    const fs = await import("node:fs/promises");
    const path = await import("node:path");
    const published = JSON.parse(
      await fs.readFile(
        path.join(
          path.dirname(new URL(import.meta.url).pathname),
          "..",
          "manifests",
          "published",
          "clinic.visit_summary@1.0.0.json",
        ),
        "utf8",
      ),
    ) as { Economics: Record<string, unknown> };

    expect(published.Economics).toHaveProperty("perRequestTokenCeiling", 9024);
    expect(published.Economics).not.toHaveProperty("perRequestCostCeiling");
  });
});

describe("5.4 freshnessHint is not a context-requirement field", () => {
  it("omits freshnessHint from the Context requirements schema keys", () => {
    expect(MANIFEST_FIELD_MANIFEST["Context requirements"]).toEqual([
      "key",
      "required",
      "shapeRef",
      "maxSize",
    ]);
    expect(MANIFEST_FIELD_MANIFEST["Context requirements"]).not.toContain(
      "freshnessHint",
    );
  });

  it("load accepts a single-shot context entry without freshnessHint", () => {
    const wire = validManifest();
    const [first] = wire["Context requirements"] as Array<
      Record<string, unknown>
    >;
    const { freshnessHint: _dropped, ...withoutHint } = first;
    void _dropped;
    wire["Context requirements"] = [withoutHint];

    const loaded = load(wire);
    const loadedEntries = loaded["Context requirements"] as Array<
      Record<string, unknown>
    >;
    expect(loadedEntries[0]).not.toHaveProperty("freshnessHint");
    expect(Object.keys(loadedEntries[0])).toEqual([
      "key",
      "required",
      "shapeRef",
      "maxSize",
    ]);
  });

  it("load rejects a context entry that still carries freshnessHint", () => {
    const wire = validManifest();
    const [first] = wire["Context requirements"] as Array<
      Record<string, unknown>
    >;
    wire["Context requirements"] = [{ ...first, freshnessHint: "session" }];

    expect(() => load(wire)).toThrow(/Context requirements/);
  });

  it("published visit-summary manifest has no freshnessHint", async () => {
    const fs = await import("node:fs/promises");
    const path = await import("node:path");
    const published = JSON.parse(
      await fs.readFile(
        path.join(
          path.dirname(new URL(import.meta.url).pathname),
          "..",
          "manifests",
          "published",
          "clinic.visit_summary@1.0.0.json",
        ),
        "utf8",
      ),
    ) as {
      "Context requirements": Array<Record<string, unknown>>;
    };

    expect(published["Context requirements"].length).toBeGreaterThan(0);
    for (const entry of published["Context requirements"]) {
      expect(entry).not.toHaveProperty("freshnessHint");
    }
  });
});
