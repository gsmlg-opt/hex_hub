# Tasks: Admin Backup Management

**Input**: Design documents from `/specs/007-admin-backup/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions

- **Core logic**: `lib/hex_hub/`
- **Admin web**: `lib/hex_hub_admin_web/`
- **Tests**: `test/hex_hub/` and `test/hex_hub_admin_web/`

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Project initialization and database schema changes

- [x] T001 Add `:backups` table to Mnesia schema in lib/hex_hub/mnesia.ex
- [x] T002 Add backup_path configuration to config/config.exs
- [x] T003 [P] Create priv/backups/ directory with .gitkeep

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core backup modules that ALL user stories depend on

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [x] T004 Create HexHub.Backup context module in lib/hex_hub/backup.ex with basic CRUD operations
- [x] T005 [P] Create HexHub.Backup.Manifest module in lib/hex_hub/backup/manifest.ex for JSON manifest handling
- [x] T006 [P] Add backup telemetry events to lib/hex_hub/telemetry.ex
- [x] T007 Add backup routes to lib/hex_hub_admin_web/router.ex per contracts/admin-routes.md
- [x] T008 Create BackupController skeleton in lib/hex_hub_admin_web/controllers/backup_controller.ex
- [x] T009 Create BackupHTML module in lib/hex_hub_admin_web/controllers/backup_html.ex

**Checkpoint**: Foundation ready - user story implementation can now begin

---

## Phase 3: User Story 1 - Create Full System Backup (Priority: P1) 🎯 MVP

**Goal**: Admin can create a complete backup of all users and locally-published packages as a downloadable tar archive

**Independent Test**: Create backup with test users/packages, verify tar contains all expected data, download file

### Implementation for User Story 1

- [x] T010 [US1] Create HexHub.Backup.Exporter module in lib/hex_hub/backup/exporter.ex with streaming tar creation
- [x] T011 [US1] Implement export_users/1 in lib/hex_hub/backup/exporter.ex to export users to JSON
- [x] T012 [US1] Implement export_packages/1 in lib/hex_hub/backup/exporter.ex to export packages metadata to JSON
- [x] T013 [US1] Implement export_releases/1 in lib/hex_hub/backup/exporter.ex to export releases to JSON
- [x] T014 [US1] Implement export_owners/1 in lib/hex_hub/backup/exporter.ex to export ownership records to JSON
- [x] T015 [US1] Implement copy_package_tarballs/2 in lib/hex_hub/backup/exporter.ex to add package files to archive
- [x] T016 [US1] Implement copy_doc_tarballs/2 in lib/hex_hub/backup/exporter.ex to add documentation files to archive
- [x] T017 [US1] Implement create_backup/1 in lib/hex_hub/backup.ex that orchestrates full backup creation
- [x] T018 [US1] Implement BackupController.new/2 in lib/hex_hub_admin_web/controllers/backup_controller.ex
- [x] T019 [US1] Implement BackupController.create/2 in lib/hex_hub_admin_web/controllers/backup_controller.ex
- [x] T020 [US1] Implement BackupController.download/2 in lib/hex_hub_admin_web/controllers/backup_controller.ex
- [x] T021 [P] [US1] Create new.html.heex template in lib/hex_hub_admin_web/controllers/backup_html/new.html.heex
- [x] T021a [US1] Add backup progress telemetry events in lib/hex_hub/backup/exporter.ex for step tracking
- [ ] T021b [US1] Add progress display component in new.html.heex showing current backup step and completion percentage
- [x] T022 [US1] Add backup creation audit logging via HexHub.Audit in lib/hex_hub/backup.ex
- [ ] T023 [US1] Write unit tests for exporter in test/hex_hub/backup/exporter_test.exs
- [ ] T024 [US1] Write controller tests for create/download in test/hex_hub_admin_web/controllers/backup_controller_test.exs

**Checkpoint**: User Story 1 complete - admin can create and download backups

---

## Phase 4: User Story 2 - Restore System from Backup (Priority: P2)

**Goal**: Admin can upload a backup tar file and restore all users and packages with conflict resolution

**Independent Test**: Upload backup tar file, verify users/packages restored, test skip/overwrite strategies

### Implementation for User Story 2

- [x] T025 [US2] Create HexHub.Backup.Importer module in lib/hex_hub/backup/importer.ex
- [x] T026 [US2] Implement validate_tar/1 in lib/hex_hub/backup/importer.ex to verify tar integrity
- [x] T027 [US2] Implement validate_manifest/1 in lib/hex_hub/backup/importer.ex to check version compatibility
- [x] T028 [US2] Implement restore_users/2 in lib/hex_hub/backup/importer.ex with conflict handling
- [x] T029 [US2] Implement restore_packages/2 in lib/hex_hub/backup/importer.ex with conflict handling
- [x] T030 [US2] Implement restore_releases/2 in lib/hex_hub/backup/importer.ex with conflict handling
- [x] T031 [US2] Implement restore_owners/2 in lib/hex_hub/backup/importer.ex with conflict handling
- [x] T032 [US2] Implement restore_package_files/2 in lib/hex_hub/backup/importer.ex to copy tarballs to storage
- [x] T033 [US2] Implement restore_doc_files/2 in lib/hex_hub/backup/importer.ex to copy docs to storage
- [x] T034 [US2] Implement restore_from_file/2 in lib/hex_hub/backup.ex that orchestrates full restore
- [x] T035 [US2] Implement BackupController.restore_form/2 in lib/hex_hub_admin_web/controllers/backup_controller.ex
- [x] T036 [US2] Implement BackupController.restore/2 in lib/hex_hub_admin_web/controllers/backup_controller.ex
- [x] T037 [P] [US2] Create restore.html.heex template in lib/hex_hub_admin_web/controllers/backup_html/restore.html.heex
- [ ] T037a [US2] Add restore progress telemetry events in lib/hex_hub/backup/importer.ex for step tracking
- [ ] T037b [US2] Add progress display component in restore.html.heex showing current restore step and completion percentage
- [x] T038 [US2] Add restore operation audit logging via HexHub.Audit in lib/hex_hub/backup.ex
- [ ] T039 [US2] Write unit tests for importer in test/hex_hub/backup/importer_test.exs
- [ ] T040 [US2] Write controller tests for restore in test/hex_hub_admin_web/controllers/backup_controller_test.exs

**Checkpoint**: User Story 2 complete - admin can restore from backup files

---

## Phase 5: User Story 3 - View Backup History (Priority: P3)

**Goal**: Admin can view list of created backups with timestamps and download previous backups

**Independent Test**: Create multiple backups, verify history list shows all with correct metadata, download from history

### Implementation for User Story 3

- [x] T041 [US3] Implement list_backups/0 in lib/hex_hub/backup.ex to retrieve backup history
- [x] T042 [US3] Implement get_backup/1 in lib/hex_hub/backup.ex to get single backup details
- [x] T043 [US3] Implement delete_backup/1 in lib/hex_hub/backup.ex for manual deletion
- [x] T044 [US3] Implement BackupController.index/2 in lib/hex_hub_admin_web/controllers/backup_controller.ex
- [x] T045 [US3] Implement BackupController.show/2 in lib/hex_hub_admin_web/controllers/backup_controller.ex
- [x] T046 [US3] Implement BackupController.delete/2 in lib/hex_hub_admin_web/controllers/backup_controller.ex
- [x] T047 [P] [US3] Create index.html.heex template in lib/hex_hub_admin_web/controllers/backup_html/index.html.heex
- [x] T048 [P] [US3] Create show.html.heex template in lib/hex_hub_admin_web/controllers/backup_html/show.html.heex
- [ ] T049 [US3] Write controller tests for index/show/delete in test/hex_hub_admin_web/controllers/backup_controller_test.exs

**Checkpoint**: User Story 3 complete - full backup history management available

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Cleanup, 30-day retention, and navigation integration

- [x] T050 [P] Create HexHub.Backup.Cleanup GenServer in lib/hex_hub/backup/cleanup.ex for 30-day retention
- [x] T051 Add Cleanup GenServer to application supervision tree in lib/hex_hub/application.ex
- [ ] T052 [P] Write tests for cleanup in test/hex_hub/backup/cleanup_test.exs
- [x] T053 Add "Backups" link to admin sidebar navigation in lib/hex_hub_admin_web/components/layouts.ex
- [x] T054 Add edge case handling for empty backups (no users/packages) in lib/hex_hub/backup/exporter.ex
- [x] T055 Add disk space check before backup creation in lib/hex_hub/backup.ex
- [ ] T056 Run full integration test: create backup, restore to clean system, verify data fidelity

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion - BLOCKS all user stories
- **User Stories (Phase 3-5)**: All depend on Foundational phase completion
- **Polish (Phase 6)**: Depends on all user stories being complete

### User Story Dependencies

- **User Story 1 (P1)**: Can start after Foundational (Phase 2) - No dependencies on other stories
- **User Story 2 (P2)**: Can start after Foundational (Phase 2) - Requires valid backup files (from US1 or test fixtures)
- **User Story 3 (P3)**: Can start after Foundational (Phase 2) - Uses Backup entity from US1

### Within Each User Story

- Exporter/Importer modules before context functions
- Context functions before controller actions
- Controller actions before templates
- Implementation before tests (or TDD: tests first)

### Parallel Opportunities

- T002 and T003 can run in parallel (Setup phase)
- T005 and T006 can run in parallel (Foundational phase)
- T021 can run in parallel with controller implementation (different files)
- T037 can run in parallel with controller implementation
- T047 and T048 can run in parallel (different template files)
- T050 and T052 can run in parallel (cleanup module and tests)

---

## Parallel Example: User Story 1

```bash
# After T017 (create_backup/1) is complete, these can run in parallel:
Task: "T018 [US1] Implement BackupController.new/2"
Task: "T021 [P] [US1] Create new.html.heex template"

# Models/exporters can be developed in parallel:
Task: "T011 [US1] Implement export_users/1"
Task: "T012 [US1] Implement export_packages/1"
Task: "T013 [US1] Implement export_releases/1"
Task: "T014 [US1] Implement export_owners/1"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (T001-T003)
2. Complete Phase 2: Foundational (T004-T009)
3. Complete Phase 3: User Story 1 (T010-T024)
4. **STOP and VALIDATE**: Create backup, download, verify tar contents
5. Deploy/demo if ready - backup creation is immediately valuable

### Incremental Delivery

1. Setup + Foundational → Foundation ready
2. Add User Story 1 → Test independently → Deploy (MVP - backup creation)
3. Add User Story 2 → Test independently → Deploy (restore capability)
4. Add User Story 3 → Test independently → Deploy (full backup management)
5. Polish phase → Production ready

### Total Task Count

| Phase | Tasks | Story |
|-------|-------|-------|
| Phase 1: Setup | 3 | - |
| Phase 2: Foundational | 6 | - |
| Phase 3: User Story 1 | 17 | US1 |
| Phase 4: User Story 2 | 18 | US2 |
| Phase 5: User Story 3 | 9 | US3 |
| Phase 6: Polish | 7 | - |
| **Total** | **60** | |

---

## Notes

- [P] tasks = different files, no dependencies on incomplete tasks in same phase
- [Story] label maps task to specific user story for traceability
- Each user story is independently completable and testable
- Commit after each task or logical group
- Stop at any checkpoint to validate story independently
- All templates use DaisyUI components per Constitution
- All logging via telemetry events per Constitution VII
