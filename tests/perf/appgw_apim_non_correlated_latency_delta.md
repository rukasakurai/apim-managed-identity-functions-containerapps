## Approximation (App Gateway vs APIM)

This folder contains quick Kusto (KQL) scripts to perform a **directional** (approximate) check of latency overhead added by inserting Azure Application Gateway (AGW) in front of Azure API Management (APIM).

> Goal: Validate telemetry plumbing and obtain a first-order mean latency delta. Not a precise per-request overhead measurement.

> ⚠️ **Warning**: This repository, and section is for demonstration purposes only and should not be considered production-ready. It is designed to showcase concepts and patterns. Before using any concepts, approaches, code or configurations in a production environment, please review and adapt them according to your organization's security, compliance, and operational requirements.

### Files

- `appgw_overhead_simple.kql` – single, beginner‑friendly query that computes a **mean vs mean** latency delta between Application Gateway access logs (`AGWAccessLogs`) and APIM gateway logs (`ApiManagementGatewayLogs`).
- (See also: more detailed slice / window queries in the sibling `appgw_overhead.kql` / `appgw_slice.kql` files if/when they are added – the simple file is intentionally the on‑ramp.)

"Simple" here means: **minimum moving parts to prove telemetry is flowing and to get a directional number** before investing in tighter correlation logic.

### How It Works (Concept)

The simple query:
1. Defines a single time window (`StartTime = ago(7d)` .. `EndTime = now()`).
2. Independently computes:
	- Mean AGW end‑to‑end request time: `TimeTaken` (seconds) from `AGWAccessLogs`, multiplied by 1000 to convert to milliseconds.
	- Mean APIM gateway processing time: `TotalTime` (already milliseconds) from `ApiManagementGatewayLogs`.
3. Subtracts the two scalar means to produce a coarse "overhead" estimate: `agw_mean_latency_ms - apim_mean_latency_ms`.

Important: This is a **difference of independent means**, not a per‑request join. It does *not* pair up individual requests flowing through both layers. It is therefore only directional.

Why start here:
- Fast feedback that both log tables contain data with expected value ranges.
- Teaches newcomers how to declare lets, use `toscalar`, and print a composite record.
- Helps catch obvious misconfigurations (e.g., `TimeTaken` zero or missing, APIM logs disabled) before building more exact correlation queries.


### Running the Queries

1. Open Log Analytics for the workspace receiving both AGW and APIM diagnostics.
2. Paste the contents of `appgw_overhead_simple.kql` into the query editor.
3. (Optional) Adjust `StartTime` / `EndTime` – keep the window reasonably narrow (e.g. 1–24h) if you want fresher signal or to avoid skew from deployments.
4. Run. The output is a single row with mean values and the computed difference.

KQL style notes (matching repo guidance):
- All definitions (`let`) are directly above their first use (no blank line) to keep scope obvious.
- A single query block; adding a blank line would intentionally start a new, unrelated query.
- We only reference confirmed columns: `TimeTaken` (AGW) and `TotalTime` (APIM). Both are standard (see Azure docs for Application Gateway access logs & APIM gateway logs).


### Interpreting Output

Fields returned:
- `agw_mean_latency_ms` – Mean of AGW `TimeTaken` converted to ms. Represents total time from AGW’s perspective (client -> AGW -> backend response) including network + APIM + backend.
- `apim_mean_latency_ms` – Mean APIM `TotalTime` (processing duration inside APIM including backend call and policies, per APIM logging semantics).
- `overhead_mean_ms` – Simple difference (AGW mean – APIM mean). Interpreted loosely as additional fronting + network overhead introduced by AGW.
- `StartTime` / `EndTime` – The evaluated window boundaries.

Directional meaning:
- A small positive number: AGW adds low average overhead (expected).
- A large positive number: investigate network path, WAF processing, TLS negotiation, or skewed window/sample differences.
- Negative: usually indicates sampling / window mismatch or missing AGW entries (APIM mean > AGW mean should not happen for true paired requests).


### Limitations / Caveats

This quick check deliberately trades accuracy for simplicity:

- Not a per‑request correlation – mixes potentially different traffic compositions between AGW and APIM (difference of means ≠ mean of differences).
- Missing logs (ingestion delay, retention gaps, throttling) distort means; any absent AGW or APIM records bias the delta.
- WAF‑blocked or otherwise short‑circuited requests appear only (or primarily) in AGW logs; they inflate AGW mean vs APIM mean.
- Different operation mixes (e.g., heavy vs light backend calls) between early and late portions of the 7‑day window can skew results; choose tighter windows for more stability.
- Clock skew is usually negligible (service‑side timestamps) but ingestion latency might still cause partial windows near `now()`.
- Outliers (very slow backend calls) impact means; consider using `percentiles` or a trimmed mean in advanced queries.
- Units: `TimeTaken` is in seconds; forgetting the `* 1000` conversion would mislead by 3 orders of magnitude (the query already handles this).
- Security / policy layers (WAF, custom policies) can add conditional overhead not visible as separate metrics here.

When to move beyond this file:
- Need per‑request correlation / distributional view (use join on operation IDs if both logs expose a stable correlation key).
- Need percentile breakdowns (P50/P90/P99) or time‑sliced trends.
- Need to exclude specific paths, status codes, or WAF actions.

If uncertain about column availability: per repo guidance, run a single lightweight schema probe (`AGWAccessLogs | getschema`) – do **not** add it to this committed file.
