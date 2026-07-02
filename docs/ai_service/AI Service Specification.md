# AI Service Specification

## Overview

Introduce a distributed AI layer where AI inference is performed by one or more AI Services running on capable devices within the local network.

The existing backend remains the single entry point for all clients and is responsible for orchestrating AI requests.

---

# AI Service

## Responsibilities

Each AI Service shall:

* Host exactly one local LLM instance.
* Expose a local HTTP API for inference.
* Process one inference request at a time.
* Register itself with the backend on startup.
* Periodically send heartbeat messages to the backend.
* Report its capabilities (model, version, supported features, busy/idle status).

The AI Service shall **not**:

* Access the clinic database.
* Authenticate users.
* Implement business logic.
* Communicate directly with Flutter clients.

---

# AI Service Registration

On startup, the AI Service shall register with the backend.

Minimum registration information:

* Service ID
* Machine ID
* Device name
* IP address
* Listening port
* Model name
* Model version
* Supported capabilities
* Current status (Idle)

The AI Service shall periodically send heartbeat messages so the backend can detect unavailable services.

---

# Backend Modifications

The backend shall become the AI orchestrator.

Additional responsibilities:

* Maintain a registry of available AI Services.
* Track each service's availability and current status.
* Select an appropriate AI Service for each request.
* Forward inference requests.
* Return generated responses to the requesting client.

The backend shall never expose AI Service addresses to clients.

If no AI Service is available, the backend shall return an appropriate error or queue the request (implementation-defined).

---

# Frontend Modifications

The Flutter application shall continue communicating only with the backend.

No direct communication with AI Services is permitted.

Existing AI-related actions (e.g. Generate Summary, Generate SOAP Note) shall invoke backend endpoints exactly as any other business operation.

The frontend shall remain completely unaware of:

* AI Service locations.
* AI routing.
* AI availability.
* AI deployment topology.

---

# Routing Rules

The backend is solely responsible for selecting the AI Service.

The routing algorithm is implementation-defined and may consider:

* Same device as requester.
* Assigned workstation.
* Idle AI Service.
* Load balancing.
* Future scheduling policies.

Clients shall not influence routing decisions.

---

# Concurrency

Each AI Service processes a single inference request at a time.

Different AI Services may process requests concurrently.

The backend shall prevent concurrent requests from being sent to the same busy AI Service.

---

# Design Constraints

* AI Services are independent and stateless with respect to clinic data.
* AI Services are replaceable without frontend changes.
* Clients never communicate directly with AI Services.
* The backend remains the single orchestration layer for all AI functionality.
