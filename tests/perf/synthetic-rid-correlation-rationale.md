> **⚠️ Draft Notice:** This document is an in-progress working draft intended for exploratory performance methodology only. Content (including hypotheses, rationale, and proposed implementation details) may be incomplete or inaccurate and MUST NOT be treated as production guidance without further validation and revision. Expect breaking revisions / removals.

> Related helper artifacts: `appgw_slice.kql` (App Gateway slice), `apimgw_slice.kql` (APIM slice), `appgw_overhead.kql` (union placeholder prior to join/overhead math), and `run-appgw-overhead.sh` (shell wrapper to execute a KQL file). These are early experimental helpers and have not been deeply tested yet.

## Synthetic Request Correlation ID (rid) Rationale

> Goal: Measure end-to-end latency overhead introduced by inserting Application Gateway (AGW) in front of API Management (APIM) with statistically trustworthy per-request pairing (p50/p90/p99). We need a deterministic join key present in *both* `AGWAccessLogs` and `ApiManagementGatewayLogs`.

_Context: This document expands the **Synthetic rid (query)** approach in the comparison table (`approaches.md`)._

### Problem Statement

The Azure resource-specific diagnostic logs for AGW and APIM are emitted independently. Neither log stream surfaces a common built-in identifier that can be used to reliably pair the same client request as it traverses AGW → APIM. Without a stable per-request key we cannot compute a distribution of overhead (only coarse aggregate deltas), and heuristic joins become error-prone under concurrent load, contaminating tail latency metrics.

### Hypotheses (Unified)

| # | Hypothesis | Evidence / Rationale | Validity |
|---|------------|----------------------|----------|
| 1 | Application Insights / Azure Monitor Application Map does not support correlating AGW + APIM | Application Map renders AI-instrumented components (APIM emits, AGW does not). No passive inference from access logs alone. | Likely valid as of 2025-10-03 |
| 2 | Application Gateway does not automatically add a request ID usable across AGW→APIM | AGW access log internal identifiers not echoed in APIM gateway logs; no shared field observed in schemas. | Likely valid as of 2025-10-03 |
| 3 | Neither AGW nor APIM resource logs can be configured to parse & persist arbitrary custom headers as columns | Fixed schemas; AGW access logs omit arbitrary headers; APIM custom header capture requires Application Insights (different tables). | Likely valid as of 2025-10-03 |
| 4 | Aggregate subtraction (AGW+APIM vs APIM-only) is not a reliable substitute for per-request pairing | Time/traffic variance (jitter, scaling) biases means & tails; cannot reconstruct true per-request distribution. | Likely valid as of 2025-10-03 |
| 5 | Query parameter survives unchanged in both logged URIs | Empirically appears verbatim in `requestUri` and `RequestUrl` (schema inspection, test traffic). | Likely valid as of 2025-10-03 |
| 6 | `traceparent` / distributed tracing headers absent from AGW access logs | Schema lacks header fields; spot tests show no header capture; docs list no option for full header logging. | Likely valid as of 2025-10-03 |
| 7 | Heuristic join (method+path+time) collides under concurrency | Hot endpoint bursts create multiple candidates within same time bucket; leads to false pairings, corrupting tail metrics. | Likely valid as of 2025-10-03 |
| 8 | Tail latency analysis requires per-request pairing | Need pairwise differences to see distribution shape; aggregate subtraction masks variance & long-tail amplification. | Likely valid as of 2025-10-03 |
| 9 | Path embedding of rid increases operational complexity vs query parameter with no logging gain | Requires route/policy updates & potential cache implications; query param offers identical observability simpler. | Likely valid as of 2025-10-03 |
|10 | Backend-only logging cannot bridge AGW gap | Backend/APIM correlation possible; AGW never logs backend span → still no AGW↔APIM join key. | Likely valid as of 2025-10-03 |
|11 | Establishing rid early benefits later WAF & WebSocket analyses | Reusable mechanism lowers incremental cost; handshake (WebSocket) still logged as HTTP with query string. | Likely valid as of 2025-10-03 |
|12 | Early adoption of synthetic rid is lower cost than retrofitting later | Minimal initial change; retroactive addition cannot fix missing historical pairing; avoids future dashboard refactors. | Likely valid as of 2025-10-03 |

### Alternatives Considered & Rejected

| Alternative | Reason Rejected | Residual Risk if Adopted |
|------------|-----------------|---------------------------|
| Heuristic join on (method, path, time window ±1s) | Collisions under concurrent identical requests; false pairing skews tails. | Silent data contamination. |
| Separate AGW vs APIM benchmark & subtract means | Fails to attribute per-request overhead; susceptible to drift (scaling, jitter). | Misestimates especially at high percentiles. |
| Use custom header (e.g., X-Request-ID) only | Not logged by AGW; no join key produced. | Impossible correlation. |
| Rely on W3C traceparent | Not present in AGW logs; header discarded from log schema. | No improvement over header case. |
| Path segment rid (`/hello/<rid>`) | Works, but requires route / policy adjustments; no logging advantage. | Higher maintenance. |
| Add APIM policy to emit AGW transactionId downstream | AGW transactionId not exposed to APIM; cannot surface. | Still no shared ID. |

### Falsifiability / Validation Steps

To keep reasoning empirical rather than dogmatic, we enumerate minimal tests:
1. Header Capture Attempt (AGW): Add distinctive header; verify absence in `AGWAccessLogs` over sample (N≥50) → expect absent.
2. Heuristic Collision Probe: Generate concurrent identical requests; attempt heuristic join; compute duplicate join rate (rid baseline as ground truth) → expect >0 collisions at modest concurrency.
3. Aggregate Subtraction Variability: Alternate 5-minute windows AGW+APIM vs APIM-only; compute standard deviation of inferred overhead vs pairwise rid overhead → expect higher variance & unstable tails.

If any test *disproves* its expectation (e.g., AGW logs begin surfacing the custom header), we would revisit the chosen strategy.

### Decision

Introduce a synthetic per-request correlation id (`rid`) as a query parameter (GUID hex) on all performance test traffic passing through AGW→APIM. Extract with a regex in KQL to produce a deterministic join key across `AGWAccessLogs` and `ApiManagementGatewayLogs` for precise overhead distribution metrics.

### Implementation Summary (Planned)

1. Client / test harness appends `?rid=<guid>` to each HTTP request.
2. KQL extraction:
    ```kql
    | extend rid = tostring(extract(@"[?&]rid=([0-9a-f]+)", 1, requestUri))
    ```
    and similarly for `RequestUrl` in APIM logs; filter `isnotempty(rid)`.
3. Join on `rid`; enforce small time skew filter as sanity guard.
4. Compute `OverheadMs = AgwTimeTakenMs - ApimTotalTimeMs` (after unit normalization).
5. Summarize distribution (p50/p90/p99) & match coverage.

### Open Items

| Item | Needed Action |
|------|---------------|
| Unit normalization | Confirm `TimeTaken` vs `TotalTime` units (seconds vs ms) using sample rows. |
| KQL join file | Add `appgw_overhead_join.kql` with extraction, join, summary. |
| README examples | (Re)introduce `rid` param in manual curl examples if not already documented. |
| WebSocket scope | Decide whether to tag only handshake (`?rid=`) for future phase. |

### Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| Missing rid in some requests (legacy scripts) | Filter out rows with empty rid; track match rate; enforce alert if coverage < 95%. |
| Regex extraction failure after route changes | Centralize extraction pattern constant; add tiny KQL health query in CI. |
| GUID format variance (uppercase, braces) | Use lowercase hex generation; regex tolerant of hyphens. |

### Future Extensions

- Use the same rid when generating OpenTelemetry traceparent headers (backend) to unify with deeper spans (even if AGW does not log it).
- Add WAF-mode comparison by reusing identical rid methodology for A/B windows.
- Explore capturing rid in Application Insights for richer cross-table correlation (optional).

### Summary

Given absence of a native cross-resource request identifier and limitations of headers and tracing metadata within AGW access logs, a synthetic query-parameter `rid` is the minimal, reliable, low-friction mechanism to enable accurate, per-request latency overhead computation between Application Gateway and API Management layers.