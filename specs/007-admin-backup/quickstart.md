# Quickstart: Admin Backup Management

**Feature**: 007-admin-backup
**Date**: 2025-12-31

## Prerequisites

- HexHub development environment set up
- Mix dependencies installed (`mix deps.get`)
- Mnesia initialized (`mix phx.server` at least once)

## Implementation Order

### Phase 1: Core Backup Module

1. **Add `:backups` table to Mnesia schema**
   ```bash
   # Edit lib/hex_hub/mnesia.ex
   # Add :backups to @tables list
   # Add table definition in create_tables/0
   ```

2. **Create `HexHub.Backup` context module**
   ```bash
   touch lib/hex_hub/backup.ex
   ```
   - Implement `create_backup/1`
   - Implement `list_backups/0`
   - Implement `get_backup/1`
   - Implement `delete_backup/1`

3. **Create `HexHub.Backup.Exporter`**
   ```bash
   mkdir -p lib/hex_hub/backup
   touch lib/hex_hub/backup/exporter.ex
   ```
   - Implement streaming tar creation with `:erl_tar`
   - Export users, packages, releases, owners to JSON
   - Copy package/doc tarballs into archive

4. **Create `HexHub.Backup.Manifest`**
   ```bash
   touch lib/hex_hub/backup/manifest.ex
   ```
   - Implement manifest generation
   - Implement manifest parsing
   - Implement version compatibility check

### Phase 2: Restore Module

5. **Create `HexHub.Backup.Importer`**
   ```bash
   touch lib/hex_hub/backup/importer.ex
   ```
   - Implement tar extraction
   - Implement manifest validation
   - Implement user/package/release restoration
   - Implement conflict resolution strategies

### Phase 3: Admin Interface

6. **Create backup controller**
   ```bash
   touch lib/hex_hub_admin_web/controllers/backup_controller.ex
   touch lib/hex_hub_admin_web/controllers/backup_html.ex
   ```

7. **Create backup templates**
   ```bash
   mkdir -p lib/hex_hub_admin_web/controllers/backup_html
   touch lib/hex_hub_admin_web/controllers/backup_html/index.html.heex
   touch lib/hex_hub_admin_web/controllers/backup_html/new.html.heex
   touch lib/hex_hub_admin_web/controllers/backup_html/show.html.heex
   touch lib/hex_hub_admin_web/controllers/backup_html/restore.html.heex
   ```

8. **Add routes to admin router**
   ```bash
   # Edit lib/hex_hub_admin_web/router.ex
   # Add backup routes as defined in contracts/admin-routes.md
   ```

### Phase 4: Cleanup & Telemetry

9. **Create cleanup GenServer**
   ```bash
   touch lib/hex_hub/backup/cleanup.ex
   ```
   - Implement daily cleanup of expired backups
   - Add to application supervision tree

10. **Add telemetry events**
    ```bash
    # Edit lib/hex_hub/telemetry.ex
    # Add backup-related events
    ```

### Phase 5: Testing

11. **Create unit tests**
    ```bash
    mkdir -p test/hex_hub/backup
    touch test/hex_hub/backup_test.exs
    touch test/hex_hub/backup/exporter_test.exs
    touch test/hex_hub/backup/importer_test.exs
    touch test/hex_hub/backup/manifest_test.exs
    touch test/hex_hub/backup/cleanup_test.exs
    ```

12. **Create controller tests**
    ```bash
    touch test/hex_hub_admin_web/controllers/backup_controller_test.exs
    ```

## Quick Verification

After implementation, verify with:

```bash
# Run tests
mix test test/hex_hub/backup
mix test test/hex_hub_admin_web/controllers/backup_controller_test.exs

# Start server and test manually
mix phx.server

# Navigate to admin dashboard
open http://localhost:4361/backups
```

## Key Files to Create

| File | Purpose |
|------|---------|
| `lib/hex_hub/backup.ex` | Main context module |
| `lib/hex_hub/backup/exporter.ex` | Tar archive creation |
| `lib/hex_hub/backup/importer.ex` | Tar archive extraction & restore |
| `lib/hex_hub/backup/manifest.ex` | Manifest handling |
| `lib/hex_hub/backup/cleanup.ex` | 30-day retention cleanup |
| `lib/hex_hub_admin_web/controllers/backup_controller.ex` | HTTP handlers |
| `lib/hex_hub_admin_web/controllers/backup_html.ex` | HTML helpers |

## Key Files to Modify

| File | Changes |
|------|---------|
| `lib/hex_hub/mnesia.ex` | Add `:backups` table |
| `lib/hex_hub_admin_web/router.ex` | Add backup routes |
| `lib/hex_hub/application.ex` | Add cleanup GenServer to supervision tree |
| `lib/hex_hub/telemetry.ex` | Add backup telemetry events |
| `config/config.exs` | Add backup storage path configuration |

## Configuration

Add to `config/config.exs`:

```elixir
config :hex_hub,
  backup_path: "priv/backups",
  backup_retention_days: 30
```

## Smoke Test Checklist

- [ ] Can create backup from admin UI
- [ ] Backup file downloads correctly
- [ ] Backup appears in history list
- [ ] Can restore from uploaded backup file
- [ ] Conflict resolution works (skip/overwrite)
- [ ] Old backups are cleaned up after 30 days
- [ ] Telemetry events are emitted
- [ ] Audit log entries created
