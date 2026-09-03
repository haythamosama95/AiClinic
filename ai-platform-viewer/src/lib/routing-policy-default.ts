/** Minified platform-default routing policy (ai-platform/control/routing-policy/platform-default/1.json). */
export const DEFAULT_ROUTING_POLICY_DOCUMENT = JSON.stringify({
  schema_version: 1,
  policy_id: 'standard',
  policy_version: 1,
  defaults: { cost_class: 'standard', max_parallel_attempts: 1 },
  rules: [
    {
      rule_id: 'platform-default-fallback',
      match: {},
      requires: { structured_output: false, min_context_window: 0, languages: [] },
      targets: [
        {
          provider_id: 'deepseek',
          model_id: 'deepseek-v4-flash',
          features: {
            structured_output: true,
            min_context_window: 128000,
            languages: ['en'],
            latency_class: 'standard',
            cost_class: 'standard',
          },
          max_attempts: 2,
          timeout_ms: 30000,
        },
        {
          provider_id: 'gemini',
          model_id: 'gemini-3.5-flash',
          features: {
            structured_output: true,
            min_context_window: 128000,
            languages: ['en'],
            latency_class: 'standard',
            cost_class: 'standard',
          },
          max_attempts: 2,
          timeout_ms: 30000,
        },
      ],
    },
  ],
  overrides: [],
})
