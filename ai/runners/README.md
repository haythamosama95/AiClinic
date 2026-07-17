# Model Runners — Operator Runbook

Model runners are **vanilla OpenAI-compatible** servers (Ollama by default). They hold no clinic
database credentials and MUST bind to localhost / the AI-internal interface only — never to a
client-routable LAN address (FR-010).

## Default stack

| Item | Value |
| --- | --- |
| Runtime | Ollama |
| Default model | Qwen3-4B Q4_K_M (`qwen3:4b`) |
| Internal port | `127.0.0.1:11434` |
| Model store | Docker volume `ollama_models` (host path: `/root/.ollama` inside container) |

## Install via Ollama pull (recommended)

```bash
cd ai/runners/ollama
docker compose up -d
docker compose exec ollama ollama pull qwen3:4b
curl -s http://127.0.0.1:11434/v1/models | jq .
```

### Use an existing host model store (no re-download)

If Ollama models are already on the host (e.g. system install at
`/usr/share/ollama/.ollama`), `scripts/ollama_compose.sh` auto-mounts that
directory when `models/` exists there. Start as usual:

```bash
cd ai/runners
./start.sh
bash scripts/ollama_compose.sh host-models   # enabled:/usr/share/ollama/.ollama
docker compose -f ollama/docker-compose.yaml -f ollama/docker-compose.host-models.yaml exec ollama ollama list
```

Override the path with `OLLAMA_HOST_MODELS=/path/to/.ollama`.

To **copy** into the named Docker volume instead of bind-mounting:

```bash
chmod +x scripts/import_host_models.sh
./scripts/import_host_models.sh
```

After pull, record the model digest in `ollama/digests.md` and pin it in Gateway config
(`gateway/config/gateway.yaml` → `runners[].models[].digest`).

## Install via local GGUF path

1. Download or copy a GGUF file to the clinic server (e.g. `/opt/aiclinic/models/`).
2. Set `models_dir` in Gateway config to that directory.
3. Create a custom model from the GGUF:

```bash
docker compose exec ollama ollama create qwen3-local -f /path/to/Modelfile
```

Example Modelfile pointing at a local file:

```dockerfile
FROM /models/qwen3-4b-q4_k_m.gguf
PARAMETER num_ctx 8192
```

4. Verify with `curl http://127.0.0.1:11434/v1/models` and pin the digest.

## Model store location

- **Docker Compose (default):** named volume `ollama_models` → `/root/.ollama` in the container.
- **Bare-metal Ollama:** `~/.ollama/models` (Linux) or `%USERPROFILE%\.ollama\models` (Windows).

To use a host directory instead of a named volume, replace the volume mapping in
`ollama/docker-compose.yaml`:

```yaml
volumes:
  - /opt/aiclinic/ollama:/root/.ollama
```

## Digest pinning

Every production deployment MUST pin the loaded model digest (`sha256:…`) in:

1. `ai/runners/ollama/digests.md` (operator record)
2. `ai/gateway/config/gateway.yaml` under each runner's `models[]` entry

The Gateway health poller reads the live digest from `GET /v1/models` and compares it against the
declared pin during capabilities reporting (Phase 3+).

## Non-routability check

From a client workstation on the LAN, this MUST fail:

```bash
curl http://<server-node>:11434/v1/models   # connection refused / unreachable
```

Only the Gateway on port `8090` is client-facing; runners stay on `127.0.0.1`.

## Model runner console (local UI)

A zero-build static console in `ai/runner-console/` lets operators probe Ollama and run
chat completions directly on the server node (localhost only — not client-routable).

```bash
# With Ollama running:
cd ai/runners
./scripts/serve_console.sh
```

Open [http://127.0.0.1:11435](http://127.0.0.1:11435). Use a different port if needed:

```bash
RUNNER_CONSOLE_PORT=11436 ./scripts/serve_console.sh
```

The console talks to Ollama at `http://127.0.0.1:11434` by default. It includes:

- **Thinking mode** — `off` → `think: false`, `on` → `think: true`, `default` → omit (model decides) on native `POST /api/chat`
- **NVIDIA GPU toggle** — restarts Ollama with `docker-compose.gpu.yaml` (requires NVIDIA Container Toolkit)
- **Raw output panel** — full request, every stream chunk, and parsed thinking/content

For registry, JWT auth, and gateway-proxied probes, use the [control plane dashboard](http://localhost:8090/dashboard) instead.

### GPU quick start

```bash
# Install NVIDIA Container Toolkit on the host, then:
cd ai/runners
bash scripts/ollama_compose.sh set-gpu 1
bash scripts/ollama_compose.sh up
docker compose -f ollama/docker-compose.yaml -f ollama/docker-compose.gpu.yaml exec ollama ollama ps
# PROCESSOR should show 100% GPU when a model is loaded
```
