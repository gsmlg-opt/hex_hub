# Research: Admin Backup Management

**Feature**: 007-admin-backup
**Date**: 2025-12-31

## Research Summary

This document captures technical decisions and research findings for implementing the backup/restore feature.

---

## 1. Tar Archive Creation in Elixir/Erlang

### Decision
Use Erlang's built-in `:erl_tar` module for creating and extracting tar archives.

### Rationale
- **Built-in**: No external dependencies required
- **Streaming support**: `:erl_tar.open/2` with `:write` mode supports adding files incrementally
- **Standard format**: Produces POSIX-compliant tar archives compatible with Unix `tar` utility
- **Memory efficient**: Can stream large files without loading entirely into memory

### Alternatives Considered
| Alternative | Why Rejected |
|-------------|--------------|
| System `tar` command via `System.cmd/3` | Platform dependency, less control, security concerns |
| Third-party Elixir library | Unnecessary complexity, `:erl_tar` is sufficient |
| Custom binary format | Not user-inspectable, compatibility issues |

### Key API Points
```elixir
# Creating a tar archive
{:ok, tar} = :erl_tar.open(~c"backup.tar", [:write])
:erl_tar.add(tar, ~c"path/to/file", ~c"archive/path", [])
:erl_tar.close(tar)

# Extracting from tar
:erl_tar.extract(~c"backup.tar", [:verbose, {:cwd, ~c"/extract/path"}])

# Listing contents
{:ok, files} = :erl_tar.table(~c"backup.tar")
```

---

## 2. Streaming Large File Uploads in Phoenix

### Decision
Use Plug.Upload with streaming and chunk processing for large backup uploads.

### Rationale
- Phoenix/Plug handles multipart uploads efficiently
- Files are streamed to temp directory, not held in memory
- Can process tar contents incrementally during upload

### Implementation Pattern
```elixir
# In controller - file already streamed to disk by Plug
def restore(conn, %{"backup" => %Plug.Upload{path: temp_path}}) do
  # temp_path contains the uploaded file
  case Backup.restore_from_file(temp_path) do
    {:ok, result} -> ...
    {:error, reason} -> ...
  end
end

# Phoenix config for large uploads (config/config.exs)
config :hex_hub, HexHubAdminWeb.Endpoint,
  http: [protocol_options: [max_request_line_length: 8192, max_header_value_length: 8192]]
```

### Alternatives Considered
| Alternative | Why Rejected |
|-------------|--------------|
| Chunked upload API | Over-engineering for admin-only feature |
| External upload service | Adds complexity, unnecessary for backup files |

---

## 3. Backup Manifest Format

### Decision
Use JSON format for the backup manifest file stored within the tar archive.

### Rationale
- Human-readable for debugging
- Easy to parse with Jason (already a dependency)
- Can include version info for compatibility checking
- Extensible for future metadata

### Manifest Structure
```json
{
  "version": "1.0",
  "hex_hub_version": "0.1.0",
  "created_at": "2025-12-31T10:30:00Z",
  "created_by": "admin",
  "contents": {
    "users": 15,
    "packages": 42,
    "releases": 128,
    "total_size_bytes": 104857600
  },
  "checksums": {
    "users.json": "sha256:abc123...",
    "packages/": "sha256:def456..."
  }
}
```

### Alternatives Considered
| Alternative | Why Rejected |
|-------------|--------------|
| YAML | Additional dependency (yaml_elixir) |
| Plain text | Harder to parse, less structured |
| Erlang term format | Not human-readable |

---

## 4. Mnesia Data Export Format

### Decision
Export Mnesia data as JSON files within the tar archive.

### Rationale
- Portable across Mnesia schema versions
- Human-readable for verification
- Can selectively restore individual records
- Handles schema evolution gracefully

### Data Files Structure
```text
backup.tar
├── manifest.json           # Backup metadata
├── users.json              # User records (excluding sensitive fields)
├── packages/
│   ├── metadata.json       # Package metadata for all packages
│   └── {name}-{version}.tar.gz  # Package tarballs
├── releases.json           # Release metadata
├── owners.json             # Package ownership relationships
└── docs/
    └── {name}-{version}.tar.gz  # Documentation tarballs
```

### Alternatives Considered
| Alternative | Why Rejected |
|-------------|--------------|
| Mnesia backup (`:mnesia.backup/1`) | Schema-dependent, not portable |
| ETF (Erlang Term Format) | Not human-readable |
| CSV | Poor support for nested structures |

---

## 5. Conflict Resolution During Restore

### Decision
Implement three conflict resolution strategies: skip, overwrite, and fail.

### Rationale
- **Skip**: Preserves existing data, only adds new records
- **Overwrite**: Replaces existing with backup data (useful for rollback)
- **Fail**: Aborts on first conflict (safest, requires clean slate)

### Implementation Approach
```elixir
@type conflict_strategy :: :skip | :overwrite | :fail

def restore(file_path, opts \\ []) do
  strategy = Keyword.get(opts, :conflict_strategy, :skip)
  # ...
end
```

---

## 6. Backup Cleanup GenServer

### Decision
Implement a GenServer that runs daily to delete backups older than 30 days.

### Rationale
- Simple, reliable OTP pattern
- No external scheduler dependencies
- Runs within application supervision tree
- Can be easily tested with time manipulation

### Implementation Pattern
```elixir
defmodule HexHub.Backup.Cleanup do
  use GenServer

  @cleanup_interval :timer.hours(24)
  @retention_days 30

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(state) do
    schedule_cleanup()
    {:ok, state}
  end

  def handle_info(:cleanup, state) do
    cleanup_old_backups()
    schedule_cleanup()
    {:noreply, state}
  end

  defp schedule_cleanup do
    Process.send_after(self(), :cleanup, @cleanup_interval)
  end
end
```

---

## 7. Progress Indication

### Decision
Use Phoenix LiveView for real-time progress updates during backup/restore.

### Rationale
- Already available in the project
- Provides real-time updates without polling
- Good user experience for long-running operations
- Follows existing HexHub patterns

### Implementation Notes
- Backup process sends progress via PubSub
- LiveView subscribes to progress topic
- Updates displayed as percentage and current item

### Alternative for MVP
If LiveView complexity is too high for initial implementation:
- Simple progress bar with JavaScript polling
- Redirect to result page after completion

---

## 8. Security Considerations

### Decision
Exclude API keys from backups; include password hashes for user restoration.

### Rationale
- **API keys excluded**: Security risk if backup is compromised; users regenerate after restore
- **Password hashes included**: Allows seamless user restoration without password reset
- **Admin-only access**: Backup feature restricted to admin dashboard

### Implementation
```elixir
# User export (excludes api_keys table entirely)
defp export_user(user) do
  %{
    username: user.username,
    email: user.email,
    password_hash: user.password_hash,  # Included for seamless restore
    totp_enabled: user.totp_enabled,
    # totp_secret excluded for security
    inserted_at: user.inserted_at,
    updated_at: user.updated_at
  }
end
```

---

## 9. Telemetry Events

### Decision
Emit telemetry events for all backup/restore operations per Constitution VII.

### Events to Implement
```elixir
# Backup created
[:hex_hub, :backup, :created]
%{duration_ms: 5000, size_bytes: 104857600}
%{backup_id: "...", user_count: 15, package_count: 42}

# Backup restore started
[:hex_hub, :backup, :restore, :start]
%{}
%{backup_id: "...", strategy: :skip}

# Backup restore completed
[:hex_hub, :backup, :restore, :complete]
%{duration_ms: 10000}
%{users_restored: 10, packages_restored: 30, conflicts: 5}

# Backup deleted (cleanup or manual)
[:hex_hub, :backup, :deleted]
%{}
%{backup_id: "...", reason: :expired | :manual}
```

---

## Open Questions Resolved

| Question | Resolution |
|----------|------------|
| Backup file size limit | No limit; streaming handles any size |
| Include cached packages | No; only locally published packages |
| Storage location | Server-side in `priv/backups/` with 30-day retention |
| Compression | None in tar; admin can compress externally |
| 2FA secrets in backup | Excluded for security; users re-enable after restore |
