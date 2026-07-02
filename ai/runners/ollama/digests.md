# Pinned model digests

Record the `sha256:` digest after pulling the default model so Gateway config and capabilities
reporting can pin integrity (FR-008, §11.6).

## Default model: `qwen3:4b` (Qwen3-4B Q4_K_M)

| Model tag  | Digest (sha256)              | Notes |
| ---------- | ---------------------------- | ----- |
| `qwen3:4b` | `sha256:3e4cb14174460404e7a233e531675303b2fbf7749c02f91864fe311ab6344e4f` | Q4_K_M via `ollama pull qwen3:4b` |

### How to capture the digest

```bash
cd ai/runners/ollama
docker compose up -d
docker compose exec ollama ollama pull qwen3:4b
curl -s http://127.0.0.1:11434/v1/models | jq '.data[0].digest'
```

Copy the reported digest into this file and into `ai/gateway/config/gateway.yaml` under
`runners[].models[].digest`.
