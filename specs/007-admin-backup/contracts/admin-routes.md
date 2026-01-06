# Admin Routes Contract: Backup Management

**Feature**: 007-admin-backup
**Date**: 2025-12-31

## Overview

This document defines the admin dashboard routes for backup management. These are browser-based HTML routes, not API endpoints.

---

## Routes

### Backup List (History)

```
GET /backups
```

**Controller**: `BackupController.index/2`

**Response**: HTML page listing all backups

**Template Variables**:
- `@backups` - List of backup records
- `@flash` - Flash messages

---

### Create Backup Form

```
GET /backups/new
```

**Controller**: `BackupController.new/2`

**Response**: HTML page with create backup form

**Template Variables**:
- `@changeset` - Empty changeset for form
- `@stats` - Current system stats (user count, package count)

---

### Create Backup Action

```
POST /backups
```

**Controller**: `BackupController.create/2`

**Request Body** (form data):
- None required (creates backup of all data)

**Response**:
- Success: Redirect to `/backups` with flash
- Error: Render `new.html.heex` with errors

**Side Effects**:
- Creates backup tar file in `priv/backups/`
- Inserts record in `:backups` Mnesia table
- Emits telemetry event

---

### Show Backup Details

```
GET /backups/:id
```

**Controller**: `BackupController.show/2`

**Path Parameters**:
- `id` - Backup UUID

**Response**: HTML page with backup details

**Template Variables**:
- `@backup` - Backup record
- `@can_download` - Boolean (file still exists)

---

### Download Backup

```
GET /backups/:id/download
```

**Controller**: `BackupController.download/2`

**Path Parameters**:
- `id` - Backup UUID

**Response**:
- Success: File download (`Content-Disposition: attachment`)
- Error: 404 if backup not found or file missing

**Headers**:
```
Content-Type: application/x-tar
Content-Disposition: attachment; filename="hexhub-backup-{id}.tar"
```

---

### Delete Backup

```
DELETE /backups/:id
```

**Controller**: `BackupController.delete/2`

**Path Parameters**:
- `id` - Backup UUID

**Response**:
- Success: Redirect to `/backups` with flash
- Error: Redirect with error flash

**Side Effects**:
- Deletes backup file from filesystem
- Removes record from `:backups` Mnesia table
- Emits telemetry event

---

### Restore Form

```
GET /backups/restore
```

**Controller**: `BackupController.restore_form/2`

**Response**: HTML page with restore upload form

**Template Variables**:
- `@conflict_strategies` - Available strategies
- `@changeset` - Form changeset

---

### Restore Action

```
POST /backups/restore
```

**Controller**: `BackupController.restore/2`

**Request Body** (multipart form):
- `backup[file]` - Uploaded tar file (`Plug.Upload`)
- `backup[conflict_strategy]` - One of: `skip`, `overwrite`, `fail`

**Response**:
- Success: Redirect to `/backups` with summary flash
- Error: Render `restore.html.heex` with errors

**Side Effects**:
- Restores users, packages, releases, owners from archive
- Copies package/doc tarballs to storage
- Emits telemetry events

---

## Router Configuration

Add to `lib/hex_hub_admin_web/router.ex`:

```elixir
scope "/", HexHubAdminWeb do
  pipe_through :browser

  # ... existing routes ...

  # Backup management
  get "/backups", BackupController, :index
  get "/backups/new", BackupController, :new
  get "/backups/restore", BackupController, :restore_form
  post "/backups", BackupController, :create
  post "/backups/restore", BackupController, :restore
  get "/backups/:id", BackupController, :show
  get "/backups/:id/download", BackupController, :download
  delete "/backups/:id", BackupController, :delete
end
```

---

## Navigation

Add to admin sidebar/navigation:

```heex
<.link navigate={~p"/backups"} class="...">
  <.icon name="hero-archive-box" />
  Backups
</.link>
```

---

## Error Responses

| Scenario | Response |
|----------|----------|
| Backup not found | Flash error, redirect to `/backups` |
| File missing (deleted) | Flash error, show details with "File unavailable" |
| Invalid tar file | Flash error, render restore form with validation error |
| Restore conflict (`:fail` strategy) | Flash error, render restore form with conflict details |
| Disk space insufficient | Flash error, render new form with space warning |
