# WebSocket Hello World Application on Azure Container Apps

This project demonstrates a WebSocket application deployed to Azure Container Apps with proper infrastructure setup including Container Registry, Log Analytics, and Managed Identity.

## Architecture

- **Azure Container Apps**: Hosts the WebSocket application
- **Azure Container Registry**: Stores the container image
- **Azure Log Analytics**: Provides monitoring and logging
- **User-Assigned Managed Identity**: Secure access to Azure resources
- **Optional API Management**: Can be integrated for API gateway functionality

## WebSocket Application Features

The WebSocket server provides:

- **Echo Messages**: Sends back received messages with additional metadata
- **Ping/Pong**: Health check functionality
- **Broadcast**: Send messages to all connected clients
- **Connection Management**: Automatic client registration and cleanup
- **Error Handling**: Robust error handling with proper logging
- **Health Monitoring**: TCP-based health probes for Container Apps

## Getting Started

### Prerequisites

- Azure CLI (`az --version`)
- Azure Developer CLI (`azd version`)
- Docker (`docker version`) - for building container images

### Deploy the Application

1. **Initialize the environment**:

   ```bash
   azd init
   ```

2. **Deploy the infrastructure and application**:

   ```bash
   azd up
   ```

   This will:

   - Create Azure resources (Container Apps, Container Registry, etc.)
   - Build and push the Docker image
   - Deploy the WebSocket application

3. **Get the application URL**:
   ```bash
   azd show --output json | jq -r '.services.websocketApp.endpoint'
   ```

### Testing the WebSocket Application

#### Using the Web Client

1. Open the `services/websocket-app/test-client.html` file in a web browser
2. Update the WebSocket URL to your deployed application's URL (use `wss://` for secure WebSocket)
3. Click "Connect" to establish a WebSocket connection
4. Send messages using the provided interface

#### Using Command Line Tools

You can test with `wscat` or similar WebSocket client tools:

```bash
npm install -g wscat
wscat -c wss://your-app-url.azurecontainerapps.io
```

#### Message Formats

The WebSocket server supports these message types:

1. **Ping Message**:

   ```json
   {
     "type": "ping",
     "timestamp": "2024-01-01T12:00:00Z"
   }
   ```

2. **Echo Message**:

   ```json
   {
     "type": "echo",
     "message": "Hello World",
     "timestamp": "2024-01-01T12:00:00Z"
   }
   ```

3. **Broadcast Message**:
   ```json
   {
     "type": "broadcast",
     "message": "Hello everyone!",
     "timestamp": "2024-01-01T12:00:00Z"
   }
   ```

## Application Structure

```
services/websocket-app/
├── app.py              # Main WebSocket server application
├── requirements.txt    # Python dependencies
├── Dockerfile         # Container image definition
└── test-client.html   # Web-based test client

infra/
├── main.bicep         # Main infrastructure template
├── main.parameters.json # Deployment parameters
└── modules/
    └── container-apps/
        └── main.bicep # Container Apps infrastructure
```

## Configuration

The application supports the following environment variables:

- `WEBSOCKET_PORT`: Port for the WebSocket server (default: 8080)
- `WEBSOCKET_HOST`: Host binding (default: 0.0.0.0)
- `ENVIRONMENT`: Environment name (dev/test/prod)
- `AZURE_CLIENT_ID`: Managed identity client ID

## Monitoring and Logging

- **Application Logs**: Available in Azure Log Analytics workspace
- **Health Monitoring**: TCP health probes ensure application availability
- **Metrics**: Container Apps provides built-in metrics for monitoring

### Viewing Logs

```bash
# Get application logs
azd logs --service websocket-app

# Or use Azure CLI
az containerapp logs show --name <app-name> --resource-group <resource-group>
```

## Security Features

- **Managed Identity**: Secure access to Azure Container Registry
- **HTTPS/WSS**: Encrypted WebSocket connections
- **Network Security**: Container Apps environment with optional internal load balancer
- **Minimal Attack Surface**: Non-root container user

## Customization

### Building Custom Images

To build and deploy your own container image:

1. Make changes to the Python application
2. Update the container image reference in the Bicep template
3. Redeploy with `azd up`

### Scaling Configuration

The application is configured with:

- **Min Replicas**: 1
- **Max Replicas**: 10
- **Scaling Rule**: HTTP-based scaling (30 concurrent requests per replica)

## Troubleshooting

### Common Issues

1. **Docker not running**: Ensure Docker Desktop is started before deployment
2. **WebSocket connection fails**: Check the URL uses `wss://` for HTTPS endpoints
3. **Container fails to start**: Check application logs in Log Analytics

### Getting Help

- Check the application logs: `azd logs --service websocket-app`
- Review the Container Apps documentation: https://docs.microsoft.com/azure/container-apps/
- Verify network connectivity and firewall settings

## Cleanup

To remove all Azure resources:

```bash
azd down
```

This will delete the resource group and all contained resources.
