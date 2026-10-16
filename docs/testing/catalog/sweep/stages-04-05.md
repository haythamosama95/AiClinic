# Silent-Workaround Sweep — Stages 04 (Entitlement & capability grants) and 05 (Routing policy)

> **Superseded.** This entrypoint document is retained only as a pointer. The v2 ABO design replaces the legacy platform control-plane flows described here. Clinic traffic now uses issuer tokens and `Aip-Contract-Version: 1` on `GET /v1/capabilities`, `POST /v1/requests`, and `GET /v1/requests/{request_reference}` against the local platform worker.

## 1. Replacement design

- [ABO contracts (v2)](../../../architecture/ai-billing-orchestration/04-abo-contracts.md)
- [ABO operations and traceability (v2)](../../../architecture/ai-billing-orchestration/05-abo-operations-and-traceability.md)

## 2. Clinic entrypoints in the viewer

The `ai-platform-viewer` catalog keeps stages 7–12 only. Use those pages to exercise discovery, ingress, guard, stream, settlement, and lookup against `http://127.0.0.1:8787` with the test issuer key from `ai-platform/.dev.vars`.
