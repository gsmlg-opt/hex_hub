# Tasks: Public MCP API for Package Information

**Input**: Design documents from `/specs/008-mcp-public-api/`
**Prerequisites**: plan.md (required), spec.md (required for user stories), research.md, data-model.md, contracts/

**Tests**: Tests are included as required by Constitution Principle VI (Test Coverage Requirements).

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions

This is a Phoenix/Elixir project:
- **Source**: `lib/hex_hub/` (core), `lib/hex_hub_web/` (web)
- **Tests**: `test/hex_hub_web/controllers/`
- **Config**: `config/`

---

## Phase 1: Setup (Configuration Verification)

**Purpose**: Verify existing MCP infrastructure and configuration for public access

- [x] T001 Verify MCP server starts with `enabled: true` in config/dev.exs
- [x] T002 [P] Verify existing MCP routes in lib/hex_hub_web/router.ex (GET /mcp/tools, POST /mcp, GET /mcp/health)
- [x] T003 [P] Verify `require_auth: false` config is recognized in lib/hex_hub/mcp.ex

---

## Phase 2: Foundational (Rate Limiting Infrastructure)

**Purpose**: Implement the rate limiting stub that blocks public deployment

**⚠️ CRITICAL**: Rate limiting must be complete before public deployment

- [x] T004 Implement `check_rate_limit/2` function in lib/hex_hub/mcp/transport.ex to use Mnesia rate limit tables
- [x] T005 Add MCP-specific rate limit key prefix "mcp:ip:" in lib/hex_hub/mcp/transport.ex
- [x] T006 Return JSON-RPC error code -32002 with retry-after header when rate limited in lib/hex_hub_web/controllers/mcp_controller.ex
- [x] T007 Add telemetry event `[:hex_hub, :mcp, :rate_limited]` in lib/hex_hub/mcp/transport.ex

**Checkpoint**: Rate limiting infrastructure ready - user story implementation can proceed

---

## Phase 3: User Story 1 - AI Client Queries Package Information (Priority: P1) 🎯 MVP

**Goal**: Enable AI clients to search and retrieve package information via MCP without authentication

**Independent Test**: Send `search_packages` and `get_package` MCP requests without API key and receive valid package data

### Tests for User Story 1

- [x] T008 [P] [US1] Create test file test/hex_hub_web/controllers/mcp_public_test.exs with test setup
- [x] T009 [P] [US1] Add test: public access to search_packages without API key in test/hex_hub_web/controllers/mcp_public_test.exs
- [x] T010 [P] [US1] Add test: public access to get_package without API key in test/hex_hub_web/controllers/mcp_public_test.exs
- [x] T011 [P] [US1] Add test: public access to list_packages without API key in test/hex_hub_web/controllers/mcp_public_test.exs
- [x] T012 [P] [US1] Add test: invalid JSON-RPC request returns error -32600 in test/hex_hub_web/controllers/mcp_public_test.exs
- [x] T013 [P] [US1] Add test: non-existent package returns proper error in test/hex_hub_web/controllers/mcp_public_test.exs

### Implementation for User Story 1

- [x] T014 [US1] Update authenticate_mcp_request/2 in lib/hex_hub_web/controllers/mcp_controller.ex to pass through when require_auth? is false
- [x] T015 [US1] Verify search_packages tool returns consistent data with REST API in lib/hex_hub/mcp/tools/packages.ex
- [x] T016 [US1] Verify get_package tool includes all releases and metadata in lib/hex_hub/mcp/tools/packages.ex
- [x] T017 [US1] Add telemetry event for successful package queries in lib/hex_hub/mcp/tools/packages.ex

**Checkpoint**: AI clients can search and retrieve package information without authentication

---

## Phase 4: User Story 2 - AI Client Lists Available Tools (Priority: P1)

**Goal**: Enable AI clients to discover available MCP tools via the tools/list endpoint

**Independent Test**: Send GET /mcp/tools without API key and receive complete tool list with schemas

### Tests for User Story 2

- [x] T018 [P] [US2] Add test: GET /mcp/tools returns all tools without authentication in test/hex_hub_web/controllers/mcp_public_test.exs
- [x] T019 [P] [US2] Add test: GET /mcp/server-info returns server capabilities in test/hex_hub_web/controllers/mcp_public_test.exs
- [x] T020 [P] [US2] Add test: returned tools include inputSchema for each tool in test/hex_hub_web/controllers/mcp_public_test.exs

### Implementation for User Story 2

- [x] T021 [US2] Verify list_tools action bypasses auth when require_auth? is false in lib/hex_hub_web/controllers/mcp_controller.ex
- [x] T022 [US2] Verify server_info action returns correct authentication status in lib/hex_hub_web/controllers/mcp_controller.ex
- [x] T023 [US2] Ensure all read-only tools are listed in capabilities in lib/hex_hub_web/controllers/mcp_controller.ex

**Checkpoint**: AI clients can discover all available MCP tools and their schemas

---

## Phase 5: User Story 3 - AI Client Retrieves Package Dependencies (Priority: P2)

**Goal**: Enable AI clients to analyze package dependencies via MCP tools

**Independent Test**: Send `get_package_metadata` and `get_dependency_tree` requests and receive dependency information

### Tests for User Story 3

- [x] T024 [P] [US3] Add test: get_package_metadata returns dependencies without auth in test/hex_hub_web/controllers/mcp_public_test.exs
- [x] T025 [P] [US3] Add test: get_dependency_tree returns tree structure in test/hex_hub_web/controllers/mcp_public_test.exs
- [x] T026 [P] [US3] Add test: optional dependencies are marked correctly in test/hex_hub_web/controllers/mcp_public_test.exs

### Implementation for User Story 3

- [x] T027 [US3] Verify get_package_metadata tool is accessible without auth in lib/hex_hub/mcp/tools/packages.ex
- [x] T028 [US3] Verify get_dependency_tree tool returns complete dependency information in lib/hex_hub/mcp/tools/dependencies.ex
- [x] T029 [US3] Ensure check_compatibility tool works for public package queries in lib/hex_hub/mcp/tools/dependencies.ex

**Checkpoint**: AI clients can analyze package dependencies without authentication

---

## Phase 6: User Story 4 - AI Client Accesses Package Documentation Links (Priority: P3)

**Goal**: Enable AI clients to retrieve documentation URLs and external links for packages

**Independent Test**: Request package info and verify documentation URLs and external links are included

### Tests for User Story 4

- [x] T030 [P] [US4] Add test: package info includes docs_url when docs exist in test/hex_hub_web/controllers/mcp_public_test.exs
- [x] T031 [P] [US4] Add test: package info includes external links (GitHub, homepage) in test/hex_hub_web/controllers/mcp_public_test.exs
- [x] T032 [P] [US4] Add test: get_documentation tool returns doc content in test/hex_hub_web/controllers/mcp_public_test.exs

### Implementation for User Story 4

- [x] T033 [US4] Verify format_package/1 includes docs_url in lib/hex_hub/mcp/tools/packages.ex
- [x] T034 [US4] Verify get_documentation tool is accessible without auth in lib/hex_hub/mcp/tools/documentation.ex
- [x] T035 [US4] Ensure list_documentation_versions works for public access in lib/hex_hub/mcp/tools/documentation.ex

**Checkpoint**: AI clients can access all package documentation and links

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Documentation, validation, and cleanup

- [x] T036 [P] Add rate limiting test: excessive requests return 429 with retry-after in test/hex_hub_web/controllers/mcp_public_test.exs
- [x] T037 [P] Add test: MCP disabled returns error -32001 in test/hex_hub_web/controllers/mcp_public_test.exs
- [x] T038 [P] Update CLAUDE.md with MCP public API documentation
- [x] T039 [P] Add MCP deployment notes to config/config.exs comments for MCP_REQUIRE_AUTH
- [x] T040 Run quickstart.md validation: test all example curl commands work (validated via test suite)
- [x] T041 Verify all MCP telemetry events are emitted correctly via test run

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - verification only
- **Foundational (Phase 2)**: Depends on Setup - implements rate limiting
- **User Stories (Phase 3-6)**: All depend on Foundational phase completion
  - US1 and US2 are both P1 and can run in parallel
  - US3 depends only on Foundational (not US1/US2)
  - US4 depends only on Foundational (not US1/US2/US3)
- **Polish (Phase 7)**: Depends on all user stories being complete

### User Story Dependencies

- **User Story 1 (P1)**: Can start after Foundational - No dependencies on other stories
- **User Story 2 (P1)**: Can start after Foundational - No dependencies on other stories
- **User Story 3 (P2)**: Can start after Foundational - No dependencies on other stories
- **User Story 4 (P3)**: Can start after Foundational - No dependencies on other stories

**All user stories are independently testable** - they can be implemented and validated in any order.

### Within Each User Story

- Tests MUST be written first and FAIL before implementation
- Implementation tasks verify/update existing code
- Story complete when all tests pass

### Parallel Opportunities

**Phase 2 (Foundational)**:
- T004, T005, T006, T007 must be sequential (rate limiting implementation)

**Phase 3 (US1)**:
- T008-T013 can all run in parallel (different test cases, same file)
- T014-T017 mostly sequential (same file modifications)

**Phase 4 (US2)**:
- T018-T020 can all run in parallel (different test cases)
- T021-T023 mostly sequential (same file)

**Phase 5-6 (US3, US4)**:
- Test tasks can run in parallel within each story
- Implementation tasks mostly sequential within each story

**Cross-Story Parallelism**:
- US1 and US2 can run fully in parallel (both P1, no dependencies)
- US3 can start while US1/US2 are in progress
- US4 can start while US1/US2/US3 are in progress

---

## Parallel Example: User Story 1 Tests

```bash
# Launch all US1 tests together (they test different scenarios in same file):
Task: T008 - Create test file
# Then in parallel:
Task: T009 - Test search_packages
Task: T010 - Test get_package
Task: T011 - Test list_packages
Task: T012 - Test invalid request
Task: T013 - Test non-existent package
```

---

## Implementation Strategy

### MVP First (User Stories 1 + 2)

1. Complete Phase 1: Setup (verification)
2. Complete Phase 2: Foundational (rate limiting)
3. Complete Phase 3: User Story 1 (package queries)
4. Complete Phase 4: User Story 2 (tool discovery)
5. **STOP and VALIDATE**: Run all tests, verify public access works
6. Deploy/demo with MVP functionality

### Incremental Delivery

1. Setup + Foundational → Rate limiting ready
2. Add US1 → AI can query packages → Demo
3. Add US2 → AI can discover tools → Demo
4. Add US3 → AI can analyze dependencies → Demo
5. Add US4 → AI can access docs → Full feature complete

### Parallel Team Strategy

With 2 developers:

1. Both complete Setup + Foundational together
2. Once Foundational is done:
   - Developer A: User Story 1 + User Story 3
   - Developer B: User Story 2 + User Story 4
3. Merge and run full test suite
4. Complete Polish phase together

---

## Notes

- This feature builds on existing MCP infrastructure - most tasks verify/update rather than create
- Rate limiting (Phase 2) is the critical new functionality
- Tests use existing test infrastructure and setup patterns
- All MCP tools already exist - tasks verify public accessibility
- Constitution Principle VI requires all endpoints have test coverage
- Telemetry-first logging already in place (Principle VII.a)
