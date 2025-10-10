# Overview
Goal: obtain per-request latency correlation (App Gateway → APIM → backend) to measure gateway-added overhead.


# Approaches
Table compares accuracy, feasibility, required traffic changes, and analysis effort; fallback methods kept only for sanity checks.

| Approach                                                                                       | Per-Request Accuracy | Production Feasibility | Traffic Mod Needed* | Analysis Complexity | Notes                                                                                                                                                                    |
| ---------------------------------------------------------------------------------------------- | -------------------- | ---------------------- | ------------------- | ------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| [**Platform header correlation**](./platform-header-correlation.md)<br>AGW `transactionId` ↔ APIM `x-appgw-trace-id` | ✅ High               | ✅ Yes                  | ❌ No                | ✅ Low–Med           | Enable APIM diagnostics to log `x-appgw-trace-id`; join to AGW `transactionId` (normalize dashes if needed). No client or URL changes.                                   |
| [**Synthetic rid (query)**](./synthetic-rid-correlation-rationale.md)                           | ✅ High               | ✅ Yes                  | ⚠️ Yes              | ⚠️ Med–High         | Add `?rid=` to requests; extract from AGW **FirewallLogs** and APIM logs (requires surfacing in APIM—e.g., header logging or trace). More moving parts than header path. |
| **Application Map (future distributed tracing)**                                               | ✅ High *(future)*    | ❌ Not yet             | ❌ No                | ✅ Low–Med           | Requires Application Gateway to emit its own trace event (timed operation) plus full standard trace context propagation to surface AGW→APIM→backend nodes; today no first-class AGW node in Application Map. |
| [**Dual benchmark (aggregate subtraction)**](./appgw_apim_non_correlated_latency_delta.md)     | ❌ Aggregate only     | ✅ Yes                  | ❌ No                | ⚠️ Medium           | Coarse guardrail; interleave windows to reduce drift.                                                                                                                    |
| **Client-side timing**                                                                         | ❌                    | ⚠️ Lab only            | ⚠️ Yes              | ✅ Low               | True end-to-end (user‑perceived) latency, but high network/client variance swamps per-request gateway delta; use only as sanity check or to validate overall UX trends. |

* **Traffic Mod Needed = modifying the HTTP request/response path (clients, headers on the wire, URL).**
APIM diagnostics configuration **does not** count as traffic modification.

## Application Map (potential future distributed tracing compatibility)

Goal is a native Azure Monitor / Application Insights Application Map chain showing Client → Application Gateway → APIM → Backend with per-hop latency and shared trace context. This requires future capability for Application Gateway to emit (or be represented by) a trace event (a timed operation record using the standard distributed trace context) so Application Insights can link it. Right now there is no first-class gateway node; synthetic trace events could be prototyped but would be custom and not production standard. After AGW emits native trace events, per-request latency attribution becomes high fidelity without any traffic modification.


## Client-side timing
Client-side timing measures the total round-trip latency as observed by the end user or client device. This includes all network, gateway, APIM, backend, and client-side processing delays. It is the only method that captures true user-perceived latency, but it cannot isolate the gateway’s contribution due to high variance from network and client factors. Best used for sanity checks, aggregate UX validation, or in tightly controlled lab environments—not for precise per-request gateway overhead attribution in production.
