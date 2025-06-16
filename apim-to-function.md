# Connecting Azure API Management to an Azure Function Backend

## Sequence Diagram: Managed Identity JWT Flow

Below is a sequence diagram representing the architecture flow from the provided image, showing how APIM, Azure AD, App Registration, Managed Identities, and the Function App interact:

```mermaid
sequenceDiagram
    participant Client
    participant APIM as API Management
    participant AAD as Azure AD
    participant AppReg as App Registration
    participant MI as User Assigned Managed Identity
    participant Function as Azure Function (Private)

    Client->>APIM: Call API (Trusted/Untrusted Operation)
    APIM->>AAD: Request JWT for User Assigned Managed Identity
    APIM->>AppReg: Request JWT for User Assigned Managed Identity
    alt Managed Identity assigned to Enterprise App
        AAD-->>APIM: Return JWT
        AppReg-->>APIM: Return JWT
        APIM->>Function: Forward request with JWT
        Function->>AAD: Validate JWT
        Function->>AppReg: Validate JWT
        alt JWT is valid and for trusted MI
            Function-->>APIM: Success Response
            APIM-->>Client: Success Response
        else JWT invalid or MI not trusted
            Function-->>APIM: 401/403 Error
            APIM-->>Client: Error Response
        end
    else Managed Identity not assigned
        AAD-->>APIM: Error (cannot create JWT)
        AppReg-->>APIM: Error (cannot create JWT)
        APIM-->>Client: 500 Error
    end
```

---

## Previous Sequence Diagram (Simple Flow)

```mermaid
sequenceDiagram
    participant Client
    participant APIM as API Management
    participant Function as Azure Function

    Client->>APIM: HTTP Request
    APIM->>APIM: Apply policies
    APIM->>Function: Forward HTTP Request
    Function-->>APIM: HTTP Response
    APIM-->>Client: HTTP Response
```
