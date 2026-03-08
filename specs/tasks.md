# Tasks: VM Isolation (aibox)

**Input**: Design documents from `/specs/003-vm-isolation/`
**Prerequisites**: plan.md (required), spec.md (required), research.md, contracts/

**Tests**: Integration tests using bats-core as specified in plan.md.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- File paths reference source code relative to repository root

---

## Phase 1: Setup

**Purpose**: Project initialization and directory structure

- [x] T001 Create aibox/ directory structure per plan.md: bin/, lib/, templates/, tests/
- [x] T002 Create aibox/bin/aibox CLI entrypoint with command routing (setup|start|stop|teardown|status|exec|init) in aibox/bin/aibox
- [x] T003 [P] Install bats-core testing framework and create test helper in aibox/tests/test_helper.bash
- [x] T004 [P] Create aibox/lib/config.sh — config file parser (read aibox.yaml, validate fields, provide defaults per contracts/config-schema.md)
- [x] T005 [P] Create aibox/templates/aibox.yaml — default configuration template per contracts/config-schema.md

**Checkpoint**: Project structure in place, CLI entrypoint routes to subcommands, config parsing works

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Runtime detection and VM management primitives that all commands depend on

**CRITICAL**: No user story work can begin until this phase is complete

- [x] T006 Implement runtime detection in aibox/lib/config.sh — auto-detect OrbStack vs Lima, validate installed, error if neither found
- [x] T007 Create aibox/templates/provision.sh — in-VM provisioning script that installs languages and agents based on config (node, python, go, rust, claude, etc.)
- [x] T008 [P] Create aibox/lib/common.sh — shared utilities (logging, color output, error handling, VM name derivation from project path)
- [x] T009 Implement `aibox init` command in aibox/lib/init.sh — generate default aibox.yaml and .aibox-env.example in current directory, add .aibox-env to .gitignore

**Checkpoint**: Runtime detection works, provisioning script handles configurable tools, shared utilities available

---

## Phase 3: User Story 1 — Sandboxed Development Environment (Priority: P1) MVP

**Goal**: AI agent runs inside VM with filesystem isolation — can only access project directory, changes sync bidirectionally

**Independent Test**: Launch agent in VM, verify project files accessible, verify host files (~/ssh, ~/.env) inaccessible

### Implementation

- [x] T010 [US1] Implement `aibox setup` in aibox/lib/setup.sh — create VM (OrbStack: `orb create`, Lima: `limactl create`), mount project dir only via VirtioFS, run provision.sh inside VM
- [x] T011 [US1] Implement `aibox start` in aibox/lib/start.sh — start existing VM, remount project directory, pass env vars from .aibox-env and config pass_through list
- [x] T012 [US1] Implement `aibox stop` in aibox/lib/stop.sh — graceful shutdown with 30s timeout, force-kill fallback
- [x] T013 [US1] Implement `aibox teardown` in aibox/lib/teardown.sh — confirm prompt (--yes to skip), stop VM, delete VM instance, report cleanup
- [x] T014 [US1] Implement `aibox status` in aibox/lib/status.sh — show VM state, uptime, resource usage, mounted paths, network rules, env vars (names only)
- [x] T015 [US1] Implement `aibox exec` in aibox/lib/exec.sh — run command inside VM as non-root user, working dir /workspace, stream stdout/stderr, pass through exit code
- [x] T016 [US1] Write filesystem isolation tests in aibox/tests/test_isolation.bats — verify /workspace accessible, ~/.ssh inaccessible, ~/Documents inaccessible, file sync bidirectional

**Checkpoint**: Full VM lifecycle works (setup → start → exec → stop → teardown). Files sync. Host filesystem isolated.

---

## Phase 4: User Story 2 — Controlled Network Access (Priority: P2)

**Goal**: Default-deny network with configurable allowlist — agent can install packages and call APIs but can't reach internal services

**Independent Test**: From inside VM, curl allowed hosts succeeds, curl blocked hosts fails, host services blocked unless explicitly allowed

### Implementation

- [x] T017 [US2] Implement network rule application in aibox/lib/network.sh — parse network config, generate iptables rules, apply inside VM on start
- [x] T018 [US2] Add default network allowlist in aibox/templates/network-defaults.yaml — registry.npmjs.org:443, github.com:443, api.anthropic.com:443, pypi.org:443, DNS
- [x] T019 [US2] Implement host_services forwarding in aibox/lib/network.sh — map configured host ports through VM gateway so agent can reach explicitly allowed host services
- [x] T020 [US2] Integrate network rules into aibox/lib/start.sh — apply iptables rules after VM start, before reporting ready
- [x] T021 [US2] Write network isolation tests in aibox/tests/test_network.bats — verify allowed hosts reachable, blocked hosts unreachable, host services blocked by default, allowed host services reachable

**Checkpoint**: Network isolation enforced. Package installs work. Host services blocked unless explicitly allowed.

---

## Phase 5: User Story 3 — Easy Setup and Teardown (Priority: P2)

**Goal**: Single-command lifecycle, VM ready in <30s, setup from scratch in <5min

**Independent Test**: Time setup, start, and teardown commands, verify within spec limits

### Implementation

- [x] T022 [US3] Add timing instrumentation to aibox/lib/setup.sh and aibox/lib/start.sh — report elapsed time at completion
- [x] T023 [US3] Implement `aibox init --preset <name>` in aibox/lib/init.sh — presets for common stacks (node, python, fullstack) to speed up config
- [x] T024 [US3] Create install.sh at aibox/install.sh — one-line installer that copies bin/aibox to /usr/local/bin and lib/ to ~/.aibox/lib/
- [x] T025 [US3] Write setup/teardown lifecycle tests in aibox/tests/test_setup.bats — verify setup creates VM, start brings it up in <30s, teardown destroys cleanly, re-setup works from scratch

**Checkpoint**: Full lifecycle is single-command. Start time <30s. Setup <5min.

---

## Phase 6: User Story 4 — Resource Limits (Priority: P3)

**Goal**: Configurable CPU, memory, and disk limits prevent runaway processes from affecting host

**Independent Test**: Run stress test inside VM, verify host performance unaffected, verify OOM kills happen inside VM

### Implementation

- [x] T026 [US4] Implement resource limit application in aibox/lib/start.sh — set CPU cores, memory cap, disk size from config (OrbStack: `orb config`, Lima: lima.yaml settings)
- [x] T027 [US4] Add resource usage to `aibox status` in aibox/lib/status.sh — show current CPU/memory/disk usage vs limits
- [x] T028 [US4] Write resource limit tests in aibox/tests/test_resources.bats — verify memory limit enforced (stress --vm), CPU limit enforced, disk limit enforced

**Checkpoint**: Resource limits configurable and enforced. Status shows usage vs limits.

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Final validation and documentation

- [x] T029 Run shellcheck on all scripts in aibox/lib/ and aibox/bin/
- [x] T030 [P] Add --help flag to all commands in aibox/bin/aibox
- [x] T031 [P] Add error handling for edge cases: VM crash mid-task, laptop sleep/wake, missing runtime
- [x] T032 Run full bats-core test suite and verify all tests pass (requires VM runtime installed)
- [x] T033 Run quickstart.md validation — execute all steps end-to-end (requires VM runtime installed)
- [x] T034 Update spec.md status from "Draft" to "Complete"

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — start immediately
- **Foundational (Phase 2)**: Depends on Phase 1 — runtime detection and provisioning
- **US1 Sandboxed Environment (Phase 3)**: Depends on Phase 2 — needs runtime and config
- **US2 Network Access (Phase 4)**: Depends on US1 — needs running VM to apply rules
- **US3 Easy Setup/Teardown (Phase 5)**: Depends on US1 — enhances existing lifecycle commands
- **US4 Resource Limits (Phase 6)**: Depends on US1 — needs running VM to set limits
- **Polish (Phase 7)**: Depends on all phases complete

### User Story Dependencies

- **US1 (P1)**: Can start after Phase 2 — no story dependencies
- **US2 (P2)**: Depends on US1 — needs VM running to apply network rules
- **US3 (P2)**: Depends on US1 — enhances lifecycle commands from US1
- **US4 (P3)**: Depends on US1 — needs VM running to set resource limits

### Parallel Opportunities

- T003, T004, T005 (setup tasks) can run in parallel
- T007, T008 (foundational) can run in parallel
- US2, US3, US4 can run in parallel AFTER US1 is complete (different concerns, different files)
- T029, T030, T031 (polish) can run in parallel

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (project structure, CLI entrypoint, config)
2. Complete Phase 2: Foundational (runtime detection, provisioning)
3. Complete Phase 3: US1 (setup → start → exec → stop → teardown + isolation tests)
4. **STOP and VALIDATE**: Can run Claude Code in isolated VM
5. Start using it immediately for noonstack development

### Incremental Delivery

1. Setup + Foundational → CLI skeleton ready
2. US1 → Full VM lifecycle with filesystem isolation (MVP!)
3. US2 → Network isolation added
4. US3 → Installer and presets for easy adoption
5. US4 → Resource limits for safety
6. Polish → Shellcheck, help text, edge cases

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps task to specific user story
- All scripts should be shellcheck-clean
- Test with both OrbStack and Lima when possible
- Config validation errors should be clear and actionable
- The tool is project-agnostic — works with any language, any AI agent
