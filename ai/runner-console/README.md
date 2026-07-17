# AI Model Runner Console

Local operator console for the Ollama inference node. Complements the
[AI Gateway dashboard](../dashboard/) — use the gateway for registry, JWT routing, and clinic
traffic; use this console for direct inference testing and runtime control on the server.

## Prerequisites

- Ollama on `127.0.0.1:11434` (`cd ai/runners && ./start.sh`)
- At least one model pulled (e.g. `qwen3:4b`)
- Python 3
- Optional: AI Gateway on `8090` for capabilities and observability bridge

## Run

```bash
cd ai/runners
./scripts/serve_console.sh
```

Open [http://127.0.0.1:11435](http://127.0.0.1:11435).

Binds to **localhost only** (`127.0.0.1`) — do not expose beyond the node.

Environment overrides:

| Variable | Default |
| --- | --- |
| `RUNNER_CONSOLE_HOST` | `127.0.0.1` |
| `RUNNER_CONSOLE_PORT` | `11435` |
| `OLLAMA_BASE_URL` | `http://127.0.0.1:11434` |
| `GATEWAY_URL` | `http://127.0.0.1:8090` |

## Server APIs (`console_server.py`)

| Endpoint | Method | Purpose |
| --- | --- | --- |
| `/api/runtime` | GET | Ollama online, GPU, processor, loaded models, compose summary |
| `/api/runtime` | POST | Toggle GPU (`{"enabled": true\|false}`) — restarts Ollama |
| `/api/config` | GET | Console bind, upstream Ollama/Gateway URLs |
| `/api/compose/status` | GET | Docker compose health, GPU profile, host models mount |
| `/api/runtime/logs?lines=N` | GET | Tail Ollama container logs |
| `/api/gateway/capabilities` | GET | Proxy → gateway `GET /v1/capabilities` |
| `/api/gateway/status` | GET | Proxy → gateway `GET /v1/status` |
| `/api/gateway/metrics` | GET | Proxy → gateway `GET /metrics` |
| `/api/gateway/auto-sign-in` | POST | Proxy → gateway dev auto sign-in |
| `/api/runner/*` | * | Proxy → Ollama (chat, generate, models, tags, version, …) |

## UI panels

| Panel | What it does |
| --- | --- |
| **Model rail** (header) | Live RAM snapshot from `ollama ps` — processor badge, context, size |
| **Playground** | Streaming `POST /api/chat`, thinking mode, request/response inspector |
| **Generate** | `POST /api/generate` completion probe |
| **Models** | Inventory from `/v1/models` + `/api/tags` |
| **API** | Quick probes + custom path/method explorer |
| **Runtime** | GPU toggle, compose status, container log tail |
| **Gateway** | Capabilities mirror, dev sign-in, registry observability |
| **Settings** | Proxy base, poll interval, gateway reference URL (`localStorage`) |

## NVIDIA GPU

Install [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/install-guide.html), then enable GPU in the **Runtime** panel or:

```bash
cd ai/runners
bash scripts/ollama_compose.sh set-gpu 1
bash scripts/ollama_compose.sh up
```

Preference is stored in `ollama/.gpu-enabled`.

## Security

For operators on the AI server node only. Inference bypasses the gateway JWT gate. Do not bind
`11435` beyond localhost. Gateway JWTs entered in the UI are stored in `localStorage` on this origin.

## Layout

| File | Role |
| --- | --- |
| `index.html` | Shell, model rail, tab panels |
| `styles.css` | Operator console theme (no build step) |
| `app.js` | Polling, chat streaming, API explorer, gateway bridge |
