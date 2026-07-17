# AI Model Runner Console

A zero-build static UI for interacting with the local Ollama runner. It complements the
[AI Gateway control plane dashboard](../dashboard/) — use the gateway dashboard for registry,
health polling, and JWT-protected proxy probes; use this console for direct inference testing on
the server node.

## Prerequisites

- Ollama running on `127.0.0.1:11434` (see `ai/runners/ollama/docker-compose.yaml`)
- At least one model pulled (e.g. `qwen3:4b`)
- Python 3 (for the static file server)

## Run locally

```bash
cd ai/runners
./scripts/serve_console.sh
```

Open [http://127.0.0.1:11435](http://127.0.0.1:11435).

The console binds to **localhost only** — same non-routability posture as Ollama itself.

The server (`scripts/console_server.py`) serves static files and localhost runtime APIs (`GET /api/runtime`, `POST /api/runtime/gpu`).

## NVIDIA GPU (optional)

On the AI server node, install [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/install-guide.html), then use the **Compute runtime** panel in the console to enable GPU and restart Ollama.

Or from the shell:

```bash
cd ai/runners
bash scripts/ollama_compose.sh set-gpu 1
bash scripts/ollama_compose.sh up
```

Disable GPU:

```bash
bash scripts/ollama_compose.sh set-gpu 0
bash scripts/ollama_compose.sh up
```

Preference is stored in `ollama/.gpu-enabled`. Verify with `docker compose exec ollama ollama ps` — **PROCESSOR** should show `100% GPU` when a model is loaded.

## Features

| Panel | API | Purpose |
| --- | --- | --- |
| Compute runtime | `GET/POST /api/runtime` | Toggle NVIDIA GPU (restarts Ollama) |
| Runner endpoint | — | Configure base URL (default `http://127.0.0.1:11434`) |
| Status | `GET /v1/models` | Latency, model count, digest, context window |
| Models | `GET /v1/models` | Pick active model for chat |
| Chat playground | `POST /api/chat` | Send messages; thinking mode maps to Ollama `think` (`false` / `true` / omit) |
| Model output (raw) | — | Full request, stream chunks, parsed thinking/content |
| API explorer | `/v1/models`, `/api/tags`, `/api/version` | Quick raw probes |

Preferences (base URL, poll interval, selected model, thinking mode) are stored in `localStorage`.

## Layout

| File | Role |
| --- | --- |
| `index.html` | Shell and panel scaffolding |
| `styles.css` | Dark-theme layout (no build step) |
| `app.js` | Polling, chat (incl. SSE streaming), API explorer |

## Security note

This UI is for **operators on the AI server node**. It bypasses the gateway and has no JWT gate.
Do not expose port `11435` beyond `127.0.0.1`.
