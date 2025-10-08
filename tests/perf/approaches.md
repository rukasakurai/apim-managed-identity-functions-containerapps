# Overview
Goal: obtain per-request latency correlation (App Gateway → APIM → backend) to measure gateway-added overhead.


# Approaches
Table compares accuracy, feasibility, required traffic changes, and analysis effort; fallback methods kept only for sanity checks.

| Approach                                                                                       | Per-Request Accuracy | Production Feasibility | Traffic Mod Needed* | Analysis Complexity | Notes                                                                                                                                                                    |
| ---------------------------------------------------------------------------------------------- | -------------------- | ---------------------- | ------------------- | ------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| [**Platform header correlation**](./platform-header-correlation.md)<br>AGW `transactionId` ↔ APIM `x-appgw-trace-id` | ✅ High               | ✅ Yes                  | ❌ No                | ✅ Low–Med           | Enable APIM diagnostics to log `x-appgw-trace-id`; join to AGW `transactionId` (normalize dashes if needed). No client or URL changes.                                   |
| [**Synthetic rid (query)**](./synthetic-rid-correlation-rationale.md)                           | ✅ High               | ✅ Yes                  | ⚠️ Yes              | ⚠️ Med–High         | Add `?rid=` to requests; extract from AGW **FirewallLogs** and APIM logs (requires surfacing in APIM—e.g., header logging or trace). More moving parts than header path. |
| **Distributed tracing**                                                                        | ✅ High *(future)*    | ⚠️ Partial today       | ⚠️ Yes              | ✅ Low–Med           | Ideal once AGW participates in W3C tracing; not full-fidelity through AGW yet.                                                                                           |
| [**Dual benchmark (aggregate subtraction)**](./appgw_apim_non_correlated_latency_delta.md)     | ❌ Aggregate only     | ✅ Yes                  | ❌ No                | ⚠️ Medium           | Coarse guardrail; interleave windows to reduce drift.                                                                                                                    |
| **Client-side timing**                                                                         | ❌                    | ⚠️ Lab only            | ⚠️ Yes              | ✅ Low               | Simple sanity check; sensitive to client↔AGW jitter.                                                                                                                     |

* **Traffic Mod Needed = modifying the HTTP request/response path (clients, headers on the wire, URL).**
APIM diagnostics configuration **does not** count as traffic modification.