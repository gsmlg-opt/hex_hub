# Feature Specification: Public MCP API for Package Information

**Feature Branch**: `008-mcp-public-api`
**Created**: 2026-01-19
**Status**: Draft
**Input**: User description: "we needs add mcp support to this repo's public interface, that support use mcp to get packages's info"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - AI Client Queries Package Information (Priority: P1)

An AI assistant (Claude, GPT, or other LLM) integrated with HexHub via MCP can search for Elixir/Erlang packages and retrieve detailed package information to help developers discover and evaluate dependencies.

**Why this priority**: This is the core functionality - AI clients need to discover and retrieve package information. Without this, the MCP integration has no value.

**Independent Test**: Can be fully tested by sending MCP JSON-RPC requests to the public endpoint and receiving package data in response. Delivers immediate value by enabling AI-assisted package discovery.

**Acceptance Scenarios**:

1. **Given** the MCP public endpoint is available, **When** an AI client sends a `search_packages` request with query "phoenix", **Then** the system returns a list of packages matching "phoenix" with name, description, and version info
2. **Given** a package "phoenix" exists, **When** an AI client sends a `get_package` request for "phoenix", **Then** the system returns complete package details including all releases, dependencies, and metadata
3. **Given** the MCP public endpoint is available, **When** an AI client sends an invalid request, **Then** the system returns a proper JSON-RPC error response with appropriate error code

---

### User Story 2 - AI Client Lists Available Tools (Priority: P1)

An AI client can discover what MCP tools are available on this HexHub instance, enabling dynamic capability detection and proper tool invocation.

**Why this priority**: Tool discovery is fundamental to MCP protocol - clients must know what tools exist before they can use them. This is equally critical as the query functionality.

**Independent Test**: Can be tested by calling the `tools/list` endpoint and verifying all package-related tools are returned with their schemas.

**Acceptance Scenarios**:

1. **Given** the MCP public endpoint is available, **When** an AI client requests the list of available tools, **Then** the system returns all package-related tools with names, descriptions, and input schemas
2. **Given** the tools list has been retrieved, **When** an AI client invokes a tool by name, **Then** the system executes the tool and returns results

---

### User Story 3 - AI Client Retrieves Package Dependencies (Priority: P2)

An AI assistant can analyze package dependencies to help developers understand dependency trees, identify potential conflicts, and make informed decisions about adding new packages.

**Why this priority**: Dependency information is highly valuable for AI-assisted development but builds on the core package query functionality from US1.

**Independent Test**: Can be tested by requesting dependency information for a specific package version and verifying the complete dependency tree is returned.

**Acceptance Scenarios**:

1. **Given** a package "phoenix" version "1.7.0" exists, **When** an AI client requests dependency information, **Then** the system returns all direct dependencies with version requirements
2. **Given** a package has optional dependencies, **When** an AI client requests dependency information, **Then** optional dependencies are clearly marked

---

### User Story 4 - AI Client Accesses Package Documentation Links (Priority: P3)

An AI assistant can retrieve documentation URLs and links for packages, enabling it to guide developers to official documentation and source repositories.

**Why this priority**: Documentation access enhances the AI's ability to help developers but is supplementary to core package information retrieval.

**Independent Test**: Can be tested by requesting package metadata and verifying documentation URLs are included in the response.

**Acceptance Scenarios**:

1. **Given** a package has documentation uploaded, **When** an AI client requests package information, **Then** the response includes the documentation URL
2. **Given** a package has external links (GitHub, homepage), **When** an AI client requests package information, **Then** all external links are included in the response

---

### Edge Cases

- What happens when an AI client requests a non-existent package?
  - System returns a proper JSON-RPC error with "not found" indication
- What happens when search returns no results?
  - System returns an empty result set with total count of 0
- How does the system handle malformed JSON-RPC requests?
  - System returns appropriate JSON-RPC parse error (-32700) or invalid request error (-32600)
- What happens when the MCP server is disabled in configuration?
  - System returns a clear error indicating MCP is not available
- How does the system handle rate limiting for MCP requests?
  - System applies standard rate limiting and returns appropriate error when limits are exceeded

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST expose MCP endpoints on the public interface without requiring authentication for read-only operations
- **FR-002**: System MUST implement the MCP JSON-RPC 2.0 protocol for all request/response handling
- **FR-003**: System MUST provide a `search_packages` tool that searches packages by name, description, and metadata
- **FR-004**: System MUST provide a `get_package` tool that retrieves complete package information including all releases
- **FR-005**: System MUST provide a `list_packages` tool with pagination support
- **FR-006**: System MUST provide a `get_package_metadata` tool for retrieving dependency and version information
- **FR-007**: System MUST return proper JSON-RPC error responses for all error conditions
- **FR-008**: System MUST support tool discovery through the MCP `tools/list` endpoint
- **FR-009**: System MUST apply rate limiting to prevent abuse of public MCP endpoints
- **FR-010**: System MUST log all MCP requests via telemetry for monitoring and debugging purposes

### Key Entities

- **MCP Tool**: A capability exposed via MCP protocol - has name, description, input schema, and handler
- **JSON-RPC Request**: Standard JSON-RPC 2.0 request with jsonrpc version, method, params, and id
- **JSON-RPC Response**: Standard JSON-RPC 2.0 response with result or error
- **Package Info**: Package metadata returned by MCP tools - includes name, description, versions, dependencies, links

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: AI clients can discover and invoke all package-related MCP tools without authentication
- **SC-002**: Package search queries return results within acceptable response time for interactive AI sessions
- **SC-003**: All standard JSON-RPC error codes are properly implemented and returned
- **SC-004**: MCP endpoint availability can be monitored via the health check endpoint
- **SC-005**: Rate limiting prevents any single client from overwhelming the MCP endpoint
- **SC-006**: 100% of package data accessible via standard API is also accessible via MCP tools

## Assumptions

- The existing MCP implementation (`/mcp/` routes in router) provides the foundation for this feature
- Read-only package information does not require authentication (consistent with public hex.pm API)
- Standard JSON-RPC 2.0 protocol is sufficient for AI client integration
- Rate limiting configuration from existing API endpoints can be reused or adapted
- The existing MCP tools in `HexHub.MCP.Tools.Packages` provide the required package query functionality
