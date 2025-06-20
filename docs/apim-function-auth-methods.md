# APIM Authentication Methods for Azure Functions

This document compares two potential approaches for configuring Managed Identity authentication between Azure API Management (APIM) and Azure Functions.

## Current Implementation: Policy-Level Authentication

### Description

The current implementation uses the `authentication-managed-identity` policy within APIM operation policies to acquire and attach bearer tokens when calling Azure Functions.

### Implementation

**Location**: `infra/modules/apim-backend-integration/main.bicep`

### Configuration Details

```bicep
// Policy with authentication
resource operationPolicy 'Microsoft.ApiManagement/service/apis/operations/policies@2024-05-01' = {
  properties: {
    value: '<policies>
      <inbound>
        <authentication-managed-identity resource="api://{function-app-id}"/>
        <set-backend-service backend-id="{backend-name}" />
      </inbound>
    </policies>'
  }
}
```

## Potential Alternative Implementation: Backend-Level Authentication

### Description

The potential alternative approach would configure Managed Identity credentials directly in the APIM backend resource definition, eliminating the need for the `authentication-managed-identity` policy.

### Challenge

As of 2025-06-20, we have decided to pause pursuing this method, because:

- Although it was set up through the Azure Portal, we were not able to enable access to an Azure Function with Microsoft Entra Auth (a.k.a. Easy Auth) enabled.
- We could not determine the correct Bicep implementation.
