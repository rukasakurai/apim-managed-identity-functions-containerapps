# Project Overview

This is a sample implementation of an HTTP API and a WebSocket API using Azure Functions and Azure Container Apps, respectively. The APIs are secured using Azure API Management (APIM) with Managed Identity authentication.


## Interaction Mode (Clarification & Verbosity)

Before implementing or giving a final answer, ask clarifying questions, unless the intent is crystal clear.

## Minimal Code Change Policy

When modifying existing code:
- Prefer refactors that maintain or reduce line count unless there is a clear net gain (security, readability, or correctness).
- Avoid preemptive generalization (YAGNI).
- If adding helper abstractions, document the rationale inline ("why now") or in the PR description.

## Coding Standards

### General Principles

- **Security First**: This project demonstrates managed identity authentication patterns. Always prioritize secure authentication and avoid storing secrets in code.
- **Demonstration Purpose**: Code is for demonstration only and not production-ready. Include appropriate warnings in documentation.

### Bicep Infrastructure Standards

- Use recent stable API versions
- Enable managed identity for Azure resources
- Configure diagnostic settings for monitoring
- Use Log Analytics for centralized logging

#### Comments
- Add section comments for major resource groups
- Document non-obvious configuration choices
- Explain security-related settings

### Scripting
- Use bash for scripting

### Documentation Standards

#### Code Comments
- Comment the "why" not the "what"
- Document workarounds and known limitations
- Reference related documentation or issues where applicable
- Keep comments up-to-date with code changes

#### Markdown Files
- Use descriptive section headers
- Link to related documentation
- Keep line length reasonable for readability

### Azure-Specific Standards

#### Managed Identity
- Always use system-assigned managed identity for Azure resources
- Document the identity's role assignments
- Use managed identity for service-to-service authentication

### KQL Query Guidance (Concise)

- In Log Analytics (Azure Monitor Logs), a blank line starts a new query; anything defined earlier in the previous block (let variables, inline functions, datatable bindings) is out of scope afterward.
- Keep related definitions (variable/function/datatable) immediately above their first use (no blank line) unless you intend a new independent query.
- Use a blank line only when you deliberately start a separate query (add a short comment if it’s not obvious).
- Terminate statements with semicolons for clarity; add a brief “why” comment for non-trivial setup definitions.

#### Schema Verification

Priority order for identifying columns (no guessing):
1. Check official docs / MS Learn for table schema (e.g. App Gateway access logs, APIM gateway logs). Copy the doc URL into a comment if you rely on it.
2. Only if docs don’t clearly show the needed field, run one lightweight schema probe (`| getschema` OR `| take 5`). Never add both.
3. Do not reference any column until confirmed by step 1 or 2.

Rules:
- No invented names. If uncertain, add `// TODO: confirm latency column` instead of guessing.
- If you *must* proceed before confirmation, mark: `// ASSUMPTION:<what>` and remove before merge.
- First exploratory change after a new table: ≤5 new lines.

Goal: zero speculative columns; smallest diff that advances knowledge.