# Implementation Plan: VM Isolation for AI Agents

**Branch**: `003-vm-isolation` | **Date**: 2026-03-08 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/003-vm-isolation/spec.md`

## Summary

A general-purpose CLI tool (`aibox`) that runs AI coding agents (Claude Code, Cursor, etc.) inside an isolated Linux VM on macOS Apple Silicon. Sandboxes filesystem, network, and system access so developers can grant AI agents broader autonomy without risk to their personal machine or sensitive data. Uses shell scripts wrapping a lightweight VM runtime (OrbStack recommended, Lima as fallback) with single-command lifecycle management, bidirectional file sync, configurable network rules, and resource limits.

## Technical Context

**Language/Version**: Bash/Shell scripting (POSIX-compatible + Bash 5.x extensions where needed)
**Primary Dependencies**: OrbStack (preferred) or Lima as VM runtime; Apple Virtualization.framework (underlying)
**Storage**: Host filesystem mounted into VM via VirtioFS; no database
**Testing**: Bash-based integration tests (bats-core); manual acceptance tests per spec scenarios
**Target Platform**: macOS Apple Silicon (ARM64, M-series chips)
**Project Type**: Standalone CLI tool / developer infrastructure (not tied to any specific project)
**Performance Goals**: VM ready in <30s (SC-001); file sync latency <5s (SC-002); setup from scratch <5min (SC-005)
**Constraints**: Must run on macOS ARM64; no GUI required; must not expose host secrets; must support configurable network rules; must be project-agnostic
**Scale/Scope**: Single-developer local use; one VM per project at a time

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| # | Principle | Status | Notes |
|---|-----------|--------|-------|
| I | Quality & Craft | PASS | Shell scripts will be linted (shellcheck), tested (bats-core), and documented. No shortcuts on error handling. |
| II | Type Safety | N/A | This is shell scripting / VM configuration, not application code. Config files will use validated YAML schemas. |
| III | Security by Design | PASS | Core purpose. VM provides filesystem isolation (FR-001, FR-011), network isolation (FR-003, FR-004), and controlled env var passing (FR-012). No secrets in scripts or version control. |
| IV | Design Excellence | PASS | CLI UX will be clean and consistent: `aibox setup`, `aibox start`, `aibox stop`, `aibox teardown`. Clear error messages and help text. |
| V | AI as Augmentation | PASS | The VM augments developer control over AI agents — it does not replace judgment. Developer explicitly configures what the agent can access. |
| VI | Modular Features | PASS | Fully standalone tool. Works with any project, any language, any AI agent. |
| VII | Privacy & Data Trust | PASS | Core purpose. VM prevents AI agents from accessing host secrets, SSH keys, cloud credentials, browser data. Only explicitly shared project files and env vars are accessible. |

## Project Structure

### Documentation (this feature)

```text
specs/003-vm-isolation/
├── plan.md              # This file
├── research.md          # VM runtime comparison and recommendations
├── quickstart.md        # Setup and testing guide
├── contracts/           # CLI command contracts and config schema
│   ├── cli-commands.md  # Command interface definitions
│   └── config-schema.md # VM configuration schema
├── checklists/
│   └── requirements.md  # Requirements checklist
└── tasks.md             # Phase 2 output (created by /speckit.tasks)
```

### Source Code (standalone project)

```text
aibox/
├── bin/
│   └── aibox                    # Main CLI entrypoint
├── lib/
│   ├── setup.sh                 # VM creation and provisioning
│   ├── start.sh                 # VM start with mounts and network
│   ├── stop.sh                  # Graceful VM shutdown
│   ├── teardown.sh              # VM destruction and cleanup
│   ├── status.sh                # VM status reporting
│   ├── network.sh               # Network rule management
│   └── config.sh                # Config file parsing and validation
├── templates/
│   ├── aibox.yaml               # Default configuration template
│   ├── provision.sh             # In-VM provisioning script (configurable tools)
│   └── network-defaults.yaml    # Default network allowlist
├── tests/
│   ├── test_setup.bats          # Setup command tests
│   ├── test_isolation.bats      # Filesystem isolation tests
│   ├── test_network.bats        # Network isolation tests
│   └── test_resources.bats      # Resource limit tests
├── install.sh                   # One-line installer
└── README.md                    # Usage documentation
```

**Structure Decision**: Standalone CLI project under `aibox/` at the repository root. This is independent tooling that can be installed globally or per-project. Uses `bin/` for the entrypoint, `lib/` for command implementations, `templates/` for configuration defaults, and `tests/` for bats-core integration tests. Could eventually be its own repo.

## Complexity Tracking

No constitution violations. All seven principles are satisfied or N/A.
