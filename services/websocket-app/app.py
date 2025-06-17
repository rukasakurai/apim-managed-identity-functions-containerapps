"""
WebSocket Hello World Application
A simple WebSocket server that echoes messages and broadcasts to all connected clients.
Implements Azure best practices with proper error handling, logging, and health monitoring.
"""

import asyncio
import json
import logging
import os
import signal
import websockets
from datetime import datetime
from typing import Set
import traceback

# Configure logging with structured format for Azure Container Apps
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

# Global set to track connected clients
connected_clients: Set[websockets.WebSocketServerProtocol] = set()

class WebSocketServer:
    """WebSocket server with connection management and error handling"""
    
    def __init__(self, host: str = "0.0.0.0", port: int = 8080):
        self.host = host
        self.port = port
        self.server = None
        
    async def register_client(self, websocket: websockets.WebSocketServerProtocol) -> None:
        """Register a new client connection"""
        connected_clients.add(websocket)
        client_count = len(connected_clients)
        logger.info(f"Client connected. Total clients: {client_count}")
        
        # Send welcome message to the new client
        welcome_message = {
            "type": "welcome",
            "message": "Welcome to Azure Container Apps WebSocket Server!",
            "timestamp": datetime.utcnow().isoformat(),
            "client_id": id(websocket)
        }
        try:
            await websocket.send(json.dumps(welcome_message))
        except websockets.exceptions.ConnectionClosed:
            logger.warning("Failed to send welcome message - client disconnected")

    async def unregister_client(self, websocket: websockets.WebSocketServerProtocol) -> None:
        """Unregister a client connection"""
        connected_clients.discard(websocket)
        client_count = len(connected_clients)
        logger.info(f"Client disconnected. Total clients: {client_count}")

    async def broadcast_message(self, message: dict, sender_websocket: websockets.WebSocketServerProtocol = None) -> None:
        """Broadcast a message to all connected clients except the sender"""
        if not connected_clients:
            return
            
        # Create list of clients to send to (excluding sender if specified)
        recipients = [client for client in connected_clients if client != sender_websocket]
        
        if recipients:
            message_str = json.dumps(message)
            # Use asyncio.gather for concurrent sending with error handling
            await asyncio.gather(
                *[self.send_safe(client, message_str) for client in recipients],
                return_exceptions=True
            )

    async def send_safe(self, websocket: websockets.WebSocketServerProtocol, message: str) -> None:
        """Safely send a message to a client with error handling"""
        try:
            await websocket.send(message)
        except websockets.exceptions.ConnectionClosed:
            logger.warning("Failed to send message - client disconnected")
            await self.unregister_client(websocket)
        except Exception as e:
            logger.error(f"Unexpected error sending message: {e}")
            await self.unregister_client(websocket)

    async def handle_client(self, websocket: websockets.WebSocketServerProtocol, path: str) -> None:
        """Handle a client connection"""
        await self.register_client(websocket)
        
        try:
            async for message in websocket:
                try:
                    # Parse incoming message
                    data = json.loads(message)
                    logger.info(f"Received message: {data}")
                    
                    # Create response based on message type
                    if data.get("type") == "ping":
                        response = {
                            "type": "pong",
                            "timestamp": datetime.utcnow().isoformat(),
                            "message": "Server is alive!"
                        }
                        await websocket.send(json.dumps(response))
                        
                    elif data.get("type") == "broadcast":
                        # Broadcast message to all other clients
                        broadcast_msg = {
                            "type": "broadcast",
                            "message": data.get("message", ""),
                            "from": f"Client-{id(websocket)}",
                            "timestamp": datetime.utcnow().isoformat()
                        }
                        await self.broadcast_message(broadcast_msg, websocket)
                        
                        # Send confirmation back to sender
                        confirmation = {
                            "type": "confirmation",
                            "message": "Message broadcasted successfully",
                            "timestamp": datetime.utcnow().isoformat()
                        }
                        await websocket.send(json.dumps(confirmation))
                        
                    else:
                        # Echo the message back with additional info
                        echo_response = {
                            "type": "echo",
                            "original_message": data,
                            "timestamp": datetime.utcnow().isoformat(),
                            "server_message": "Hello from Azure Container Apps WebSocket Server!"
                        }
                        await websocket.send(json.dumps(echo_response))
                        
                except json.JSONDecodeError:
                    # Handle invalid JSON
                    error_response = {
                        "type": "error",
                        "message": "Invalid JSON format",
                        "timestamp": datetime.utcnow().isoformat()
                    }
                    await websocket.send(json.dumps(error_response))
                    
                except Exception as e:
                    logger.error(f"Error handling message: {e}")
                    logger.error(traceback.format_exc())
                    error_response = {
                        "type": "error",
                        "message": "Internal server error",
                        "timestamp": datetime.utcnow().isoformat()
                    }
                    try:
                        await websocket.send(json.dumps(error_response))
                    except:
                        pass  # Client might have disconnected
                        
        except websockets.exceptions.ConnectionClosed:
            logger.info("Client connection closed normally")
        except Exception as e:
            logger.error(f"Unexpected error in client handler: {e}")
            logger.error(traceback.format_exc())
        finally:
            await self.unregister_client(websocket)

    async def start_server(self) -> None:
        """Start the WebSocket server"""
        logger.info(f"Starting WebSocket server on {self.host}:{self.port}")
        
        # Configure server with appropriate settings for Container Apps
        self.server = await websockets.serve(
            self.handle_client,
            self.host,
            self.port,
            ping_interval=30,  # Send ping every 30 seconds
            ping_timeout=10,   # Wait 10 seconds for pong
            max_size=1024*1024,  # 1MB max message size
            max_queue=32,      # Max queued messages per connection
        )
        
        logger.info(f"WebSocket server started successfully on ws://{self.host}:{self.port}")
        return self.server

    async def stop_server(self) -> None:
        """Stop the WebSocket server gracefully"""
        if self.server:
            logger.info("Stopping WebSocket server...")
            self.server.close()
            await self.server.wait_closed()
            logger.info("WebSocket server stopped")

# Health check endpoint for Container Apps
async def health_check_handler(websocket: websockets.WebSocketServerProtocol, path: str) -> None:
    """Simple health check endpoint"""
    health_response = {
        "status": "healthy",
        "timestamp": datetime.utcnow().isoformat(),
        "connected_clients": len(connected_clients),
        "version": "1.0.0"
    }
    await websocket.send(json.dumps(health_response))
    await websocket.close()

async def main():
    """Main function to run the WebSocket server"""
    # Get configuration from environment variables
    host = os.getenv("WEBSOCKET_HOST", "0.0.0.0")
    port = int(os.getenv("WEBSOCKET_PORT", "8080"))
    
    # Create server instance
    server = WebSocketServer(host, port)
    
    # Setup graceful shutdown handlers
    def signal_handler():
        logger.info("Received shutdown signal")
        asyncio.create_task(server.stop_server())
    
    # Register signal handlers for graceful shutdown
    loop = asyncio.get_event_loop()
    for sig in [signal.SIGTERM, signal.SIGINT]:
        loop.add_signal_handler(sig, signal_handler)
    
    try:
        # Start the server
        await server.start_server()
        
        # Keep the server running
        await asyncio.Future()  # Run forever
        
    except KeyboardInterrupt:
        logger.info("Received keyboard interrupt")
    except Exception as e:
        logger.error(f"Server error: {e}")
        logger.error(traceback.format_exc())
    finally:
        await server.stop_server()

if __name__ == "__main__":
    # Run the server
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        logger.info("Server shutdown completed")
    except Exception as e:
        logger.error(f"Failed to start server: {e}")
        logger.error(traceback.format_exc())
