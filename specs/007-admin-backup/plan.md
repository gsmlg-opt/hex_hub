# Implementation Plan: Admin Backup Management

**Branch**: `007-admin-backup` | **Date**: 2025-12-31 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/007-admin-backup/spec.md`

## Summary

Implement a backup and restore system for HexHub administrators that allows exporting all users and locally-published packages to a standard tar archive, and restoring from such archives. The feature includes server-side storage with 30-day automatic cleanup, streaming support for large files, and backup history management.

## Technical Context

**Language/Version**: Elixir 1.15+ / OTP 26+
**Primary Dependencies**: Phoenix 1.8+, Mnesia (built-in), :erl_tar (Erlang stdlib)
**Storage**: Mnesia for metadata, HexHub.Storage for package tarballs, local filesystem for backup archives
**Testing**: ExUnit with Mnesia test isolation
**Target Platform**: Linux server (same as HexHub deployment)
**Project Type**: Phoenix web application (admin dashboard extension)
**Performance Goals**: Create backup of 100 packages in under 5 minutes; restore 1000 packages without timeout
**Constraints**: Streaming processing for large files to avoid memory exhaustion
**Scale/Scope**: Support backup archives of any size; 30-day retention for server-stored backups

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Hex.pm API Compatibility | N/A | Admin-only feature, does not affect public API |
| II. Upstream Proxy First | PASS | Backups exclude cached upstream packages (only local) |
| III. Zero External Database | PASS | Uses Mnesia for backup metadata storage |
| IV. Dual Interface Architecture | PASS | Feature in `hex_hub_admin_web` with logic in `hex_hub` context |
| V. Storage Abstraction | PASS | Will use HexHub.Storage for reading package files |
| VI. Test Coverage Requirements | PENDING | Tests required for all backup/restore operations |
| VII. Observability and Audit | PASS | Telemetry events for backup/restore; audit logging required |

**Gate Status**: PASS - No violations. Proceed to Phase 0.

## Project Structure

### Documentation (this feature)

```text
specs/007-admin-backup/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/           # Phase 1 output (admin routes)
└── tasks.md             # Phase 2 output (/speckit.tasks)
```

### Source Code (repository root)

```text
lib/
├── hex_hub/
│   ├── backup.ex                    # Core backup/restore business logic
│   └── backup/
│       ├── exporter.ex              # Streaming tar creation
│       ├── importer.ex              # Streaming tar extraction & restore
│       ├── manifest.ex              # Backup manifest handling
│       └── cleanup.ex               # 30-day retention cleanup (GenServer)
├── hex_hub_admin_web/
│   ├── controllers/
│   │   ├── backup_controller.ex     # HTTP handlers for backup operations
│   │   └── backup_html.ex           # HTML helpers
│   └── templates/backup/
│       ├── index.html.heex          # Backup history list
│       ├── new.html.heex            # Create backup form
│       └── restore.html.heex        # Upload restore form

priv/
└── backups/                         # Server-stored backup archives

test/
├── hex_hub/
│   ├── backup_test.exs              # Unit tests for backup logic
│   └── backup/
│       ├── exporter_test.exs
│       ├── importer_test.exs
│       └── cleanup_test.exs
└── hex_hub_admin_web/
    └── controllers/
        └── backup_controller_test.exs
```

**Structure Decision**: Follows existing HexHub patterns. Core logic in `hex_hub/backup.ex` context module with supporting modules for export/import/cleanup. Admin interface in `hex_hub_admin_web` with standard Phoenix controller pattern.

## Complexity Tracking

> No Constitution Check violations requiring justification.

| Aspect | Decision | Rationale |
|--------|----------|-----------|
| Backup storage | Local filesystem in `priv/backups/` | Simpler than S3, sufficient for backup archives |
| Tar format | Standard uncompressed tar via `:erl_tar` | Maximum compatibility, users can compress externally |
| Cleanup | GenServer with daily check | Simple, reliable, follows OTP patterns |
