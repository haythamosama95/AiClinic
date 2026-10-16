// Fixture for guard_model_identifier_fails_build (T3).
// Lives outside clean scan roots — invoked only in expect-fail CI runs.
// Uses current vendor naming (letters after the hyphen) plus the platform model id.

/// Representative model identifier that must fail the architecture guard.
const String forbiddenModelIdentifier = 'claude-sonnet-4-5';

/// Platform-integrated model id that must also fail the architecture guard.
const String forbiddenPlatformModelIdentifier = 'deepseek-chat';
