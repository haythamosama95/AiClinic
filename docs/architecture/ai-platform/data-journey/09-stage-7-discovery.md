# AI Platform Data Journey — Stage 7 — Discovery (`GET /v1/capabilities`)

## Table of Contents

1. [Plain language](#1-plain-language)
2. [Request](#2-request)
3. [D1 reads (via config cache)](#3-d1-reads-via-config-cache)
4. [Response shape (conceptual)](#4-response-shape-conceptual)
5. [Failure paths](#5-failure-paths)

---




## 1. Plain language

The client asks "what AI features can I use?" The platform lists capabilities where entitlement + grants pass. Kill switches are **not** applied on discovery (they apply on invoke).

## 2. Request


| Item   | Value                         |
| ------ | ----------------------------- |
| Method | `GET /v1/capabilities`        |
| Auth   | `Authorization: Bearer <AAT>` |


No body. No extra required headers.

## 3. D1 reads (via config cache)


| Cache kind      | Key                | Purpose                          |
| --------------- | ------------------ | -------------------------------- |
| `installations` | `{installationId}` | Installation exists              |
| `entitlements`  | `{installationId}` | `status`, `allowed_capabilities` |
| `grants`        | per capability     | Version grants                   |




## 4. Response shape (conceptual)

List of capability manifests the installation may invoke — filtered to entitled, granted, non-retired capabilities.

**Pending entitlement:** typically empty list or no capabilities.

## 5. Failure paths

Same as identity stage 2 — invalid AAT → `401 unauthenticated`.
