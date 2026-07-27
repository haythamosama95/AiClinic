---
name: multi-composer-agents
description: >-
  Spawn multiple parallel Composer 2.5 (non-fast) subagents to facilitate the
  task. Use when the user invokes this skill or asks for multiple Composer 2.5
  agents.
---

# Multi-Composer Agents

Spawn multiple parallel subagents via the Task tool to facilitate the user's task.

- Use `model: "composer-2.5"` for every subagent
- Do **not** use `composer-2.5-fast`
- Launch them in parallel in one message when their work is independent
- Synthesize their results when they return
