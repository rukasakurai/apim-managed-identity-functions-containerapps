# Platform Header Correlation (Recommended)

> Status: **Draft** – intended for establishing accurate per‑request latency overhead between Azure Application Gateway (AGW) and Azure API Management (APIM) **without modifying traffic** (no query params, no custom headers injected by clients). Follows repo KQL + documentation standards.
>
> Goal: Derive a deterministic join key between AGW and APIM diagnostic log tables using platform‑emitted identifiers so we can compute per‑request overhead distribution (p50 / p90 / p99) with minimal operational friction.

> ⚠️ **Warning**: This repository, and section is for demonstration purposes only and should not be considered production-ready. It is designed to showcase concepts and patterns. Before using any concepts, approaches, code or configurations in a production environment, please review and adapt them according to your organization's security, compliance, and operational requirements.

## Rationale (Why This Approach)
- **Zero client changes**: Relies only on enabling diagnostic categories; no query parameter (`rid`) or header adornment needed.
- **Deterministic pairing**: Uses AGW `transactionId` and APIM surface of the same identifier via the `x-appgw-trace-id` request header (exposed in APIM gateway logs once included in diagnostic logging).
- **Operationally safer** than synthetic IDs (no risk of forgetting to append a parameter or polluting caches / analytics).
- **Future‑proof**: If/when broader distributed tracing lands for AGW, this mapping can complement W3C trace context rather than compete with it.

## Preconditions
| Item | Requirement |
|------|-------------|
| Diagnostic Destination | Both AGW & APIM gateway logs routed to the **same** Log Analytics workspace. |
| AGW Logs | `AccessLogs` (and WAF logs if WAF enabled) turned on. |
| APIM Logs | `GatewayLogs` diagnostic category enabled (captures request/response context + selected headers). |
| Header Capture | Ensure `x-appgw-trace-id` is among the logged headers (add to APIM diagnostic setting if selective capture is configured). |
| Time Sync | Default Azure resource timestamp alignment is sufficient; no manual clock sync needed. |

## High-Level Flow
1. Client issues request → AGW assigns a `transactionId` (UUID format) and forwards to APIM.
2. AGW injects `x-appgw-trace-id` (alias of the same underlying id) on the upstream request toward APIM.
3. APIM gateway diagnostics record the inbound header value when header logging is enabled.
4. In Log Analytics:
   - From `AGWAccessLogs` extract `transactionId` as `corrId`.
   - From `ApiManagementGatewayLogs` extract header value `x-appgw-trace-id` as `corrId`.
   - Inner join on `corrId` with an optional time skew guard (e.g. | where abs(datetime_diff('second', AgwTime, ApimTime)) < 5 ).
5. Compute per‑request overhead = `AgwTimeTakenMs - ApimTotalTimeMs` (after unit normalization).

## KQL Query Skeleton
> Only reference confirmed columns. If uncertain, run a one‑off schema probe for each table separately (`... | getschema`) – DO NOT commit probes.

Maintained query file: [`./kql/platform_header_correlation_overhead.kql`](./kql/platform_header_correlation_overhead.kql). Treat the file as the authoritative source; the inline snippet below is a simplified snapshot and may drift.

```kql
// Window (adjust as needed)
let StartTime = ago(1h);
let EndTime = now();

// AGW slice: TimeTaken is in seconds per docs – convert to ms.
let Agw = AGWAccessLogs
| where TimeGenerated between (StartTime .. EndTime)
| project corrId = tostring(transactionId),
          agw_time = TimeGenerated,
          agw_latency_ms = toreal(TimeTaken) * 1000.0,
          agw_status = tostring(httpStatus);

// APIM slice: TotalTime already in ms; header captured as x-appgw-trace-id.
let Apim = ApiManagementGatewayLogs
| where TimeGenerated between (StartTime .. EndTime)
| extend corrId = tostring(RequestHeaders['x-appgw-trace-id'])
| where isnotempty(corrId)
| project corrId,
          apim_time = TimeGenerated,
          apim_latency_ms = toreal(TotalTime),
          apim_operation = OperationName,
          apim_status = ResponseCode;

Agw
| join kind=inner Apim on corrId
| extend overhead_ms = agw_latency_ms - apim_latency_ms
| where overhead_ms >= 0 // sanity: negative indicates mismatch / partial window
| summarize count = count(),
            p50_overhead = percentile(overhead_ms, 50),
            p90_overhead = percentile(overhead_ms, 90),
            p99_overhead = percentile(overhead_ms, 99),
            mean_overhead = avg(overhead_ms),
            agw_mean = avg(agw_latency_ms),
            apim_mean = avg(apim_latency_ms)
| project StartTime, EndTime, count,
          agw_mean_latency_ms = agw_mean,
          apim_mean_latency_ms = apim_mean,
          mean_overhead_ms = mean_overhead,
          p50_overhead, p90_overhead, p99_overhead;
```

### Notes on the KQL
- `RequestHeaders['x-appgw-trace-id']` assumes APIM gateway logs include the full headers map; confirm presence once before relying on it.
- The explicit `overhead_ms >= 0` filter is a guard against accidental mismatches (e.g., stale APIM entry joined with a fresh AGW entry). Investigate any significant proportion of dropped (negative) rows.
- Consider adding an additional skew filter: `| where abs(datetime_diff('second', agw_time, apim_time)) < 5` before summarizing for tighter pairing validation.

## Validation Checklist
| Check | Purpose | Action |
|-------|---------|--------|
| Header presence | Ensure correlation key exists | Spot query: `ApiManagementGatewayLogs | take 1 | project RequestHeaders` |
| Coverage rate | Ensure high pairing fraction | Compare joined count vs AGW count for window (expect >95% excluding WAF blocks). |
| Unit sanity | Prevent ms vs s mistakes | Verify typical agw_latency_ms magnitude aligns with apim_latency_ms + plausible overhead. |
| Negative overhead anomalies | Detect join drift | Count filtered negatives; if >1%, inspect time skew or missing headers. |

## Advantages
- No test harness dependency (can be adopted in production traffic once diagnostics policy approved).
- Scales transparently with load; no identifier generation bottleneck.
- Simplifies performance regression monitoring (drop query into Workbook / scheduled alert).

## Limitations / Caveats
| Limitation | Impact | Mitigation |
|------------|--------|------------|
| Requires header to be captured | Misconfiguration breaks join | Add deployment validation step; alert on low join coverage. |
| Potential schema evolution | Query breakage | Version control queries; add lightweight CI schema probe. |
| WAF short‑circuit requests | Appear only in AGW logs | Track unmatched AGW count separately for context. |
| Diagnostic cost | Additional log ingestion | Scope window & categories; consider sampling for non‑critical environments. |

## When to Use Synthetic rid Instead
Use the synthetic `rid` query parameter approach only if:
- Regulatory or policy constraints disallow logging the `x-appgw-trace-id` header, OR
- You need side‑by‑side experimentation isolating header capture overhead vs baseline, OR
- Future scenario: platform stops emitting the header (unlikely but covered by fallback).

## Production Hardening Ideas (Optional)
- Add a Workbook panel: (a) Overhead percentiles trend, (b) Join coverage (% of AGW requests paired), (c) Distribution histogram top N operations.
- Alert if p99 overhead exceeds an SLO band (e.g., `> 40 ms` for 3 consecutive 5‑minute windows).
- Track drift of mean overhead vs deploy markers (annotations).

## Removal / Migration Strategy
If/when AGW provides first‑class W3C trace context end‑to‑end, migrate to `traceparent` correlation:
1. Run both methods in parallel for a deprecation window.
2. Compare overhead distributions (two‑sample KS test or percentile difference thresholds).
3. Remove header correlation query only after parity is demonstrated.

## Summary
Platform header correlation offers a **low‑friction, high‑accuracy** mechanism to pair AGW and APIM requests using existing platform identifiers, enabling reliable per‑request overhead analysis without modifying traffic shape. Maintain strict validation (coverage, unit sanity) and you obtain trustworthy latency percentiles suitable for regression detection.
