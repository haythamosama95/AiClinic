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

## `models_dir` (Gateway config)

`models_dir` is an optional Gateway config key (`gateway.yaml` / `gateway.example.yaml`) that
records the **canonical on-disk path** for model artifacts on the clinic server. The Gateway does
not read or serve files from this directory — it is an operator/installer reference that keeps
runner model entries, Modelfiles, and volume mounts aligned.

| Use case | Typical `models_dir` value | Runner wiring |
| --- | --- | --- |
| Local GGUF files (offline install) | `/opt/aiclinic/models` | Bind-mount into the Ollama container; reference in a Modelfile `FROM` line |
| Shared Ollama blob store (host install) | `/usr/share/ollama/.ollama` | Use `OLLAMA_HOST_MODELS` + `docker-compose.host-models.yaml` overlay |
| Dev / native Ollama | `~/.ollama` | `scripts/native_ollama.sh` (no Docker volume) |

Set in Gateway config:

```yaml
models_dir: /opt/aiclinic/models
```

Declare each model under `runners[].models[]` with `source` pointing at the Ollama tag or GGUF
path relative to that store, for example:

```yaml
runners:
  - id: ollama-local
    base_url: http://127.0.0.1:11434
    models:
      - name: qwen3-local
        source: /opt/aiclinic/models/qwen3-4b-q4_k_m.gguf
        digest: sha256:REPLACE_WITH_PINNED_DIGEST
        capabilities: [json_grammar]
```

### Install via local GGUF path

1. Download or copy a GGUF file into `models_dir` (e.g. `/opt/aiclinic/models/qwen3-4b-q4_k_m.gguf`).
2. Set `models_dir` in Gateway config to that directory (see above).
3. Bind-mount the directory into the Ollama container (add to `ollama/docker-compose.yaml` or an
   operator overlay):

```yaml
volumes:
  - /opt/aiclinic/models:/models:ro
```

4. Create a custom model from the GGUF:

```bash
docker compose exec ollama ollama create qwen3-local -f /path/to/Modelfile
```

Example Modelfile pointing at the mounted GGUF:

```dockerfile
FROM /models/qwen3-4b-q4_k_m.gguf
PARAMETER num_ctx 8192
```

5. Verify with `curl http://127.0.0.1:11434/v1/models` and pin the digest in Gateway config and
   `ollama/digests.md`.

## Model store location

- **Docker Compose (default):** named volume `ollama_models` → `/root/.ollama` in the container.
- **Host bind-mount overlay:** `docker-compose.host-models.yaml` (auto-enabled by `ollama_compose.sh`
  when `${OLLAMA_HOST_MODELS}/models` exists).
- **Bare-metal Ollama:** `~/.ollama/models` (Linux) or `%USERPROFILE%\.ollama\models` (Windows).

To use a fixed host directory instead of a named volume, replace the volume mapping in
`ollama/docker-compose.yaml`:

```yaml
volumes:
  - /opt/aiclinic/ollama:/root/.ollama
```

## Model swap (Gateway auto-trigger)

Feature 016 adds **automatic model swap** when no `READY` runner advertises the required
capability but a configured runner has the capable model **unloaded**. The Gateway (not the
runner) orchestrates the swap — no runner-side code or compose changes are required; Ollama's
native load API is used.

### How the Gateway swaps

1. A generation request arrives for a capability (e.g. `json_grammar`) with no `READY` match.
2. The selector picks the **least-busy** candidate runner whose `models[]` entry provides the
   capability but is not currently loaded.
3. The runner enters `STARTING`; the Gateway calls Ollama's load endpoint:

   `POST http://127.0.0.1:11434/api/load` with body `{"name": "<model_tag>"}`

   (`swap.py` strips an OpenAI-compatible `/v1` suffix from `base_url` before calling `/api/load`.)
4. The Gateway polls until the runner reports `READY` with the expected model+digest, within
   `model_swap_first_token_timeout_s` (default **60 s** in `gateway.yaml`).
5. On success, routing proceeds normally. On timeout or load failure → `503 ai_no_capacity`.

**Invariant:** at most **one model resident in RAM** per runner during a swap (Ollama unloads the
previous model before the new one is ready). Concurrent requests while the runner is `STARTING`
queue or receive `503 ai_busy` per the resilience envelope.

Configure multiple swappable models on one runner by listing each under `runners[].models[]`
with distinct `name`, `digest`, and `capabilities` pins.

### Manual swap (operator / debug)

Use the same API the Gateway calls — useful when validating a new model tag before pinning:

```bash
# Unload current model (optional — /api/load replaces in place)
curl -s -X POST http://127.0.0.1:11434/api/unload -d '{"name": "qwen3:4b"}'

# Load target model (Gateway sends this during auto-swap)
curl -s -X POST http://127.0.0.1:11434/api/load \
  -H 'Content-Type: application/json' \
  -d '{"name": "qwen3:4b"}'

# Confirm resident model + digest
curl -s http://127.0.0.1:11434/v1/models | jq .
docker compose -f ollama/docker-compose.yaml exec ollama ollama ps
```

Watch Gateway metrics during a swap: `ai_model_swaps_total{runner,outcome}` on `:8090/metrics`.

## Digest pinning

Every production deployment MUST pin the loaded model digest (`sha256:…`) in:

1. `ai/runners/ollama/digests.md` (operator record)
2. `ai/gateway/config/gateway.yaml` under each runner's `models[]` entry

The Gateway health poller reads the live digest from `GET /v1/models` and compares it against the
declared pin during capabilities reporting.

## Grammar-constrained decoding (feature 016)

### Ollama (default runtime)

The Gateway sends scheduling JSON schemas as Ollama's `format` field on
`POST /v1/chat/completions` (OpenAI-compatible API). No runner code changes are required — Ollama
enforces the schema per request via `to_ollama_format()` in
`ai/gateway/src/gateway/agents/scheduling/grammar.py`.

### `llama-server` (alternative runtime — GBNF)

If you replace Ollama with **`llama-server`** (llama.cpp), Ollama's `format` parameter is not
available. The Gateway provides the same scheduling JSON schema translated to **GBNF** via
`to_gbnf()` in `grammar.py` (mapping rules in
`specs/016-ai-generation-scheduling/contracts/scheduling-schema.md` §4.2).

| JSON Schema construct | GBNF equivalent |
| --- | --- |
| `"type":"object"` | `object ::= ws "{" ... "}" ws` |
| `"required"` | named field rules in fixed order |
| `"enum"` | `"(" value "|" value ")"` alternation |
| `"format":"date"` | ISO-date character pattern |
| `"pattern"` | corresponding GBNF character class |

**Operator steps for `llama-server`:**

1. Generate the grammar (from the gateway venv):

```bash
cd ai/gateway
python -c "
from gateway.agents.scheduling.schemas import envelope_schema
from gateway.agents.scheduling.grammar import to_gbnf
print(to_gbnf(envelope_schema()))
" > /opt/aiclinic/models/scheduling.gbnf
```

2. Start `llama-server` with the grammar file (example):

```bash
llama-server \
  --model /opt/aiclinic/models/qwen3-4b-q4_k_m.gguf \
  --grammar-file /opt/aiclinic/models/scheduling.gbnf \
  --host 127.0.0.1 --port 8080
```

3. Point Gateway `runners[].base_url` at the `llama-server` OpenAI-compatible endpoint
   (e.g. `http://127.0.0.1:8080/v1`). Constrained decoding is enforced by the grammar file on
   the runner; the Gateway still runs `jsonschema` validation as defense-in-depth.

Production deployments use **Ollama + `format`** by default; GBNF is documented for the
documented alternative runtime only.

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
