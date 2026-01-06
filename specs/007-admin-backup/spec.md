# Feature Specification: Admin Backup Management

**Feature Branch**: `007-admin-backup`
**Created**: 2025-12-31
**Status**: Draft
**Input**: User description: "we should have a backup manage in the admin, it needs to backup and restore the users and users's published package to this service, the backup output should be a tar and import with this a tar"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Create Full System Backup (Priority: P1)

An administrator needs to create a complete backup of all users and their published packages to protect against data loss or to migrate to another server. The administrator navigates to the admin backup section and initiates a backup export, receiving a downloadable tar archive containing all user data and package files.

**Why this priority**: This is the core functionality - without the ability to create backups, the restore feature is useless. It provides the fundamental data protection capability.

**Independent Test**: Can be fully tested by creating a backup with existing users/packages and verifying the tar archive contains all expected data. Delivers immediate value by enabling data protection.

**Acceptance Scenarios**:

1. **Given** an admin user is logged into the admin dashboard, **When** they navigate to the backup section and click "Create Backup", **Then** the system generates a tar archive containing all users and packages
2. **Given** a backup is being created, **When** the backup generation completes, **Then** the admin can download the tar file to their local machine
3. **Given** there are users with published packages in the system, **When** a backup is created, **Then** the tar archive includes user account data, package metadata, and package tarball files
4. **Given** a backup is created, **When** the admin downloads the tar file, **Then** the file is properly formatted and can be extracted using standard tar utilities

---

### User Story 2 - Restore System from Backup (Priority: P2)

An administrator needs to restore users and packages from a previously created backup tar file. This could be for disaster recovery, migrating to a new server, or restoring accidentally deleted data. The administrator uploads the tar file and the system restores all users and packages contained within.

**Why this priority**: Restoration completes the backup cycle. Without restore, backups are not useful. It depends on P1 to have valid backup files to restore.

**Independent Test**: Can be tested by uploading a valid backup tar file and verifying all users and packages are restored correctly. Delivers value by enabling disaster recovery.

**Acceptance Scenarios**:

1. **Given** an admin has a valid backup tar file, **When** they upload it to the restore section, **Then** the system restores all users and packages from the backup
2. **Given** a backup tar file contains users that already exist in the system, **When** restore is performed, **Then** the system prompts the admin to choose between skip or overwrite strategies
3. **Given** a backup tar file is uploaded, **When** the restore process starts, **Then** the admin sees progress indication during the restore operation
4. **Given** a restore operation completes successfully, **When** the admin checks the system, **Then** all users from the backup exist with their original credentials and all packages are available with their releases

---

### User Story 3 - View Backup History (Priority: P3)

An administrator wants to see a history of backups that have been created, including when they were created and their contents summary. This helps track backup frequency and verify backup practices.

**Why this priority**: This is an enhancement that improves usability but is not essential for core backup/restore functionality.

**Independent Test**: Can be tested by creating multiple backups and verifying the history list shows all backups with correct metadata. Delivers value by providing backup audit trail.

**Acceptance Scenarios**:

1. **Given** backups have been created previously, **When** the admin views the backup history, **Then** they see a list of backups with creation timestamps
2. **Given** a backup exists in the history, **When** the admin clicks on it, **Then** they can view details including user count and package count
3. **Given** a backup exists in the history, **When** the admin chooses to download it, **Then** the backup tar file is downloaded

---

### Edge Cases

- What happens when a backup is created with no users or packages in the system? (System creates an empty but valid tar archive)
- How does system handle corrupted or invalid tar files during restore? (System validates tar integrity before processing and shows clear error message)
- What happens if disk space is insufficient during backup creation? (System checks available space before starting and fails gracefully with appropriate message)
- How does system handle very large backups (many packages)? (System streams the backup creation to avoid memory issues)
- What happens if restore is interrupted midway? (System performs restore in transaction - all or nothing)
- How does system handle backup files from different HexHub versions? (Backup includes version metadata for compatibility checking)

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST provide a dedicated backup management section in the admin dashboard
- **FR-002**: System MUST allow administrators to create a backup containing all user accounts
- **FR-003**: System MUST include all locally published packages and their releases in the backup (excluding cached upstream packages)
- **FR-004**: System MUST include package tarball files (the actual .tar.gz package files) in the backup
- **FR-005**: System MUST include package documentation files in the backup when they exist
- **FR-006**: System MUST output the backup as a standard tar archive file (.tar format)
- **FR-007**: System MUST allow administrators to download the created backup file
- **FR-008**: System MUST allow administrators to upload a backup tar file for restoration
- **FR-009**: System MUST validate the backup tar file format and integrity before restoration
- **FR-010**: System MUST restore user accounts with their credentials (password hashes preserved)
- **FR-011**: System MUST restore all packages and releases with their original metadata
- **FR-012**: System MUST restore package ownership relationships
- **FR-013**: System MUST provide conflict resolution options when restoring existing users/packages (skip, overwrite)
- **FR-014**: System MUST show progress indication during backup and restore operations
- **FR-015**: System MUST maintain a history of created backups with timestamps
- **FR-016**: System MUST allow downloading previously created backups from history
- **FR-017**: System MUST include backup version metadata for compatibility checking
- **FR-018**: System MUST exclude ephemeral data (rate limits, active sessions) from backups
- **FR-019**: System MUST log all backup and restore operations in the audit log
- **FR-020**: System MUST store created backups on the server for history access
- **FR-021**: System MUST automatically delete backups older than 30 days
- **FR-022**: System MUST accept backup uploads of any size without artificial limits
- **FR-023**: System MUST process large backup files using streaming to avoid memory exhaustion

### Key Entities

- **Backup Archive**: A tar file containing all backup data, with a manifest describing contents, backup version, creation timestamp, and source system information
- **Backup Manifest**: Metadata file within the archive listing all included users, packages, and versions along with backup compatibility version
- **User Backup Data**: User account information including username, email, password hash, 2FA settings (if enabled), account status
- **Package Backup Data**: Package metadata, all release versions, requirements, documentation references, ownership information
- **Package Files**: The actual tarball files (.tar.gz) for each package release stored in the system

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Administrators can create a complete system backup in under 5 minutes for systems with up to 100 packages
- **SC-002**: Backup tar files can be restored to a fresh HexHub instance with 100% data fidelity
- **SC-003**: 95% of administrators can successfully create and restore a backup without documentation on first attempt
- **SC-004**: Backup file format is compatible with standard tar utilities (can be inspected with tar -tf)
- **SC-005**: Restore operation handles 1000 packages without timeout or memory issues
- **SC-006**: All backup and restore operations are logged for audit compliance

## Clarifications

### Session 2025-12-31

- Q: Where should backups be stored for the history feature? → A: Server storage with 30-day automatic cleanup
- Q: What is the maximum upload size for restore? → A: No limit (handle any size)
- Q: Should cached upstream packages be included in backups? → A: Only locally published packages (exclude cached)

## Assumptions

- Administrators have sufficient disk space to store backup files (system will check and warn if space is low)
- Backup files may be stored externally and re-imported at any time
- API keys are intentionally excluded from backups for security reasons (users will need to generate new keys after restore)
- Backup format uses standard tar without compression to allow inspection; admins can compress externally if needed
- Package tarball integrity is preserved exactly as uploaded (checksums match after restore)
- Cached upstream packages are excluded from backups (can be re-fetched from upstream after restore)
