# Project Overview

This is a sample implementation of an HTTP API and a WebSocket API using Azure Functions and Azure Container Apps, respectively. The APIs are secured using Azure API Management (APIM) with Managed Identity authentication.


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