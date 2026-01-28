# Quickstart: Public MCP API for Package Information

**Feature**: 008-mcp-public-api
**Date**: 2026-01-19

## Overview

This guide explains how to use HexHub's MCP (Model Context Protocol) API to query package information. The MCP API provides a JSON-RPC 2.0 interface optimized for AI assistants.

---

## Prerequisites

- HexHub server running with MCP enabled (`MCP_ENABLED=true`)
- Public access enabled (`MCP_REQUIRE_AUTH=false` for unauthenticated access)

---

## Quick Start

### 1. Check MCP Server Status

```bash
curl http://localhost:4000/mcp/health
```

Expected response:
```json
{
  "status": "healthy",
  "enabled": true,
  "tools_available": 16
}
```

### 2. List Available Tools

```bash
curl http://localhost:4000/mcp/tools
```

Returns all available MCP tools with their schemas.

### 3. Search for Packages

```bash
curl -X POST http://localhost:4000/mcp \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc": "2.0",
    "id": 1,
    "method": "tools/call/search_packages",
    "params": {
      "arguments": {
        "query": "phoenix",
        "limit": 5
      }
    }
  }'
```

### 4. Get Package Details

```bash
curl -X POST http://localhost:4000/mcp \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc": "2.0",
    "id": 2,
    "method": "tools/call/get_package",
    "params": {
      "arguments": {
        "name": "phoenix"
      }
    }
  }'
```

---

## Available Tools

### Package Tools

| Tool | Description | Required Params |
|------|-------------|-----------------|
| `search_packages` | Search by name/description | `query` |
| `get_package` | Get package details | `name` |
| `list_packages` | Paginated package list | none |
| `get_package_metadata` | Get dependencies | `name` |

### Release Tools

| Tool | Description | Required Params |
|------|-------------|-----------------|
| `list_releases` | List package versions | `name` |
| `get_release` | Get release details | `name`, `version` |
| `compare_releases` | Compare versions | `name`, `version1`, `version2` |

### Dependency Tools

| Tool | Description | Required Params |
|------|-------------|-----------------|
| `get_dependency_tree` | Build dep tree | `name`, `version` |
| `check_compatibility` | Check compatibility | `packages` |
| `resolve_dependencies` | Resolve deps | `requirements` |

### Documentation Tools

| Tool | Description | Required Params |
|------|-------------|-----------------|
| `get_documentation` | Access docs | `name` |
| `list_documentation_versions` | List doc versions | `name` |
| `search_documentation` | Search docs | `name`, `query` |

---

## Rate Limiting

Public MCP endpoints are rate-limited to prevent abuse:

- **Limit**: 100 requests per minute per IP (configurable)
- **Header**: `X-RateLimit-Remaining` shows remaining quota
- **Error**: HTTP 429 with `retry-after` header when exceeded

---

## Error Codes

| Code | Meaning | Action |
|------|---------|--------|
| -32700 | Parse error | Check JSON syntax |
| -32600 | Invalid request | Check required fields |
| -32601 | Method not found | Check tool name |
| -32602 | Invalid params | Check tool arguments |
| -32001 | MCP disabled | Enable MCP on server |
| -32002 | Rate limited | Wait and retry |

---

## Example: AI Client Integration

For Claude Code or similar AI clients, configure MCP server:

```json
{
  "mcp": {
    "servers": {
      "hexhub": {
        "url": "http://localhost:4000/mcp",
        "transport": "http"
      }
    }
  }
}
```

The AI client will automatically discover available tools via `/mcp/tools`.

---

## Development Testing

Run HexHub in development mode (MCP enabled by default):

```bash
mix phx.server
```

Development config (`config/dev.exs`):
```elixir
config :hex_hub, :mcp,
  enabled: true,
  require_auth: false,  # Public access
  debug: true
```

---

## Production Deployment

For production public access:

```bash
export MCP_ENABLED=true
export MCP_REQUIRE_AUTH=false
export MCP_RATE_LIMIT=1000  # requests per hour

./bin/hex_hub start
```

**Security Note**: Rate limiting is automatically applied to prevent abuse.
