# Use Python 3.11 slim image for optimal performance and security
FROM python:3.11-slim

# Set working directory
WORKDIR /app

# Set environment variables for optimal Python performance in containers
ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

# Install system dependencies and security updates
RUN apt-get update && apt-get install -y \
    --no-install-recommends \
    && rm -rf /var/lib/apt/lists/*

# Create non-root user for security
RUN useradd --create-home --shell /bin/bash app

# Copy requirements first for better caching
COPY requirements.txt .

# Install Python dependencies
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY app.py .

# Change ownership to app user
RUN chown -R app:app /app

# Switch to non-root user
USER app

# Expose the WebSocket port
EXPOSE 8080

# Health check for Container Apps
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD python -c "import socket; s=socket.socket(); s.settimeout(5); s.connect(('localhost', 8080)); s.close()" || exit 1

# Run the application
CMD ["python", "app.py"]
