// Fixture for guard_prompt_like_string_fails_build (T1).
// Lives outside clean scan roots — invoked only in expect-fail CI runs.
// Multi-line form proves whole-file / whitespace-tolerant matching (review E1-R3).

/// Representative prompt-like string that must fail the architecture guard.
const String forbiddenPromptFragment = '''
You are a helpful
assistant that summarizes clinical notes.
''';
