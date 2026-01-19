# Implementation Plan: Public MCP API for Package Information

**Branch**: `008-mcp-public-api` | **Date**: 2026-01-19 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/008-mcp-public-api/spec.md`

## Summary

Enable the existing MCP (Model Context Protocol) server to function as a public API for AI clients to query package information. The implementation leverages the already-built MCP infrastructure at `/mcp/` routes, making read-only package tools accessible without authentication while maintaining rate limiting for abuse prevention.

## Technical Context

**Language/Version**: Elixir 1.15+ / OTP 26+
**Primary Dependencies**: Phoenix 1.8+, Mnesia, `:telemetry`
**Storage**: Mnesia (existing `:packages`, `:package_releases` tables)
**Testing**: ExUnit with existing MCP test infrastructure
**Target Platform**: Linux server / Docker container
**Project Type**: Phoenix web application (monolith)
**Performance Goals**: <500ms response time for package queries, consistent with existing REST API
**Constraints**: Must maintain compatibility with existing MCP authentication for write operations
**Scale/Scope**: Same scale as existing REST API package endpoints

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Hex.pm API Compatibility | ✅ PASS | MCP is an additional interface, does not affect Hex API |
| II. Upstream Proxy First | ✅ PASS | Package queries already use upstream fallback |
| III. Zero External Database | ✅ PASS | Uses Mnesia only |
| IV. Dual Interface Architecture | ✅ PASS | MCP is part of `hex_hub_web` public interface |
| V. Storage Abstraction | ✅ PASS | Uses existing `HexHub.Storage` for any package data |
| VI. Test Coverage | ✅ REQUIRED | Must add tests for public MCP endpoints |
| VII. Observability & Audit | ✅ PASS | MCP already emits telemetry events via `HexHub.Telemetry` |
| VII.a Telemetry-First Logging | ✅ PASS | Existing MCP code uses `Telemetry.log/4` pattern |

**Gate Result**: PASS - Proceed to Phase 0

## Project Structure

### Documentation (this feature)

```text
specs/008-mcp-public-api/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/           # Phase 1 output (MCP tool schemas)
└── tasks.md             # Phase 2 output (/speckit.tasks command)
```

### Source Code (repository root)

```text
lib/
├── hex_hub/
│   └── mcp/
│       ├── server.ex          # Existing - no changes needed
│       ├── handler.ex         # Existing - no changes needed
│       ├── transport.ex       # Update: implement rate limiting
│       ├── tools.ex           # Existing - no changes needed
│       └── tools/
│           └── packages.ex    # Existing - no changes needed
└── hex_hub_web/
    └── controllers/
        └── mcp_controller.ex  # Update: allow public access for read-only tools

config/
├── config.exs             # Update: document MCP_REQUIRE_AUTH=false for public mode
└── runtime.exs            # Update: ensure runtime MCP config is applied

test/
└── hex_hub_web/
    └── controllers/
        └── mcp_controller_test.exs  # Add: public MCP endpoint tests
```

**Structure Decision**: Minimal changes to existing MCP infrastructure. The implementation primarily updates configuration and adds tests for public access scenarios.

## Complexity Tracking

> No violations - implementation uses existing infrastructure

| Component | Complexity | Justification |
|-----------|------------|---------------|
| Rate Limiting | Low | Reuse existing `HexHubWeb.Plugs.RateLimit` patterns |
| Public Auth Bypass | Low | Already supported via `require_auth: false` config |
| Testing | Medium | Need comprehensive tests for public access scenarios |
