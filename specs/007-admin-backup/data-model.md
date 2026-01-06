# Data Model: Admin Backup Management

**Feature**: 007-admin-backup
**Date**: 2025-12-31

## Overview

This document defines the data entities, relationships, and state transitions for the backup/restore feature.

---

## Entities

### 1. Backup (Mnesia Table: `:backups`)

Represents a created backup archive stored on the server.

| Field | Type | Description |
|-------|------|-------------|
| `id` | `String.t()` | Unique backup identifier (UUID) |
| `filename` | `String.t()` | Tar archive filename |
| `file_path` | `String.t()` | Full path to backup file |
| `size_bytes` | `integer()` | Archive size in bytes |
| `user_count` | `integer()` | Number of users in backup |
| `package_count` | `integer()` | Number of packages in backup |
| `release_count` | `integer()` | Number of releases in backup |
| `created_by` | `String.t()` | Admin username who created backup |
| `status` | `atom()` | `:pending` \| `:completed` \| `:failed` |
| `error_message` | `String.t() \| nil` | Error details if status is `:failed` |
| `created_at` | `DateTime.t()` | When backup was initiated |
| `completed_at` | `DateTime.t() \| nil` | When backup finished |
| `expires_at` | `DateTime.t()` | When backup will be auto-deleted (created_at + 30 days) |

**Primary Key**: `id`
**Indexes**: `created_at`, `expires_at`

### 2. BackupManifest (JSON within tar archive)

Metadata stored inside the backup archive for self-description.

| Field | Type | Description |
|-------|------|-------------|
| `version` | `String.t()` | Manifest format version (e.g., "1.0") |
| `hex_hub_version` | `String.t()` | HexHub version that created backup |
| `created_at` | `String.t()` | ISO 8601 timestamp |
| `created_by` | `String.t()` | Admin username |
| `contents.users` | `integer()` | User count |
| `contents.packages` | `integer()` | Package count |
| `contents.releases` | `integer()` | Release count |
| `contents.total_size_bytes` | `integer()` | Total uncompressed size |
| `checksums` | `map()` | SHA256 checksums for integrity verification |

### 3. RestoreOperation (Transient - not persisted)

Tracks a restore operation in progress.

| Field | Type | Description |
|-------|------|-------------|
| `id` | `String.t()` | Operation identifier |
| `source` | `:upload \| :history` | Where backup came from |
| `backup_id` | `String.t() \| nil` | If from history, the backup ID |
| `conflict_strategy` | `atom()` | `:skip` \| `:overwrite` \| `:fail` |
| `progress` | `map()` | Current progress state |
| `started_at` | `DateTime.t()` | Operation start time |

---

## Relationships

```text
┌─────────────────┐
│     Backup      │
│  (Mnesia table) │
└────────┬────────┘
         │ contains (in tar file)
         ▼
┌─────────────────┐      ┌─────────────────┐
│ BackupManifest  │      │   Users.json    │
│    (JSON)       │      │ Packages/*.tar  │
└─────────────────┘      │ Releases.json   │
                         │ Owners.json     │
                         │ Docs/*.tar      │
                         └─────────────────┘
```

### Backup Archive Contents

| File Path | Content | Source |
|-----------|---------|--------|
| `manifest.json` | BackupManifest | Generated |
| `users.json` | Array of user records | `:users` Mnesia table |
| `packages/metadata.json` | Array of package metadata | `:packages` Mnesia table |
| `packages/{name}-{version}.tar.gz` | Package tarball | `HexHub.Storage` |
| `releases.json` | Array of release records | `:package_releases` Mnesia table |
| `owners.json` | Array of ownership records | `:package_owners` Mnesia table |
| `docs/{name}-{version}.tar.gz` | Documentation tarball | `HexHub.Storage` |

---

## State Transitions

### Backup Lifecycle

```text
                    ┌──────────┐
                    │ (start)  │
                    └────┬─────┘
                         │ create_backup/1
                         ▼
                   ┌──────────┐
                   │ :pending │
                   └────┬─────┘
                        │
           ┌────────────┼────────────┐
           │ success    │            │ error
           ▼            │            ▼
    ┌────────────┐      │     ┌──────────┐
    │ :completed │      │     │ :failed  │
    └─────┬──────┘      │     └────┬─────┘
          │             │          │
          │ 30 days     │          │ manual delete
          │ elapsed     │          │ or 30 days
          ▼             │          ▼
    ┌──────────┐        │    ┌──────────┐
    │ (deleted)│◄───────┘    │ (deleted)│
    └──────────┘             └──────────┘
```

### Restore Operation Flow

```text
┌─────────────┐     ┌──────────────┐     ┌────────────────┐
│ Upload file │ ──► │ Validate tar │ ──► │ Parse manifest │
└─────────────┘     └──────────────┘     └───────┬────────┘
                                                 │
                                                 ▼
                    ┌──────────────────────────────────────┐
                    │ For each entity type (users, pkgs):  │
                    │  ┌─────────────────────────────────┐ │
                    │  │ Read from archive               │ │
                    │  │         ▼                       │ │
                    │  │ Check for conflicts             │ │
                    │  │         ▼                       │ │
                    │  │ Apply conflict strategy         │ │
                    │  │         ▼                       │ │
                    │  │ Write to Mnesia                 │ │
                    │  └─────────────────────────────────┘ │
                    └──────────────────────────────────────┘
                                                 │
                    ┌────────────────────────────┼─────────────────────┐
                    │ success                    │                     │ error
                    ▼                            │                     ▼
          ┌──────────────────┐                   │           ┌────────────────┐
          │ Emit telemetry   │                   │           │ Rollback txn   │
          │ Return summary   │                   │           │ Return error   │
          └──────────────────┘                   │           └────────────────┘
```

---

## Validation Rules

### Backup Creation

| Rule | Description |
|------|-------------|
| Unique ID | UUID generated for each backup |
| Valid admin | `created_by` must be valid admin user |
| Disk space | Check available space before starting |
| No concurrent | Only one backup at a time (simple lock) |

### Backup Restoration

| Rule | Description |
|------|-------------|
| Valid tar | Must be valid tar archive |
| Has manifest | Must contain `manifest.json` |
| Version compatible | Manifest version must be supported |
| Checksums match | All files must pass checksum verification |

### Conflict Resolution

| Entity | Conflict Key | Resolution |
|--------|--------------|------------|
| User | `username` | Skip, overwrite, or fail |
| Package | `name` | Skip, overwrite, or fail |
| Release | `(package_name, version)` | Skip, overwrite, or fail |
| Ownership | `(package_name, username)` | Skip, overwrite, or fail |

---

## Data Excluded from Backups

| Table | Reason |
|-------|--------|
| `:api_keys` | Security - users regenerate after restore |
| `:rate_limit` | Ephemeral - no value in backing up |
| `:audit_logs` | Not restored - new instance gets fresh logs |
| `:upstream_configs` | Configuration - not user data |
| `:publish_configs` | Configuration - not user data |
| `:blocked_addresses` | Security policy - not user data |
| `:system_metadata` | System state - not user data |
| Cached packages (source: `:cached`) | Can be re-fetched from upstream |

---

## Mnesia Schema Addition

```elixir
# Add to HexHub.Mnesia @tables
:backups

# Table definition
{:backups,
 [
   attributes: [
     :id,
     :filename,
     :file_path,
     :size_bytes,
     :user_count,
     :package_count,
     :release_count,
     :created_by,
     :status,
     :error_message,
     :created_at,
     :completed_at,
     :expires_at
   ],
   type: :set,
   index: [:created_at, :expires_at]
 ] ++ storage_opt(storage_type)}
```
