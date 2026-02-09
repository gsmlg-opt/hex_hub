# HexHub MCP Server Deployment Guide

## Overview

The HexHub MCP (Model Context Protocol) server provides a comprehensive interface for AI clients to interact with Hex package management functionality. This guide covers configuration, deployment, and usage of the MCP server.

## Features

### Package Management Tools
- **search_packages**: Search packages by name, description, or metadata
- **get_package**: Get detailed package information
- **list_packages**: List packages with pagination and filtering
- **get_package_metadata**: Access package metadata and requirements

### Release Management Tools
- **list_releases**: List all versions of a package
- **get_release**: Get specific release details
- **download_release**: Download package tarballs
- **compare_releases**: Compare different package versions

### Documentation Access Tools
- **get_documentation**: Access package documentation
- **list_documentation_versions**: List available documentation versions
- **search_documentation**: Search within documentation

### Dependency Resolution Tools
- **resolve_dependencies**: Mix-style dependency resolution
- **get_dependency_tree**: Build dependency graphs
- **check_compatibility**: Version compatibility checking

### Repository Management Tools
- **list_repositories**: List available repositories
- **get_repository_info**: Get repository details
- **toggle_package_visibility**: Manage package visibility

## Configuration

### Basic Configuration

Add to your `config/config.exs`:

```elixir
# Enable MCP server
config :hex_hub, :mcp,
  enabled: true,
  websocket_path: "/mcp/ws",
  rate_limit: 1000,  # requests per hour
  require_auth: true,
  websocket_heartbeat: true,
  heartbeat_interval: 30_000  # 30 seconds
```

### Environment Variables

```bash
# Required
MCP_ENABLED=true                    # Enable MCP server

# Optional
MCP_WEBSOCKET_PATH=/mcp/ws         # WebSocket endpoint path
MCP_RATE_LIMIT=1000                 # Rate limit per hour
MCP_REQUIRE_AUTH=true               # Require API key authentication
MCP_HEARTBEAT_INTERVAL=30000        # WebSocket heartbeat interval (ms)
```

### Authentication Configuration

The MCP server uses the same API key system as the main HexHub application:

```elixir
# API key configuration (same as main app)
config :hex_hub, HexHub.APIKeys,
  # Your existing API key configuration
```

### Transport Configuration

```elixir
config :hex_hub, :mcp,
  transport: %{
    type: :websocket,  # or :http
    timeout: 60_000,   # WebSocket timeout
    max_frame_size: 1_048_576  # 1MB max frame size
  }
```

## Deployment

### Development Setup

1. Enable MCP in development:

```elixir
# config/dev.exs
config :hex_hub, :mcp,
  enabled: true,
  require_auth: false  # Optional: disable auth for development
```

2. Start the server:

```bash
mix phx.server
```

The MCP server will be available at:
- WebSocket: `ws://localhost:4000/mcp/ws`
- HTTP: `http://localhost:4000/mcp`

### Production Deployment

1. Configure production settings:

```elixir
# config/prod.exs
config :hex_hub, :mcp,
  enabled: true,
  require_auth: true,
  rate_limit: 1000,
  websocket_path: "/mcp/ws"
```

2. Set environment variables:

```bash
export MCP_ENABLED=true
export MCP_REQUIRE_AUTH=true
export MCP_RATE_LIMIT=1000
```

3. Build and deploy:

```bash
MIX_ENV=prod mix assets.deploy
MIX_ENV=prod mix release
```

4. Start the release:

```bash
_build/prod/rel/hex_hub/bin/hex_hub start
```

### Docker Deployment

```dockerfile
# Dockerfile
FROM elixir:1.15-alpine

WORKDIR /app

# Install dependencies
COPY mix.exs mix.lock ./
RUN mix deps.get --only prod

# Copy application code
COPY . .

# Build assets and release
RUN mix assets.deploy
RUN mix release

EXPOSE 4000

# Set MCP environment variables
ENV MCP_ENABLED=true
ENV MCP_REQUIRE_AUTH=true

CMD ["./_build/prod/rel/hex_hub/bin/hex_hub", "start"]
```

### Kubernetes Deployment

```yaml
# mcp-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: hexhub-mcp
spec:
  replicas: 3
  selector:
    matchLabels:
      app: hexhub-mcp
  template:
    metadata:
      labels:
        app: hexhub-mcp
    spec:
      containers:
      - name: hexhub
        image: hexhub:latest
        ports:
        - containerPort: 4000
        env:
        - name: MCP_ENABLED
          value: "true"
        - name: MCP_REQUIRE_AUTH
          value: "true"
        - name: MCP_RATE_LIMIT
          value: "1000"
        - name: SECRET_KEY_BASE
          valueFrom:
            secretKeyRef:
              name: hexhub-secrets
              key: secret-key-base
---
apiVersion: v1
kind: Service
metadata:
  name: hexhub-mcp-service
spec:
  selector:
    app: hexhub-mcp
  ports:
  - port: 4000
    targetPort: 4000
  type: LoadBalancer
```

## Usage

### WebSocket Client

```javascript
// Example WebSocket client
const ws = new WebSocket('ws://localhost:4000/mcp/ws');

ws.onopen = () => {
  console.log('Connected to MCP server');

  // List available tools
  ws.send(JSON.stringify({
    jsonrpc: "2.0",
    method: "tools/list",
    id: 1
  }));
};

ws.onmessage = (event) => {
  const response = JSON.parse(event.data);
  console.log('MCP Response:', response);
};

// Search for packages
ws.send(JSON.stringify({
  jsonrpc: "2.0",
  method: "tools/call/search_packages",
  params: {
    arguments: {
      query: "ecto",
      limit: 10
    }
  },
  id: 2
}));
```

### HTTP Client

```javascript
// Example HTTP client
const response = await fetch('http://localhost:4000/mcp', {
  method: 'POST',
  headers: {
    'Content-Type': 'application/json',
    'Authorization': 'Bearer YOUR_API_KEY'
  },
  body: JSON.stringify({
    jsonrpc: "2.0",
    method: "tools/call/get_package",
    params: {
      arguments: {
        name: "ecto"
      }
    },
    id: 1
  })
});

const result = await response.json();
console.log(result);
```

### Python Client

```python
import requests
import json

# MCP HTTP client
class MCPClient:
    def __init__(self, base_url, api_key=None):
        self.base_url = base_url.rstrip('/')
        self.api_key = api_key
        self.session = requests.Session()

        if api_key:
            self.session.headers.update({
                'Authorization': f'Bearer {api_key}'
            })

    def call_tool(self, tool_name, arguments):
        payload = {
            "jsonrpc": "2.0",
            "method": f"tools/call/{tool_name}",
            "params": {
                "arguments": arguments
            },
            "id": 1
        }

        response = self.session.post(
            f"{self.base_url}/mcp",
            json=payload
        )

        return response.json()

# Usage
client = MCPClient("http://localhost:4000", "your-api-key")

# Search packages
result = client.call_tool("search_packages", {
    "query": "ecto",
    "limit": 5
})

print(result)
```

## Monitoring and Observability

### Health Checks

```bash
# MCP health check
curl http://localhost:4000/mcp/health
```

Response:
```json
{
  "status": "healthy",
  "timestamp": "2024-01-01T12:00:00Z",
  "server_status": "running",
  "tool_count": 15,
  "stats": {
    "total_requests": 1250,
    "success_rate": 0.98,
    "avg_response_time": 45
  }
}
```

### Metrics

The MCP server emits telemetry events:

- `[:hex_hub, :mcp, :request]` - Request processing
- `[:hex_hub, :mcp, :packages]` - Package operations
- `[:hex_hub, :mcp, :releases]` - Release operations
- `[:hex_hub, :mcp, :documentation]` - Documentation access
- `[:hex_hub, :mcp, :dependencies]` - Dependency resolution
- `[:hex_hub, :mcp, :repositories]` - Repository operations

### Logging

MCP server logs are prefixed with `[MCP]`:

```
[info]  MCP Server started with 15 tools
[debug] MCP handling request: tools/call/search_packages
[info]  MCP request completed (method=tools/call/search_packages duration_ms=23 status=success)
```

## Security Considerations

### API Key Authentication

- Always require API keys in production
- Use short-lived API keys for automated systems
- Rotate API keys regularly
- Monitor API key usage

### Rate Limiting

- Configure appropriate rate limits (default: 1000 requests/hour)
- Monitor rate limit violations
- Consider higher limits for trusted clients

### Network Security

- Use HTTPS in production
- Consider WebSocket secure (WSS) connections
- Implement network-level access controls if needed

### Input Validation

The MCP server validates all inputs according to JSON schemas:
- Tool arguments are validated against tool schemas
- JSON-RPC requests are validated against the protocol specification
- Invalid requests are rejected with appropriate error codes

## Troubleshooting

### Common Issues

1. **MCP server not starting**
   - Check that `MCP_ENABLED=true` is set
   - Verify configuration in `config.exs`
   - Check application logs for startup errors

2. **WebSocket connection failures**
   - Verify WebSocket endpoint path
   - Check firewall settings
   - Ensure WebSocket is enabled in load balancer

3. **Authentication failures**
   - Verify API key is valid
   - Check API key permissions
   - Ensure `MCP_REQUIRE_AUTH` matches expectations

4. **Rate limiting**
   - Check current rate limit settings
   - Monitor API key usage
   - Consider increasing limits if needed

### Debug Mode

Enable debug logging:

```elixir
# config/dev.exs
config :logger, level: :debug

config :hex_hub, :mcp,
  debug: true
```

### Test Connections

```bash
# Test MCP server info
curl http://localhost:4000/mcp/server-info

# Test tool listing
curl -H "Authorization: Bearer YOUR_API_KEY" \
     http://localhost:4000/mcp/tools

# Test health check
curl http://localhost:4000/mcp/health
```

## Performance Tuning

### Connection Pooling

Configure appropriate connection limits:

```elixir
config :hex_hub, :mcp,
  max_connections: 1000,
  connection_timeout: 30_000
```

### Caching

Enable package metadata caching:

```elixir
config :hex_hub, :mcp,
  cache_enabled: true,
  cache_ttl: 300  # 5 minutes
```

### Resource Limits

Set appropriate resource limits:

```elixir
config :hex_hub, :mcp,
  max_request_size: 1_048_576,  # 1MB
  max_response_size: 10_485_760,  # 10MB
  request_timeout: 30_000  # 30 seconds
```

## Example Configurations

### Development Environment

```elixir
# config/dev.exs
config :hex_hub, :mcp,
  enabled: true,
  require_auth: false,
  rate_limit: :infinity,
  debug: true,
  websocket_heartbeat: false
```

### Production Environment

```elixir
# config/prod.exs
config :hex_hub, :mcp,
  enabled: true,
  require_auth: true,
  rate_limit: 1000,
  websocket_path: "/mcp/ws",
  websocket_heartbeat: true,
  heartbeat_interval: 30_000,
  max_connections: 1000,
  timeout: 60_000
```

### High-Traffic Environment

```elixir
# config/prod.exs for high traffic
config :hex_hub, :mcp,
  enabled: true,
  require_auth: true,
  rate_limit: 5000,
  cache_enabled: true,
  cache_ttl: 600,
  max_connections: 5000,
  timeout: 30_000,
  max_request_size: 2_097_152  # 2MB
```

## Integration Examples

### Claude Desktop Integration

```json
{
  "mcpServers": {
    "hexhub": {
      "command": "curl",
      "args": [
        "-X", "POST",
        "-H", "Content-Type: application/json",
        "-H", "Authorization: Bearer YOUR_API_KEY",
        "-d", "@-",
        "http://localhost:4000/mcp"
      ]
    }
  }
}
```

### MCP Client Library

```elixir
# Example MCP client in Elixir
defmodule HexHubMCPClient do
  use WebSockex

  def start_link(url, api_key \\ nil) do
    headers = if api_key, do: [{"Authorization", "Bearer #{api_key}"}], else: []
    WebSockex.start_link(url, __MODULE__, %{api_key: api_key}, extra_headers: headers)
  end

  def call_tool(pid, tool_name, arguments) do
    request = %{
      jsonrpc: "2.0",
      method: "tools/call/#{tool_name}",
      params: %{arguments: arguments},
      id: 1
    }

    WebSockex.send_frame(pid, {:text, Jason.encode!(request)})
  end

  def handle_frame({:text, msg}, state) do
    response = Jason.decode!(msg)
    IO.inspect(response, label: "MCP Response")
    {:ok, state}
  end
end
```

This comprehensive deployment guide provides everything needed to successfully deploy and operate the HexHub MCP server in various environments.