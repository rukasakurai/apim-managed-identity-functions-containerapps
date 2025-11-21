#!/usr/bin/env bash
# Minimal variant (no explicit error handling / conditionals)
source <(azd env get-values)
WORKSPACE_ID="$logAnalyticsWorkspaceCustomerId" # GUID form accepted by az monitor log-analytics query
KQL_FILE="${1:-tests/perf/appgw_overhead_simple.kql}"   # optional positional arg to pick a different .kql file
KQL_QUERY="$(<"$KQL_FILE")"
echo "Workspace: $WORKSPACE_ID  QueryFile: $KQL_FILE" >&2
az monitor log-analytics query --workspace "$WORKSPACE_ID" --analytics-query "$KQL_QUERY" -o table
