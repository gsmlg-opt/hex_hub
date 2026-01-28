# Research: Public MCP API for Package Information

**Date**: 2026-01-19
**Feature**: 008-mcp-public-api

## Research Summary

This feature leverages the existing MCP implementation in HexHub. Research focused on understanding the current architecture and identifying minimal changes needed for public access.

---

## 1. Existing MCP Infrastructure Analysis

### Decision: Use Existing MCP Server Implementation

**Rationale**: The codebase already has a comprehensive MCP implementation with:
- JSON-RPC 2.0 server (`HexHub.MCP.Server`)
- HTTP transport with controller (`HexHubWeb.MCPController`)
- 16 registered tools across 5 capability areas
- Telemetry integration for observability
- Configuration-driven authentication (`require_auth: true/false`)

**Alternatives Considered**:
1. Build new public-only MCP endpoints - Rejected (code duplication)
2. Proxy MCP through REST API - Rejected (adds latency, breaks MCP protocol)

**Evidence**: Analysis of existing files:
- `lib/hex_hub/mcp/server.ex` - Full MCP server GenServer
- `lib/hex_hub/mcp/tools.ex` - 16 tools including all package operations
- `lib/hex_hub_web/controllers/mcp_controller.ex` - HTTP endpoint handlers
- `config/dev.exs` - Already supports `require_auth: false`

---

## 2. Public Access Configuration

### Decision: Use `MCP_REQUIRE_AUTH=false` Environment Variable

**Rationale**: The existing configuration system already supports disabling authentication:
```elixir
# config/config.exs line 40
require_auth: System.get_env("MCP_REQUIRE_AUTH", "true") == "true"
```

For production public access, operators set `MCP_REQUIRE_AUTH=false`.

**Alternatives Considered**:
1. Separate public vs private endpoints - Rejected (increases complexity)
2. Allowlist specific tools for public access - Considered for future enhancement

**Implementation Note**: Development already uses `require_auth: false` in `config/dev.exs`.

---

## 3. Rate Limiting Strategy

### Decision: Implement IP-Based Rate Limiting for MCP Endpoints

**Rationale**: Public endpoints require rate limiting to prevent abuse. The existing `rate_limit_mcp_request/2` function in `mcp_controller.ex` is a stub that needs implementation.

**Recommended Limits** (aligned with existing API limits in `HexHubWeb.Plugs.RateLimit`):
- IP-based: 100 requests/minute (matches existing API)
- Configurable via `MCP_RATE_LIMIT` environment variable

**Implementation Approach**:
1. Call `HexHub.MCP.Transport.check_rate_limit/2` (already referenced but stub)
2. Use Mnesia-based rate limit storage (existing infrastructure)
3. Return JSON-RPC error code `-32002` for rate limit exceeded

**Alternatives Considered**:
1. No rate limiting - Rejected (abuse risk)
2. Per-tool rate limiting - Rejected (over-engineering for initial release)

---

## 4. Tool Security Classification

### Decision: All Read-Only Tools are Public, Write Tools Require Auth

**Rationale**: Maintain security for operations that modify data while enabling AI clients to query package information.

**Public Tools (read-only)**:
- `search_packages` - Search by name/description
- `get_package` - Package details
- `list_packages` - Paginated listing
- `get_package_metadata` - Dependencies and metadata
- `list_releases` - Package versions
- `get_release` - Release details
- `get_documentation` - Doc access
- `list_documentation_versions` - Doc versions
- `search_documentation` - Doc search
- `resolve_dependencies` - Dependency resolution
- `get_dependency_tree` - Dependency graph
- `check_compatibility` - Version compatibility
- `list_repositories` - Repository listing (public repos only)
- `get_repository_info` - Repository details (public repos only)

**Protected Tools (require auth)**:
- `toggle_package_visibility` - Modifies package state
- `download_release` - Could be rate-limited differently due to bandwidth

**Future Enhancement**: Consider fine-grained tool-level permissions.

---

## 5. Error Response Standards

### Decision: Use Standard JSON-RPC 2.0 Error Codes

**Rationale**: MCP clients expect JSON-RPC 2.0 compliant responses.

**Error Code Mapping**:
| Code | Meaning | When Used |
|------|---------|-----------|
| -32700 | Parse error | Invalid JSON |
| -32600 | Invalid Request | Missing required fields |
| -32601 | Method not found | Unknown tool |
| -32602 | Invalid params | Bad tool arguments |
| -32000 | Server error | Internal failure |
| -32001 | MCP disabled | MCP not enabled |
| -32002 | Rate limited | Too many requests |

**Evidence**: Already implemented in `HexHub.MCP.Handler` and transport modules.

---

## 6. Telemetry and Observability

### Decision: Continue Using Existing Telemetry Pattern

**Rationale**: Existing MCP code already uses `HexHub.Telemetry.log/4` which complies with Constitution Principle VII (Telemetry-First Logging).

**Events Emitted**:
- `[:hex_hub, :mcp, :request]` - All incoming requests
- `[:hex_hub, :mcp, :error]` - Failed requests
- `[:hex_hub, :mcp, :packages]` - Package tool operations

**No Changes Needed**: Telemetry integration is already complete.

---

## 7. Testing Strategy

### Decision: Add Integration Tests for Public Access Scenarios

**Rationale**: Constitution Principle VI requires test coverage for all API endpoints.

**Test Scenarios**:
1. Public access without API key - Should succeed for read-only tools
2. Public access with invalid API key - Should succeed (key ignored for public mode)
3. Rate limiting - Should return 429 with retry-after header
4. Tool discovery - Should return all public tools with schemas
5. Package search - Should return results matching REST API
6. Invalid requests - Should return proper JSON-RPC errors

**Test Location**: `test/hex_hub_web/controllers/mcp_controller_test.exs`

---

## Implementation Checklist

Based on research, the implementation requires:

1. **Configuration** (Low effort)
   - Document `MCP_REQUIRE_AUTH=false` for public deployment
   - Consider adding `MCP_PUBLIC_TOOLS` for tool-level control (future)

2. **Rate Limiting** (Medium effort)
   - Implement `check_rate_limit/2` in `HexHub.MCP.Transport`
   - Use existing Mnesia rate limit tables

3. **Testing** (Medium effort)
   - Add public access test cases
   - Test rate limiting behavior
   - Test error responses

4. **Documentation** (Low effort)
   - Update CLAUDE.md with MCP public API information
   - Add deployment notes for public MCP configuration

---

## References

- MCP Specification: https://modelcontextprotocol.io/
- JSON-RPC 2.0: https://www.jsonrpc.org/specification
- Existing implementation: `lib/hex_hub/mcp/`
